using System.Windows;
using System.Windows.Controls;

namespace OpenNotch;

/// <summary>Aba Textos: anotações à esquerda, textos copiados à direita e uma busca para os dois.</summary>
public partial class TextsView : UserControl
{
    private readonly NotesStore _notes = Services.Instance.Notes;
    private readonly ClipboardManager _clipboard = Services.Instance.Clipboard;
    private Note? _editing;

    public TextsView()
    {
        InitializeComponent();
        var settings = Settings.Current;
        if (!settings.ModNotes)
        {
            NotesPanel.Visibility = Visibility.Collapsed;
            NotesColumn.Width = new GridLength(0);
        }
        if (!settings.ModClipboard)
        {
            CopiedPanel.Visibility = Visibility.Collapsed;
            CopiedColumn.Width = new GridLength(0);
        }
        _notes.Notes.CollectionChanged += (_, _) => Refresh();
        _clipboard.Items.CollectionChanged += (_, _) => Refresh();
        Refresh();
    }

    /// <summary>Filtra as duas listas pelo texto da busca, sem diferenciar maiúsculas.</summary>
    private void Refresh()
    {
        var query = Search.Text.Trim();
        bool Matches(string text) => query.Length == 0 || text.Contains(query, StringComparison.CurrentCultureIgnoreCase);
        NotesItems.ItemsSource = _notes.Notes.Where(n => Matches(n.Text)).ToList();
        CopiedItems.ItemsSource = _clipboard.Items.Where(c => Matches(c.Text)).ToList();
    }

    private static T? Item<T>(object sender) where T : class
    {
        if (sender is MenuItem { Parent: ContextMenu { PlacementTarget: FrameworkElement target } }) return target.DataContext as T;
        return (sender as FrameworkElement)?.DataContext as T;
    }

    private void OnSearch(object sender, TextChangedEventArgs e)
    {
        if (SearchHint == null) return;   // ainda montando a tela
        SearchHint.Visibility = Search.Text.Length == 0 ? Visibility.Visible : Visibility.Collapsed;
        Refresh();
    }

    // Anotações

    private void OnAdd(object sender, RoutedEventArgs e) => Edit(_notes.Add());

    private void OnOpenNote(object sender, RoutedEventArgs e)
    {
        if (Item<Note>(sender) is { } note) Edit(note);
    }

    private void Edit(Note? note)
    {
        // Anotações criadas e deixadas em branco não ficam na lista.
        if (_editing is { } previous && note == null && string.IsNullOrWhiteSpace(previous.Text)) _notes.Delete(previous);
        _editing = note;
        var editing = note != null;
        Editor.Visibility = editing ? Visibility.Visible : Visibility.Collapsed;
        NotesList.Visibility = editing ? Visibility.Collapsed : Visibility.Visible;
        AddButton.Visibility = editing ? Visibility.Collapsed : Visibility.Visible;
        DoneButton.Visibility = DeleteButton.Visibility = editing ? Visibility.Visible : Visibility.Collapsed;
        NotesTitle.Text = editing ? Loc.T("Anotação") : Loc.T("Anotações");
        if (note != null)
        {
            Editor.Text = note.Text;
            Editor.Focus();
        }
        else
        {
            _notes.Save();
            Refresh();
        }
    }

    private void OnEdit(object sender, TextChangedEventArgs e)
    {
        if (_editing == null || _editing.Text == Editor.Text) return;
        _editing.Text = Editor.Text;
        _editing.Updated = DateTime.Now;
    }

    private void OnDone(object sender, RoutedEventArgs e) => Edit(null);

    private void OnDelete(object sender, RoutedEventArgs e)
    {
        if (_editing is { } note) _notes.Delete(note);
        _editing = null;
        Edit(null);
    }

    // Textos copiados

    private void OnCopy(object sender, RoutedEventArgs e)
    {
        if (Item<ClipItem>(sender) is { } item) _clipboard.Copy(item);
    }

    private void OnSaveAsNote(object sender, RoutedEventArgs e)
    {
        if (Item<ClipItem>(sender) is { } item) _notes.Add(item.Text);
    }

    private void OnRemoveCopied(object sender, RoutedEventArgs e)
    {
        if (Item<ClipItem>(sender) is { } item) _clipboard.Remove(item);
    }

    private void OnClear(object sender, RoutedEventArgs e) => _clipboard.Clear();
}
