using System.Collections.Generic;
using System.Linq;
using System.Windows;
using FineClipboard.Models;
using FineClipboard.Services;

namespace FineClipboard.Views;

public partial class PasswordsWindow : Window
{
    private readonly PasswordVault _vault;
    private long _editingId; // 0 = new/unsaved

    public PasswordsWindow(PasswordVault vault)
    {
        InitializeComponent();
        _vault = vault;
        Reload(selectId: 0);
    }

    private void Reload(long selectId)
    {
        List.ItemsSource = _vault.GetEntries();
        if (selectId != 0 && List.ItemsSource is List<PasswordEntry> items)
        {
            List.SelectedItem = items.FirstOrDefault(s => s.Id == selectId);
        }
    }

    private void List_SelectionChanged(object sender, System.Windows.Controls.SelectionChangedEventArgs e)
    {
        if (List.SelectedItem is PasswordEntry entry)
        {
            _editingId = entry.Id;
            NameBox.Text = entry.Name;
            SetSecret(_vault.Reveal(entry.Id) ?? string.Empty);
        }
    }

    private void New_Click(object sender, RoutedEventArgs e)
    {
        _editingId = 0;
        List.SelectedIndex = -1;
        NameBox.Clear();
        SetSecret(string.Empty);
        NameBox.Focus();
    }

    private void Save_Click(object sender, RoutedEventArgs e)
    {
        string name = NameBox.Text.Trim();
        if (name.Length == 0)
        {
            MessageBox.Show("请填写名称。", "FineClipboard", MessageBoxButton.OK, MessageBoxImage.Information);
            return;
        }

        string secret = GetSecret();
        if (_editingId == 0)
        {
            _editingId = _vault.AddEntry(name, secret);
        }
        else
        {
            _vault.UpdateEntry(_editingId, name, secret);
        }
        Reload(selectId: _editingId);
    }

    private void Delete_Click(object sender, RoutedEventArgs e)
    {
        if (_editingId == 0)
        {
            return;
        }
        _vault.DeleteEntry(_editingId);
        _editingId = 0;
        NameBox.Clear();
        SetSecret(string.Empty);
        Reload(selectId: 0);
    }

    private void ShowCheck_Click(object sender, RoutedEventArgs e)
    {
        if (ShowCheck.IsChecked == true)
        {
            SecretText.Text = SecretBox.Password;
            SecretText.Visibility = Visibility.Visible;
            SecretBox.Visibility = Visibility.Collapsed;
        }
        else
        {
            SecretBox.Password = SecretText.Text;
            SecretBox.Visibility = Visibility.Visible;
            SecretText.Visibility = Visibility.Collapsed;
        }
    }

    private string GetSecret() => ShowCheck.IsChecked == true ? SecretText.Text : SecretBox.Password;

    private void SetSecret(string value)
    {
        SecretBox.Password = value;
        SecretText.Text = value;
    }
}
