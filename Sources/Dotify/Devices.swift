import AppKit
import CoreAudio
import IOBluetooth
import Network

// MARK: - Mac audio outputs (CoreAudio)

struct AudioOutput: Identifiable, Equatable {
    let id: AudioDeviceID
    let name: String
    let transport: UInt32

    var isBluetooth: Bool { transport == kAudioDeviceTransportTypeBluetooth || transport == kAudioDeviceTransportTypeBluetoothLE }
    /// Software devices (BlackHole, Teams, remote-desktop drivers) rather than real speakers.
    var isVirtual: Bool { transport == kAudioDeviceTransportTypeVirtual || transport == kAudioDeviceTransportTypeUnknown }

    var symbol: String {
        switch transport {
        case kAudioDeviceTransportTypeBuiltIn: "laptopcomputer"
        case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE:
            name.localizedCaseInsensitiveContains("airpods") || name.localizedCaseInsensitiveContains("headphone")
                || name.localizedCaseInsensitiveContains("buds") ? "headphones" : "hifispeaker"
        case kAudioDeviceTransportTypeAirPlay: "airplayaudio"
        case kAudioDeviceTransportTypeHDMI, kAudioDeviceTransportTypeDisplayPort: "tv"
        case kAudioDeviceTransportTypeUSB: "cable.connector"
        default: "speaker.wave.2"
        }
    }
}

/// Spotify plays through the Mac's default output, so switching it moves Spotify too.
enum AudioOutputs {
    private static let system = AudioObjectID(kAudioObjectSystemObject)

    static func all() -> [AudioOutput] {
        var addr = address(kAudioHardwarePropertyDevices)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &addr, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(system, &addr, 0, nil, &size, &ids) == noErr else { return [] }
        return ids.compactMap { id in
            guard hasOutput(id), let name = string(id, kAudioObjectPropertyName) else { return nil }
            let transport: UInt32 = value(id, kAudioDevicePropertyTransportType) ?? 0
            // Aggregate/multi-output devices are plumbing, not speakers.
            if transport == kAudioDeviceTransportTypeAggregate { return nil }
            return AudioOutput(id: id, name: name, transport: transport)
        }
        .sorted { ($0.transport == kAudioDeviceTransportTypeBuiltIn ? 0 : 1, $0.name) < ($1.transport == kAudioDeviceTransportTypeBuiltIn ? 0 : 1, $1.name) }
    }

    static func defaultOutput() -> AudioDeviceID? {
        value(system, kAudioHardwarePropertyDefaultOutputDevice)
    }

    @discardableResult
    static func setDefault(_ id: AudioDeviceID) -> Bool {
        var addr = address(kAudioHardwarePropertyDefaultOutputDevice)
        var device = id
        return AudioObjectSetPropertyData(system, &addr, 0, nil, UInt32(MemoryLayout<AudioDeviceID>.size), &device) == noErr
    }

    /// Calls `handler` on the main queue when devices appear/disappear or the default output changes.
    static func observe(_ handler: @escaping () -> Void) {
        for selector in [kAudioHardwarePropertyDevices, kAudioHardwarePropertyDefaultOutputDevice] {
            var addr = address(selector)
            AudioObjectAddPropertyListenerBlock(system, &addr, .main) { _, _ in handler() }
        }
    }

    private static func address(_ selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    private static func hasOutput(_ id: AudioDeviceID) -> Bool {
        var addr = address(kAudioDevicePropertyStreams, scope: kAudioObjectPropertyScopeOutput)
        var size: UInt32 = 0
        return AudioObjectGetPropertyDataSize(id, &addr, 0, nil, &size) == noErr && size > 0
    }

    private static func value<T>(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector) -> T? {
        var addr = address(selector)
        var size = UInt32(MemoryLayout<T>.size)
        let ptr = UnsafeMutablePointer<T>.allocate(capacity: 1)
        defer { ptr.deallocate() }
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, ptr) == noErr else { return nil }
        return ptr.pointee
    }

    private static func string(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
        var addr = address(selector)
        var size = UInt32(MemoryLayout<CFString?>.size)
        var result: Unmanaged<CFString>?
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &result) == noErr, let result else { return nil }
        return result.takeRetainedValue() as String
    }
}

// MARK: - Paired Bluetooth audio devices

struct BluetoothSpeaker: Identifiable, Equatable {
    let id: String // address
    let name: String
    let isConnected: Bool
}

enum BluetoothAudio {
    static func paired() -> [BluetoothSpeaker] {
        let devices = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] ?? []
        return devices
            .filter { $0.deviceClassMajor == BluetoothDeviceClassMajor(kBluetoothDeviceClassMajorAudio) }
            .compactMap { d in
                guard let address = d.addressString else { return nil }
                return BluetoothSpeaker(id: address, name: d.name ?? address, isConnected: d.isConnected())
            }
            .sorted { $0.name < $1.name }
    }

    /// Opens a connection; macOS then brings up the audio profile. Blocks, so call off the main thread.
    static func connect(address: String) -> Bool {
        guard let device = IOBluetoothDevice(addressString: address) else { return false }
        if device.isConnected() { return true }
        return device.openConnection() == kIOReturnSuccess
    }
}

// MARK: - AirPlay receivers (Bonjour)

struct AirPlaySpeaker: Identifiable, Equatable {
    var id: String { name }
    let name: String
    let isSonos: Bool
}

/// Watches the local network for AirPlay receivers, and Sonos rooms so we can label them.
/// Apps can't pick an AirPlay target themselves, so these are listed for the user to choose in Sound settings.
@MainActor
final class AirPlayBrowser {
    private var browsers: [NWBrowser] = []
    private var airplay: Set<String> = []
    private var sonosRooms: Set<String> = []
    var onChange: (([AirPlaySpeaker]) -> Void)?

    func start() {
        guard browsers.isEmpty else { return }
        browse("_airplay._tcp") { [weak self] names in self?.airplay = names }
        // Sonos instance names look like "RINCON_5CAAFDD25768014000@Office".
        browse("_sonos._tcp") { [weak self] names in
            self?.sonosRooms = Set(names.compactMap { $0.split(separator: "@", maxSplits: 1).last.map(String.init) })
        }
    }

    private func browse(_ type: String, update: @escaping (Set<String>) -> Void) {
        let browser = NWBrowser(for: .bonjour(type: type, domain: "local."), using: .tcp)
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            let names = Set(results.compactMap { result -> String? in
                if case .service(let name, _, _, _) = result.endpoint { return name }
                return nil
            })
            Task { @MainActor in
                update(names)
                self?.publish()
            }
        }
        browser.start(queue: .main)
        browsers.append(browser)
    }

    private func publish() {
        let thisMac = Host.current().localizedName ?? ""
        let speakers = airplay
            .filter { $0 != thisMac }
            .map { AirPlaySpeaker(name: $0, isSonos: sonosRooms.contains($0)) }
            .sorted { ($0.isSonos ? 0 : 1, $0.name) < ($1.isSonos ? 0 : 1, $1.name) }
        onChange?(speakers)
    }
}

// MARK: - Store

@MainActor
final class DeviceStore: ObservableObject {
    @Published private(set) var outputs: [AudioOutput] = []
    @Published private(set) var defaultOutput: AudioDeviceID?
    /// Paired Bluetooth audio devices that aren't connected yet.
    @Published private(set) var bluetooth: [BluetoothSpeaker] = []
    @Published private(set) var connectDevices: [ConnectDevice] = []
    @Published private(set) var airplay: [AirPlaySpeaker] = []
    @Published private(set) var loadingConnect = false
    /// ID of the output, Bluetooth device or Connect device currently being switched to.
    @Published private(set) var busy: String?
    @Published var errorMessage: String?

    private let api: SpotifyAPI
    private let auth: SpotifyAuth
    private let airplayBrowser = AirPlayBrowser()

    init(api: SpotifyAPI, auth: SpotifyAuth) {
        self.api = api
        self.auth = auth
        reloadOutputs()
        AudioOutputs.observe { [weak self] in
            Task { @MainActor in self?.reloadOutputs() }
        }
        airplayBrowser.onChange = { [weak self] in self?.airplay = $0 }
    }

    /// The Spotify Connect device for this Mac's Spotify app, if we can tell which one it is.
    var thisComputer: ConnectDevice? {
        let computers = connectDevices.filter { $0.type.lowercased() == "computer" }
        let names = [Host.current().localizedName, ProcessInfo.processInfo.hostName.components(separatedBy: ".").first]
            .compactMap { $0?.lowercased() }
        return computers.first { names.contains($0.name.lowercased()) } ?? (computers.count == 1 ? computers.first : nil)
    }

    /// Connect devices other than this Mac.
    var remoteDevices: [ConnectDevice] {
        connectDevices.filter { $0.id != thisComputer?.id }
    }

    /// Spotify is playing somewhere other than this Mac.
    var remoteActive: ConnectDevice? {
        remoteDevices.first(where: \.isActive)
    }

    func refresh() {
        // Started on first open rather than at launch, so the Local Network prompt appears in context.
        airplayBrowser.start()
        reloadOutputs()
        bluetooth = BluetoothAudio.paired().filter { !$0.isConnected }
        Task { await reloadConnect() }
    }

    private func reloadOutputs() {
        outputs = AudioOutputs.all()
        defaultOutput = AudioOutputs.defaultOutput()
    }

    func reloadConnect() async {
        guard auth.canControlPlayback else {
            connectDevices = []
            return
        }
        loadingConnect = true
        defer { loadingConnect = false }
        do {
            connectDevices = try await api.devices()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Switching

    func select(_ output: AudioOutput) async {
        errorMessage = nil
        guard AudioOutputs.setDefault(output.id) else {
            errorMessage = "Couldn't switch to \(output.name)."
            return
        }
        reloadOutputs()
        await bringPlaybackHome()
    }

    func connect(_ speaker: BluetoothSpeaker) async {
        errorMessage = nil
        busy = speaker.id
        defer { busy = nil }
        let address = speaker.id
        let ok = await Task.detached { BluetoothAudio.connect(address: address) }.value
        guard ok else {
            errorMessage = "Couldn't connect to \(speaker.name). Make sure it's on and in range."
            return
        }
        // Wait for the audio device to show up, then make it the output.
        for _ in 0..<20 {
            reloadOutputs()
            if let output = outputs.first(where: { $0.isBluetooth && $0.name == speaker.name }) {
                bluetooth.removeAll { $0.id == speaker.id }
                await select(output)
                return
            }
            try? await Task.sleep(for: .milliseconds(500))
        }
        bluetooth = BluetoothAudio.paired().filter { !$0.isConnected }
        errorMessage = "\(speaker.name) connected, but no audio output appeared. Pick it under This Mac once it does."
    }

    /// macOS doesn't let apps choose an AirPlay target, so open the Sound output list where it's one click.
    func select(_ speaker: AirPlaySpeaker) {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Sound-Settings.extension")!)
    }

    func select(_ device: ConnectDevice) async {
        guard let id = device.id else { return }
        errorMessage = nil
        busy = id
        defer { busy = nil }
        do {
            try await api.transferPlayback(to: id, play: true)
            try? await Task.sleep(for: .seconds(1))
            await reloadConnect()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func setVolume(_ percent: Int, on device: ConnectDevice) {
        guard let id = device.id else { return }
        Task {
            do {
                try await api.setVolume(percent, deviceID: id)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    /// Picking a Mac output means "play here": pull playback back from any Connect device.
    private func bringPlaybackHome() async {
        guard auth.canControlPlayback else { return }
        await reloadConnect()
        guard remoteActive != nil, let here = thisComputer?.id else { return }
        do {
            try await api.transferPlayback(to: here, play: true)
            try? await Task.sleep(for: .seconds(1))
            await reloadConnect()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
