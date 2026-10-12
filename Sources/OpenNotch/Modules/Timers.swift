import AppKit
import SwiftUI

final class TimerManager: ObservableObject {
    enum Mode: String, CaseIterable, Identifiable {
        case pomodoro = "Pomodoro"
        case countdown = "Contagem"
        case stopwatch = "Cronômetro"
        var id: String { rawValue }
    }

    @Published var mode: Mode = .pomodoro { didSet { stop(); reset() } }
    @Published private(set) var isRunning = false
    /// Restante (pomodoro/contagem) ou decorrido (cronômetro), em segundos.
    @Published private(set) var seconds = 25 * 60
    @Published private(set) var onBreak = false
    @Published var focusMinutes: Int { didSet { save("focusMinutes", focusMinutes); resetIfIdle() } }
    @Published var breakMinutes: Int { didSet { save("breakMinutes", breakMinutes); resetIfIdle() } }
    @Published var countdownMinutes: Int { didSet { save("countdownMinutes", countdownMinutes); resetIfIdle() } }

    private var timer: Timer?

    init() {
        let d = UserDefaults.standard
        focusMinutes = d.object(forKey: "focusMinutes") as? Int ?? 25
        breakMinutes = d.object(forKey: "breakMinutes") as? Int ?? 5
        countdownMinutes = d.object(forKey: "countdownMinutes") as? Int ?? 10
        reset()
    }

    var display: String {
        let h = seconds / 3600, m = (seconds % 3600) / 60, s = seconds % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%02d:%02d", m, s)
    }

    func toggle() { isRunning ? stop() : start() }

    func start() {
        guard !isRunning else { return }
        if mode != .stopwatch, seconds <= 0 { reset() }
        isRunning = true
        let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        isRunning = false
    }

    func reset() {
        switch mode {
        case .pomodoro: seconds = (onBreak ? breakMinutes : focusMinutes) * 60
        case .countdown: seconds = countdownMinutes * 60
        case .stopwatch: seconds = 0
        }
    }

    func restart() {
        stop()
        onBreak = false
        reset()
    }

    private func resetIfIdle() { if !isRunning { reset() } }

    private func tick() {
        if mode == .stopwatch {
            seconds += 1
            return
        }
        seconds -= 1
        guard seconds <= 0 else { return }
        if Prefs.shared.bool(.timersSound) { NSSound(named: "Glass")?.play() }
        if mode == .pomodoro {
            // Alterna foco/pausa e segue contando.
            onBreak.toggle()
            reset()
        } else {
            stop()
        }
    }

    private func save(_ key: String, _ value: Int) { UserDefaults.standard.set(value, forKey: key) }
}

struct TimersView: View {
    @EnvironmentObject var timers: TimerManager

    var body: some View {
        HStack(spacing: 24) {
            VStack(spacing: 8) {
                Picker("", selection: $timers.mode) {
                    ForEach(TimerManager.Mode.allCases) { Text(LocalizedStringKey($0.rawValue)).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                Text(timers.display)
                    .font(.system(size: 52, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(timers.mode == .pomodoro && timers.onBreak ? .green : .white)

                if timers.mode == .pomodoro {
                    Text(timers.onBreak ? "Pausa" : "Foco").font(.caption).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity)

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Button(action: timers.toggle) {
                        Label(timers.isRunning ? "Pausar" : "Iniciar",
                              systemImage: timers.isRunning ? "pause.fill" : "play.fill")
                            .frame(width: 84)
                    }
                    Button(action: timers.restart) { Image(systemName: "arrow.counterclockwise") }
                        .help("Zerar")
                }
                switch timers.mode {
                case .pomodoro:
                    Stepper("Foco: \(timers.focusMinutes) min", value: $timers.focusMinutes, in: 1...120)
                    Stepper("Pausa: \(timers.breakMinutes) min", value: $timers.breakMinutes, in: 1...60)
                case .countdown:
                    Stepper("Duração: \(timers.countdownMinutes) min", value: $timers.countdownMinutes, in: 1...600)
                case .stopwatch:
                    EmptyView()
                }
            }
            .font(.system(size: 12))
            .frame(width: 190, alignment: .leading)
        }
    }
}
