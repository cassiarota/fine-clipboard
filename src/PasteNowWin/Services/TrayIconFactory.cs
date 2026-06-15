using System;
using SD = System.Drawing;

namespace PasteNowWin.Services;

/// <summary>
/// Builds the tray icon at runtime so the project ships without a binary .ico asset.
/// Draws an orange rounded tile with a white asterisk (a nod to PasteNow's mark).
/// </summary>
internal static class TrayIconFactory
{
    public static SD.Icon Create()
    {
        using var bmp = new SD.Bitmap(32, 32);
        using (SD.Graphics g = SD.Graphics.FromImage(bmp))
        {
            g.SmoothingMode = SD.Drawing2D.SmoothingMode.AntiAlias;
            g.Clear(SD.Color.Transparent);

            using var fill = new SD.SolidBrush(SD.Color.FromArgb(0xF5, 0x6A, 0x36));
            g.FillEllipse(fill, 2, 2, 28, 28);

            using var pen = new SD.Pen(SD.Color.White, 2.4f) { StartCap = SD.Drawing2D.LineCap.Round, EndCap = SD.Drawing2D.LineCap.Round };
            const float cx = 16f, cy = 16f, r = 7f;
            for (int i = 0; i < 6; i++)
            {
                double a = Math.PI * i / 3.0;
                float dx = (float)(r * Math.Cos(a));
                float dy = (float)(r * Math.Sin(a));
                g.DrawLine(pen, cx - dx, cy - dy, cx + dx, cy + dy);
            }
        }

        // Icon.FromHandle does not own the HICON; clone so we can free the handle immediately.
        IntPtr hIcon = bmp.GetHicon();
        try
        {
            using SD.Icon temp = SD.Icon.FromHandle(hIcon);
            return (SD.Icon)temp.Clone();
        }
        finally
        {
            DestroyIcon(hIcon);
        }
    }

    [System.Runtime.InteropServices.DllImport("user32.dll", SetLastError = true)]
    private static extern bool DestroyIcon(IntPtr handle);
}
