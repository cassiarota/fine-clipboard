using System;

namespace FineClipboard.Models;

/// <summary>A single clipboard history entry.</summary>
public sealed class ClipboardItem
{
    public long Id { get; set; }

    public ClipItemType Type { get; set; }

    /// <summary>For Text: the full text. For Files: newline-joined absolute paths. Null for Image.</summary>
    public string? Text { get; set; }

    /// <summary>PNG-encoded bytes for Image entries; null otherwise.</summary>
    public byte[]? ImageData { get; set; }

    /// <summary>Short text shown in the popup list.</summary>
    public string Preview { get; set; } = string.Empty;

    /// <summary>Process name of the app that owned the foreground when copied (best effort).</summary>
    public string? SourceApp { get; set; }

    public bool Pinned { get; set; }

    /// <summary>UTC creation/last-used time.</summary>
    public DateTime CreatedAt { get; set; }

    public string[] FilePaths =>
        Type == ClipItemType.Files && !string.IsNullOrEmpty(Text)
            ? Text.Split('\n', StringSplitOptions.RemoveEmptyEntries)
            : Array.Empty<string>();
}
