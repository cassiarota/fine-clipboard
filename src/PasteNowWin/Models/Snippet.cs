namespace PasteNowWin.Models;

/// <summary>A named, reusable text snippet (signature, address, template, …).</summary>
public sealed class Snippet
{
    public long Id { get; set; }
    public string Name { get; set; } = string.Empty;
    public string Text { get; set; } = string.Empty;
}
