using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Shapes;
using FineClipboard.Services;
using Microsoft.Win32;

namespace FineClipboard.Views;

/// <summary>Non-destructive screenshot annotation surface with full editing history and PNG export/copy.</summary>
public partial class ScreenshotPreviewWindow : Window
{
    private sealed record EditorAction(UIElement Item, bool Added, int Index);

    private readonly BitmapSource _bitmap;
    private readonly BitmapSource _pixelBitmap;
    private readonly List<UIElement> _operations = new();
    private readonly Stack<EditorAction> _history = new();
    private readonly Stack<EditorAction> _redo = new();
    private string _tool = "shape";
    private string _shape = "rect";
    private string _line = "arrow";
    private Color _color = Color.FromRgb(245, 34, 45);
    private double _penWidth = 5;
    private bool _roundPen = true;
    private Point _start;
    private UIElement? _active;
    private bool _drawing;

    public ScreenshotPreviewWindow(byte[] png)
    {
        InitializeComponent();
        Icon = AppIconFactory.CreateImageSource();
        _bitmap = LoadBitmap(png);
        _pixelBitmap = new FormatConvertedBitmap(_bitmap, PixelFormats.Bgra32, null, 0);
        PreviewImage.Source = _bitmap;
        EditorSurface.Width = AnnotationCanvas.Width = _bitmap.PixelWidth;
        EditorSurface.Height = AnnotationCanvas.Height = _bitmap.PixelHeight;
        ShapeTool.IsChecked = true;
        UpdateHistoryButtons();
    }

    private SolidColorBrush CurrentBrush() => new(_color);

    private void Tool_Checked(object sender, RoutedEventArgs e)
    {
        if (sender is not ToggleButton selected || selected.Tag is not string tool) return;
        _tool = tool;
        foreach (ToggleButton button in new[] { ShapeTool, LineTool, PenTool, MosaicTool, TextTool, EraserTool })
            if (!ReferenceEquals(button, selected)) button.IsChecked = false;
        selected.IsChecked = true;
        ColorTool.IsChecked = false;
        AnnotationCanvas.Cursor = tool == "text" ? Cursors.IBeam : tool == "eraser" ? Cursors.Hand : Cursors.Cross;
    }

    private void SelectTool(ToggleButton button)
    {
        button.IsChecked = true;
        Tool_Checked(button, new RoutedEventArgs());
    }

    private void ShapeMenu_Click(object sender, RoutedEventArgs e) { ShapePopup.IsOpen = true; }
    private void LineMenu_Click(object sender, RoutedEventArgs e) { LinePopup.IsOpen = true; }
    private void PenMenu_Click(object sender, RoutedEventArgs e) { PenPopup.IsOpen = true; }
    private void ColorMenu_Click(object sender, RoutedEventArgs e) { ColorPopup.IsOpen = true; ColorTool.IsChecked = false; }

    private void ShapeChoice_Click(object sender, RoutedEventArgs e)
    {
        if (sender is Button { Tag: string value }) _shape = value;
        ShapePopup.IsOpen = false; SelectTool(ShapeTool);
    }

    private void LineChoice_Click(object sender, RoutedEventArgs e)
    {
        if (sender is Button { Tag: string value }) _line = value;
        LinePopup.IsOpen = false; SelectTool(LineTool);
    }

    private void ColorChoice_Click(object sender, RoutedEventArgs e)
    {
        if (sender is Button { Tag: string value })
        {
            _color = (Color)ColorConverter.ConvertFromString(value);
            CurrentColorDot.Fill = CurrentBrush();
        }
        ColorPopup.IsOpen = false;
    }

    private void PenWidth_Click(object sender, RoutedEventArgs e)
    {
        if (sender is Button { Tag: string value } && double.TryParse(value, out double width)) _penWidth = width;
        SelectTool(PenTool);
    }

    private void PenShape_Click(object sender, RoutedEventArgs e)
    {
        if (sender is Button { Tag: string value }) _roundPen = value == "round";
        PenPopup.IsOpen = false; SelectTool(PenTool);
    }

    private void Editor_MouseLeftButtonDown(object sender, MouseButtonEventArgs e)
    {
        Point p = Clamp(e.GetPosition(AnnotationCanvas));
        if (_tool == "eraser") { EraseAt(p); e.Handled = true; return; }
        if (_tool == "text") { AddTextEditor(p); e.Handled = true; return; }

        _start = p; _drawing = true; AnnotationCanvas.CaptureMouse();
        Brush brush = CurrentBrush();
        _active = _tool switch
        {
            "shape" when _shape == "ellipse" => new Ellipse { Stroke = brush, StrokeThickness = _penWidth, Fill = Brushes.Transparent },
            "shape" => new Rectangle { Stroke = brush, StrokeThickness = _penWidth, Fill = Brushes.Transparent,
                RadiusX = _shape == "roundedRect" ? 14 : 0, RadiusY = _shape == "roundedRect" ? 14 : 0 },
            "line" => new Canvas { Width = _bitmap.PixelWidth, Height = _bitmap.PixelHeight },
            "pen" => new Polyline { Stroke = brush, StrokeThickness = _penWidth, StrokeLineJoin = _roundPen ? PenLineJoin.Round : PenLineJoin.Bevel,
                StrokeStartLineCap = _roundPen ? PenLineCap.Round : PenLineCap.Square, StrokeEndLineCap = _roundPen ? PenLineCap.Round : PenLineCap.Square },
            "mosaic" => new Canvas { Width = _bitmap.PixelWidth, Height = _bitmap.PixelHeight },
            _ => null,
        };
        if (_active == null) { _drawing = false; return; }
        AddOperation(_active);
        if (_active is Polyline polyline) polyline.Points.Add(p);
        if (_tool == "mosaic") AddMosaicBlock((Canvas)_active, p);
        e.Handled = true;
    }

    private void Editor_MouseMove(object sender, MouseEventArgs e)
    {
        if (!_drawing || _active == null || e.LeftButton != MouseButtonState.Pressed) return;
        Point p = Clamp(e.GetPosition(AnnotationCanvas));
        if (_active is Shape shape)
        {
            Canvas.SetLeft(shape, Math.Min(_start.X, p.X)); Canvas.SetTop(shape, Math.Min(_start.Y, p.Y));
            shape.Width = Math.Abs(p.X - _start.X); shape.Height = Math.Abs(p.Y - _start.Y);
        }
        else if (_tool == "line" && _active is Canvas lineCanvas) DrawLine(lineCanvas, _start, p, _line == "arrow", CurrentBrush(), _penWidth);
        else if (_active is Polyline line) line.Points.Add(p);
        else if (_tool == "mosaic" && _active is Canvas mosaic) AddMosaicBlock(mosaic, p);
    }

    private void Editor_MouseLeftButtonUp(object sender, MouseButtonEventArgs e)
    {
        if (!_drawing) return;
        _drawing = false; _active = null; AnnotationCanvas.ReleaseMouseCapture(); e.Handled = true;
    }

    private void AddOperation(UIElement item)
    {
        int index = _operations.Count;
        AnnotationCanvas.Children.Add(item); _operations.Add(item);
        _history.Push(new EditorAction(item, true, index)); _redo.Clear(); UpdateHistoryButtons();
    }

    private void AddTextEditor(Point point)
    {
        var box = new TextBox
        {
            Text = "输入文字", Foreground = CurrentBrush(), Background = new SolidColorBrush(Color.FromArgb(185, 255, 255, 255)),
            BorderBrush = CurrentBrush(), BorderThickness = new Thickness(1), FontSize = Math.Max(18, _bitmap.PixelWidth / 60.0),
            MinWidth = 100, Padding = new Thickness(3), AcceptsReturn = true,
        };
        box.LostKeyboardFocus += (_, _) => { box.Background = Brushes.Transparent; box.BorderBrush = Brushes.Transparent; };
        Canvas.SetLeft(box, point.X); Canvas.SetTop(box, point.Y); AddOperation(box); box.Focus(); box.SelectAll();
    }

    private void EraseAt(Point point)
    {
        HitTestResult? hit = VisualTreeHelper.HitTest(AnnotationCanvas, point);
        DependencyObject? current = hit?.VisualHit;
        while (current != null && VisualTreeHelper.GetParent(current) != AnnotationCanvas) current = VisualTreeHelper.GetParent(current);
        if (current is UIElement item)
        {
            int index = _operations.IndexOf(item);
            if (index < 0) return;
            _operations.RemoveAt(index); AnnotationCanvas.Children.Remove(item);
            _history.Push(new EditorAction(item, false, index)); _redo.Clear(); UpdateHistoryButtons(); Hint.Text = "已擦除一项标注";
        }
    }

    private void AddMosaicBlock(Canvas layer, Point p)
    {
        int size = Math.Max(12, (int)(_penWidth * 4));
        int x = Math.Clamp((int)p.X / size * size, 0, Math.Max(0, _bitmap.PixelWidth - size));
        int y = Math.Clamp((int)p.Y / size * size, 0, Math.Max(0, _bitmap.PixelHeight - size));
        if (layer.Children.Cast<FrameworkElement>().Any(v => (int)Canvas.GetLeft(v) == x && (int)Canvas.GetTop(v) == y)) return;
        int w = Math.Min(size, _bitmap.PixelWidth - x), h = Math.Min(size, _bitmap.PixelHeight - y);
        var block = new Rectangle { Fill = new SolidColorBrush(SampleColor(x + w / 2, y + h / 2)), Width = w, Height = h };
        Canvas.SetLeft(block, x); Canvas.SetTop(block, y); layer.Children.Add(block);
    }

    private Color SampleColor(int x, int y)
    {
        var pixel = new byte[4];
        _pixelBitmap.CopyPixels(new Int32Rect(Math.Clamp(x, 0, _bitmap.PixelWidth - 1), Math.Clamp(y, 0, _bitmap.PixelHeight - 1), 1, 1), pixel, 4, 0);
        return Color.FromArgb(255, pixel[2], pixel[1], pixel[0]);
    }

    private static void DrawLine(Canvas canvas, Point start, Point end, bool arrow, Brush brush, double width)
    {
        canvas.Children.Clear();
        canvas.Children.Add(new Line { X1 = start.X, Y1 = start.Y, X2 = end.X, Y2 = end.Y, Stroke = brush, StrokeThickness = width,
            StrokeStartLineCap = PenLineCap.Round, StrokeEndLineCap = PenLineCap.Round });
        if (!arrow) return;
        double angle = Math.Atan2(end.Y - start.Y, end.X - start.X), length = Math.Max(16, width * 4), spread = 0.55;
        canvas.Children.Add(new Polygon { Fill = brush, Points = new PointCollection
        {
            end,
            new(end.X - length * Math.Cos(angle - spread), end.Y - length * Math.Sin(angle - spread)),
            new(end.X - length * Math.Cos(angle + spread), end.Y - length * Math.Sin(angle + spread)),
        }});
    }

    private void Undo_Click(object sender, RoutedEventArgs e)
    {
        if (_history.Count == 0) return;
        EditorAction action = _history.Pop();
        if (action.Added)
        {
            _operations.Remove(action.Item); AnnotationCanvas.Children.Remove(action.Item);
        }
        else
        {
            int index = Math.Min(action.Index, _operations.Count);
            _operations.Insert(index, action.Item); AnnotationCanvas.Children.Insert(index, action.Item);
        }
        _redo.Push(action); UpdateHistoryButtons();
    }

    private void Redo_Click(object sender, RoutedEventArgs e)
    {
        if (_redo.Count == 0) return;
        EditorAction action = _redo.Pop();
        if (action.Added)
        {
            int index = Math.Min(action.Index, _operations.Count);
            _operations.Insert(index, action.Item); AnnotationCanvas.Children.Insert(index, action.Item);
        }
        else
        {
            _operations.Remove(action.Item); AnnotationCanvas.Children.Remove(action.Item);
        }
        _history.Push(action); UpdateHistoryButtons();
    }

    private void UpdateHistoryButtons()
    {
        if (UndoButton == null || RedoButton == null) return;
        UndoButton.IsEnabled = _history.Count > 0; RedoButton.IsEnabled = _redo.Count > 0;
    }

    private void Copy_Click(object sender, RoutedEventArgs e)
    {
        BitmapSource result = Render();
        try { Clipboard.SetImage(result); Hint.Text = "已复制标注后的截图"; } catch { Hint.Text = "复制失败：剪贴板正被其他程序占用"; }
    }

    private void Save_Click(object sender, RoutedEventArgs e)
    {
        var dialog = new SaveFileDialog { Filter = "PNG 图片|*.png", FileName = $"screenshot-{DateTime.Now:yyyyMMdd-HHmmss}.png" };
        if (dialog.ShowDialog(this) != true) return;
        using FileStream file = File.Create(dialog.FileName);
        var encoder = new PngBitmapEncoder(); encoder.Frames.Add(BitmapFrame.Create(Render())); encoder.Save(file); Hint.Text = $"已保存到 {dialog.FileName}";
    }

    private void Window_PreviewKeyDown(object sender, KeyEventArgs e)
    {
        if ((Keyboard.Modifiers & ModifierKeys.Control) != 0)
        {
            if (e.Key == Key.Z) { Undo_Click(sender, e); e.Handled = true; }
            else if (e.Key == Key.Y) { Redo_Click(sender, e); e.Handled = true; }
            else if (e.Key == Key.S) { Save_Click(sender, e); e.Handled = true; }
            else if (e.Key == Key.C && Keyboard.FocusedElement is not TextBox) { Copy_Click(sender, e); e.Handled = true; }
        }
        else if (e.Key == Key.Escape) Close();
    }

    private BitmapSource Render()
    {
        Keyboard.ClearFocus(); EditorSurface.UpdateLayout();
        var result = new RenderTargetBitmap(_bitmap.PixelWidth, _bitmap.PixelHeight, 96, 96, PixelFormats.Pbgra32);
        result.Render(EditorSurface); result.Freeze(); return result;
    }

    private Point Clamp(Point p) => new(Math.Clamp(p.X, 0, _bitmap.PixelWidth), Math.Clamp(p.Y, 0, _bitmap.PixelHeight));

    private static BitmapImage LoadBitmap(byte[] png)
    {
        var bmp = new BitmapImage(); using var ms = new MemoryStream(png);
        bmp.BeginInit(); bmp.CacheOption = BitmapCacheOption.OnLoad; bmp.StreamSource = ms; bmp.EndInit(); bmp.Freeze(); return bmp;
    }
}
