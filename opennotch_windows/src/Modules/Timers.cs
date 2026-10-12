using System.Windows.Threading;

namespace OpenNotch;

public enum TimerMode { Pomodoro, Countdown, Stopwatch }

/// <summary>Pomodoro, contagem regressiva e cronômetro. Mesmas regras da versão macOS (Timers.swift).</summary>
public sealed class TimerManager : Observable
{
    private TimerMode _mode = TimerMode.Pomodoro;
    private bool _isRunning, _onBreak;
    private int _seconds;
    private readonly DispatcherTimer _timer = new() { Interval = TimeSpan.FromSeconds(1) };

    public TimerMode Mode
    {
        get => _mode;
        set
        {
            if (!Set(ref _mode, value)) return;
            Stop();
            Reset();
            Raise(nameof(PhaseText));
        }
    }

    public bool IsRunning { get => _isRunning; private set { if (Set(ref _isRunning, value)) Raise(nameof(ToggleText)); } }
    public bool OnBreak { get => _onBreak; private set { if (Set(ref _onBreak, value)) Raise(nameof(PhaseText)); } }

    /// <summary>Restante (pomodoro/contagem) ou decorrido (cronômetro), em segundos.</summary>
    public int Seconds { get => _seconds; private set { if (Set(ref _seconds, value)) Raise(nameof(Display)); } }

    public string Display
    {
        get
        {
            int h = Seconds / 3600, m = Seconds % 3600 / 60, s = Seconds % 60;
            return h > 0 ? $"{h}:{m:00}:{s:00}" : $"{m:00}:{s:00}";
        }
    }

    public string ToggleText => IsRunning ? Loc.T("Pausar") : Loc.T("Iniciar");
    public string PhaseText => Mode != TimerMode.Pomodoro ? "" : OnBreak ? Loc.T("Pausa") : Loc.T("Foco");

    public TimerManager()
    {
        _timer.Tick += (_, _) => Tick();
        Reset();
    }

    public void Toggle()
    {
        if (IsRunning) Stop(); else Start();
    }

    public void Start()
    {
        if (IsRunning) return;
        if (Mode != TimerMode.Stopwatch && Seconds <= 0) Reset();
        IsRunning = true;
        _timer.Start();
    }

    public void Stop()
    {
        _timer.Stop();
        IsRunning = false;
    }

    public void Reset()
    {
        var settings = Settings.Current;
        Seconds = Mode switch
        {
            TimerMode.Pomodoro => (OnBreak ? settings.BreakMinutes : settings.FocusMinutes) * 60,
            TimerMode.Countdown => settings.CountdownMinutes * 60,
            _ => 0,
        };
    }

    public void Restart()
    {
        Stop();
        OnBreak = false;
        Reset();
    }

    private void Tick()
    {
        if (Mode == TimerMode.Stopwatch)
        {
            Seconds++;
            return;
        }
        Seconds--;
        if (Seconds > 0) return;
        if (Settings.Current.TimersSound) System.Media.SystemSounds.Asterisk.Play();
        if (Mode == TimerMode.Pomodoro)
        {
            // Alterna foco/pausa e segue contando.
            OnBreak = !OnBreak;
            Reset();
        }
        else
        {
            Stop();
        }
    }
}
