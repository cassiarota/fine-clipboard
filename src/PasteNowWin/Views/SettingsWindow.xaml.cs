using System.Reflection;
using System.Windows;
using PasteNowWin.Services;

namespace PasteNowWin.Views;

public partial class SettingsWindow : Window
{
    private readonly HistoryStore _store;

    public SettingsWindow(HistoryStore store)
    {
        InitializeComponent();
        _store = store;

        string version = Assembly.GetExecutingAssembly().GetName().Version?.ToString(3) ?? "0.1.0";
        VersionText.Text = $"版本 {version}";
        StartupCheck.IsChecked = StartupManager.IsEnabled();
        RefreshCount();
    }

    private void RefreshCount() => CountText.Text = $"已保存 {_store.Count()} 条历史记录";

    private void StartupCheck_Click(object sender, RoutedEventArgs e) =>
        StartupManager.SetEnabled(StartupCheck.IsChecked == true);

    private void ClearKeepPinned_Click(object sender, RoutedEventArgs e)
    {
        if (Confirm("确定清空历史吗?(置顶项会保留)"))
        {
            _store.Clear(keepPinned: true);
            RefreshCount();
        }
    }

    private void ClearAll_Click(object sender, RoutedEventArgs e)
    {
        if (Confirm("确定清空全部历史吗?(包括置顶项,不可恢复)"))
        {
            _store.Clear(keepPinned: false);
            RefreshCount();
        }
    }

    private static bool Confirm(string message) =>
        MessageBox.Show(message, "PasteNowWin", MessageBoxButton.OKCancel, MessageBoxImage.Question)
            == MessageBoxResult.OK;
}
