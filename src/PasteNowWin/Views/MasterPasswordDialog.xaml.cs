using System.Windows;

namespace PasteNowWin.Views;

public partial class MasterPasswordDialog : Window
{
    public string Password => Box.Password;

    public MasterPasswordDialog(string title, string prompt)
    {
        InitializeComponent();
        Title = title;
        PromptText.Text = prompt;
        Loaded += (_, _) => Box.Focus();
    }

    private void Ok_Click(object sender, RoutedEventArgs e) => DialogResult = true;
}
