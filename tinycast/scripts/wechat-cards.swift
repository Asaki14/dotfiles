#!/usr/bin/swift

// @raycast.schemaVersion 1
// @raycast.title Batch WeChat Cards
// @raycast.mode silent
// @raycast.needsConfirmation false
// @raycast.packageName WeChat
// @raycast.description Read copied DingTalk messages and generate e 码特 cards in WeChat.

import AppKit
import ApplicationServices
import Vision

struct CardError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

struct Card {
    let link: String
    let title: String
    let description: String
}

func parse(_ text: String) throws -> [Card] {
    let url = #/(?i)(?:https?://)?(?:[a-z0-9](?:[a-z0-9-]*[a-z0-9])?\.)+[a-z]{2,}(?::[0-9]+)?(?:[/?#][\x21-\x7E]*)?/#
    let field = #/^(?:分享|卡片)?(标题|描述)\s*[：:]\s*/#
    let metadata = #/^群号\s*[：:]/#
    let trim = CharacterSet.whitespacesAndNewlines
    var cards: [Card] = []
    var link: String?, title: String?, description: String?
    var complete: Bool { link != nil && title != nil && description != nil }
    func finish() throws {
        guard link != nil || title != nil || description != nil else { return }
        let number = cards.count + 1
        guard let link, let title, !title.isEmpty, let description, !description.isEmpty else {
            throw CardError("第 \(number) 张缺少链接、标题或描述；未开始生成。")
        }
        for (label, value, limit) in [("标题", title, 25), ("描述", description, 35)] where value.utf16.count > limit {
            throw CardError("第 \(number) 张\(label)超限（\(value.utf16.count)/\(limit)）；请缩短后重新复制。未开始生成。")
        }
        cards.append(Card(link: link, title: title, description: description))
    }
    for (index, raw) in text.components(separatedBy: .newlines).enumerated() {
        var line = raw.trimmingCharacters(in: trim)
        if line.isEmpty || line.prefixMatch(of: metadata) != nil { continue }
        let label = line.prefixMatch(of: field)
        if let label, label.1 == "描述" {
            guard description == nil else { throw CardError("第 \(index + 1) 行重复标注描述；未开始生成。") }
            description = String(line[label.range.upperBound...]).trimmingCharacters(in: trim)
            continue
        }
        if complete { try finish(); link = nil; title = nil; description = nil }
        if let label { line.removeSubrange(label.range) }
        let matches = line.matches(of: url)
        if let match = matches.first {
            let value = String(match.output)
            let normalized = value.contains("://") ? value : "https://" + value
            guard matches.count == 1, link == nil, let parsed = URL(string: normalized), parsed.host != nil,
                  line[match.range.upperBound...].trimmingCharacters(in: CharacterSet(charactersIn: "，。；、）» ")).isEmpty else {
                throw CardError("第 \(index + 1) 行的链接有歧义；未开始生成。")
            }
            link = normalized
            line = String(line[..<match.range.lowerBound]).trimmingCharacters(in: trim.union(CharacterSet(charactersIn: ":：")))
        }
        if label != nil {
            guard title == nil else { throw CardError("第 \(index + 1) 行重复标注标题；未开始生成。") }
            title = line
        } else if matches.isEmpty {
            throw CardError("第 \(index + 1) 行无法识别；未开始生成。")
        }
    }
    try finish()
    guard !cards.isEmpty else { throw CardError("剪贴板中没有卡片。") }
    return cards
}

struct TextHit {
    let text: String
    let box: CGRect
    var center: CGPoint { CGPoint(x: box.midX, y: box.midY) }
}

struct View {
    let image: CGImage
    let bounds: CGRect
    let hits: [TextHit]
    func find(_ text: String, inRightPane: Bool = true) -> TextHit? {
        hits.first { $0.text.contains(text) && (!inRightPane || $0.box.midX > bounds.minX + bounds.width * 0.46) }
    }

    var isEMartChat: Bool {
        hits.contains {
            $0.text == "e码特" && $0.box.minX > bounds.minX + 180 &&
                $0.box.maxY < bounds.minY + 55
        }
    }

    var accountMenu: CGPoint? {
        let bottom = hits.filter { $0.box.midY > bounds.maxY - 65 }
        guard let guide = bottom.first(where: { $0.text.contains("服务指引") }),
              let user = bottom.first(where: { $0.text.contains("用户中心") }),
              abs(guide.center.y - user.center.y) < 10, guide.center.x < user.center.x else { return nil }
        return CGPoint(x: (guide.center.x + user.center.x) / 2, y: (guide.center.y + user.center.y) / 2)
    }
    func preview(in area: CGRect) -> Data? {
        let sx = CGFloat(image.width) / bounds.width, sy = CGFloat(image.height) / bounds.height
        let region = area.offsetBy(dx: -bounds.minX, dy: -bounds.minY).applying(CGAffineTransform(scaleX: sx, y: sy)).integral
        guard let crop = image.cropping(to: region),
              let bitmap = CGContext(data: nil, width: 64, height: 12, bitsPerComponent: 8, bytesPerRow: 256,
                                     space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue),
              let bytes = bitmap.data else { return nil }
        bitmap.draw(crop, in: CGRect(x: 0, y: 0, width: 64, height: 12))
        return Data(bytes: bytes, count: bitmap.bytesPerRow * bitmap.height)
    }
}

final class WeChat {
    let app: NSRunningApplication
    let ax: AXUIElement
    let screenFile: URL
    let clipboard = NSPasteboard.general
    let savedClipboard: [[(NSPasteboard.PasteboardType, Data)]]
    var clipboardChange: Int
    var didPaste = false

    init(screenFile: URL) throws {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: "com.tencent.xinWeChat").first else {
            throw CardError("请先打开微信的 e 码特公众号会话。")
        }
        guard AXIsProcessTrusted() else { throw CardError("请给运行脚本的应用开启 macOS「辅助功能」权限。") }
        guard CGPreflightScreenCaptureAccess() else {
            _ = CGRequestScreenCaptureAccess()
            throw CardError("请给运行脚本的应用开启 macOS「屏幕与系统音频录制」权限，再重试。")
        }
        self.app = app
        ax = AXUIElementCreateApplication(app.processIdentifier)
        self.screenFile = screenFile
        clipboardChange = clipboard.changeCount
        savedClipboard = (clipboard.pasteboardItems ?? []).map { item in
            item.types.compactMap { kind in item.data(forType: kind).map { (kind, $0) } }
        }
        _ = app.activate()
        AXUIElementSetAttributeValue(ax, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
    }

    func restoreClipboard() {
        guard didPaste, clipboard.changeCount == clipboardChange else { return }
        clipboard.clearContents()
        let items = savedClipboard.map { pairs in
            let item = NSPasteboardItem()
            for (kind, data) in pairs { item.setData(data, forType: kind) }
            return item
        }
        if !items.isEmpty { clipboard.writeObjects(items) }
    }

    private func axList(_ element: AXUIElement, _ key: String) -> [AXUIElement] {
        var value: CFTypeRef?
        AXUIElementCopyAttributeValue(element, key as CFString, &value)
        return value as? [AXUIElement] ?? []
    }

    private func sheet(in element: AXUIElement) -> AXUIElement? {
        axList(element, kAXChildrenAttribute).first { child in
            var role: CFTypeRef?
            AXUIElementCopyAttributeValue(child, kAXRoleAttribute as CFString, &role)
            return (role as? String) == kAXSheetRole
        }
    }

    private func fileSheet() -> AXUIElement? {
        axList(ax, kAXWindowsAttribute).lazy.compactMap { self.sheet(in: $0) }.first
    }

    private func ensureForeground() throws {
        guard app.isActive else { throw CardError("微信不在前台。请先切到微信所在工作区，再运行快捷命令；运行中不要切换应用。") }
    }

    func snap() throws -> View {
        try ensureForeground()
        let windows = (CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? [])
        let frames = windows.compactMap { entry -> (Int, CGRect)? in
            guard (entry[kCGWindowOwnerPID as String] as? Int32) == app.processIdentifier,
                  (entry[kCGWindowLayer as String] as? Int) == 0,
                  let id = entry[kCGWindowNumber as String] as? Int,
                  let dictionary = entry[kCGWindowBounds as String] as? [String: Any],
                  let bounds = CGRect(dictionaryRepresentation: dictionary as CFDictionary) else { return nil }
            return (id, bounds)
        }
        guard let (id, bounds) = frames.max(by: { $0.1.width * $0.1.height < $1.1.width * $1.1.height }) else {
            throw CardError("找不到前台微信窗口。")
        }
        try? FileManager.default.removeItem(at: screenFile)
        let capture = Process()
        capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        capture.arguments = ["-x", "-o", "-l", String(id), screenFile.path]
        try capture.run()
        capture.waitUntilExit()
        guard capture.terminationStatus == 0,
              let source = CGImageSourceCreateWithURL(screenFile as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw CardError("无法识别微信窗口；检查屏幕录制权限。")
        }
        let request = VNRecognizeTextRequest()
        request.recognitionLanguages = ["zh-Hans", "en-US"]
        try VNImageRequestHandler(cgImage: image).perform([request])
        let hits = (request.results ?? []).compactMap { result -> TextHit? in
            guard let text = result.topCandidates(1).first?.string else { return nil }
            let b = result.boundingBox
            let box = CGRect(x: bounds.minX + b.minX * bounds.width, y: bounds.minY + (1 - b.maxY) * bounds.height,
                             width: b.width * bounds.width, height: b.height * bounds.height)
            return TextHit(text: text.replacingOccurrences(of: " ", with: ""), box: box)
        }
        return View(image: image, bounds: bounds, hits: hits)
    }

    func wait<T>(_ message: String, seconds: TimeInterval = 6, _ check: () throws -> T?) throws -> T {
        let deadline = Date().addingTimeInterval(seconds)
        repeat {
            if let result = try check() { return result }
            Thread.sleep(forTimeInterval: 0.2)
        } while Date() < deadline
        throw CardError(message)
    }

    func click(_ point: CGPoint) throws {
        try ensureForeground()
        var display: CGDirectDisplayID = 0
        var count: UInt32 = 0
        guard CGGetDisplaysWithPoint(point, 1, &display, &count) == .success, count == 1 else {
            throw CardError("表单控件在屏幕外；请先展开微信窗口。")
        }
        for type in [CGEventType.leftMouseDown, .leftMouseUp] {
            CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
        }
        Thread.sleep(forTimeInterval: 0.15)
    }

    func key(_ code: CGKeyCode, _ flags: CGEventFlags = []) throws {
        try ensureForeground()
        for down in [true, false] {
            let event = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: down)
            event?.flags = flags
            event?.post(tap: .cghidEventTap)
        }
        Thread.sleep(forTimeInterval: 0.15)
    }

    func paste(_ text: String) throws {
        guard clipboard.changeCount == clipboardChange else { throw CardError("剪贴板在运行中被改动；已停止。") }
        clipboard.clearContents()
        clipboard.setString(text, forType: .string)
        clipboardChange = clipboard.changeCount
        didPaste = true
        try key(0, .maskCommand)
        try key(9, .maskCommand)
    }

    func sendBatchMessage() throws {
        let start = try wait("请先打开 e 码特公众号的主会话，并关闭制卡表单。") { () throws -> View? in
            guard app.isActive else { return nil }
            let view = try snap()
            return view.isEMartChat && view.find("e码特｜") == nil ? view : nil
        }
        if let menu = start.accountMenu {
            try click(CGPoint(x: start.bounds.maxX - 38, y: menu.y))
        }
        let composer = try wait("未打开 e 码特消息输入框。") {
            let view = try snap()
            return view.isEMartChat && view.accountMenu == nil ? view : nil
        }
        let draftPoint = CGPoint(x: composer.bounds.midX, y: composer.bounds.maxY - 57)
        try click(draftPoint)
        guard clipboard.changeCount == clipboardChange else { throw CardError("剪贴板在运行中被改动；已停止。") }
        try key(0, .maskCommand)
        try key(8, .maskCommand)
        if clipboard.changeCount != clipboardChange {
            clipboardChange = clipboard.changeCount
            didPaste = true
            throw CardError("e 码特输入区已有内容，未发送。请先处理草稿。")
        }
        let code = Int(Date().timeIntervalSince1970) % 1_000_000
        let message = String(format: "制卡%06d", code)
        try paste(message)
        _ = try wait("未在 e 码特输入框确认待发送消息；未生成卡片。") {
            let view = try snap()
            return view.isEMartChat && view.accountMenu == nil && view.hits.contains {
                $0.text == message && $0.center.x > view.bounds.minX + 240 && $0.center.y > view.bounds.maxY - 300
            } ? true : nil
        }
        try key(36)
        let sent = try wait("未确认制卡消息已发出。请检查公众号会话；未生成卡片。") { () throws -> View? in
            let view = try snap()
            return view.isEMartChat && view.hits.contains {
                $0.text == message && $0.center.x > view.bounds.midX && $0.center.y < view.bounds.maxY - 85
            } ? view : nil
        }
        try click(CGPoint(x: sent.bounds.maxX - 68, y: sent.bounds.maxY - 35))
        _ = try wait("消息已发，但未切回公众号菜单；未生成卡片。") { try snap().accountMenu }
    }

    func openForm() throws -> View {
        let start = try wait("请先打开 e 码特公众号会话。") { () throws -> View? in
            guard app.isActive else { return nil }
            let view = try snap()
            return view.find("点击卡片后") != nil ||
                (view.isEMartChat && view.accountMenu != nil) ? view : nil
        }
        if start.find("点击卡片后") != nil { return start }
        if let entry = start.find("微信分享卡片") {
            try click(entry.center)
        } else if let use = start.accountMenu {
            try click(use)
            let entry = try wait("找不到「微信分享卡片」入口。") { try snap().find("微信分享卡片") }
            try click(entry.center)
        }
        return try wait("未打开空白的微信分享卡片表单。") {
            let view = try snap()
            return view.find("点击卡片后") != nil && view.find("立即生成") != nil ? view : nil
        }
    }

    func upload(_ path: String, at point: CGPoint) throws {
        try click(point)
        let open = try wait("没有打开封面文件选择窗口。") { fileSheet() }
        try key(5, [.maskCommand, .maskShift])
        _ = try wait("找不到封面路径输入框。") { sheet(in: open) }
        try paste(path)
        try key(36)
        _ = try wait("封面路径没有定位到文件。") { sheet(in: open) == nil ? true : nil }
        try key(36)
        _ = try wait("封面文件选择窗口未关闭。") {
            fileSheet() == nil ? true : nil
        }
    }

    func fill(_ card: Card, cover: String) throws -> View {
        let form = try openForm()
        guard let link = form.find("点击卡片后"), let image = form.find("图片链接或者上传"),
              let title = form.find("分享标题"), let description = form.find("分享描述"), let expiry = form.find("有效期") else {
            throw CardError("表单字段不完整；请展开微信窗口并回到空白表单。")
        }
        let coverPoint = CGPoint(x: image.box.minX + 17, y: image.center.y + 29)
        let previewX = coverPoint.x + 32
        let preview = CGRect(x: previewX, y: coverPoint.y - 30, width: form.bounds.maxX - previewX - 10, height: 58)
        guard let before = form.preview(in: preview) else { throw CardError("找不到封面预览区域。") }
        try upload(cover, at: coverPoint)
        _ = try wait("未确认封面上传成功。") { () throws -> Bool? in
            let current = try snap()
            guard current.find("点击卡片后") != nil, let after = current.preview(in: preview) else { return nil }
            return before != after ? true : nil
        }
        let x = link.box.minX + 50
        for (row, value) in [(link, card.link), (title, card.title), (description, card.description)] {
            try click(CGPoint(x: x, y: row.center.y))
            try paste(value)
        }
        try click(CGPoint(x: x, y: expiry.center.y))
        let month = try wait("找不到「1个月」有效期。") { try snap().find("1个月") }
        try click(month.center)
        return try wait("未确认表单已填完且有效期为 1 个月。") {
            let view = try snap()
            guard let value = view.find("1个月"), abs(value.center.y - expiry.center.y) < 12,
                  view.find("点击卡片后") == nil, view.find("长度不超过") == nil,
                  view.find("立即生成") != nil else { return nil }
            return view
        }
    }

    func generate(_ form: View) throws {
        guard let submit = form.find("立即生成") else { throw CardError("找不到「立即生成」。") }
        try click(submit.center)
        _ = try wait("已点击「立即生成」，但未确认结果。请检查公众号是否收到卡片，不要直接重跑。", seconds: 12) {
            let view = try snap()
            return view.find("生成完毕") != nil ? view.find("确定") : nil
        }
    }

    func dismissSuccess() throws {
        try key(36)
        _ = try wait("生成结果仍在屏幕上，请手动点「确定」。") {
            try snap().find("生成完毕") == nil ? true : nil
        }
    }
}

func run() throws {
    let args = Array(CommandLine.arguments.dropFirst())
    if args == ["--parse"] {
        let text = String(decoding: FileHandle.standardInput.readDataToEndOfFile(), as: UTF8.self)
        for card in try parse(text) { print("\(card.link)\t\(card.title)\t\(card.description)") }
        return
    }
    guard args.isEmpty || (args.count == 2 && args[0] == "--cover") else {
        throw CardError("用法：wechat-cards.swift [--cover /path/to/image.png]")
    }
    let config = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/tinycast/wechat-card.local.conf")
    let rawCover = args.count == 2 ? args[1] : (try? String(contentsOf: config, encoding: .utf8)) ?? ""
    let cover = (rawCover.trimmingCharacters(in: .whitespacesAndNewlines) as NSString).expandingTildeInPath
    guard cover.hasPrefix("/"), CGImageSourceCreateWithURL(URL(fileURLWithPath: cover) as CFURL, nil) != nil else {
        throw CardError("请在 \(config.path) 写入固定封面的本机绝对路径。")
    }
    let cards = try parse(NSPasteboard.general.string(forType: .string) ?? "")
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: directory) }
    let wechat = try WeChat(screenFile: directory.appendingPathComponent("window.png"))
    defer { wechat.restoreClipboard() }
    try wechat.sendBatchMessage()
    print("已向 e 码特发送本批制卡消息")
    for (index, card) in cards.enumerated() {
        do {
            try wechat.generate(wechat.fill(card, cover: cover))
        } catch {
            throw CardError("已完成 \(index)/\(cards.count) 张；第 \(index + 1) 张：\(error.localizedDescription)")
        }
        print("已生成 \(index + 1)/\(cards.count)：\(card.title)")
        do {
            try wechat.dismissSuccess()
        } catch {
            throw CardError("已完成 \(index + 1)/\(cards.count) 张；\(error.localizedDescription)")
        }
    }
}

do { try run() } catch {
    FileHandle.standardError.write(Data((error.localizedDescription + "\n").utf8))
    exit(1)
}
