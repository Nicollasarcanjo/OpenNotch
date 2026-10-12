using System.Windows.Controls;

namespace OpenNotch;

/// <summary>CPU, memória, disco, bateria e rede.</summary>
public partial class SystemView : UserControl
{
    public SystemView()
    {
        InitializeComponent();
        DataContext = Services.Instance.System;
    }
}
