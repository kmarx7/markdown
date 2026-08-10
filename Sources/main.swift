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
class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    
    // Status Bar & Menu
    var statusItem: NSStatusItem!
    
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
        
        // Hide Dock icon completely (Pure status bar app)
        NSApp.setActivationPolicy(.accessory)
        
        // Setup Status Item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            if #available(macOS 11.0, *) {
                button.image = NSImage(systemSymbolName: "doc.richtext", accessibilityDescription: "Markdown Clipboard Formatter")
                button.image?.isTemplate = true
            } else {
                button.title = "MD"
            }
        }
        
        buildMenu()
        setupNotifications()
        
        // Initialize lastChangeCount & Start monitoring
        lastChangeCount = NSPasteboard.general.changeCount
        startClipboardMonitoring()
        
        print("Markdown Clipboard Formatter successfully started in background status bar.")
    }
    
    // MARK: - Menu Setup
    func buildMenu() {
        let menu = NSMenu()
        
        let titleItem = NSMenuItem(title: "Markdown Formatter", action: nil, keyEquivalent: "")
        titleItem.isEnabled = false
        menu.addItem(titleItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let toggleItem = NSMenuItem(title: "Enable Automatic Formatting", action: #selector(toggleEnabled), keyEquivalent: "e")
        toggleItem.state = isEnabled ? .on : .off
        menu.addItem(toggleItem)
        
        let autoDetectItem = NSMenuItem(title: "Auto-Detect Markdown Syntax", action: #selector(toggleAutoDetect), keyEquivalent: "d")
        autoDetectItem.state = autoDetect ? .on : .off
        menu.addItem(autoDetectItem)
        
        let notifyItem = NSMenuItem(title: "Show Toast Notifications", action: #selector(toggleNotifications), keyEquivalent: "n")
        notifyItem.state = notifyOnChange ? .on : .off
        menu.addItem(notifyItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let convertNowItem = NSMenuItem(title: "Format Clipboard Now", action: #selector(convertNow), keyEquivalent: "f")
        menu.addItem(convertNowItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let quitItem = NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q")
        menu.addItem(quitItem)
        
        statusItem.menu = menu
    }
    
    @objc func toggleEnabled() {
        isEnabled.toggle()
        buildMenu()
    }
    
    @objc func toggleAutoDetect() {
        autoDetect.toggle()
        buildMenu()
    }
    
    @objc func toggleNotifications() {
        notifyOnChange.toggle()
        buildMenu()
    }
    
    @objc func convertNow() {
        processClipboard(force: true)
    }
    
    @objc func quitApp() {
        NSApp.terminate(nil)
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
            background-color: #282c34;
            border-radius: 6px;
          }
          pre code {
            background-color: transparent;
            padding: 0;
            border-radius: 0;
            color: #abb2bf;
            font-family: "SFMono-Regular", Consolas, "Liberation Mono", Menlo, Courier, monospace;
          }
          a { color: #0366d6; text-decoration: none; }
          a:hover { text-decoration: underline; }
          
          /* Syntax Highlighting CSS */
          .keyword { color: #c678dd; font-weight: bold; }
          .string { color: #98c379; }
          .number { color: #d19a66; }
          .comment { color: #5c6370; font-style: italic; }
          .function { color: #61afef; }
          .type { color: #e5c07b; }
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
