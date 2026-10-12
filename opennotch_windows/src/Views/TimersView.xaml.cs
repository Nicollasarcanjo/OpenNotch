using System.Windows;
using System.Windows.Controls;

namespace OpenNotch;

/// <summary>Pomodoro, contagem regressiva e cronômetro.</summary>
public partial class TimersView : UserControl
{
    private readonly TimerManager _timers = Services.Instance.Timers;

    public TimersView()
    {
        InitializeComponent();
        DataContext = _timers;
        Rebuild();
    }

    private void OnMode(object sender, RoutedEventArgs e)
    {
        _timers.Mode = Enum.Parse<TimerMode>((string)((Button)sender).Tag);
        Rebuild();
    }

    private void OnToggle(object sender, RoutedEventArgs e) => _timers.Toggle();
    private void OnRestart(object sender, RoutedEventArgs e) => _timers.Restart();

    /// <summary>Destaca o modo ativo e mostra os ajustes de duração dele.</summary>
    private void Rebuild()
    {
        ModePomodoro.Opacity = _timers.Mode == TimerMode.Pomodoro ? 1 : 0.5;
        ModeCountdown.Opacity = _timers.Mode == TimerMode.Countdown ? 1 : 0.5;
        ModeStopwatch.Opacity = _timers.Mode == TimerMode.Stopwatch ? 1 : 0.5;
        Durations.Children.Clear();
        var settings = Settings.Current;
        switch (_timers.Mode)
        {
            case TimerMode.Pomodoro:
                Durations.Children.Add(Stepper(Loc.T("Foco"), () => settings.FocusMinutes, v => settings.FocusMinutes = v, 120));
                Durations.Children.Add(Stepper(Loc.T("Pausa"), () => settings.BreakMinutes, v => settings.BreakMinutes = v, 60));
                break;
            case TimerMode.Countdown:
                Durations.Children.Add(Stepper(Loc.T("Duração"), () => settings.CountdownMinutes, v => settings.CountdownMinutes = v, 600));
                break;
        }
    }

    private UIElement Stepper(string title, Func<int> get, Action<int> set, int max)
    {
        var label = new TextBlock { VerticalAlignment = VerticalAlignment.Center, Width = 110 };
        void Update() => label.Text = $"{title}: {get()} min";
        Button Make(string text, int delta)
        {
            var button = new Button { Style = (Style)FindResource("Chip"), Content = text, Padding = new Thickness(8, 1, 8, 1), Margin = new Thickness(4, 0, 0, 0) };
            button.Click += (_, _) =>
            {
                set(Math.Clamp(get() + delta, 1, max));
                Update();
                if (!_timers.IsRunning) _timers.Reset();
            };
            return button;
        }
        Update();
        var row = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(0, 0, 0, 6) };
        row.Children.Add(label);
        row.Children.Add(Make("−", -1));
        row.Children.Add(Make("+", 1));
        return row;
    }
}
