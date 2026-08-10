import Cocoa
import UserNotifications

// MARK: - String Helpers
extension String {
    func droppingPrefix(_ prefix: String) -> String {
        guard self.hasPrefix(prefix) else { return self }
        return String(self.dropFirst(prefix.count))
    }
}

// MARK: - App Delegate
// MARK: - Custom Floating Window
class ButtonWindow: NSWindow {
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        self.isOpaque = false
        self.backgroundColor = .clear
        self.level = .floating // Float above normal windows
        self.isMovableByWindowBackground = false // We handle dragging manually to prevent click hijacking!
        self.hasShadow = true
        self.setFrameAutosaveName("MarkdownFormatterWindow") // Remember position automatically
    }
    
    override var canBecomeKey: Bool {
        return true
    }
}

// MARK: - Pill Button View
class PillButtonView: NSView {
    var isActive = true {
        didSet {
            updateAppearance()
        }
    }
    
    var onClick: (() -> Void)?
    
    // Manual dragging and click tracking
    private var initialLocation: NSPoint?
    private var isDragging = false
    
    private let titleLabel = NSTextField(labelWithString: "📝 MD Active")
    private let gradientLayer = CAGradientLayer()
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupView()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }
    
    private func setupView() {
        wantsLayer = true
        layer?.cornerRadius = frame.height / 2
        layer?.masksToBounds = true
        
        // Setup shadow for visual depth
        layer?.shadowColor = NSColor.systemBlue.cgColor
        layer?.shadowRadius = 8.0
        layer?.shadowOpacity = 0.4
        layer?.shadowOffset = CGSize(width: 0, height: 2)
        
        // Setup gradient layer
        gradientLayer.frame = bounds
        gradientLayer.colors = [
            NSColor(red: 0.0, green: 0.48, blue: 1.0, alpha: 1.0).cgColor, // #007aff (Vibrant Blue)
            NSColor(red: 0.63, green: 0.0, blue: 1.0, alpha: 1.0).cgColor  // #a100ff (Vibrant Purple)
        ]
        gradientLayer.startPoint = CGPoint(x: 0, y: 0.5)
        gradientLayer.endPoint = CGPoint(x: 1, y: 0.5)
        layer?.addSublayer(gradientLayer)
        
        // Setup label
        titleLabel.font = NSFont.systemFont(ofSize: 13, weight: .bold)
        titleLabel.textColor = .white
        titleLabel.alignment = .center
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)
        
        NSLayoutConstraint.activate([
            titleLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
        
        updateAppearance()
    }
    
    override func layout() {
        super.layout()
        gradientLayer.frame = bounds
    }
    
    func updateAppearance() {
        if isActive {
            titleLabel.stringValue = "📝 MD Active"
            titleLabel.textColor = .white
            gradientLayer.isHidden = false
            layer?.backgroundColor = nil
            layer?.shadowColor = NSColor.systemBlue.cgColor
        } else {
            titleLabel.stringValue = "📝 MD Off"
            titleLabel.textColor = NSColor.disabledControlTextColor
            gradientLayer.isHidden = true
            layer?.backgroundColor = NSColor.controlColor.cgColor
            layer?.shadowColor = nil
        }
    }
    
    // MARK: - Mouse Handlers for Dragging & Clicking
    override func mouseDown(with event: NSEvent) {
        // Store click location relative to the window
        initialLocation = event.locationInWindow
        isDragging = false
        
        // Tactile scale click animation
        let animation = CABasicAnimation(keyPath: "transform.scale")
        animation.fromValue = 1.0
        animation.toValue = 0.92
        animation.duration = 0.08
        animation.autoreverses = true
        layer?.add(animation, forKey: "click")
    }
    
    override func mouseDragged(with event: NSEvent) {
        guard let window = self.window, let initial = initialLocation else { return }
        
        let mouseLocation = NSEvent.mouseLocation
        let newOrigin = NSPoint(
            x: mouseLocation.x - initial.x,
            y: mouseLocation.y - initial.y
        )
        
        // Set window origin position
        window.setFrameOrigin(newOrigin)
        isDragging = true
    }
    
    override func mouseUp(with event: NSEvent) {
        if !isDragging {
            // It was a click (no dragging happened)
            onClick?()
        }
        
        initialLocation = nil
        isDragging = false
    }
}

// MARK: - App Delegate
class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    
    // UI Elements
    var window: ButtonWindow!
    var buttonView: PillButtonView!
    
    // Settings (Defaults)
    var isEnabled: Bool = true {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: "isEnabled")
        }
    }
    
    var autoDetect: Bool = true {
        didSet {
            UserDefaults.standard.set(autoDetect, forKey: "autoDetect")
        }
    }
    
    var notifyOnChange: Bool = true {
        didSet {
            UserDefaults.standard.set(notifyOnChange, forKey: "notifyOnChange")
        }
    }
    
    // Clipboard State
    var lastChangeCount: Int = 0
    var monitorTimer: Timer?
    
    // Custom pasteboard type for identifying our own writes
    let markerType = NSPasteboard.PasteboardType("org.markdown-formatter.marker")
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        // Load preferences
        UserDefaults.standard.register(defaults: [
            "isEnabled": true,
            "autoDetect": true,
            "notifyOnChange": true
        ])
        isEnabled = UserDefaults.standard.bool(forKey: "isEnabled")
        autoDetect = UserDefaults.standard.bool(forKey: "autoDetect")
        notifyOnChange = UserDefaults.standard.bool(forKey: "notifyOnChange")
        
        // Hide Dock icon completely (Accessory app without a Dock icon)
        NSApp.setActivationPolicy(.accessory)
        
        // Setup Window size
        let width: CGFloat = 160
        let height: CGFloat = 50
        
        // Get primary screen visible rect
        let screenRect = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 800, height: 600)
        let defaultRect = NSRect(
            x: screenRect.maxX - width - 40,
            y: screenRect.maxY - height - 40,
            width: width,
            height: height
        )
        
        // Create window
        window = ButtonWindow(contentRect: defaultRect)
        
        // Create button view
        buttonView = PillButtonView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        buttonView.isActive = true // Starts active
        buttonView.onClick = { [weak self] in
            self?.toggleAppActiveState()
        }
        
        window.contentView = buttonView
        window.makeKeyAndOrderFront(nil)
        
        setupNotifications()
        
        // Initialize lastChangeCount & Start monitoring
        lastChangeCount = NSPasteboard.general.changeCount
        startClipboardMonitoring()
        
        print("Markdown Clipboard Formatter widget successfully launched on Desktop.")
    }
    
    func toggleAppActiveState() {
        if isEnabled {
            // Turn OFF & Exit
            isEnabled = false
            buttonView.isActive = false
            
            // Invalidate clipboard timer
            monitorTimer?.invalidate()
            monitorTimer = nil
            
            // Graceful exit after showing the "MD Off" state transition
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                NSApp.terminate(nil)
            }
        }
    }
    
    // MARK: - Clipboard Monitor Loop
    func startClipboardMonitoring() {
        monitorTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.checkClipboard()
        }
    }
    
    func checkClipboard() {
        let currentChangeCount = NSPasteboard.general.changeCount
        if currentChangeCount != lastChangeCount {
            lastChangeCount = currentChangeCount
            processClipboard(force: false)
        }
    }
    
    // MARK: - Clipboard Processing
    func processClipboard(force: Bool) {
        let pasteboard = NSPasteboard.general
        
        // 1. Check for infinite loop protection marker
        if let types = pasteboard.types, types.contains(markerType) {
            return
        }
        
        // 2. If formatting is disabled and we aren't forcing, do nothing
        if !isEnabled && !force {
            return
        }
        
        // 3. Extract plain text string
        guard let plainText = pasteboard.string(forType: .string), !plainText.isEmpty else {
            return
        }
        
        // 4. Double formatting prevention: skip if it's already HTML or RTF (unless forced)
        if !force {
            if let types = pasteboard.types {
                let hasRichData = types.contains(.html) ||
                                  types.contains(.rtf) ||
                                  types.contains(NSPasteboard.PasteboardType("public.html"))
                if hasRichData {
                    return
                }
            }
        }
        
        // 5. Run Markdown heuristic check (unless forced)
        if autoDetect && !force {
            if !isProbablyMarkdown(plainText) {
                return
            }
        }
        
        // 6. Convert Markdown plain text to styled HTML
        let htmlContent = convertMarkdownToHtml(plainText)
        
        // 7. Write formatted HTML & RTF back to clipboard
        writeFormattedTextToClipboard(plainText: plainText, htmlContent: htmlContent)
        
        // Update state to match new write count to prevent redundant trigger
        lastChangeCount = pasteboard.changeCount
        
        // 8. Visual feedback
        if notifyOnChange {
            showNotification(title: "Markdown Formatted", body: "Clipboard text has been formatted into rich text.")
        }
    }
    
    // MARK: - Markdown Detection Heuristic
    func isProbablyMarkdown(_ text: String) -> Bool {
        let lines = text.components(separatedBy: .newlines)
        var indicators = 0
        var inCodeBlock = false
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }
            
            // Fenced code blocks
            if trimmed.hasPrefix("```") {
                inCodeBlock = !inCodeBlock
                indicators += 1
                continue
            }
            
            if inCodeBlock { continue }
            
            // Headers
            if trimmed.hasPrefix("# ") || trimmed.hasPrefix("## ") || trimmed.hasPrefix("### ") || trimmed.hasPrefix("#### ") {
                indicators += 1
            }
            
            // Bullet lists
            if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || trimmed.hasPrefix("+ ") {
                indicators += 1
            }
            
            // Blockquotes
            if trimmed.hasPrefix("> ") {
                indicators += 1
            }
            
            // Numbered lists (e.g. "1. ")
            if let firstSpaceIndex = trimmed.firstIndex(of: " ") {
                let prefix = String(trimmed[..<firstSpaceIndex])
                if prefix.hasSuffix(".") {
                    let numPart = prefix.dropLast()
                    if Int(numPart) != nil {
                        indicators += 1
                    }
                }
            }
        }
        
        // Inline formatting check (e.g. `code` or **bold**)
        if text.contains("`") && text.components(separatedBy: "`").count >= 3 {
            indicators += 1
        }
        if text.contains("**") && text.components(separatedBy: "**").count >= 3 {
            indicators += 1
        }
        if text.contains("__") && text.components(separatedBy: "__").count >= 3 {
            indicators += 1
        }
        if text.contains("[") && text.contains("]") && text.contains("(") && text.contains(")") {
            let linkPattern = "\\[[^\\]]+\\]\\([^)]+\\)"
            if let regex = try? NSRegularExpression(pattern: linkPattern),
               regex.firstMatch(in: text, options: [], range: NSRange(location: 0, length: text.utf16.count)) != nil {
                indicators += 1
            }
        }
        
        return indicators >= 1
    }
    
    // MARK: - Markdown Parser (Markdown -> HTML)
    func convertMarkdownToHtml(_ markdown: String) -> String {
        let lines = markdown.components(separatedBy: .newlines)
        var htmlLines: [String] = []
        
        var inCodeBlock = false
        var codeLanguage = ""
        var codeLines: [String] = []
        
        var listType: String? = nil // nil, "ul", or "ol"
        var inBlockquote = false
        
        var paragraphLines: [String] = []
        
        func flushList() {
            if let type = listType {
                htmlLines.append("</\(type)>")
                listType = nil
            }
        }
        
        func flushBlockquote() {
            if inBlockquote {
                htmlLines.append("</blockquote>")
                inBlockquote = false
            }
        }
        
        func flushParagraph() {
            if !paragraphLines.isEmpty {
                let paragraphText = paragraphLines.joined(separator: " ")
                let formattedText = parseInlineMarkdown(escapeHtml(paragraphText))
                htmlLines.append("<p>\(formattedText)</p>")
                paragraphLines.removeAll()
            }
        }
        
        func flushAll() {
            flushParagraph()
            flushList()
            flushBlockquote()
        }
        
        for rawLine in lines {
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            
            // 1. Code Block Processing
            if trimmed.hasPrefix("```") {
                if inCodeBlock {
                    inCodeBlock = false
                    let codeText = codeLines.joined(separator: "\n")
                    let escapedCode = escapeHtml(codeText)
                    let highlightedCode = highlightSyntax(escapedCode, language: codeLanguage)
                    
                    htmlLines.append("<pre><code class=\"language-\(codeLanguage)\">\(highlightedCode)</code></pre>")
                    codeLines.removeAll()
                    codeLanguage = ""
                } else {
                    flushAll()
                    inCodeBlock = true
                    codeLanguage = trimmed.droppingPrefix("```").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                }
                continue
            }
            
            if inCodeBlock {
                codeLines.append(rawLine)
                continue
            }
            
            // 2. Empty Line flushes all active containers
            if trimmed.isEmpty {
                flushAll()
                continue
            }
            
            // 3. Headers (# -> h1, ## -> h2, etc.)
            if trimmed.hasPrefix("#") {
                var level = 0
                for char in trimmed {
                    if char == "#" {
                        level += 1
                    } else {
                        break
                    }
                }
                
                if level >= 1 && level <= 6 && trimmed.hasPrefix(String(repeating: "#", count: level) + " ") {
                    flushAll()
                    let headerText = trimmed.droppingPrefix(String(repeating: "#", count: level)).trimmingCharacters(in: .whitespaces)
                    let formattedHeader = parseInlineMarkdown(escapeHtml(headerText))
                    htmlLines.append("<h\(level)>\(formattedHeader)</h\(level)>")
                    continue
                }
            }
            
            // 4. Blockquotes (> text)
            if trimmed.hasPrefix(">") {
                flushParagraph()
                flushList()
                if !inBlockquote {
                    inBlockquote = true
                    htmlLines.append("<blockquote>")
                }
                let quoteText = trimmed.droppingPrefix(">").trimmingCharacters(in: .whitespaces)
                let formattedQuote = parseInlineMarkdown(escapeHtml(quoteText))
                htmlLines.append("<p>\(formattedQuote)</p>")
                continue
            } else {
                flushBlockquote()
            }
            
            // 5. Unordered List Items (- item, * item, + item)
            if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || trimmed.hasPrefix("+ ") {
                flushParagraph()
                if listType != "ul" {
                    flushList()
                    listType = "ul"
                    htmlLines.append("<ul>")
                }
                let itemText = trimmed.droppingPrefix(String(trimmed.prefix(2))).trimmingCharacters(in: .whitespaces)
                let formattedItem = parseInlineMarkdown(escapeHtml(itemText))
                htmlLines.append("<li>\(formattedItem)</li>")
                continue
            }
            
            // 6. Ordered List Items (1. item)
            var isOrderedList = false
            var oItemText = ""
            if let firstSpaceIndex = trimmed.firstIndex(of: " ") {
                let prefix = String(trimmed[..<firstSpaceIndex])
                if prefix.hasSuffix(".") {
                    let numPart = prefix.dropLast()
                    if Int(numPart) != nil {
                        isOrderedList = true
                        oItemText = String(trimmed[firstSpaceIndex...]).trimmingCharacters(in: .whitespaces)
                    }
                }
            }
            
            if isOrderedList {
                flushParagraph()
                if listType != "ol" {
                    flushList()
                    listType = "ol"
                    htmlLines.append("<ol>")
                }
                let formattedItem = parseInlineMarkdown(escapeHtml(oItemText))
                htmlLines.append("<li>\(formattedItem)</li>")
                continue
            }
            
            // 7. Regular paragraph lines (merged to support multi-line paragraphs)
            flushList()
            paragraphLines.append(rawLine)
        }
        
        flushAll()
        
        let bodyContent = htmlLines.joined(separator: "\n")
        return wrapInHtmlTemplate(bodyContent)
    }
    
    func escapeHtml(_ text: String) -> String {
        var escaped = text
        escaped = escaped.replacingOccurrences(of: "&", with: "&amp;")
        escaped = escaped.replacingOccurrences(of: "<", with: "&lt;")
        escaped = escaped.replacingOccurrences(of: ">", with: "&gt;")
        escaped = escaped.replacingOccurrences(of: "\"", with: "&quot;")
        escaped = escaped.replacingOccurrences(of: "'", with: "&#39;")
        return escaped
    }
    
    // MARK: - Inline Markdown Parser
    func parseInlineMarkdown(_ text: String) -> String {
        var result = text
        var codeBlocks: [String] = []
        
        // 1. Tokenize Inline Code to protect it from other inline replacements
        let codePattern = "`([^`]+)`"
        if let regex = try? NSRegularExpression(pattern: codePattern) {
            var matchCount = 0
            while true {
                let nsString = result as NSString
                let range = NSRange(location: 0, length: nsString.length)
                guard let match = regex.firstMatch(in: result, options: [], range: range) else {
                    break
                }
                let codeContent = nsString.substring(with: match.range(at: 1))
                codeBlocks.append(codeContent)
                
                let token = "___INLINE_CODE_TOKEN_\(matchCount)___"
                result = nsString.replacingCharacters(in: match.range, with: token)
                matchCount += 1
            }
        }
        
        // 2. Links: [text](url) -> <a href="url">text</a>
        let linkPattern = "\\[([^\\]]+)\\]\\(([^)]+)\\)"
        if let regex = try? NSRegularExpression(pattern: linkPattern) {
            let nsString = result as NSString
            let matches = regex.matches(in: result, options: [], range: NSRange(location: 0, length: nsString.length))
            
            for match in matches.reversed() {
                let linkText = nsString.substring(with: match.range(at: 1))
                let linkUrl = nsString.substring(with: match.range(at: 2))
                let htmlLink = "<a href=\"\(linkUrl)\">\(linkText)</a>"
                result = (result as NSString).replacingCharacters(in: match.range, with: htmlLink)
            }
        }
        
        // 3. Bold: **text** and __text__
        let boldPatterns = ["\\*\\*([^*]+)\\*\\*", "__([^_]+)__"]
        for pattern in boldPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern) {
                while true {
                    let nsString = result as NSString
                    guard let match = regex.firstMatch(in: result, options: [], range: NSRange(location: 0, length: nsString.length)) else {
                        break
                    }
                    let content = nsString.substring(with: match.range(at: 1))
                    result = nsString.replacingCharacters(in: match.range, with: "<strong>\(content)</strong>")
                }
            }
        }
        
        // 4. Italic: *text* and _text_
        let italicPatterns = ["\\*([^*]+)\\*", "_([^_]+)_"]
        for pattern in italicPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern) {
                while true {
                    let nsString = result as NSString
                    guard let match = regex.firstMatch(in: result, options: [], range: NSRange(location: 0, length: nsString.length)) else {
                        break
                    }
                    let content = nsString.substring(with: match.range(at: 1))
                    result = nsString.replacingCharacters(in: match.range, with: "<em>\(content)</em>")
                }
            }
        }
        
        // 5. Restore Inline Code Blocks wrapped in <code>
        for (index, codeContent) in codeBlocks.enumerated() {
            let token = "___INLINE_CODE_TOKEN_\(index)___"
            let htmlCode = "<code>\(codeContent)</code>"
            result = result.replacingOccurrences(of: token, with: htmlCode)
        }
        
        return result
    }
    
    // MARK: - Code Block Syntax Highlighting (Regex Tokenizer Method)
    func highlightSyntax(_ code: String, language: String) -> String {
        // Plain text / empty languages don't highlight
        if language.isEmpty || ["txt", "text", "plaintext", "md", "markdown"].contains(language) {
            return code
        }
        
        var result = code
        var commentTokens: [String] = []
        var stringTokens: [String] = []
        
        // 1. Block Comments /* ... */
        let blockCommentPattern = "/\\*[^*]*\\*+(?:[^/*][^*]*\\*+)*/"
        if let regex = try? NSRegularExpression(pattern: blockCommentPattern) {
            var matchCount = 0
            while true {
                let nsString = result as NSString
                guard let match = regex.firstMatch(in: result, options: [], range: NSRange(location: 0, length: nsString.length)) else {
                    break
                }
                let comment = nsString.substring(with: match.range)
                commentTokens.append(comment)
                let token = "___BLOCK_COMMENT_TOKEN_\(matchCount)___"
                result = nsString.replacingCharacters(in: match.range, with: token)
                matchCount += 1
            }
        }
        
        // 2. Line Comments: //... or #...
        let isHashComment = ["python", "py", "sh", "bash", "yaml", "yml", "ruby", "rb", "dockerfile", "makefile"].contains(language)
        let lineCommentPattern = isHashComment ? "#.*$" : "//.*$"
        if let regex = try? NSRegularExpression(pattern: lineCommentPattern, options: [.anchorsMatchLines]) {
            var matchCount = 0
            while true {
                let nsString = result as NSString
                guard let match = regex.firstMatch(in: result, options: [], range: NSRange(location: 0, length: nsString.length)) else {
                    break
                }
                let comment = nsString.substring(with: match.range)
                commentTokens.append(comment)
                let token = "___LINE_COMMENT_TOKEN_\(matchCount)___"
                result = nsString.replacingCharacters(in: match.range, with: token)
                matchCount += 1
            }
        }
        
        // 3. String Literals
        let stringPattern = "\"(?:[^\"\\\\]|\\\\.)*\"|'(?:[^'\\\\\\\\]|\\\\.)*'"
        if let regex = try? NSRegularExpression(pattern: stringPattern) {
            var matchCount = 0
            while true {
                let nsString = result as NSString
                guard let match = regex.firstMatch(in: result, options: [], range: NSRange(location: 0, length: nsString.length)) else {
                    break
                }
                let stringVal = nsString.substring(with: match.range)
                stringTokens.append(stringVal)
                let token = "___STRING_TOKEN_\(matchCount)___"
                result = nsString.replacingCharacters(in: match.range, with: token)
                matchCount += 1
            }
        }
        
        // 4. Keywords List
        let keywords = [
            "func", "class", "struct", "enum", "protocol", "extension", "let", "var", "import", "return",
            "if", "else", "switch", "case", "default", "for", "while", "do", "try", "catch", "throw", "throws",
            "guard", "defer", "init", "self", "nil", "true", "false", "def", "from", "as", "and", "or", "not",
            "in", "is", "lambda", "with", "yield", "pass", "break", "continue", "const", "function",
            "async", "await", "public", "private", "fileprivate", "internal", "static", "final", "override",
            "typealias", "associatedtype", "where", "package", "void", "int", "float", "double", "char",
            "boolean", "null", "undefined", "print", "console", "log", "string", "number", "bool"
        ]
        
        let sortedKeywords = keywords.sorted { $0.count > $1.count }
        for keyword in sortedKeywords {
            let pattern = "\\b\(keyword)\\b"
            if let regex = try? NSRegularExpression(pattern: pattern) {
                var offset = 0
                let nsString = result as NSString
                let matches = regex.matches(in: result, options: [], range: NSRange(location: 0, length: nsString.length))
                for match in matches {
                    let adjustedRange = NSRange(location: match.range.location + offset, length: match.range.length)
                    let replacement = "<span class=\"keyword\">\(keyword)</span>"
                    result = (result as NSString).replacingCharacters(in: adjustedRange, with: replacement)
                    offset += replacement.count - match.range.length
                }
            }
        }
        
        // 5. Highlight Functions
        let functionPattern = "\\b([a-zA-Z_][a-zA-Z0-9_]*)\\s*(?=\\()"
        if let regex = try? NSRegularExpression(pattern: functionPattern) {
            var offset = 0
            let nsString = result as NSString
            let matches = regex.matches(in: result, options: [], range: NSRange(location: 0, length: nsString.length))
            for match in matches {
                let adjustedRange = NSRange(location: match.range.location + offset, length: match.range.length)
                let funcName = (result as NSString).substring(with: NSRange(location: adjustedRange.location, length: match.range(at: 1).length))
                let replacement = "<span class=\"function\">\(funcName)</span>"
                result = (result as NSString).replacingCharacters(in: adjustedRange, with: replacement)
                offset += replacement.count - match.range.length
            }
        }
        
        // 6. Highlight Capitalized Types/Classes
        let typePattern = "\\b([A-Z][a-zA-Z0-9_]*)\\b"
        if let regex = try? NSRegularExpression(pattern: typePattern) {
            var offset = 0
            let nsString = result as NSString
            let matches = regex.matches(in: result, options: [], range: NSRange(location: 0, length: nsString.length))
            for match in matches {
                let adjustedRange = NSRange(location: match.range.location + offset, length: match.range.length)
                let typeName = (result as NSString).substring(with: adjustedRange)
                if ["HTML", "CSS", "URL"].contains(typeName) {
                    continue
                }
                let replacement = "<span class=\"type\">\(typeName)</span>"
                result = (result as NSString).replacingCharacters(in: adjustedRange, with: replacement)
                offset += replacement.count - match.range.length
            }
        }
        
        // 7. Highlight Numbers
        let numberPattern = "\\b(\\d+(?:\\.\\d+)?)\\b"
        if let regex = try? NSRegularExpression(pattern: numberPattern) {
            var offset = 0
            let nsString = result as NSString
            let matches = regex.matches(in: result, options: [], range: NSRange(location: 0, length: nsString.length))
            for match in matches {
                let adjustedRange = NSRange(location: match.range.location + offset, length: match.range.length)
                let numberVal = (result as NSString).substring(with: adjustedRange)
                let replacement = "<span class=\"number\">\(numberVal)</span>"
                result = (result as NSString).replacingCharacters(in: adjustedRange, with: replacement)
                offset += replacement.count - match.range.length
            }
        }
        
        // 8. Restore Strings
        for (index, stringVal) in stringTokens.enumerated() {
            let token = "___STRING_TOKEN_\(index)___"
            let htmlString = "<span class=\"string\">\(stringVal)</span>"
            result = result.replacingOccurrences(of: token, with: htmlString)
        }
        
        // 9. Restore Comments
        for (index, commentVal) in commentTokens.enumerated() {
            let blockToken = "___BLOCK_COMMENT_TOKEN_\(index)___"
            let lineToken = "___LINE_COMMENT_TOKEN_\(index)___"
            let htmlComment = "<span class=\"comment\">\(commentVal)</span>"
            result = result.replacingOccurrences(of: blockToken, with: htmlComment)
            result = result.replacingOccurrences(of: lineToken, with: htmlComment)
        }
        
        return result
    }
    
    // MARK: - HTML Wrapper Template
    func wrapInHtmlTemplate(_ content: String) -> String {
        return """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <style>
          body {
            font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
            font-size: 14px;
            line-height: 1.6;
            color: #1a1a1a;
            background-color: #ffffff;
          }
          h1 { font-size: 1.8em; border-bottom: 1px solid #eaecef; padding-bottom: 0.3em; margin-top: 24px; margin-bottom: 16px; color: #111111; }
          h2 { font-size: 1.4em; border-bottom: 1px solid #eaecef; padding-bottom: 0.3em; margin-top: 24px; margin-bottom: 16px; color: #222222; }
          h3 { font-size: 1.25em; margin-top: 24px; margin-bottom: 16px; color: #333333; }
          h4 { font-size: 1.1em; color: #444444; }
          p, blockquote, ul, ol, dl, table, pre { margin-top: 0; margin-bottom: 16px; }
          blockquote {
            padding: 0 1em;
            color: #6a737d;
            border-left: 0.25em solid #dfe2e5;
            background-color: #f6f8fa;
            margin-left: 0;
            margin-right: 0;
          }
          code {
            font-family: "SFMono-Regular", Consolas, "Liberation Mono", Menlo, Courier, monospace;
            font-size: 85%;
            background-color: rgba(27,31,35,0.05);
            padding: 0.2em 0.4em;
            border-radius: 3px;
            color: #d63384;
          }
          pre {
            padding: 16px;
            overflow: auto;
            font-size: 85%;
            line-height: 1.45;
            background-color: #f6f8fa;
            border: 1px solid #e1e4e8;
            border-radius: 6px;
          }
          pre code {
            background-color: transparent;
            padding: 0;
            border-radius: 0;
            color: #24292e;
            font-family: "SFMono-Regular", Consolas, "Liberation Mono", Menlo, Courier, monospace;
          }
          a { color: #0366d6; text-decoration: none; }
          a:hover { text-decoration: underline; }
          
          /* Syntax Highlighting (Light Theme) */
          .keyword { color: #d73a49; font-weight: bold; }
          .string { color: #032f62; }
          .number { color: #005cc5; }
          .comment { color: #6a737d; font-style: italic; }
          .function { color: #6f42c1; }
          .type { color: #e36209; }
        </style>
        </head>
        <body>
          \(content)
        </body>
        </html>
        """
    }
    
    // MARK: - Clipboard Output Writer
    func writeFormattedTextToClipboard(plainText: String, htmlContent: String) {
        let pasteboard = NSPasteboard.general
        
        guard let htmlData = htmlContent.data(using: .utf8) else { return }
        
        // Convert HTML to NSAttributedString for RTF generation
        var rtfData: Data? = nil
        if let attrStr = try? NSAttributedString(
            data: htmlData,
            options: [
                .documentType: NSAttributedString.DocumentType.html,
                .characterEncoding: String.Encoding.utf8.rawValue
            ],
            documentAttributes: nil
        ) {
            rtfData = attrStr.rtf(from: NSRange(location: 0, length: attrStr.length), documentAttributes: [:])
        }
        
        // Write formats to Pasteboard
        pasteboard.clearContents()
        
        let item = NSPasteboardItem()
        
        // 1. Write plain text (for compatibility with editors like VS Code, Vim, etc.)
        item.setString(plainText, forType: .string)
        
        // 2. Write HTML format
        item.setString(htmlContent, forType: NSPasteboard.PasteboardType("public.html"))
        
        // 3. Write RTF format
        if let rtf = rtfData {
            item.setData(rtf, forType: .rtf)
        }
        
        // 4. Write marker to prevent self-triggering infinite loops
        item.setString("processed", forType: markerType)
        
        pasteboard.writeObjects([item])
    }
    
    // MARK: - Notifications Setup
    func setupNotifications() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }
    
    func showNotification(title: String, body: String) {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized else { return }
            
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = UNNotificationSound.default
            
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.1, repeats: false)
            let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: trigger)
            
            center.add(request) { error in
                if let error = error {
                    print("Failed to send notification: \(error)")
                }
            }
        }
    }
    
    // Allow notifications to show even if app is in foreground
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        if #available(macOS 11.0, *) {
            completionHandler([.banner, .sound])
        } else {
            completionHandler([.alert, .sound])
        }
    }
}

// MARK: - Main Loop Entry Point
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
