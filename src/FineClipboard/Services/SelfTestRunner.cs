using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Threading;
using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Threading;
using FineClipboard.Models;
using FineClipboard.Views;

namespace FineClipboard.Services;

/// <summary>Isolated release smoke test, activated only by the --self-test command-line flag.</summary>
internal static class SelfTestRunner
{
    public static int Run(string? reportPath)
    {
        string dir = Path.Combine(Path.GetTempPath(), "FineClipboard-selftest-" + Guid.NewGuid().ToString("N"));
        Environment.SetEnvironmentVariable("FINECLIPBOARD_DATA_DIR", dir);
        var results = new List<string>();
        int failures = 0;

        void Check(string name, bool passed, string? detail = null)
        {
            results.Add($"{(passed ? "PASS" : "FAIL")} {name}{(detail == null ? "" : ": " + detail)}");
            if (!passed) failures++;
        }

        try
        {
            using var store = new HistoryStore();
            store.SetSetting(HistoryStore.ThemeKey, "dark");
            Check("settings round-trip", store.GetSetting(HistoryStore.ThemeKey) == "dark");

            long textId = store.Add(Item(ClipItemType.Text, "self-test searchable text", null, "self-test text", "<b>rich</b>", "{\\rtf1 rich}"));
            long fileId = store.Add(Item(ClipItemType.Files, "C:\\Temp\\one.txt\nC:\\Temp\\two.txt", null, "2 files"));
            byte[] png = MakePng(160, 100, Colors.CornflowerBlue);
            long imageId = store.Add(Item(ClipItemType.Image, null, png, "image 160x100"));
            Check("text/image/file history", store.Count() == 3 && store.GetAll().Select(x => x.Type).Distinct().Count() == 3);
            Check("search and rich text", store.Search("searchable").Any(x => x.Id == textId && x.HasRichText));
            Check("file paths", store.GetAll().Single(x => x.Id == fileId).FilePaths.Length == 2);
            Check("image bytes", store.GetAll().Single(x => x.Id == imageId).ImageData?.Length > 20);

            store.TogglePin(textId);
            Check("favorite", store.GetAll().First(x => x.Id == textId).Pinned);
            long listId = store.AddList("Release test");
            store.AssignToList(fileId, listId);
            Check("custom list", store.GetByList(listId).Single().Id == fileId);
            store.RenameList(listId, "Renamed test");
            Check("rename list", store.GetLists().Any(x => x.Id == listId && x.Name == "Renamed test"));

            long snippetId = store.AddSnippet("Greeting", "hello world");
            store.UpdateSnippet(snippetId, "Greeting 2", "hello again");
            Check("snippet CRUD", store.GetSnippets().Any(x => x.Id == snippetId && x.Text == "hello again"));
            store.DeleteSnippet(snippetId);
            Check("snippet delete", store.GetSnippets().All(x => x.Id != snippetId));

            var vault = new PasswordVault(store);
            vault.SetMasterPassword("self-test-master-one");
            long passwordId = vault.AddEntry("API", "secret-value");
            Check("password encrypt/decrypt", vault.Reveal(passwordId) == "secret-value");
            vault.Lock();
            Check("password lock/wrong password", vault.Reveal(passwordId) == null && !vault.Unlock("wrong"));
            Check("password unlock", vault.Unlock("self-test-master-one") && vault.Reveal(passwordId) == "secret-value");
            Check("password change", vault.ChangeMasterPassword("self-test-master-one", "self-test-master-two"));
            vault.Lock();
            Check("password new master", vault.Unlock("self-test-master-two") && vault.Reveal(passwordId) == "secret-value");

            using var messageWindow = new NativeMessageWindow();
            using var monitor = new ClipboardMonitor(messageWindow);
            ClipboardItem? captured = null;
            monitor.ItemCaptured += item => captured = item;
            Clipboard.SetText("monitor self-test");
            PumpUntil(() => captured != null, TimeSpan.FromSeconds(2));
            Check("clipboard text monitor", captured?.Text == "monitor self-test");
            captured = null; monitor.Paused = true; Clipboard.SetText("paused self-test"); Pump(TimeSpan.FromMilliseconds(250));
            Check("pause recording", captured == null);
            monitor.Paused = false;

            var paste = new PasteService(monitor, store);
            ClipboardItem richItem = store.GetAll().Single(x => x.Id == textId);
            paste.CopyToClipboard(richItem);
            Check("clipboard rich/plain write", Clipboard.GetText() == richItem.Text && Clipboard.ContainsData(System.Windows.DataFormats.Html));

            ScreenshotService.CaptureFullscreen();
            Pump(TimeSpan.FromMilliseconds(150));
            Check("fullscreen screenshot", Clipboard.ContainsImage() && Clipboard.GetImage() is { PixelWidth: > 0, PixelHeight: > 0 });

            var preview = new ScreenshotPreviewWindow(png) { ShowActivated = false, Left = -32000, Top = -32000 };
            preview.Show(); preview.UpdateLayout();
            MethodInfo? render = typeof(ScreenshotPreviewWindow).GetMethods(BindingFlags.Instance | BindingFlags.NonPublic | BindingFlags.DeclaredOnly)
                .SingleOrDefault(method => method.Name == "Render" && method.GetParameters().Length == 0);
            BitmapSource? rendered = render?.Invoke(preview, null) as BitmapSource;
            Check("screenshot editor render", rendered?.PixelWidth == 160 && rendered.PixelHeight == 100);
            preview.Close();

            var selector = new ScreenshotCaptureWindow(() => { }) { ShowActivated = false };
            selector.Show(); Pump(TimeSpan.FromMilliseconds(100));
            Check("smart selector opens", selector.IsVisible && selector.ActualWidth > 0 && selector.ActualHeight > 0);
            selector.Close();

            store.Clear(keepPinned: true);
            Check("clear keeps favorites", store.Count() == 1 && store.GetAll().Single().Id == textId);
            store.Clear(keepPinned: false);
            Check("clear all", store.Count() == 0);
        }
        catch (Exception ex)
        {
            failures++;
            results.Add("FAIL unhandled: " + ex);
        }
        finally
        {
            Environment.SetEnvironmentVariable("FINECLIPBOARD_DATA_DIR", null);
            try { Directory.Delete(dir, recursive: true); } catch { }
        }

        results.Add($"SUMMARY failures={failures}");
        string output = string.Join(Environment.NewLine, results);
        if (!string.IsNullOrWhiteSpace(reportPath)) File.WriteAllText(reportPath, output);
        return failures == 0 ? 0 : 1;
    }

    private static ClipboardItem Item(ClipItemType type, string? text, byte[]? image, string preview, string? html = null, string? rtf = null) => new()
    {
        Type = type, Text = text, ImageData = image, Preview = preview, Html = html, Rtf = rtf,
        SourceApp = "SelfTest", CreatedAt = DateTime.UtcNow,
    };

    private static byte[] MakePng(int width, int height, Color color)
    {
        var visual = new DrawingVisual();
        using (DrawingContext dc = visual.RenderOpen()) dc.DrawRectangle(new SolidColorBrush(color), null, new Rect(0, 0, width, height));
        var bitmap = new RenderTargetBitmap(width, height, 96, 96, PixelFormats.Pbgra32);
        bitmap.Render(visual);
        var encoder = new PngBitmapEncoder(); encoder.Frames.Add(BitmapFrame.Create(bitmap));
        using var stream = new MemoryStream(); encoder.Save(stream); return stream.ToArray();
    }

    private static void PumpUntil(Func<bool> done, TimeSpan timeout)
    {
        DateTime end = DateTime.UtcNow + timeout;
        while (!done() && DateTime.UtcNow < end) Pump(TimeSpan.FromMilliseconds(40));
    }

    private static void Pump(TimeSpan duration)
    {
        var frame = new DispatcherFrame();
        var timer = new DispatcherTimer(DispatcherPriority.Background) { Interval = duration };
        timer.Tick += (_, _) => { timer.Stop(); frame.Continue = false; };
        timer.Start(); Dispatcher.PushFrame(frame);
    }
}
