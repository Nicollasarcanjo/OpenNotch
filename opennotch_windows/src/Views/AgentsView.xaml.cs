using System.Windows;
using System.Windows.Controls;

namespace OpenNotch;

/// <summary>Sessões de agentes de IA, com o aviso de tarefa concluída no topo.</summary>
public partial class AgentsView : UserControl
{
    private readonly AgentMonitor _agents = Services.Instance.Agents;

    public AgentsView()
    {
        InitializeComponent();
        DataContext = _agents;
        _agents.Providers.CollectionChanged += (_, _) => UpdateEmpty();
        UpdateEmpty();
    }

    private void UpdateEmpty() =>
        Empty.Visibility = _agents.Providers.Count == 0 ? Visibility.Visible : Visibility.Collapsed;

    public void ShowBanner(string text)
    {
        BannerText.Text = "✓  " + text;
        Banner.Visibility = Visibility.Visible;
    }

    public void ClearBanner() => Banner.Visibility = Visibility.Collapsed;
}
