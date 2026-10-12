using System.Globalization;
using System.Windows;
using System.Windows.Data;

namespace OpenNotch;

/// <summary>true vira visível (ou o contrário, com Invert). Aceita bool, texto e objeto nulo.</summary>
public sealed class BoolToVisibility : IValueConverter
{
    public bool Invert { get; set; }

    public object Convert(object? value, Type targetType, object? parameter, CultureInfo culture)
    {
        var on = value switch
        {
            bool flag => flag,
            string text => text.Length > 0,
            null => false,
            _ => true,
        };
        return on != Invert ? Visibility.Visible : Visibility.Collapsed;
    }

    public object ConvertBack(object? value, Type targetType, object? parameter, CultureInfo culture) =>
        throw new NotSupportedException();
}
