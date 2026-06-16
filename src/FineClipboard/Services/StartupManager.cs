using System;
using System.Diagnostics;
using Microsoft.Win32;

namespace FineClipboard.Services;

/// <summary>Toggles "start at login" via the per-user Run registry key.</summary>
public static class StartupManager
{
    private const string RunKey = @"Software\Microsoft\Windows\CurrentVersion\Run";
    private const string AppName = "FineClipboard";

    public static bool IsEnabled()
    {
        using RegistryKey? key = Registry.CurrentUser.OpenSubKey(RunKey, writable: false);
        return key?.GetValue(AppName) != null;
    }

    public static void SetEnabled(bool enabled)
    {
        using RegistryKey? key = Registry.CurrentUser.OpenSubKey(RunKey, writable: true)
                                 ?? Registry.CurrentUser.CreateSubKey(RunKey);
        if (key == null)
        {
            return;
        }

        if (enabled)
        {
            key.SetValue(AppName, $"\"{GetExecutablePath()}\"");
        }
        else
        {
            key.DeleteValue(AppName, throwOnMissingValue: false);
        }
    }

    private static string GetExecutablePath()
    {
        string? path = Environment.ProcessPath;
        if (!string.IsNullOrEmpty(path))
        {
            return path;
        }
        using Process p = Process.GetCurrentProcess();
        return p.MainModule?.FileName ?? AppName + ".exe";
    }
}
