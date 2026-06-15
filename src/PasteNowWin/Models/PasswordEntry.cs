namespace PasteNowWin.Models;

/// <summary>A stored password entry. The secret itself lives encrypted in the database;
/// only id + display name are carried in memory for listing.</summary>
public sealed class PasswordEntry
{
    public long Id { get; set; }
    public string Name { get; set; } = string.Empty;
}
