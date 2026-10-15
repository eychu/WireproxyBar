import Cocoa

private struct Strings {
    let statusOn: String
    let statusOff: String
    let connect: String
    let disconnect: String
    let paramsHeader: String
    let copyTooltip: (String) -> String
    let openConfig: String
    let viewLogs: String
    let quit: String
    let copiedTitle: String
    let errNotFoundBinary: String
    let errNotFoundConfig: String
    let errLaunchFailed: (String) -> String
    let tooltipStatusOn: String
    let tooltipStatusOff: String
    
    static var current: Strings {
        let preferred = Locale.preferredLanguages.first?.lowercased() ?? ""
        let isRussian = preferred.hasPrefix("ru")
        
        if isRussian {
            return Strings(
                statusOn: "🟢 Wireproxy: Включен",
                statusOff: "⚪️ Wireproxy: Выключен",
                connect: "Подключить",
                disconnect: "Отключить",
                paramsHeader: "Параметры подключения (клик для копирования):",
                copyTooltip: { "Скопировать \($0) в буфер обмена" },
                openConfig: "Открыть wireproxy.conf...",
                viewLogs: "Показать логи...",
                quit: "Выход",
                copiedTitle: "Скопировано в буфер",
                errNotFoundBinary: "Не найден исполняемый файл wireproxy (ни внутри приложения, ни в системе).",
                errNotFoundConfig: "Конфигурационный файл не найден. Создан шаблон: ~/.config/wireproxy/wireproxy.conf. Заполните его вашими данными WireGuard.",
                errLaunchFailed: { "Не удалось запустить wireproxy: \($0)" },
                tooltipStatusOn: "Wireproxy: Включен",
                tooltipStatusOff: "Wireproxy: Выключен"
            )
        } else {
            return Strings(
                statusOn: "🟢 Wireproxy: Connected",
                statusOff: "⚪️ Wireproxy: Disconnected",
                connect: "Connect",
                disconnect: "Disconnect",
                paramsHeader: "Connection Parameters (click to copy):",
                copyTooltip: { "Copy \($0) to clipboard" },
                openConfig: "Open wireproxy.conf...",
                viewLogs: "View Logs...",
                quit: "Quit",
                copiedTitle: "Copied to clipboard",
                errNotFoundBinary: "wireproxy executable not found (neither inside the app bundle nor in system PATH).",
                errNotFoundConfig: "Configuration file not found. Created template: ~/.config/wireproxy/wireproxy.conf. Please configure your WireGuard details.",
                errLaunchFailed: { "Failed to start wireproxy: \($0)" },
                tooltipStatusOn: "Wireproxy: Connected",
                tooltipStatusOff: "Wireproxy: Disconnected"
            )
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var statusTimer: Timer?
    private var wireproxyProcess: Process?
    private var logFileHandle: FileHandle?
    
    private let configPath: String = {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/.config/wireproxy/wireproxy.conf"
    }()
    
    private let logPath: String = {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/Library/Logs/WireproxyBar/wireproxy.log"
    }()
    
    private var wireproxyBinaryPath: String? {
        // 1. Auxiliary executable inside App bundle (Contents/MacOS/wireproxy)
        if let bundlePath = Bundle.main.path(forAuxiliaryExecutable: "wireproxy"),
           FileManager.default.isExecutableFile(atPath: bundlePath) {
            return bundlePath
        }
        
        let macosPath = Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/wireproxy").path
        if FileManager.default.isExecutableFile(atPath: macosPath) {
            return macosPath
        }
        
        let resourcesPath = Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/wireproxy").path
        if FileManager.default.isExecutableFile(atPath: resourcesPath) {
            return resourcesPath
        }
        
        // 2. Fallbacks in system PATH
        let candidates = [
            "/opt/homebrew/bin/wireproxy",
            "/usr/local/bin/wireproxy",
            "\(FileManager.default.homeDirectoryForCurrentUser.path)/.local/bin/wireproxy"
        ]
        for path in candidates {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }
        return nil
    }
    
    private var socks5Address: String = "127.0.0.1:1080"
    private var httpAddress: String = "127.0.0.1:8080"
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        ensureLogFileExists()
        loadConfig()
        updateStatus()
        
        // Monitor wireproxy status every 1.5 seconds
        statusTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            self?.updateStatus()
        }
    }
    
    func loadConfig() {
        guard let content = try? String(contentsOfFile: configPath, encoding: .utf8) else { return }
        
        var currentSection = ""
        let lines = content.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") {
                currentSection = trimmed.lowercased()
                continue
            }
            if currentSection == "[socks5]" && trimmed.lowercased().hasPrefix("bindaddress") {
                let parts = trimmed.components(separatedBy: "=")
                if parts.count > 1 {
                    socks5Address = parts[1].trimmingCharacters(in: .whitespaces)
                }
            } else if currentSection == "[http]" && trimmed.lowercased().hasPrefix("bindaddress") {
                let parts = trimmed.components(separatedBy: "=")
                if parts.count > 1 {
                    httpAddress = parts[1].trimmingCharacters(in: .whitespaces)
                }
            }
        }
    }
    
    private func ensureConfigExists() {
        let fileManager = FileManager.default
        let dir = (configPath as NSString).deletingLastPathComponent
        
        if !fileManager.fileExists(atPath: dir) {
            try? fileManager.createDirectory(atPath: dir, withIntermediateDirectories: true, attributes: nil)
        }
        
        if !fileManager.fileExists(atPath: configPath) {
            let sampleTemplate = """
            [Interface]
            PrivateKey = YOUR_PRIVATE_KEY
            Address = 10.0.0.2/32
            DNS = 1.1.1.1

            [Peer]
            PublicKey = YOUR_SERVER_PUBLIC_KEY
            Endpoint = your.server.ip:51820
            AllowedIPs = 0.0.0.0/0
            PersistentKeepalive = 25

            [Socks5]
            BindAddress = 127.0.0.1:1080

            [Http]
            BindAddress = 127.0.0.1:8080
            """
            try? sampleTemplate.write(toFile: configPath, atomically: true, encoding: .utf8)
            try? fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: configPath)
        }
    }
    
    private func ensureLogFileExists() {
        let fileManager = FileManager.default
        let dir = (logPath as NSString).deletingLastPathComponent
        if !fileManager.fileExists(atPath: dir) {
            try? fileManager.createDirectory(atPath: dir, withIntermediateDirectories: true, attributes: nil)
        }
        if !fileManager.fileExists(atPath: logPath) {
            let initialHeader = "=== Wireproxy Log Started ===\n"
            try? initialHeader.write(toFile: logPath, atomically: true, encoding: .utf8)
        }
    }
    
    private func appendLog(_ message: String) {
        ensureLogFileExists()
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let line = "[\(timestamp)] \(message)\n"
        if let data = line.data(using: .utf8), let handle = FileHandle(forWritingAtPath: logPath) {
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        }
    }
    
    private func isWireproxyRunning() -> Bool {
        if let proc = wireproxyProcess, proc.isRunning {
            return true
        }
        
        let pgrep = Process()
        pgrep.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        pgrep.arguments = ["-x", "wireproxy"]
        let pipe = Pipe()
        pgrep.standardOutput = pipe
        pgrep.standardError = Pipe()
        
        do {
            try pgrep.run()
            pgrep.waitUntilExit()
            return pgrep.terminationStatus == 0
        } catch {
            return false
        }
    }
    
    private func getIcon(running: Bool) -> NSImage? {
        let iconName = running ? "WireProxyFilledTemplate" : "WireProxyOutlineTemplate"
        
        var image: NSImage?
        if let bundlePath = Bundle.main.path(forResource: iconName, ofType: "svg") {
            image = NSImage(contentsOfFile: bundlePath)
        } else {
            let fallbackPaths = [
                "/Users/eychu/Applications/WireproxyBar.app/Contents/Resources/\(iconName).svg",
                "/Users/eychu/Projects/WireproxyBar/Resources/\(iconName).svg",
                "/Users/eychu/Downloads/WireProxy-icons/\(iconName).svg"
            ]
            for path in fallbackPaths {
                if FileManager.default.fileExists(atPath: path), let img = NSImage(contentsOfFile: path) {
                    image = img
                    break
                }
            }
        }
        
        if let image = image {
            image.isTemplate = true
            image.size = NSSize(width: 18, height: 18)
            return image
        }
        
        let fallbackSymbol = running ? "shield.fill" : "shield"
        let img = NSImage(systemSymbolName: fallbackSymbol, accessibilityDescription: "Wireproxy")
        img?.isTemplate = true
        return img
    }
    
    private func updateStatus() {
        let running = isWireproxyRunning()
        let strings = Strings.current
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if let button = self.statusItem.button {
                button.image = self.getIcon(running: running)
                button.toolTip = running ? strings.tooltipStatusOn : strings.tooltipStatusOff
            }
            self.rebuildMenu(isRunning: running)
        }
    }
    
    func menuWillOpen(_ menu: NSMenu) {
        loadConfig()
        updateStatus()
    }
    
    private func rebuildMenu(isRunning: Bool) {
        let menu = NSMenu()
        menu.delegate = self
        let strings = Strings.current
        
        // Status header
        let statusTitle = isRunning ? strings.statusOn : strings.statusOff
        let statusItem = NSMenuItem(title: statusTitle, action: nil, keyEquivalent: "")
        statusItem.isEnabled = false
        menu.addItem(statusItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Connect / Disconnect action
        if isRunning {
            let disconnectItem = NSMenuItem(title: strings.disconnect, action: #selector(disconnectAction), keyEquivalent: "d")
            disconnectItem.target = self
            menu.addItem(disconnectItem)
        } else {
            let connectItem = NSMenuItem(title: strings.connect, action: #selector(connectAction), keyEquivalent: "c")
            connectItem.target = self
            menu.addItem(connectItem)
        }
        
        menu.addItem(NSMenuItem.separator())
        
        // Parameters header
        let paramsHeader = NSMenuItem(title: strings.paramsHeader, action: nil, keyEquivalent: "")
        paramsHeader.isEnabled = false
        menu.addItem(paramsHeader)
        
        // SOCKS5 parameter
        let socksItem = NSMenuItem(
            title: "  SOCKS5: \(socks5Address)",
            action: #selector(copySocksAction),
            keyEquivalent: ""
        )
        socksItem.target = self
        socksItem.toolTip = strings.copyTooltip(socks5Address)
        menu.addItem(socksItem)
        
        // HTTP parameter
        let httpItem = NSMenuItem(
            title: "  HTTP:   \(httpAddress)",
            action: #selector(copyHttpAction),
            keyEquivalent: ""
        )
        httpItem.target = self
        httpItem.toolTip = strings.copyTooltip(httpAddress)
        menu.addItem(httpItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Open config file
        let openConfItem = NSMenuItem(title: strings.openConfig, action: #selector(openConfigAction), keyEquivalent: "o")
        openConfItem.target = self
        menu.addItem(openConfItem)
        
        // View logs item
        let viewLogsItem = NSMenuItem(title: strings.viewLogs, action: #selector(viewLogsAction), keyEquivalent: "l")
        viewLogsItem.target = self
        menu.addItem(viewLogsItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Quit
        let quitItem = NSMenuItem(title: strings.quit, action: #selector(quitAction), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        
        self.statusItem.menu = menu
    }
    
    @objc private func connectAction() {
        if isWireproxyRunning() { return }
        let strings = Strings.current
        
        guard let binaryPath = wireproxyBinaryPath else {
            showError(strings.errNotFoundBinary)
            return
        }
        
        if !FileManager.default.fileExists(atPath: configPath) {
            ensureConfigExists()
            showError(strings.errNotFoundConfig)
            openConfigAction()
            return
        }
        
        ensureLogFileExists()
        appendLog("Connecting with config: \(configPath)")
        
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: binaryPath)
        proc.arguments = ["-c", configPath]
        proc.standardInput = FileHandle.nullDevice
        
        // Direct stdout and stderr into wireproxy.log
        if let handle = FileHandle(forWritingAtPath: logPath) {
            handle.seekToEndOfFile()
            proc.standardOutput = handle
            proc.standardError = handle
            self.logFileHandle = handle
        } else {
            proc.standardOutput = Pipe()
            proc.standardError = Pipe()
        }
        
        do {
            try proc.run()
            self.wireproxyProcess = proc
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.updateStatus()
            }
        } catch {
            appendLog("Error launching wireproxy: \(error.localizedDescription)")
            showError(strings.errLaunchFailed(error.localizedDescription))
        }
    }
    
    @objc private func disconnectAction() {
        appendLog("Disconnect requested")
        
        if let proc = wireproxyProcess, proc.isRunning {
            proc.terminate()
            wireproxyProcess = nil
        }
        
        let killTask = Process()
        killTask.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
        killTask.arguments = ["-x", "wireproxy"]
        try? killTask.run()
        killTask.waitUntilExit()
        
        try? logFileHandle?.close()
        logFileHandle = nil
        
        appendLog("Wireproxy disconnected")
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.updateStatus()
        }
    }
    
    @objc private func viewLogsAction() {
        ensureLogFileExists()
        
        let consolePath = "/System/Applications/Utilities/Console.app"
        if FileManager.default.fileExists(atPath: consolePath) {
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            proc.arguments = ["-a", "Console", logPath]
            try? proc.run()
        } else {
            let url = URL(fileURLWithPath: logPath)
            NSWorkspace.shared.open(url)
        }
    }
    
    @objc private func copySocksAction() {
        copyToClipboard(socks5Address)
    }
    
    @objc private func copyHttpAction() {
        copyToClipboard(httpAddress)
    }
    
    private func copyToClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        
        let strings = Strings.current
        showNotification(title: strings.copiedTitle, message: text)
    }
    
    private func showNotification(title: String, message: String) {
        let notification = NSUserNotification()
        notification.title = title
        notification.informativeText = message
        NSUserNotificationCenter.default.deliver(notification)
    }
    
    private func showError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "Wireproxy"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.runModal()
    }
    
    @objc private func openConfigAction() {
        ensureConfigExists()
        let url = URL(fileURLWithPath: configPath)
        NSWorkspace.shared.open(url)
    }
    
    @objc private func quitAction() {
        if let proc = wireproxyProcess, proc.isRunning {
            proc.terminate()
        }
        try? logFileHandle?.close()
        NSApp.terminate(nil)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
