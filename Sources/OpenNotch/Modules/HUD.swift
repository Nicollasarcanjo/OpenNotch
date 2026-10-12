import AppKit
import AudioToolbox
import CoreAudio
import SwiftUI

struct HUDState: Equatable {
    enum Kind { case volume, brightness }
    var kind: Kind
    var value: Double       // 0...1
    var muted = false

    var icon: String {
        switch kind {
        case .brightness: return value < 0.5 ? "sun.min.fill" : "sun.max.fill"
        case .volume:
            if muted || value <= 0.001 { return "speaker.slash.fill" }
            return value < 0.34 ? "speaker.wave.1.fill" : value < 0.67 ? "speaker.wave.2.fill" : "speaker.wave.3.fill"
        }
    }
}

/// Mostra volume e brilho ao lado do notch quando eles mudam.
/// Só observa os valores do sistema; não intercepta as teclas.
final class HUDMonitor: ObservableObject {
    @Published private(set) var current: HUDState?

    private var device = AudioObjectID(kAudioObjectUnknown)
    private var lastVolume: (value: Double, muted: Bool)?
    private var lastBrightness: Double?
    private var hide: DispatchWorkItem?
    private var timer: Timer?
    private var volumeListener: AudioObjectPropertyListenerBlock?

    private static var defaultDeviceAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultOutputDevice,
        mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    private static var volumeAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
        mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
    private static var muteAddress = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyMute,
        mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)

    // Leitura do brilho da tela embutida. Não há API pública para isso; se a função
    // sumir numa versão futura do macOS, o indicador de brilho simplesmente não aparece.
    private static let brightnessFn: (@convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32)? = {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY),
              let symbol = dlsym(handle, "DisplayServicesGetBrightness") else { return nil }
        return unsafeBitCast(symbol, to: (@convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32).self)
    }()

    init() {
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &Self.defaultDeviceAddress,
                                            .main) { [weak self] _, _ in self?.bindDevice() }
        bindDevice()
        lastBrightness = Self.readBrightness()
        let t = Timer(timeInterval: 0.35, repeats: true) { [weak self] _ in self?.pollBrightness() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    // MARK: Volume

    private func bindDevice() {
        if let volumeListener, device != kAudioObjectUnknown {
            AudioObjectRemovePropertyListenerBlock(device, &Self.volumeAddress, .main, volumeListener)
            AudioObjectRemovePropertyListenerBlock(device, &Self.muteAddress, .main, volumeListener)
        }
        var id = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &Self.defaultDeviceAddress, 0, nil, &size, &id)
        device = id
        guard device != kAudioObjectUnknown else { return }
        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in self?.volumeChanged() }
        AudioObjectAddPropertyListenerBlock(device, &Self.volumeAddress, .main, listener)
        AudioObjectAddPropertyListenerBlock(device, &Self.muteAddress, .main, listener)
        volumeListener = listener
        lastVolume = readVolume()   // trocar de saída de áudio não é "mudar o volume"
    }

    private func readVolume() -> (value: Double, muted: Bool)? {
        var volume: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        guard AudioObjectGetPropertyData(device, &Self.volumeAddress, 0, nil, &size, &volume) == noErr else { return nil }
        var muted: UInt32 = 0
        size = UInt32(MemoryLayout<UInt32>.size)
        AudioObjectGetPropertyData(device, &Self.muteAddress, 0, nil, &size, &muted)
        return (Double(volume), muted != 0)
    }

    private func volumeChanged() {
        guard let now = readVolume() else { return }
        let changed = lastVolume.map { abs($0.value - now.value) > 0.001 || $0.muted != now.muted } ?? false
        lastVolume = now
        guard changed, Prefs.shared.bool(.hudVolume) else { return }
        show(HUDState(kind: .volume, value: now.value, muted: now.muted))
    }

    // MARK: Brilho

    private static func readBrightness() -> Double? {
        guard let fn = brightnessFn else { return nil }
        var value: Float = 0
        return fn(CGMainDisplayID(), &value) == 0 ? Double(value) : nil
    }

    private func pollBrightness() {
        guard Prefs.shared.bool(.hudBrightness), let now = Self.readBrightness() else { return }
        defer { lastBrightness = now }
        // O brilho automático muda aos poucos; só um salto do tamanho de um toque de tecla conta.
        guard let last = lastBrightness, abs(now - last) >= 0.012 else { return }
        show(HUDState(kind: .brightness, value: now))
    }

    private func show(_ state: HUDState) {
        hide?.cancel()
        withAnimation(.easeOut(duration: 0.15)) { current = state }
        let item = DispatchWorkItem { [weak self] in
            withAnimation(.easeIn(duration: 0.25)) { self?.current = nil }
        }
        hide = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6, execute: item)
    }
}

/// Barrinha de nível mostrada ao lado do notch.
struct HUDBar: View {
    let state: HUDState

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.22))
                Capsule().fill(Color.white)
                    .frame(width: geo.size.width * (state.muted ? 0 : min(max(state.value, 0), 1)))
            }
        }
        .frame(height: 5)
    }
}
