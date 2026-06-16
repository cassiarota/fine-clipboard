using System.Windows;

namespace FineClipboard.Views;

public partial class EditWindow : Window
{
    public string ResultText { get; private set; } = string.Empty;

    public EditWindow(string text)
    {
        InitializeComponent();
        Editor.Text = text;
        Loaded += (_, _) =>
        {
            Editor.Focus();
            Editor.CaretIndex = Editor.Text.Length;
        };
    }

    private void Ok_Click(object sender, RoutedEventArgs e)
    {
        ResultText = Editor.Text;
        DialogResult = true;
    }
}
