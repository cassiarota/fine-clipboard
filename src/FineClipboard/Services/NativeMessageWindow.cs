using System;
using System.Windows.Interop;

namespace FineClipboard.Services;

/// <summary>
/// A hidden message-only window (HWND_MESSAGE) that receives WM_* notifications.
/// Both the clipboard listener and the global hotkeys hang off this single HWND.
/// </summary>
public sealed class NativeMessageWindow : IDisposable
{
    private const int HWND_MESSAGE = -3;

    private readonly HwndSource _source;

    /// <summary>Raised for every window message: (msg, wParam, lParam).</summary>
    public event Action<int, IntPtr, IntPtr>? MessageReceived;

    public IntPtr Handle => _source.Handle;

    public NativeMessageWindow()
    {
        var parameters = new HwndSourceParameters("FineClipboardMessageWindow")
        {
            Width = 0,
            Height = 0,
            ParentWindow = new IntPtr(HWND_MESSAGE),
            WindowStyle = 0,
        };

        _source = new HwndSource(parameters);
        _source.AddHook(WndProc);
    }

    private IntPtr WndProc(IntPtr hwnd, int msg, IntPtr wParam, IntPtr lParam, ref bool handled)
    {
        MessageReceived?.Invoke(msg, wParam, lParam);
        return IntPtr.Zero;
    }

    public void Dispose()
    {
        _source.RemoveHook(WndProc);
        _source.Dispose();
    }
}
