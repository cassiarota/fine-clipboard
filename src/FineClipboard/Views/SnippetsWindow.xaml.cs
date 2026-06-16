using System.Linq;
using System.Windows;
using FineClipboard.Models;
using FineClipboard.Services;

namespace FineClipboard.Views;

public partial class SnippetsWindow : Window
{
    private readonly HistoryStore _store;
    private long _editingId; // 0 = new/unsaved

    public SnippetsWindow(HistoryStore store)
    {
        InitializeComponent();
        _store = store;
        Reload(selectId: 0);
    }

    private void Reload(long selectId)
    {
        List.ItemsSource = _store.GetSnippets();
        if (selectId != 0 && List.ItemsSource is System.Collections.Generic.List<Snippet> items)
        {
            List.SelectedItem = items.FirstOrDefault(s => s.Id == selectId);
        }
    }

    private void List_SelectionChanged(object sender, System.Windows.Controls.SelectionChangedEventArgs e)
    {
        if (List.SelectedItem is Snippet s)
        {
            _editingId = s.Id;
            NameBox.Text = s.Name;
            ContentBox.Text = s.Text;
        }
    }

    private void New_Click(object sender, RoutedEventArgs e)
    {
        _editingId = 0;
        List.SelectedIndex = -1;
        NameBox.Clear();
        ContentBox.Clear();
        NameBox.Focus();
    }

    private void Save_Click(object sender, RoutedEventArgs e)
    {
        string name = NameBox.Text.Trim();
        if (name.Length == 0)
        {
            MessageBox.Show("请填写片段名称。", "FineClipboard", MessageBoxButton.OK, MessageBoxImage.Information);
            return;
        }

        if (_editingId == 0)
        {
            _editingId = _store.AddSnippet(name, ContentBox.Text);
        }
        else
        {
            _store.UpdateSnippet(_editingId, name, ContentBox.Text);
        }
        Reload(selectId: _editingId);
    }

    private void Delete_Click(object sender, RoutedEventArgs e)
    {
        if (_editingId == 0)
        {
            return;
        }
        _store.DeleteSnippet(_editingId);
        _editingId = 0;
        NameBox.Clear();
        ContentBox.Clear();
        Reload(selectId: 0);
    }
}
