import AppKit
import AudioToolbox
import CoreAudio
import SwiftUI

struct MixerApp: Identifiable, Equatable {
    let id: String              // bundle id, ou "pid-N" para processos sem bundle
    var name: String
    var icon: NSImage?
    var objects: [AudioObjectID]   // processos de áudio do app (o principal e os auxiliares)
    var playing: Bool
    var volume: Double          // 0...1

    static func == (a: MixerApp, b: MixerApp) -> Bool {
        a.id == b.id && a.name == b.name && a.objects == b.objects && a.playing == b.playing && a.volume == b.volume
    }
}

struct MixerTab: Identifiable, Equatable {
    let id: Int
    var title: String
    var site: String
    var volume: Double
}

/// Volume por app e por aba do navegador, sem mexer no volume geral do sistema.
///
/// Apps: enquanto o volume de um app está em 100%, nada é tocado. Ao baixar, o OpenNotch
/// cria uma "escuta" (process tap) que silencia a saída direta do app e a reproduz com o
/// ganho escolhido. Ao voltar a 100% a escuta é desfeita e o app toca direto de novo.
/// Abas: o volume é aplicado dentro da página pela extensão do navegador.
final class AudioMixer: ObservableObject {
    @Published private(set) var apps: [MixerApp] = []
    @Published private(set) var tabs: [MixerTab] = []
    /// A escuta não pôde ser criada (em geral falta a permissão de gravação de áudio do sistema).
    @Published private(set) var blocked = false

    /// Só atualiza a lista enquanto a aba está visível (ou enquanto há algum volume alterado).
    var active = false { didSet { if active { refresh() } } }
    var isSupported: Bool { if #available(macOS 14.2, *) { return true } else { return false } }

    private var volumes: [String: Double] = [:]
    private var taps: [String: AnyObject] = [:]
    private var timer: Timer?
    private weak var bridge: BrowserBridge?

    init(bridge: BrowserBridge?) {
        self.bridge = bridge
        guard !Demo.enabled else {
            apps = Demo.mixerApps
            tabs = Demo.mixerTabs
            return
        }
        let t = Timer(timeInterval: 1.5, repeats: true) { [weak self] _ in
            guard let self, self.active || !self.taps.isEmpty else { return }
            self.refresh()
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        // Trocar a saída de áudio (ex.: plugar o fone) exige refazer as escutas no novo aparelho.
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main) { [weak self] _, _ in
            self?.rebuildTaps()
        }
    }

    // MARK: Lista de apps com áudio

    private func refresh() {
        guard !Demo.enabled, Prefs.shared.bool(.modMixer) else { return }
        var grouped: [String: MixerApp] = [:]
        let me = ProcessInfo.processInfo.processIdentifier
        for object in Self.processObjects() {
            guard let pid = Self.pid(of: object), pid != me, let owner = Self.owner(of: pid) else { continue }
            let key = owner.bundleIdentifier ?? "pid-\(owner.processIdentifier)"
            var app = grouped[key] ?? MixerApp(id: key, name: owner.localizedName ?? key, icon: owner.icon,
                                               objects: [], playing: false, volume: volumes[key] ?? 1)
            app.objects.append(object)
            app.playing = app.playing || Self.isPlaying(object)
            grouped[key] = app
        }
        // Aparece quem está tocando agora ou quem está com o volume alterado.
        let list = grouped.values
            .filter { $0.playing || $0.volume < 0.995 }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        if list != apps { apps = list }

        // Se os processos de áudio de um app mudaram (ex.: o navegador abriu outro auxiliar), refaz a escuta.
        for app in list where app.volume < 0.995 {
            if #available(macOS 14.2, *), let tap = taps[app.id] as? AppTap, tap.objects != app.objects {
                taps[app.id] = nil
                apply(app)
            }
        }
        // O app fechou: a escuta dele não serve mais.
        for key in taps.keys where grouped[key] == nil { taps[key] = nil }

        let seen = bridge?.activeTabs() ?? []
        let tabList = seen.map { MixerTab(id: $0.id, title: $0.title, site: $0.site, volume: bridge?.volume(ofTab: $0.id) ?? 1) }
        if tabList != tabs { tabs = tabList }
    }

    func setVolume(_ value: Double, for app: MixerApp) {
        let clamped = min(max(value, 0), 1)
        volumes[app.id] = clamped
        if let index = apps.firstIndex(where: { $0.id == app.id }) { apps[index].volume = clamped }
        var updated = app
        updated.volume = clamped
        apply(updated)
    }

    func setVolume(_ value: Double, forTab tab: MixerTab) {
        let clamped = min(max(value, 0), 1)
        bridge?.setVolume(clamped, forTab: tab.id)
        if let index = tabs.firstIndex(where: { $0.id == tab.id }) { tabs[index].volume = clamped }
    }

    private func apply(_ app: MixerApp) {
        guard #available(macOS 14.2, *) else { return }
        if app.volume >= 0.995 {
            taps[app.id] = nil      // volta a tocar direto, sem passar pelo OpenNotch
            volumes[app.id] = nil
            return
        }
        if let tap = taps[app.id] as? AppTap {
            tap.gain = Float(app.volume)
        } else if let tap = AppTap(objects: app.objects, gain: Float(app.volume)) {
            taps[app.id] = tap
            blocked = false
        } else {
            // Sem a escuta o app continua tocando normalmente, no volume cheio.
            blocked = true
            volumes[app.id] = nil
            if let index = apps.firstIndex(where: { $0.id == app.id }) { apps[index].volume = 1 }
        }
    }

    private func rebuildTaps() {
        guard #available(macOS 14.2, *) else { return }
        taps = [:]
        for app in apps where app.volume < 0.995 { apply(app) }
    }

    func openPermissionSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: CoreAudio

    private static func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
                                   mElement: kAudioObjectPropertyElementMain)
    }

    private static func processObjects() -> [AudioObjectID] {
        guard #available(macOS 14.2, *) else { return [] }
        var addr = address(kAudioHardwarePropertyProcessObjectList)
        var size: UInt32 = 0
        let system = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyDataSize(system, &addr, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &addr, 0, nil, &size, &ids) == noErr else { return [] }
        return ids
    }

    private static func pid(of object: AudioObjectID) -> pid_t? {
        guard #available(macOS 14.2, *) else { return nil }
        var addr = address(kAudioProcessPropertyPID)
        var pid: pid_t = 0
        var size = UInt32(MemoryLayout<pid_t>.size)
        return AudioObjectGetPropertyData(object, &addr, 0, nil, &size, &pid) == noErr ? pid : nil
    }

    private static func isPlaying(_ object: AudioObjectID) -> Bool {
        guard #available(macOS 14.2, *) else { return false }
        var addr = address(kAudioProcessPropertyIsRunningOutput)
        var running: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(object, &addr, 0, nil, &size, &running) == noErr && running != 0
    }

    /// O app a que um processo de áudio pertence (o áudio do navegador sai de um processo auxiliar).
    private static func owner(of pid: pid_t) -> NSRunningApplication? {
        if let app = NSRunningApplication(processIdentifier: pid), app.activationPolicy != .prohibited { return app }
        if let responsible = ProcScan.responsible(for: pid), responsible != pid,
           let app = NSRunningApplication(processIdentifier: responsible), app.activationPolicy != .prohibited {
            return app
        }
        return nil
    }
}

/// A "escuta" de um app: silencia a saída direta dele e a reproduz na saída padrão com um ganho.
/// Desfeita (deinit), o app volta a tocar direto.
@available(macOS 14.2, *)
private final class AppTap {
    let objects: [AudioObjectID]
    var gain: Float {
        get { gainPointer.pointee }
        set { gainPointer.pointee = newValue }
    }

    // O bloco de áudio roda em outra thread e lê o ganho por este ponteiro.
    private let gainPointer: UnsafeMutablePointer<Float>
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var procID: AudioDeviceIOProcID?

    init?(objects: [AudioObjectID], gain: Float) {
        self.objects = objects
        gainPointer = .allocate(capacity: 1)
        gainPointer.initialize(to: gain)

        let description = CATapDescription(stereoMixdownOfProcesses: objects)
        description.uuid = UUID()
        description.name = "OpenNotch"
        description.isPrivate = true
        description.muteBehavior = .mutedWhenTapped
        guard AudioHardwareCreateProcessTap(description, &tapID) == noErr, let output = Self.defaultOutputUID() else {
            teardown()
            return nil
        }

        let aggregate: [String: Any] = [
            kAudioAggregateDeviceNameKey: "OpenNotch",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceMainSubDeviceKey: output,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: output]],
            kAudioAggregateDeviceTapListKey: [[kAudioSubTapDriftCompensationKey: true,
                                               kAudioSubTapUIDKey: description.uuid.uuidString]],
        ]
        guard AudioHardwareCreateAggregateDevice(aggregate as CFDictionary, &aggregateID) == noErr else {
            teardown()
            return nil
        }

        let pointer = gainPointer
        let status = AudioDeviceCreateIOProcIDWithBlock(&procID, aggregateID, nil) { _, input, _, output, _ in
            let source = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
            let target = UnsafeMutableAudioBufferListPointer(output)
            let gain = pointer.pointee
            for index in 0..<target.count {
                guard let destination = target[index].mData else { continue }
                let capacity = Int(target[index].mDataByteSize)
                guard index < source.count, let origin = source[index].mData else {
                    memset(destination, 0, capacity)
                    continue
                }
                // As duas pontas são Float32; copia o que couber, com o ganho, e zera o resto.
                let bytes = min(capacity, Int(source[index].mDataByteSize))
                let samples = bytes / MemoryLayout<Float>.size
                let from = origin.assumingMemoryBound(to: Float.self)
                let to = destination.assumingMemoryBound(to: Float.self)
                for sample in 0..<samples { to[sample] = from[sample] * gain }
                if bytes < capacity { memset(destination + bytes, 0, capacity - bytes) }
            }
        }
        guard status == noErr, let procID, AudioDeviceStart(aggregateID, procID) == noErr else {
            teardown()
            return nil
        }
    }

    deinit {
        teardown()
        gainPointer.deallocate()
    }

    private func teardown() {
        if aggregateID != kAudioObjectUnknown {
            if let procID {
                AudioDeviceStop(aggregateID, procID)
                AudioDeviceDestroyIOProcID(aggregateID, procID)
            }
            AudioHardwareDestroyAggregateDevice(aggregateID)
            aggregateID = AudioObjectID(kAudioObjectUnknown)
        }
        if tapID != kAudioObjectUnknown {
            AudioHardwareDestroyProcessTap(tapID)
            tapID = AudioObjectID(kAudioObjectUnknown)
        }
        procID = nil
    }

    private static func defaultOutputUID() -> String? {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device) == noErr
        else { return nil }
        address.mSelector = kAudioDevicePropertyDeviceUID
        var uid: Unmanaged<CFString>?
        size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &uid) == noErr, let uid else { return nil }
        return uid.takeRetainedValue() as String
    }
}

struct MixerView: View {
    @EnvironmentObject var mixer: AudioMixer

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if mixer.blocked {
                HStack(spacing: 8) {
                    Image(systemName: "lock.fill").foregroundStyle(.orange)
                    Text("Libere “Gravação de Tela e Áudio do Sistema” para o OpenNotch poder ajustar o volume dos apps.")
                        .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    Spacer(minLength: 0)
                    Button("Abrir Ajustes", action: mixer.openPermissionSettings).font(.caption)
                }
            }
            if !mixer.isSupported {
                Text("O volume por app precisa do macOS 14.2 ou mais recente.")
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if mixer.apps.isEmpty && mixer.tabs.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "speaker.wave.2").font(.system(size: 26)).foregroundStyle(.secondary)
                    Text("Nenhum app tocando som").font(.headline)
                    Text("Os apps e as abas com áudio aparecem aqui, cada um com o seu volume.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(mixer.apps) { app in
                            VolumeRow(icon: app.icon, symbol: "app.fill", title: app.name, subtitle: nil,
                                      volume: app.volume) { mixer.setVolume($0, for: app) }
                        }
                        if !mixer.tabs.isEmpty {
                            Text("Abas do navegador")
                                .font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 4)
                            ForEach(mixer.tabs) { tab in
                                VolumeRow(icon: nil, symbol: "globe", title: tab.title, subtitle: tab.site,
                                          volume: tab.volume) { mixer.setVolume($0, forTab: tab) }
                            }
                        }
                    }
                }
            }
        }
        .onAppear { mixer.active = true }
        .onDisappear { mixer.active = false }
    }
}

private struct VolumeRow: View {
    let icon: NSImage?
    let symbol: String
    let title: String
    let subtitle: String?
    let volume: Double
    let change: (Double) -> Void
    /// Volume de antes de silenciar, para o botão do alto-falante devolver.
    @State private var beforeMute = 1.0

    var body: some View {
        HStack(spacing: 8) {
            if let icon {
                Image(nsImage: icon).resizable().frame(width: 18, height: 18)
            } else {
                Image(systemName: symbol).font(.system(size: 12)).foregroundStyle(.secondary).frame(width: 18)
            }
            VStack(alignment: .leading, spacing: 0) {
                Text(title).font(.system(size: 12, weight: .medium)).lineLimit(1)
                if let subtitle {
                    Text(subtitle).font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            .frame(width: 150, alignment: .leading)
            Button {
                if volume > 0.005 {
                    beforeMute = volume
                    change(0)
                } else {
                    change(beforeMute > 0.005 ? beforeMute : 1)
                }
            } label: {
                Image(systemName: volume <= 0.005 ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .font(.system(size: 11)).frame(width: 22, height: 20).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(volume <= 0.005 ? "Devolver o som" : "Silenciar")
            Slider(value: Binding(get: { volume }, set: change), in: 0...1)
                .controlSize(.small)
            Text("\(Int((volume * 100).rounded()))%")
                .font(.system(size: 11).monospacedDigit()).frame(width: 36, alignment: .trailing)
        }
        .padding(.horizontal, 9).padding(.vertical, 5)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 7))
    }
}
