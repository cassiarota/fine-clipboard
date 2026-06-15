using System.Windows;
using System.Windows.Media;
using Microsoft.Win32;

namespace PasteNowWin.Services;

/// <summary>
/// Applies a light/dark colour set as application resources. The popup references these
/// via DynamicResource, so changing them re-themes it live. (Settings stays system-default.)
/// </summary>
public static class ThemeManager
{
    public static void Apply(string? mode)
    {
        if (IsDark(mode))
        {
            Set("PopupBackground", "#1E1E22");
            Set("SurfaceBackground", "#2C2C31");
            Set("SurfaceHover", "#3A3A41");
            Set("SurfaceSelected", "#34507A");
            Set("TextPrimary", "#ECECEC");
            Set("TextSecondary", "#9AA0A6");
            Set("BorderBrush", "#33FFFFFF");
            Set("AccentBrush", "#3B82F6");
        }
        else
        {
            Set("PopupBackground", "#F4F4F6");
            Set("SurfaceBackground", "#FFFFFF");
            Set("SurfaceHover", "#EAF2FF");
            Set("SurfaceSelected", "#DCEBFF");
            Set("TextPrimary", "#222222");
            Set("TextSecondary", "#9A9A9A");
            Set("BorderBrush", "#22000000");
            Set("AccentBrush", "#3B82F6");
        }
    }

    private static bool IsDark(string? mode)
    {
        if (mode == "dark") return true;
        if (mode == "light") return false;

        // "system" (or unset): follow the Windows app theme.
        try
        {
            using RegistryKey? key = Registry.CurrentUser.OpenSubKey(
                @"Software\Microsoft\Windows\CurrentVersion\Themes\Personalize");
            if (key?.GetValue("AppsUseLightTheme") is int v)
            {
                return v == 0; // 0 = dark, 1 = light
            }
        }
        catch
        {
            // ignore — fall back to light
        }
        return false;
    }

    private static void Set(string key, string hex)
    {
        var brush = (SolidColorBrush)new BrushConverter().ConvertFromString(hex)!;
        brush.Freeze();
        Application.Current.Resources[key] = brush;
    }
}
