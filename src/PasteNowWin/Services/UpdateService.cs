using System;
using System.Net.Http;
using System.Reflection;
using System.Text.Json;
using System.Threading.Tasks;

namespace PasteNowWin.Services;

/// <summary>Result of an update check.</summary>
public sealed record UpdateInfo(string Version, string Url);

/// <summary>
/// Checks the GitHub Releases API for a newer version. No token is used (the repo must be
/// public for this to return results); failures are swallowed and treated as "no update".
/// </summary>
public sealed class UpdateService
{
    private const string LatestReleaseApi =
        "https://api.github.com/repos/cassiarota/win-paste/releases/latest";

    private static readonly HttpClient Http = new() { Timeout = TimeSpan.FromSeconds(10) };

    public async Task<UpdateInfo?> CheckAsync()
    {
        try
        {
            using var request = new HttpRequestMessage(HttpMethod.Get, LatestReleaseApi);
            request.Headers.UserAgent.ParseAdd("PasteNowWin-UpdateCheck");
            request.Headers.Accept.ParseAdd("application/vnd.github+json");

            using HttpResponseMessage response = await Http.SendAsync(request).ConfigureAwait(false);
            if (!response.IsSuccessStatusCode)
            {
                return null;
            }

            string json = await response.Content.ReadAsStringAsync().ConfigureAwait(false);
            using JsonDocument doc = JsonDocument.Parse(json);

            string tag = doc.RootElement.TryGetProperty("tag_name", out JsonElement t) ? t.GetString() ?? "" : "";
            string url = doc.RootElement.TryGetProperty("html_url", out JsonElement u) ? u.GetString() ?? "" : "";

            Version? latest = ParseVersion(tag);
            Version current = Normalize(Assembly.GetExecutingAssembly().GetName().Version);

            if (latest != null && latest > current && !string.IsNullOrEmpty(url))
            {
                return new UpdateInfo(tag, url);
            }
            return null;
        }
        catch
        {
            return null;
        }
    }

    private static Version? ParseVersion(string tag)
    {
        string s = tag.TrimStart('v', 'V').Trim();
        return Version.TryParse(s, out Version? v) ? Normalize(v) : null;
    }

    /// <summary>Reduces a version to Major.Minor.Build so 0.2.0 and 0.2.0.0 compare equal.</summary>
    private static Version Normalize(Version? v)
    {
        if (v == null)
        {
            return new Version(0, 0, 0);
        }
        return new Version(v.Major, v.Minor, v.Build < 0 ? 0 : v.Build);
    }
}
