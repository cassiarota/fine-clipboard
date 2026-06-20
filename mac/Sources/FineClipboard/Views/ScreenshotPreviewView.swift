import SwiftUI
import AppKit

private enum ScreenshotTool: Hashable { case shape, line, pen, mosaic, text, eraser }
private enum ScreenshotShape: String, CaseIterable { case rectangle = "矩形", roundedRectangle = "圆角矩形", ellipse = "椭圆" }
private enum ScreenshotLine: String, CaseIterable { case line = "直线", arrow = "箭头" }

private struct ScreenshotMark {
    enum Kind { case shape(ScreenshotShape), line(ScreenshotLine), pen, mosaic, text }
    var kind: Kind
    var points: [NSPoint]
    var color: NSColor = .systemRed
    var width: CGFloat = 5
    var roundPen = true
    var text = ""
}

private struct ScreenshotEditAction {
    enum Kind { case add, remove }
    var kind: Kind
    var index: Int
    var mark: ScreenshotMark
}

private final class ScreenshotEditorModel: ObservableObject {
    let image: NSImage
    @Published var tool: ScreenshotTool = .shape
    @Published var shape: ScreenshotShape = .rectangle
    @Published var line: ScreenshotLine = .arrow
    @Published var color: NSColor = .systemRed
    @Published var penWidth: CGFloat = 5
    @Published var roundPen = true
    @Published var marks: [ScreenshotMark] = []
    @Published var canUndo = false
    @Published var canRedo = false
    @Published var status = "选择工具后在图片上拖动；工具菜单可切换类型。"
    private var history: [ScreenshotEditAction] = []
    private var redoActions: [ScreenshotEditAction] = []

    init(data: Data) { image = NSImage(data: data) ?? NSImage(size: NSSize(width: 1, height: 1)) }

    func begin(at point: NSPoint) {
        if tool == .eraser { erase(at: point); return }
        let mark: ScreenshotMark?
        switch tool {
        case .shape: mark = ScreenshotMark(kind: .shape(shape), points: [point, point], color: color, width: penWidth)
        case .line: mark = ScreenshotMark(kind: .line(line), points: [point, point], color: color, width: penWidth)
        case .pen: mark = ScreenshotMark(kind: .pen, points: [point], color: color, width: penWidth, roundPen: roundPen)
        case .mosaic: mark = ScreenshotMark(kind: .mosaic, points: [point], width: penWidth)
        case .text:
            guard let value = Prompt.text("添加文字", "标注内容"), !value.isEmpty else { return }
            mark = ScreenshotMark(kind: .text, points: [point], color: color, width: penWidth, text: value)
        case .eraser: mark = nil
        }
        guard let mark else { return }
        let index = marks.count; marks.append(mark); history.append(ScreenshotEditAction(kind: .add, index: index, mark: mark))
        redoActions.removeAll(); updateHistoryState()
    }

    func drag(to point: NSPoint) {
        guard !marks.isEmpty else { return }
        switch marks[marks.count - 1].kind {
        case .shape, .line: marks[marks.count - 1].points[1] = point
        case .pen, .mosaic: marks[marks.count - 1].points.append(point)
        case .text: break
        }
    }

    func undo() {
        guard var action = history.popLast() else { return }
        switch action.kind {
        case .add:
            guard action.index < marks.count else { return }; action.mark = marks.remove(at: action.index)
        case .remove:
            marks.insert(action.mark, at: min(action.index, marks.count))
        }
        redoActions.append(action); updateHistoryState()
    }

    func redo() {
        guard let action = redoActions.popLast() else { return }
        switch action.kind {
        case .add: marks.insert(action.mark, at: min(action.index, marks.count))
        case .remove: if action.index < marks.count { marks.remove(at: action.index) }
        }
        history.append(action); updateHistoryState()
    }

    private func erase(at point: NSPoint) {
        guard let index = marks.lastIndex(where: { hit($0, point) }) else { status = "此处没有标注"; return }
        let mark = marks.remove(at: index); history.append(ScreenshotEditAction(kind: .remove, index: index, mark: mark))
        redoActions.removeAll(); updateHistoryState(); status = "已擦除一项标注"
    }

    private func updateHistoryState() { canUndo = !history.isEmpty; canRedo = !redoActions.isEmpty }

    private func hit(_ mark: ScreenshotMark, _ p: NSPoint) -> Bool {
        let tolerance = max(10, mark.width * 2)
        switch mark.kind {
        case .shape:
            guard mark.points.count > 1 else { return false }
            return Self.normalized(mark.points[0], mark.points[1]).insetBy(dx: -tolerance, dy: -tolerance).contains(p)
        case .line:
            guard mark.points.count > 1 else { return false }
            return Self.distance(p, toSegmentFrom: mark.points[0], to: mark.points[1]) <= tolerance
        case .pen, .mosaic:
            return mark.points.contains { hypot($0.x - p.x, $0.y - p.y) <= tolerance }
        case .text:
            guard let origin = mark.points.first else { return false }
            let size = (mark.text as NSString).size(withAttributes: [.font: NSFont.boldSystemFont(ofSize: max(18, image.size.width / 60))])
            return NSRect(origin: origin, size: size).insetBy(dx: -tolerance, dy: -tolerance).contains(p)
        }
    }

    private static func distance(_ p: NSPoint, toSegmentFrom a: NSPoint, to b: NSPoint) -> CGFloat {
        let dx = b.x - a.x, dy = b.y - a.y
        if dx == 0 && dy == 0 { return hypot(p.x - a.x, p.y - a.y) }
        let t = max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / (dx * dx + dy * dy)))
        return hypot(p.x - (a.x + t * dx), p.y - (a.y + t * dy))
    }

    fileprivate static func normalized(_ a: NSPoint, _ b: NSPoint) -> NSRect {
        NSRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
    }

    func renderedPNG() -> Data? {
        let result = NSImage(size: image.size); result.lockFocus(); image.draw(in: NSRect(origin: .zero, size: image.size))
        ScreenshotEditorCanvas.draw(marks: marks, image: image); result.unlockFocus()
        guard let tiff = result.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }

    func copy() {
        guard let data = renderedPNG() else { status = "复制失败"; return }
        NSPasteboard.general.clearContents(); NSPasteboard.general.setData(data, forType: .png); status = "已复制标注后的截图"
    }

    func save() {
        guard let data = renderedPNG() else { status = "保存失败"; return }
        let panel = NSSavePanel(); panel.nameFieldStringValue = "screenshot.png"
        if #available(macOS 11.0, *) { panel.allowedContentTypes = [.png] }
        if panel.runModal() == .OK, let url = panel.url {
            do { try data.write(to: url); status = "已保存到 \(url.path)" } catch { status = "保存失败：\(error.localizedDescription)" }
        }
    }
}

struct ScreenshotPreviewView: View {
    @StateObject private var model: ScreenshotEditorModel
    private let colors: [NSColor] = [.systemRed, .systemOrange, .systemYellow, .systemGreen, .systemBlue, .systemPurple, .white, .black]

    init(data: Data) { _model = StateObject(wrappedValue: ScreenshotEditorModel(data: data)) }

    var body: some View {
        VStack(spacing: 10) {
            ScreenshotEditorRepresentable(model: model)
                .background(Color.black.opacity(0.65)).overlay(Rectangle().stroke(Color.blue.opacity(0.55)))

            HStack(spacing: 2) {
                Menu { ForEach(ScreenshotShape.allCases, id: \.self) { value in Button(value.rawValue) { model.shape = value; model.tool = .shape } } }
                    label: { toolIcon("square.on.circle", "图形", active: model.tool == .shape) }.menuStyle(.borderlessButton)
                Menu { ForEach(ScreenshotLine.allCases, id: \.self) { value in Button(value.rawValue) { model.line = value; model.tool = .line } } }
                    label: { toolIcon("arrow.up.right", "直线 / 箭头", active: model.tool == .line) }.menuStyle(.borderlessButton)
                Menu {
                    ForEach(Array(colors.enumerated()), id: \.offset) { _, color in
                        Button { model.color = color } label: { Label(colorName(color), systemImage: "circle.fill") }
                    }
                } label: {
                    ZStack { toolIcon("pencil.tip", "颜色", active: false); Circle().fill(Color(nsColor: model.color)).frame(width: 6, height: 6).offset(x: 10, y: -10) }
                }.menuStyle(.borderlessButton)
                Menu {
                    Picker("粗细", selection: $model.penWidth) { Text("细").tag(CGFloat(2)); Text("中").tag(CGFloat(5)); Text("粗").tag(CGFloat(10)) }
                    Picker("笔头", selection: $model.roundPen) { Text("圆头").tag(true); Text("方头").tag(false) }
                } label: { toolIcon("pencil", "画笔", active: model.tool == .pen) }
                .menuStyle(.borderlessButton).simultaneousGesture(TapGesture().onEnded { model.tool = .pen })
                toolButton("squareshape.split.2x2", "马赛克", .mosaic)
                toolButton("textformat", "插入文字", .text)
                toolButton("eraser", "橡皮", .eraser)
                Divider().frame(height: 24).padding(.horizontal, 3)
                actionButton("arrow.uturn.backward", "撤销") { model.undo() }.disabled(!model.canUndo)
                actionButton("arrow.uturn.forward", "重做") { model.redo() }.disabled(!model.canRedo)
                actionButton("square.and.arrow.down", "保存") { model.save() }
                actionButton("doc.on.doc", "复制") { model.copy() }
            }
            .padding(.horizontal, 6).padding(.vertical, 4).background(Color.white.opacity(0.97))
            .overlay(Rectangle().stroke(Color.blue.opacity(0.75))).fixedSize()

            Text(model.status).font(.caption).foregroundStyle(.white).frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(14).background(Color(nsColor: NSColor(white: 0.49, alpha: 1))).frame(minWidth: 760, minHeight: 560)
        .onKeyboardShortcut("z", modifiers: .command) { model.undo() }
        .onKeyboardShortcut("y", modifiers: .command) { model.redo() }
    }

    private func toolIcon(_ image: String, _ help: String, active: Bool) -> some View {
        Image(systemName: image).font(.system(size: 16)).foregroundStyle(Color.primary).frame(width: 32, height: 30)
            .background(active ? Color.blue.opacity(0.16) : Color.clear).help(help)
    }

    private func toolButton(_ image: String, _ help: String, _ tool: ScreenshotTool) -> some View {
        Button { model.tool = tool } label: { toolIcon(image, help, active: model.tool == tool) }.buttonStyle(.plain)
    }

    private func actionButton(_ image: String, _ help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { toolIcon(image, help, active: false) }.buttonStyle(.plain)
    }

    private func colorName(_ color: NSColor) -> String {
        if color == .systemRed { return "红色" }; if color == .systemOrange { return "橙色" }; if color == .systemYellow { return "黄色" }
        if color == .systemGreen { return "绿色" }; if color == .systemBlue { return "蓝色" }; if color == .systemPurple { return "紫色" }
        if color == .white { return "白色" }; return "黑色"
    }
}

private struct ScreenshotEditorRepresentable: NSViewRepresentable {
    @ObservedObject var model: ScreenshotEditorModel
    func makeNSView(context: Context) -> ScreenshotEditorCanvas { ScreenshotEditorCanvas(model: model) }
    func updateNSView(_ view: ScreenshotEditorCanvas, context: Context) { view.model = model; view.needsDisplay = true }
}

private final class ScreenshotEditorCanvas: NSView {
    var model: ScreenshotEditorModel
    private var drawing = false
    override var acceptsFirstResponder: Bool { true }

    init(model: ScreenshotEditorModel) { self.model = model; super.init(frame: .zero) }
    required init?(coder: NSCoder) { nil }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.55).setFill(); bounds.fill(); let target = imageRect; model.image.draw(in: target)
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.saveGState(); context.translateBy(x: target.minX, y: target.minY)
        let scale = target.width / max(1, model.image.size.width); context.scaleBy(x: scale, y: scale)
        Self.draw(marks: model.marks, image: model.image); context.restoreGState()
    }

    override func mouseDown(with event: NSEvent) {
        guard let p = imagePoint(event.locationInWindow) else { return }
        drawing = model.tool != .text && model.tool != .eraser; model.begin(at: p); needsDisplay = true
    }
    override func mouseDragged(with event: NSEvent) { guard drawing, let p = imagePoint(event.locationInWindow) else { return }; model.drag(to: p); needsDisplay = true }
    override func mouseUp(with event: NSEvent) { drawing = false }

    private var imageRect: NSRect {
        let size = model.image.size, scale = min(bounds.width / max(1, size.width), bounds.height / max(1, size.height))
        let fitted = NSSize(width: size.width * scale, height: size.height * scale)
        return NSRect(x: (bounds.width - fitted.width) / 2, y: (bounds.height - fitted.height) / 2, width: fitted.width, height: fitted.height)
    }

    private func imagePoint(_ point: NSPoint) -> NSPoint? {
        let rect = imageRect; guard rect.contains(point) else { return nil }; let scale = model.image.size.width / max(1, rect.width)
        return NSPoint(x: (point.x - rect.minX) * scale, y: (point.y - rect.minY) * scale)
    }

    fileprivate static func draw(marks: [ScreenshotMark], image: NSImage) {
        for mark in marks {
            mark.color.setStroke(); mark.color.setFill()
            switch mark.kind {
            case .shape(let shape):
                guard mark.points.count >= 2 else { continue }; let rect = ScreenshotEditorModel.normalized(mark.points[0], mark.points[1])
                let path: NSBezierPath = shape == .ellipse ? NSBezierPath(ovalIn: rect) :
                    (shape == .roundedRectangle ? NSBezierPath(roundedRect: rect, xRadius: 14, yRadius: 14) : NSBezierPath(rect: rect))
                path.lineWidth = mark.width; path.stroke()
            case .line(let line):
                guard mark.points.count >= 2 else { continue }; drawLine(from: mark.points[0], to: mark.points[1], arrow: line == .arrow, width: mark.width)
            case .pen:
                guard let first = mark.points.first else { continue }; let path = NSBezierPath(); path.lineWidth = mark.width
                path.lineCapStyle = mark.roundPen ? .round : .square; path.lineJoinStyle = mark.roundPen ? .round : .bevel; path.move(to: first)
                for p in mark.points.dropFirst() { path.line(to: p) }; path.stroke()
            case .mosaic: drawMosaic(points: mark.points, image: image, block: max(12, mark.width * 4))
            case .text:
                guard let point = mark.points.first else { continue }
                (mark.text as NSString).draw(at: point, withAttributes: [.font: NSFont.boldSystemFont(ofSize: max(18, image.size.width / 60)), .foregroundColor: mark.color, .strokeColor: NSColor.white, .strokeWidth: -1.5])
            }
        }
    }

    private static func drawLine(from a: NSPoint, to b: NSPoint, arrow: Bool, width: CGFloat) {
        let path = NSBezierPath(); path.lineWidth = width; path.lineCapStyle = .round; path.move(to: a); path.line(to: b); path.stroke()
        guard arrow else { return }; let angle = atan2(b.y - a.y, b.x - a.x), length = max(16, width * 4), spread: CGFloat = 0.55
        let head = NSBezierPath(); head.move(to: b)
        head.line(to: NSPoint(x: b.x - length * cos(angle - spread), y: b.y - length * sin(angle - spread)))
        head.line(to: NSPoint(x: b.x - length * cos(angle + spread), y: b.y - length * sin(angle + spread))); head.close(); head.fill()
    }

    private static func drawMosaic(points: [NSPoint], image: NSImage, block: CGFloat) {
        guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff) else { return }; var drawn = Set<String>()
        for p in points {
            let x = floor(p.x / block) * block, y = floor(p.y / block) * block, key = "\(Int(x))-\(Int(y))"; guard drawn.insert(key).inserted else { continue }
            let px = min(max(0, Int((x + block / 2) * CGFloat(bitmap.pixelsWide) / max(1, image.size.width))), bitmap.pixelsWide - 1)
            let py = min(max(0, Int((y + block / 2) * CGFloat(bitmap.pixelsHigh) / max(1, image.size.height))), bitmap.pixelsHigh - 1)
            (bitmap.colorAt(x: px, y: py) ?? .gray).setFill(); NSRect(x: x, y: y, width: min(block, image.size.width - x), height: min(block, image.size.height - y)).fill()
        }
    }
}

private extension View {
    func onKeyboardShortcut(_ key: KeyEquivalent, modifiers: EventModifiers, action: @escaping () -> Void) -> some View {
        background(Button(action: action) { EmptyView() }.keyboardShortcut(key, modifiers: modifiers).hidden())
    }
}
