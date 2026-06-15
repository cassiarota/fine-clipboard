using System;
using System.IO;
using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using PasteNowWin.Models;

namespace PasteNowWin.Views;

/// <summary>Display wrapper for a clipboard item or a snippet shown in the popup list.</summary>
public sealed class PopupItemVm
{
    public ClipboardItem? Item { get; }
    public Snippet? Snippet { get; }
    public PasswordEntry? Password { get; }
    public bool IsSnippet => Snippet != null;
    public bool IsPassword => Password != null;

    public string PreviewText { get; }
    public string TimeText { get; }
    public string Glyph { get; }
    public ImageSource? Thumbnail { get; }

    /// <summary>Quick-paste number (1-9) for the first rows; empty otherwise.</summary>
    public string Badge { get; set; } = string.Empty;

    public Visibility GlyphVisibility => Thumbnail == null ? Visibility.Visible : Visibility.Collapsed;
    public Visibility PinVisibility => Item?.Pinned == true ? Visibility.Visible : Visibility.Collapsed;
    public Visibility TimeVisibility => IsSnippet ? Visibility.Collapsed : Visibility.Visible;
    public Visibility BadgeVisibility => string.IsNullOrEmpty(Badge) ? Visibility.Collapsed : Visibility.Visible;

    /// <summary>The text this row would paste (item or snippet); null for passwords (decrypted on demand).</summary>
    public string? PasteText => IsSnippet ? Snippet!.Text : IsPassword ? null : Item?.Text;

    public PopupItemVm(ClipboardItem item)
    {
        Item = item;
        TimeText = item.CreatedAt.ToLocalTime().ToString("HH:mm");
        PreviewText = CollapseWhitespace(item.Preview);

        switch (item.Type)
        {
            case ClipItemType.Image:
                Glyph = "🖼";
                Thumbnail = item.ImageData != null ? LoadThumbnail(item.ImageData) : null;
                break;
            case ClipItemType.Files:
                Glyph = "📁";
                break;
            default:
                Glyph = "T";
                break;
        }
    }

    public PopupItemVm(Snippet snippet)
    {
        Snippet = snippet;
        Glyph = "✦";
        TimeText = string.Empty;
        PreviewText = CollapseWhitespace(snippet.Name);
    }

    public PopupItemVm(PasswordEntry password)
    {
        Password = password;
        Glyph = "🔒";
        TimeText = string.Empty;
        PreviewText = CollapseWhitespace(password.Name) + "   ••••••";
    }

    private static string CollapseWhitespace(string text)
    {
        string s = text.Replace('\r', ' ').Replace('\n', ' ').Replace('\t', ' ').Trim();
        return s.Length > 160 ? s[..160] + "…" : s;
    }

    private static ImageSource? LoadThumbnail(byte[] png)
    {
        try
        {
            var bmp = new BitmapImage();
            using var ms = new MemoryStream(png);
            bmp.BeginInit();
            bmp.CacheOption = BitmapCacheOption.OnLoad;
            bmp.DecodePixelWidth = 80;
            bmp.StreamSource = ms;
            bmp.EndInit();
            bmp.Freeze();
            return bmp;
        }
        catch
        {
            return null;
        }
    }
}
