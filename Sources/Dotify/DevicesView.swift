import AppKit
import SwiftUI

/// Floating speaker picker. Opens with D in the player or from the menus.
@MainActor
final class DevicePanelController {
    let panel: NSPanel
    private let devices: DeviceStore
    private var keyMonitor: Any?
    private var pollTimer: Timer?

    init(devices: DeviceStore, auth: SpotifyAuth, spotify: SpotifyController) {
        self.devices = devices
        panel = makeUtilityPanel(size: NSSize(width: 320, height: 500), minSize: NSSize(width: 280, height: 260))
        panel.contentView = NSHostingView(
            rootView: DevicesView()
                .environmentObject(devices)
                .environmentObject(auth)
                .environmentObject(spotify)
        )
        panel.setFrameAutosaveName("DevicePanel")

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.window === self.panel, event.keyCode == 53 else { return event }
            self.hide()
            return nil
        }
    }

    func toggle(near anchor: NSRect?) {
        if panel.isVisible { hide() } else { show(near: anchor) }
    }

    func show(near anchor: NSRect?) {
        showUtilityPanel(panel, autosaveName: "DevicePanel", near: anchor)
        devices.refresh()
        // Connect devices come and go (speakers sleep, phones open Spotify); keep the list fresh while open.
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.panel.isVisible else { return }
                await self.devices.reloadConnect()
            }
        }
    }

    func hide() {
        panel.orderOut(nil)
        pollTimer?.invalidate()
        pollTimer = nil
    }
}

struct DevicesView: View {
    @EnvironmentObject private var devices: DeviceStore
    @EnvironmentObject private var auth: SpotifyAuth
    @EnvironmentObject private var spotify: SpotifyController
    @AppStorage("showVirtualOutputs") private var showVirtual = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Play On").font(.system(size: 15, weight: .semibold))
                Spacer()
                if devices.loadingConnect {
                    ProgressView().controlSize(.small)
                } else {
                    Button { devices.refresh() } label: { Image(systemName: "arrow.clockwise") }
                        .buttonStyle(.borderless)
                        .help("Refresh")
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 32)
            .padding(.bottom, 8)

            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    if let error = devices.errorMessage {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(8)
                    }
                    macSection
                    bluetoothSection
                    airplaySection
                    connectSection
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 10)
            }
        }
        .background(VisualEffectBackground().ignoresSafeArea())
        .environment(\.colorScheme, .dark)
    }

    // MARK: Sections

    @ViewBuilder
    private var macSection: some View {
        DeviceSectionHeader(title: "This Mac")
        let playingHere = devices.remoteActive == nil
        let real = devices.outputs.filter { !$0.isVirtual }
        let virtual = devices.outputs.filter(\.isVirtual)
        // A virtual device that's currently selected stays visible.
        let shown = real + virtual.filter { showVirtual || $0.id == devices.defaultOutput }
        ForEach(shown) { output in
            DeviceRow(
                symbol: output.symbol,
                name: output.name,
                detail: output.isBluetooth ? "Bluetooth" : output.isVirtual ? "Virtual" : nil,
                selected: playingHere && devices.defaultOutput == output.id,
                busy: false
            ) {
                Task { await devices.select(output) }
            }
        }
        if !virtual.isEmpty {
            Button(showVirtual ? "Hide virtual devices" : "More (\(virtual.count) virtual)") { showVirtual.toggle() }
                .buttonStyle(.borderless)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private var bluetoothSection: some View {
        if !devices.bluetooth.isEmpty {
            DeviceSectionHeader(title: "Bluetooth · Not Connected")
            ForEach(devices.bluetooth) { speaker in
                DeviceRow(
                    symbol: "dot.radiowaves.left.and.right",
                    name: speaker.name,
                    detail: devices.busy == speaker.id ? "Connecting…" : "Click to connect",
                    selected: false,
                    busy: devices.busy == speaker.id,
                    dimmed: true
                ) {
                    Task { await devices.connect(speaker) }
                }
            }
        }
    }

    @ViewBuilder
    private var airplaySection: some View {
        if !devices.airplay.isEmpty {
            DeviceSectionHeader(title: "AirPlay")
            ForEach(devices.airplay) { speaker in
                DeviceRow(
                    symbol: "airplayaudio",
                    name: speaker.name,
                    detail: (speaker.isSonos ? "Sonos · " : "") + "Choose in Sound settings",
                    selected: false,
                    busy: false
                ) {
                    devices.select(speaker)
                }
                .help("Opens Sound settings. Select \(speaker.name) under Output; it then shows under This Mac.")
            }
        }
    }

    @ViewBuilder
    private var connectSection: some View {
        DeviceSectionHeader(title: "Spotify Connect")
        if !auth.isConnected {
            note("Connect your Spotify account (press F, then search) to play on network speakers, TVs and phones.")
        } else if !auth.canControlPlayback {
            VStack(alignment: .leading, spacing: 8) {
                note("Reconnect Spotify to allow Dotify to switch speakers.")
                HStack {
                    Button(auth.isConnecting ? "Finish in your browser…" : "Reconnect") {
                        Task {
                            await auth.connect()
                            await devices.reloadConnect()
                        }
                    }
                    .controlSize(.small)
                    .disabled(auth.isConnecting)
                }
                .padding(.horizontal, 8)
                if let error = auth.authError {
                    note(error).foregroundStyle(.orange)
                }
            }
        } else if devices.remoteDevices.isEmpty && !devices.loadingConnect {
            note("No other devices found. Open Spotify on your phone, TV or smart speaker, or wake it up, then refresh.")
        } else {
            ForEach(devices.remoteDevices) { device in
                DeviceRow(
                    symbol: device.symbol,
                    name: device.name,
                    detail: device.isRestricted ? "Can't be controlled" : device.type,
                    selected: device.isActive,
                    busy: devices.busy == device.id
                ) {
                    Task { await devices.select(device) }
                }
                .disabled(device.isRestricted)
                if device.isActive, device.supportsVolume == true, let volume = device.volumePercent {
                    ConnectVolumeSlider(device: device, initial: volume)
                        .padding(.leading, 46)
                        .padding(.trailing, 12)
                        .padding(.bottom, 6)
                }
            }
        }
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
    }
}

private struct DeviceSectionHeader: View {
    let title: String

    var body: some View {
        Text(title.uppercased())
            .font(.system(size: 10, weight: .bold))
            .tracking(0.6)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.top, 12)
            .padding(.bottom, 4)
    }
}

private struct DeviceRow: View {
    @EnvironmentObject private var spotify: SpotifyController
    let symbol: String
    let name: String
    let detail: String?
    let selected: Bool
    let busy: Bool
    var dimmed = false
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 15))
                    .foregroundStyle(selected ? spotify.accent : .white.opacity(dimmed ? 0.45 : 0.8))
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 1) {
                    Text(name)
                        .font(.system(size: 13, weight: selected ? .semibold : .regular))
                        .foregroundStyle(selected ? spotify.accent : .white.opacity(dimmed ? 0.6 : 1))
                    if let detail {
                        Text(detail).font(.system(size: 10)).foregroundStyle(.white.opacity(0.45))
                    }
                }
                .lineLimit(1)
                Spacer(minLength: 4)
                if busy {
                    ProgressView().controlSize(.small)
                } else if selected {
                    Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(spotify.accent)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.white.opacity(hovering ? 0.08 : 0)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

private struct ConnectVolumeSlider: View {
    @EnvironmentObject private var devices: DeviceStore
    let device: ConnectDevice
    @State private var value: Double

    init(device: ConnectDevice, initial: Int) {
        self.device = device
        _value = State(initialValue: Double(initial))
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "speaker.fill").font(.system(size: 9))
            Slider(value: $value, in: 0...100) { editing in
                if !editing { devices.setVolume(Int(value), on: device) }
            }
            .controlSize(.mini)
            Image(systemName: "speaker.wave.3.fill").font(.system(size: 9))
        }
        .foregroundStyle(.white.opacity(0.5))
    }
}
