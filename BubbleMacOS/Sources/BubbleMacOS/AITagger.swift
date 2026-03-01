import SwiftUI
import AppKit
import BubbleCore

@main
struct BubbleApp: App {
    @StateObject private var appState = AppState()

    init() {
        // Required so that the app can receive keyboard events in its windows (like Settings)
        NSApplication.shared.setActivationPolicy(.accessory)
    }

    var body: some Scene {
        MenuBarExtra("Bubble", systemImage: appState.isScanning ? appState.spinSymbol : "tag.circle.fill") {
            Button("Status: \(appState.statusMessage)") {
                // No action needed
            }
            .disabled(true)
            
            Divider()
            
            Button("Add Folder Automation...") {
                appState.addFolderAutomation()
            }
            
            if #available(macOS 14.0, *) {
                SettingsLink {
                    Text("Settings...")
                }
                .keyboardShortcut(",", modifiers: .command)
            } else {
                Button("Settings...") {
                    appState.openSettings()
                }
                .keyboardShortcut(",", modifiers: .command)
            }
            
            Divider()
            
            Button("Process Clipboard Image") {
                appState.processClipboardImage()
            }
            .keyboardShortcut("v", modifiers: [.command, .shift])
            
            Divider()
            
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
        }
        .menuBarExtraStyle(.menu) // Makes it look like a standard menu
        
        Settings {
            SettingsView(appState: appState)
        }
    }
}

// MARK: - Automation Models

enum AutomationTrigger: String, Codable, CaseIterable {
    case manual = "Manual"
    case scheduled = "Scheduled"
    case onUpdate = "On File Update"
}

struct FolderAutomationConfig: Identifiable, Codable, Equatable {
    var id = UUID()
    var bookmarkData: Data?
    var trigger: AutomationTrigger = .manual
    var scheduleIntervalMinutes: Int = 60
    var overrideProvider: LLMProvider? = nil // nil means use global default
    var openAIModel: String = "gpt-4o-mini"
    var anthropicModel: String = "claude-3-5-sonnet-20241022"
    var ollamaModel: String = "llama3"
    var geminiModel: String = "gemini-2.5-flash"
    
    func resolvedURL() -> URL? {
        guard let data = bookmarkData else { return nil }
        var isStale = false
        do {
            let url = try URL(resolvingBookmarkData: data, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &isStale)
            return url
        } catch {
            print("Failed to resolve bookmark: \(error)")
            return nil
        }
    }
}

struct ModelsCache: Codable, Equatable {
    var openAI: [String] = ["gpt-4o", "gpt-4o-mini", "o1", "o3-mini"]
    var anthropic: [String] = ["claude-3-7-sonnet-20250219", "claude-3-5-sonnet-20241022", "claude-3-5-haiku-20241022"]
    var gemini: [String] = ["gemini-2.5-flash", "gemini-2.5-pro"]
}

// Tagging history data structure
struct TagEvent: Identifiable, Codable {
    let id: UUID
    let timestamp: Date
    let filename: String
    let status: String
    let configId: UUID
}

@MainActor
class AppState: ObservableObject {
    @Published var isScanning: Bool = false
    @Published var statusMessage: String = "Idle"
    
    @Published var provider: LLMProvider = LLMProvider(rawValue: UserDefaults.standard.string(forKey: "LLMProvider") ?? "Gemini") ?? .gemini {
        didSet { UserDefaults.standard.set(provider.rawValue, forKey: "LLMProvider") }
    }
    
    @Published var geminiApiKey: String = UserDefaults.standard.string(forKey: "GeminiAPIKey") ?? "" {
        didSet { 
            UserDefaults.standard.set(geminiApiKey, forKey: "GeminiAPIKey")
            Task { await fetchGeminiModels() }
        }
    }
    
    @Published var geminiModel: String = UserDefaults.standard.string(forKey: "GeminiModel") ?? "gemini-2.5-flash" {
        didSet { UserDefaults.standard.set(geminiModel, forKey: "GeminiModel") }
    }
    
    @Published var openAIApiKey: String = UserDefaults.standard.string(forKey: "OpenAIApiKey") ?? "" {
        didSet { 
            UserDefaults.standard.set(openAIApiKey, forKey: "OpenAIApiKey")
            Task { await fetchOpenAIModels() }
        }
    }
    
    @Published var openAIModel: String = UserDefaults.standard.string(forKey: "OpenAIModel") ?? "gpt-4o-mini" {
        didSet { UserDefaults.standard.set(openAIModel, forKey: "OpenAIModel") }
    }
    
    @Published var anthropicApiKey: String = UserDefaults.standard.string(forKey: "AnthropicApiKey") ?? "" {
        didSet { 
            UserDefaults.standard.set(anthropicApiKey, forKey: "AnthropicApiKey")
            Task { await fetchAnthropicModels() }
        }
    }
    
    @Published var anthropicModel: String = UserDefaults.standard.string(forKey: "AnthropicModel") ?? "claude-3-5-sonnet-20241022" {
        didSet { UserDefaults.standard.set(anthropicModel, forKey: "AnthropicModel") }
    }
    
    @Published var ollamaHost: String = UserDefaults.standard.string(forKey: "BubbleOllamaHost") ?? "http://localhost:11434" {
        didSet { 
            UserDefaults.standard.set(ollamaHost, forKey: "BubbleOllamaHost")
            Task { await fetchOllamaModels() }
        }
    }
    
    @Published var ollamaModel: String = UserDefaults.standard.string(forKey: "OllamaModel") ?? "llama3" {
        didSet { UserDefaults.standard.set(ollamaModel, forKey: "OllamaModel") }
    }
    
    @Published var folderConfigs: [FolderAutomationConfig] = {
        if let docURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            let fileURL = docURL.appendingPathComponent("Bubble").appendingPathComponent("folder_configs.json")
            if let data = try? Data(contentsOf: fileURL),
               let decoded = try? JSONDecoder().decode([FolderAutomationConfig].self, from: data) {
                return decoded
            }
        }
        return []
    }() {
        didSet {
            if let docURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
                let dirURL = docURL.appendingPathComponent("Bubble")
                try? FileManager.default.createDirectory(at: dirURL, withIntermediateDirectories: true)
                let fileURL = dirURL.appendingPathComponent("folder_configs.json")
                if let encoded = try? JSONEncoder().encode(folderConfigs) {
                    try? encoded.write(to: fileURL)
                }
            }
            applyAutomationConfigs()
        }
    }
    
    @Published var cachedModels: ModelsCache = {
        if let docURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            let fileURL = docURL.appendingPathComponent("Bubble").appendingPathComponent("models.json")
            if let data = try? Data(contentsOf: fileURL),
               let decoded = try? JSONDecoder().decode(ModelsCache.self, from: data) {
                return decoded
            }
        }
        return ModelsCache()
    }() {
        didSet {
            if let docURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
                let dirURL = docURL.appendingPathComponent("Bubble")
                try? FileManager.default.createDirectory(at: dirURL, withIntermediateDirectories: true)
                let fileURL = dirURL.appendingPathComponent("models.json")
                if let encoded = try? JSONEncoder().encode(cachedModels) {
                    try? encoded.write(to: fileURL)
                }
            }
        }
    }
    
    @Published var imageStorageDir: String = UserDefaults.standard.string(forKey: "BubbleImageStorageDir") ?? "~/Pictures/Bubble" {
        didSet { UserDefaults.standard.set(imageStorageDir, forKey: "BubbleImageStorageDir") }
    }
    
    @Published var isMagicClipboardEnabled: Bool = UserDefaults.standard.bool(forKey: "BubbleIsMagicClipboardEnabled") {
        didSet { UserDefaults.standard.set(isMagicClipboardEnabled, forKey: "BubbleIsMagicClipboardEnabled") }
    }
    
    @Published var remoteSyncTarget: String = UserDefaults.standard.string(forKey: "BubbleRemoteSyncTarget") ?? "" {
        didSet { UserDefaults.standard.set(remoteSyncTarget, forKey: "BubbleRemoteSyncTarget") }
    }
    
    @Published var ollamaModels: [String] = []
    
    @Published var shortcut: ShortcutConfig = {
        if let data = UserDefaults.standard.data(forKey: "BubbleShortcut"),
           let decoded = try? JSONDecoder().decode(ShortcutConfig.self, from: data) {
            return decoded
        }
        return ShortcutConfig(key: "v", modifiers: [.command, .shift])
    }() {
        didSet {
            if let encoded = try? JSONEncoder().encode(shortcut) {
                UserDefaults.standard.set(encoded, forKey: "BubbleShortcut")
            }
        }
    }

    // Tag History
    @Published var taggingHistory: [TagEvent] = []
    
    // UI State
    @Published var currentShortcutPrompt: String? = nil
    
    // Spin UI Animation State
    @Published var spinSymbol: String = "arrow.triangle.2.circlepath.circle.fill"
    private var spinTimer: Timer?
    private var spinTick: Int = 0
    
    private let scanningEngine = ScanningEngine()
    private let clipboardService = ClipboardService()
    private var clipboardTimer: Timer?
    private var lastChangeCount: Int = NSPasteboard.general.changeCount
    
    private var folderMonitors: [UUID: FolderMonitor] = [:]
    private var scheduleTimers: [UUID: Timer] = [:]
    
    @Published var installedWorkspaceMCPs: [UUID: Bool] = [:]
    
    @Published var isGlobalMCPInstalled: Bool = false
    @Published var isAntigravityMCPInstalled: Bool = false
    @Published var isClaudeCodeSkillInstalled: Bool = false

    init() {
        setupClipboardMonitoring()
        
        Task {
            await fetchOllamaModels()
            await fetchRemoteModels()
        }
        
        checkIntegrations()
        
        // Apply initial automation after a slight delay to ensure UI is ready
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.applyAutomationConfigs()
        }
    }
    
    func checkIntegrations() {
        let fileManager = FileManager.default
        let skillPath = fileManager.homeDirectoryForCurrentUser.appendingPathComponent(".gemini/antigravity/skills/bubble-skill/SKILL.md")
        DispatchQueue.main.async {
            self.isClaudeCodeSkillInstalled = fileManager.fileExists(atPath: skillPath.path)
        }
        
        let claudeConfigPath = fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Claude/claude_desktop_config.json")
        var globalInstalled = false
        if let data = try? Data(contentsOf: claudeConfigPath),
           let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
           let mcpServers = json["mcpServers"] as? [String: Any],
           mcpServers["bubble-toolbox"] != nil {
            globalInstalled = true
        }
        
        let agConfigPath = fileManager.homeDirectoryForCurrentUser.appendingPathComponent(".gemini/antigravity/mcp_config.json")
        var agInstalled = false
        if let data = try? Data(contentsOf: agConfigPath),
           let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
           let mcpServers = json["mcpServers"] as? [String: Any],
           mcpServers["bubble-toolbox"] != nil {
            agInstalled = true
        }
        
        var workspaceStatus: [UUID: Bool] = [:]
        for config in self.folderConfigs {
            if let url = config.resolvedURL() {
                let mcpPath = url.appendingPathComponent(".cursor/mcp.json")
                var isInstalled = false
                if let data = try? Data(contentsOf: mcpPath),
                   let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
                   let mcpServers = json["mcpServers"] as? [String: Any],
                   mcpServers["bubble-toolbox"] != nil {
                    isInstalled = true
                }
                workspaceStatus[config.id] = isInstalled
            }
        }
        
        DispatchQueue.main.async {
            self.installedWorkspaceMCPs = workspaceStatus
            self.isGlobalMCPInstalled = globalInstalled
            self.isAntigravityMCPInstalled = agInstalled
        }
    }
    
    func fetchOllamaModels() async {
        let host = ollamaHost.trimmingCharacters(in: .whitespacesAndNewlines).appending(ollamaHost.hasSuffix("/") ? "" : "/")
        guard let url = URL(string: "\(host)api/tags") else { return }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let response = try JSONDecoder().decode(OllamaTagsResponse.self, from: data)
            self.ollamaModels = response.models.map { $0.name }
            
            // If current model is empty but we have models, pick the first one
            if ollamaModel.isEmpty || !ollamaModels.contains(ollamaModel) {
                if let first = ollamaModels.first {
                    ollamaModel = first
                }
            }
        } catch {
            print("Failed to fetch Ollama models: \(error)")
        }
    }
    
    func fetchRemoteModels() async {
        await fetchOpenAIModels()
        await fetchAnthropicModels()
        await fetchGeminiModels()
    }
    
    private func fetchOpenAIModels() async {
        guard !openAIApiKey.isEmpty, let url = URL(string: "https://api.openai.com/v1/models") else { return }
        var request = URLRequest(url: url)
        request.addValue("Bearer \(openAIApiKey)", forHTTPHeaderField: "Authorization")
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let response = try JSONDecoder().decode(OpenAIModelsResponse.self, from: data)
            let models = response.data.map { $0.id }
                .filter { $0.contains("gpt") || $0.contains("o1") || $0.contains("o3") }
                .sorted().reversed()
            if !models.isEmpty {
                Task { @MainActor in self.cachedModels.openAI = Array(models) }
            }
        } catch { print("Failed OpenAI: \(error)") }
    }
    
    private func fetchAnthropicModels() async {
        guard !anthropicApiKey.isEmpty, let url = URL(string: "https://api.anthropic.com/v1/models") else { return }
        var request = URLRequest(url: url)
        request.addValue(anthropicApiKey, forHTTPHeaderField: "x-api-key")
        request.addValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let response = try JSONDecoder().decode(AnthropicModelsResponse.self, from: data)
            let models = response.data.map { $0.id }
                .filter { $0.contains("claude") }
                .sorted().reversed()
            if !models.isEmpty {
                Task { @MainActor in self.cachedModels.anthropic = Array(models) }
            }
        } catch { print("Failed Anthropic: \(error)") }
    }
    
    private func fetchGeminiModels() async {
        guard !geminiApiKey.isEmpty, let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models?key=\(geminiApiKey)") else { return }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let response = try JSONDecoder().decode(GeminiModelsResponse.self, from: data)
            let models = response.models.map { $0.name.replacingOccurrences(of: "models/", with: "") }
                .filter { $0.contains("gemini") && !$0.contains("vision") }
                .sorted().reversed()
            if !models.isEmpty {
                Task { @MainActor in self.cachedModels.gemini = Array(models) }
            }
        } catch { print("Failed Gemini: \(error)") }
    }
    
    private func setupClipboardMonitoring() {
        clipboardTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self, self.isMagicClipboardEnabled else { return }
                let pasteboard = NSPasteboard.general
                if pasteboard.changeCount != self.lastChangeCount {
                    self.lastChangeCount = pasteboard.changeCount
                    self.processClipboardImage(isAuto: true)
                }
            }
        }
    }

    func processClipboardImage(isAuto: Bool = false) {
        // If it's an auto-process from timer, check if Magic Clipboard is enabled
        if isAuto && !isMagicClipboardEnabled { return }
        
        let targetDir = imageStorageDir
        let remoteTarget = remoteSyncTarget
        
        // Derive SSH prefix from remote target if possible
        var sshPrefix = ""
        if let colonRange = remoteTarget.range(of: ":") {
            sshPrefix = String(remoteTarget[colonRange.upperBound...])
        }
        
        if let localPath = clipboardService.convertClipboardImageToFile(storageDir: targetDir, sshPrefix: sshPrefix) {
            statusMessage = (isAuto ? "Auto-saved: " : "Image saved: ") + localPath
            
            // Trigger remote sync if configured
            if !remoteTarget.isEmpty {
                syncToRemote(localPath: localPath, remoteTarget: remoteTarget)
            }
        } else if !isAuto {
            statusMessage = "No new image in clipboard"
        }
    }
    
    private func syncToRemote(localPath: String, remoteTarget: String) {
        // Run scp in the background
        let task = Process()
        task.launchPath = "/usr/bin/scp"
        
        // Resolve ~ in localPath
        let resolvedLocalPath = (localPath as NSString).expandingTildeInPath
        
        // Extract remote path for the clipboard if scp target includes host:path
        // remoteTarget format: user@host:/path/to/dir/
        task.arguments = [resolvedLocalPath, remoteTarget]
        
        task.terminationHandler = { task in
            if task.terminationStatus == 0 {
                print("Successfully synced \(localPath) to \(remoteTarget)")
            } else {
                print("Failed to sync to remote: \(task.terminationStatus)")
            }
        }
        
        do {
            try task.run()
            
            // If remote sync is enabled, we should ideally update the clipboard path to the remote one
            // We'll calculate the remote path based on the filename and the target directory
            if let colonRange = remoteTarget.range(of: ":") {
                let remoteDir = String(remoteTarget[colonRange.upperBound...])
                let filename = (localPath as NSString).lastPathComponent
                let remoteFinalPath = remoteDir.appending(filename)
                
                // Augment clipboard again with the remote path instead of local
                _ = clipboardService.convertClipboardImageToFile(storageDir: imageStorageDir, sshPrefix: "", overridePath: remoteFinalPath)
            }
        } catch {
            print("Error running scp: \(error)")
        }
    }

    func openSettings() {
        if #available(macOS 14.0, *) {
             NSApp.activate(ignoringOtherApps: true)
             NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        } else {
             NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
        }
    }
    
    func addFolderAutomation() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Select Folder to Automate"
        
        if panel.runModal() == .OK, let url = panel.url {
            do {
                let bookmarkData = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
                var newConfig = FolderAutomationConfig()
                newConfig.bookmarkData = bookmarkData
                folderConfigs.append(newConfig)
            } catch {
                print("Failed to create bookmark: \(error)")
            }
        }
    }
    
    func removeFolderAutomation(id: UUID) {
        folderConfigs.removeAll(where: { $0.id == id })
    }
    
    private func stopSpinTimer() {
        spinTimer?.invalidate()
        spinTimer = nil
        spinSymbol = "arrow.triangle.2.circlepath.circle.fill"
        spinTick = 0
    }
    
    func startSpinTimer() {
        stopSpinTimer()
        // There is no native rotational modifier inside a structural `MenuBarExtra` that easily loops continuously in older macos versions. 
        // We simulate a rotation using alternative SF Symbols to create a flashing or movement effect.
        
        spinTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            DispatchQueue.main.async {
                self.spinTick += 1
                switch self.spinTick % 3 {
                case 0: self.spinSymbol = "arrow.triangle.2.circlepath"
                case 1: self.spinSymbol = "arrow.triangle.2.circlepath.circle"
                case 2: self.spinSymbol = "arrow.triangle.2.circlepath.circle.fill"
                default: self.spinSymbol = "arrow.triangle.2.circlepath"
                }
                
                // Hack to force a refresh of the MenuBar string if it's static
                self.objectWillChange.send()
            }
        }
    }
    
    private func applyAutomationConfigs() {
        // Stop existing
        for (_, monitor) in folderMonitors { monitor.stopMonitoring() }
        folderMonitors.removeAll()
        for (_, timer) in scheduleTimers { timer.invalidate() }
        scheduleTimers.removeAll()
        
        if folderConfigs.isEmpty {
            statusMessage = "Waiting..."
            return
        }
        
        var anyWatching = false
        var anyScheduled = false
        
        for config in folderConfigs {
            guard let url = config.resolvedURL() else { continue }
            
            switch config.trigger {
            case .manual:
                continue
            case .onUpdate:
                anyWatching = true
                let monitor = FolderMonitor(url: url) { [weak self] in
                    DispatchQueue.main.async {
                        if self?.isScanning == false {
                            self?.executeFolderScan(config: config)
                        }
                    }
                }
                folderMonitors[config.id] = monitor
                monitor.startMonitoring()
            case .scheduled:
                anyScheduled = true
                let interval = max(1, TimeInterval(config.scheduleIntervalMinutes * 60))
                let timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
                    DispatchQueue.main.async {
                        if self?.isScanning == false {
                            self?.executeFolderScan(config: config)
                        }
                    }
                }
                scheduleTimers[config.id] = timer
            }
        }
        
        if anyWatching || anyScheduled {
            statusMessage = "Running Automations (\(folderConfigs.count) configuration(s))"
        } else {
            statusMessage = "Waiting..."
        }
    }
    
    func executeFolderScan(config: FolderAutomationConfig) {
        guard let folder = config.resolvedURL() else { return }
        
        if isScanning { return }
        isScanning = true
        statusMessage = "Scanning \(folder.lastPathComponent)..."
        
        let activeProvider = config.overrideProvider ?? provider
        
        var apiKey = ""
        var model = ""
        
        switch activeProvider {
        case .gemini:
            apiKey = geminiApiKey
            model = config.overrideProvider != nil ? config.geminiModel : geminiModel
        case .openAI:
            apiKey = openAIApiKey
            model = config.overrideProvider != nil ? config.openAIModel : openAIModel
        case .anthropic:
            apiKey = anthropicApiKey
            model = config.overrideProvider != nil ? config.anthropicModel : anthropicModel
        case .ollama:
            model = config.overrideProvider != nil ? config.ollamaModel : ollamaModel
        }
        
        let llmConfig = LLMConfiguration(
            apiKey: apiKey,
            model: model,
            host: ollamaHost
        )
        
        Task {
            let _ = folder.startAccessingSecurityScopedResource()
            let didSucceed = true // Placeholder for execution result
            
            await scanningEngine.scanAndTag(folder: folder, provider: activeProvider, configuration: llmConfig) { progress in
                Task { @MainActor in
                    self.statusMessage = progress
                    
                    // Log as individual event if it looks like a file name
                    if progress.contains("Tagging ") {
                        let filename = progress.replacingOccurrences(of: "Tagging ", with: "")
                        let event = TagEvent(id: UUID(), timestamp: Date(), filename: filename, status: "Complete", configId: config.id)
                        self.taggingHistory.insert(event, at: 0)
                        if self.taggingHistory.count > 100 {
                            self.taggingHistory.removeLast()
                        }
                    }
                }
            }
            folder.stopAccessingSecurityScopedResource()
            
            isScanning = false
            if config.trigger == .manual {
                statusMessage = "Waiting... (Last scan finished)"
            } else {
                applyAutomationConfigs() // resets the status message to waiting/scheduled
            }
            
            // Log the completion event
            let event = TagEvent(id: UUID(), timestamp: Date(), filename: folder.lastPathComponent + " Contents", status: "Complete", configId: config.id)
            DispatchQueue.main.async {
                self.taggingHistory.insert(event, at: 0)
                if self.taggingHistory.count > 100 {
                    self.taggingHistory.removeLast()
                }
            }
        }
    }
    
    func clearTaggingHistory() {
        self.taggingHistory.removeAll()
    }
    
    func getBubbleExecutablePath() -> String? {
        let fileManager = FileManager.default
        let currentPath = fileManager.currentDirectoryPath
        
        let possiblePaths = [
            fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs/JIMI/Bubble/BubbleLinuxGo/bubble").path,
            "\(currentPath)/BubbleLinuxGo/bubble",
            "/usr/local/bin/bubble",
            fileManager.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin/bubble").path
        ]
        
        for p in possiblePaths {
            if fileManager.fileExists(atPath: p) {
                return p
            }
        }
        
        DispatchQueue.main.async {
            self.statusMessage = "Error: 'bubble' CLI not found. Please build it first."
        }
        return nil
    }
    
    func installGlobalMCP() {
        guard let executablePath = getBubbleExecutablePath() else { return }
        let fileManager = FileManager.default
        let claudeDir = fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Claude")
        let claudeConfigPath = claudeDir.appendingPathComponent("claude_desktop_config.json")
        
        do {
            if !fileManager.fileExists(atPath: claudeDir.path) {
                try fileManager.createDirectory(at: claudeDir, withIntermediateDirectories: true)
            }
            
            var configData = Data()
            if fileManager.fileExists(atPath: claudeConfigPath.path) {
                configData = try Data(contentsOf: claudeConfigPath)
            } else {
                configData = "{}".data(using: .utf8)!
            }
            
            if var json = try JSONSerialization.jsonObject(with: configData, options: []) as? [String: Any] {
                var mcpServers = json["mcpServers"] as? [String: Any] ?? [String: Any]()
                let bubbleServerConfig: [String: Any] = [
                    "command": executablePath,
                    "args": ["--mcp"]
                ]
                mcpServers["bubble-toolbox"] = bubbleServerConfig
                json["mcpServers"] = mcpServers
                
                let newData = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted])
                try newData.write(to: claudeConfigPath)
                
                DispatchQueue.main.async {
                    self.isGlobalMCPInstalled = true
                    self.statusMessage = "Added Bubble MCP to Claude Desktop!"
                }
            }
        } catch {
            DispatchQueue.main.async {
                self.statusMessage = "Err modifying Claude config: \(error.localizedDescription)"
            }
        }
    }
    
    func installAntigravityMCP() {
        guard let executablePath = getBubbleExecutablePath() else { return }
        let fileManager = FileManager.default
        let agConfigPath = fileManager.homeDirectoryForCurrentUser.appendingPathComponent(".gemini/antigravity/mcp_config.json")
        
        do {
            if !fileManager.fileExists(atPath: agConfigPath.path) {
                let initialConfig: [String: Any] = ["mcpServers": [:]]
                let initialData = try JSONSerialization.data(withJSONObject: initialConfig, options: [.prettyPrinted])
                try fileManager.createDirectory(at: agConfigPath.deletingLastPathComponent(), withIntermediateDirectories: true)
                try initialData.write(to: agConfigPath)
            }
            
            let configData = try Data(contentsOf: agConfigPath)
            if var json = try JSONSerialization.jsonObject(with: configData, options: []) as? [String: Any] {
                var mcpServers = json["mcpServers"] as? [String: Any] ?? [String: Any]()
                let bubbleServerConfig: [String: Any] = [
                    "command": executablePath,
                    "args": ["--mcp"]
                ]
                mcpServers["bubble-toolbox"] = bubbleServerConfig
                json["mcpServers"] = mcpServers
                let newData = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted])
                try newData.write(to: agConfigPath)
                
                DispatchQueue.main.async {
                    self.statusMessage = "Antigravity Global MCP configured!"
                    self.isAntigravityMCPInstalled = true
                }
            }
        } catch {
            DispatchQueue.main.async {
                self.statusMessage = "Err modifying Antigravity config: \(error.localizedDescription)"
            }
        }
    }
    
    func promptAndInstallWorkspaceMCP() {
        guard let executablePath = getBubbleExecutablePath() else { return }
        
        let openPanel = NSOpenPanel()
        openPanel.message = "Choose a workspace folder to install MCP config"
        openPanel.prompt = "Install"
        openPanel.canChooseFiles = false
        openPanel.canChooseDirectories = true
        openPanel.canCreateDirectories = true
        openPanel.showsHiddenFiles = true

        openPanel.begin { response in
            if response == .OK, let url = openPanel.url {
                self.writeMCPConfigToWorkspace(url: url, executablePath: executablePath)
                self.checkIntegrations() // Check after manual installation as well
            }
        }
    }
    
    func installWorkspaceMCPForAllFolders() {
        guard let executablePath = getBubbleExecutablePath() else { return }
        var count = 0
        for config in folderConfigs {
            if let url = config.resolvedURL() {
                writeMCPConfigToWorkspace(url: url, executablePath: executablePath)
                count += 1
            }
        }
        
        DispatchQueue.main.async {
            self.checkIntegrations() // Update checkmarks
            if count > 0 {
                self.statusMessage = "Installed MCP config for \(count) workspace(s)!"
            } else {
                self.statusMessage = "No valid workspaces found to install MCP."
            }
        }
    }
    
    func installWorkspaceMCP(for config: FolderAutomationConfig) {
        guard let executablePath = getBubbleExecutablePath(), let url = config.resolvedURL() else { return }
        self.writeMCPConfigToWorkspace(url: url, executablePath: executablePath)
        self.checkIntegrations()
    }
    
    private func writeMCPConfigToWorkspace(url: URL, executablePath: String) {
        let cursorDir = url.appendingPathComponent(".cursor")
        let fileManager = FileManager.default
        
        do {
            if !fileManager.fileExists(atPath: cursorDir.path) {
                try fileManager.createDirectory(at: cursorDir, withIntermediateDirectories: true)
            }
            
            let mcpPath = cursorDir.appendingPathComponent("mcp.json")
            var configData = Data()
            if fileManager.fileExists(atPath: mcpPath.path) {
                configData = try Data(contentsOf: mcpPath)
            } else {
                configData = "{}".data(using: .utf8)!
            }
            
            if var json = try JSONSerialization.jsonObject(with: configData, options: []) as? [String: Any] {
                var mcpServers = json["mcpServers"] as? [String: Any] ?? [String: Any]()
                let bubbleServerConfig: [String: Any] = [
                    "command": executablePath,
                    "args": ["--mcp"]
                ]
                mcpServers["bubble-toolbox"] = bubbleServerConfig
                json["mcpServers"] = mcpServers
                let newData = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted])
                try newData.write(to: mcpPath)
                
                DispatchQueue.main.async {
                    self.statusMessage = "Added MCP config to \(url.lastPathComponent) workspace!"
                }
            }
        } catch {
            DispatchQueue.main.async {
                self.statusMessage = "Error modifying workspace config: \(error.localizedDescription)"
            }
        }
    }
    
    func installClaudeCodeSkill() {
        let fileManager = FileManager.default
        let antigravitySkillsDir = fileManager.homeDirectoryForCurrentUser.appendingPathComponent(".gemini/antigravity/skills/bubble-skill")
        do {
            if !fileManager.fileExists(atPath: antigravitySkillsDir.path) {
                try fileManager.createDirectory(at: antigravitySkillsDir, withIntermediateDirectories: true)
            }
            
            let skillPath = antigravitySkillsDir.appendingPathComponent("SKILL.md")
            let skillContent = """
            ---
            name: bubble-toolbox
            description: Bubble provides tools for tagging, summarizing images, and retrieving contents of the user's clipboard.
            ---
            
            # Bubble Toolbox Skill
            
            This skill provides access to the `bubble-toolbox` MCP server, which exposes tools for interacting with the Bubble app.
            
            Available tools:
            - `get_latest_pasted_image`: Retrieves the path to the most recent image saved to the magic clipboard.
            - `get_file_summary`: Retrieves the AI-generated AI summary and tags for a given file path (useful for understanding images/documents).
            
            Usage:
            Use these tools to get context about files the user is working with, or to grab the latest image the user copied to their clipboard.
            """
            
            try skillContent.write(to: skillPath, atomically: true, encoding: .utf8)
            
            DispatchQueue.main.async {
                self.isClaudeCodeSkillInstalled = true
                self.statusMessage = "Installed Claude Code skill for Bubble!"
            }
        } catch {
            DispatchQueue.main.async {
                self.statusMessage = "Error installing skill: \(error.localizedDescription)"
            }
        }
    }
}

// MARK: - Premium UI Components

struct CardView<Content: View>: View {
    let title: String?
    let content: Content
    
    init(title: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let title = title {
                Text(title)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)
                    .tracking(1.2)
            }
            
            content
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
                .shadow(color: Color.black.opacity(0.1), radius: 10, x: 0, y: 5)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
    }
}

struct SettingsView: View {
    @ObservedObject var appState: AppState
    
    var body: some View {
        ZStack {
            // Iridescent Background
            LinearGradient(colors: [
                Color(red: 0.05, green: 0.05, blue: 0.1),
                Color(red: 0.1, green: 0.05, blue: 0.2)
            ], startPoint: .topLeading, endPoint: .bottomTrailing)
            .ignoresSafeArea()
            
            ScrollView {
                VStack(spacing: 24) {
                    // Hero Header
                    ZStack(alignment: .bottomLeading) {
                        Image("banner", bundle: .module)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(height: 120)
                            .clipped()
                            .mask(LinearGradient(gradient: Gradient(colors: [.black, .black.opacity(0.8), .clear]), startPoint: .top, endPoint: .bottom))
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Bubble")
                                .font(.system(size: 32, weight: .black, design: .rounded))
                                .foregroundStyle(
                                    LinearGradient(colors: [.white, .white.opacity(0.8)], startPoint: .top, endPoint: .bottom)
                                )
                            
                            Text("v1.0 • Toolbox for AI Builders")
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundColor(.accentColor.opacity(0.9))
                        }
                        .padding(.leading, 20)
                        .padding(.bottom, 20)
                    }
                    .padding(.top, 40)
                    .padding(.bottom, 10)

                    if !appState.statusMessage.isEmpty {
                        HStack {
                            Image(systemName: "sparkles")
                            Text(appState.statusMessage)
                                .font(.system(size: 13, weight: .medium))
                            Spacer()
                            Button(action: { appState.statusMessage = "" }) {
                                Image(systemName: "xmark.circle.fill")
                            }
                            .buttonStyle(.plain)
                        }
                        .padding()
                        .background(Color.accentColor.opacity(0.2))
                        .clipShape(Capsule())
                        .padding(.horizontal)
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }
                    
                    VStack(alignment: .leading, spacing: 24) {
                        // Section: Integrations
                        CardView(title: "Integrations") {
                            VStack(spacing: 0) {
                                IntegrationRow(
                                    name: "Claude Desktop",
                                    isInstalled: appState.isGlobalMCPInstalled,
                                    action: { appState.installGlobalMCP() }
                                )
                                
                                Divider().padding(.vertical, 8)
                                
                                IntegrationRow(
                                    name: "Antigravity",
                                    isInstalled: appState.isAntigravityMCPInstalled,
                                    action: { appState.installAntigravityMCP() }
                                )
                                
                                Divider().padding(.vertical, 8)
                                
                                IntegrationRow(
                                    name: "Claude Code Skill",
                                    isInstalled: appState.isClaudeCodeSkillInstalled,
                                    action: { appState.installClaudeCodeSkill() }
                                )
                                
                                Divider().padding(.vertical, 8)
                                
                                HStack {
                                    Label("Workspace MCPs", systemImage: "folder.badge.gearshape")
                                        .font(.body)
                                    Spacer()
                                    Text("\(appState.installedWorkspaceMCPs.values.filter{$0}.count) folders")
                                        .font(.caption)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 2)
                                        .background(Color.accentColor.opacity(0.2))
                                        .cornerRadius(4)
                                }
                            }
                        }

                        // Section: AI Configuration
                        CardView(title: "AI Configuration") {
                            VStack(alignment: .leading, spacing: 20) {
                                Picker("Provider", selection: $appState.provider) {
                                    ForEach(LLMProvider.allCases, id: \.self) { provider in
                                        Text(provider.rawValue).tag(provider)
                                    }
                                }
                                .pickerStyle(.segmented)
                                
                                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 12) {
                                    if appState.provider == .gemini {
                                        providerGridRow(label: "API Key", content: SecureField("Paste key...", text: $appState.geminiApiKey))
                                        providerGridRow(label: "Model", content: modelPicker(selection: $appState.geminiModel, options: appState.cachedModels.gemini))
                                    } else if appState.provider == .openAI {
                                        providerGridRow(label: "API Key", content: SecureField("Paste key...", text: $appState.openAIApiKey))
                                        providerGridRow(label: "Model", content: modelPicker(selection: $appState.openAIModel, options: appState.cachedModels.openAI))
                                    } else if appState.provider == .anthropic {
                                        providerGridRow(label: "API Key", content: SecureField("Paste key...", text: $appState.anthropicApiKey))
                                        providerGridRow(label: "Model", content: modelPicker(selection: $appState.anthropicModel, options: appState.cachedModels.anthropic))
                                    } else {
                                        providerGridRow(label: "Host", content: TextField("http://localhost:11434", text: $appState.ollamaHost))
                                        providerGridRow(label: "Model", content: modelPicker(selection: $appState.ollamaModel, options: appState.ollamaModels))
                                    }
                                }
                            }
                        }
    
                        // Section: Folder Automation
                        CardView(title: "Folder Automation") {
                            VStack(alignment: .leading, spacing: 16) {
                                HStack {
                                    Text("Monitored Folders")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                    Spacer()
                                    Button(action: { appState.addFolderAutomation() }) {
                                        Label("Add Folder", systemImage: "plus")
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .controlSize(.small)
                                }
                                
                                if appState.folderConfigs.isEmpty {
                                    Text("No folders tracked.")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .frame(maxWidth: .infinity, alignment: .center)
                                        .padding(.vertical, 20)
                                } else {
                                    ForEach($appState.folderConfigs) { $config in
                                        FolderAutomationRow(config: $config, appState: appState)
                                    }
                                }
                            }
                        }
                        
                        // Section: Activity Log
                        CardView(title: "Recent Activity") {
                            VStack(spacing: 0) {
                                if appState.taggingHistory.isEmpty {
                                    Text("Waiting for activity...")
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundColor(.secondary)
                                        .frame(maxWidth: .infinity, alignment: .center)
                                        .padding(.vertical, 40)
                                } else {
                                    ScrollView {
                                        VStack(spacing: 8) {
                                            ForEach(appState.taggingHistory) { event in
                                                HStack {
                                                    Circle()
                                                        .fill(event.status == "Complete" ? Color.green : Color.orange)
                                                        .frame(width: 6, height: 6)
                                                    Text(event.filename)
                                                        .font(.system(size: 11, design: .monospaced))
                                                    Spacer()
                                                    Text(event.timestamp, style: .time)
                                                        .font(.system(size: 10))
                                                        .foregroundColor(.secondary)
                                                }
                                                .padding(8)
                                                .background(Color.white.opacity(0.05))
                                                .cornerRadius(6)
                                            }
                                        }
                                    }
                                    .frame(height: 150)
                                    
                                    Button("Clear Console") {
                                        appState.clearTaggingHistory()
                                    }
                                    .buttonStyle(.link)
                                    .font(.system(size: 10, weight: .bold))
                                    .padding(.top, 12)
                                }
                            }
                        }
                        
                        // Section: Magic Clipboard
                        CardView(title: "Magic Clipboard") {
                            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 16) {
                                GridRow {
                                    Text("Status")
                                    Toggle("Auto-save on copy", isOn: $appState.isMagicClipboardEnabled)
                                        .toggleStyle(.switch)
                                }
                                Divider()
                                GridRow {
                                    Text("Storage")
                                    TextField("~/Pictures/Bubble", text: $appState.imageStorageDir)
                                        .textFieldStyle(.plain)
                                        .padding(8)
                                        .background(Color.black.opacity(0.2))
                                        .cornerRadius(6)
                                }
                                Divider()
                                GridRow {
                                    Text("Hotkey")
                                    ShortcutRecorderView(shortcut: $appState.shortcut)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 40)
                    
                    Text("crafted with care • Jade Kwon")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundColor(.secondary.opacity(0.5))
                        .padding(.bottom, 20)
                }
            }
        }
        .frame(width: 580, height: 800)
    }

    // MARK: - Settings Subviews
    @ViewBuilder
    func providerGridRow(label: String, content: some View) -> some View {
        GridRow {
            Text(label)
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.secondary)
                .frame(width: 80, alignment: .trailing)
            content
                .textFieldStyle(.plain)
                .padding(8)
                .background(Color.white.opacity(0.05))
                .cornerRadius(8)
        }
    }
    
    @ViewBuilder
    func modelPicker(selection: Binding<String>, options: [String]) -> some View {
        HStack {
            Picker("", selection: selection) {
                ForEach(options, id: \.self) { model in
                    Text(model).tag(model)
                }
                Divider()
                Text("Custom...").tag("custom")
            }
            .labelsHidden()
            
            Button(action: { Task { await appState.fetchRemoteModels() } }) {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.plain)
        }
    }
}


struct FolderAutomationRow: View {
    @Binding var config: FolderAutomationConfig
    let appState: AppState
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(config.resolvedURL()?.lastPathComponent ?? "Folder")
                        .font(.headline)
                    Text(config.resolvedURL()?.path ?? "")
                        .font(.system(size: 10, design: .monospaced))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundColor(.secondary)
                }
                Spacer()
                
                Button(action: { appState.executeFolderScan(config: config) }) {
                    Image(systemName: "play.circle.fill")
                        .font(.title2)
                        .symbolRenderingMode(.hierarchical)
                }
                .buttonStyle(.plain)
                .foregroundColor(.accentColor)
                
                Button(action: { appState.removeFolderAutomation(id: config.id) }) {
                    Image(systemName: "trash")
                        .foregroundColor(.red.opacity(0.8))
                }
                .buttonStyle(.plain)
            }
            
            HStack(spacing: 20) {
                Picker("Trigger", selection: $config.trigger) {
                    ForEach(AutomationTrigger.allCases, id: \.self) { trigger in
                        Text(trigger.rawValue).tag(trigger)
                    }
                }
                .controlSize(.small)
                
                if appState.installedWorkspaceMCPs[config.id] == true {
                    Label("MCP Active", systemImage: "bolt.fill")
                        .font(.caption2)
                        .foregroundColor(.green)
                } else {
                    Button("Install MCP") {
                        appState.installWorkspaceMCP(for: config)
                    }
                    .font(.caption2)
                    .buttonStyle(.link)
                }
            }
        }
        .padding(16)
        .background(Color.white.opacity(0.03))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.05), lineWidth: 1))
    }
}

// Global scope for supporting types to avoid scope errors
struct OllamaTagsResponse: Codable {
    struct Model: Codable { let name: String }
    let models: [Model]
}

struct OpenAIModelsResponse: Codable {
    struct Model: Codable { let id: String }
    let data: [Model]
}

struct AnthropicModelsResponse: Codable {
    struct Model: Codable { let id: String }
    let data: [Model]
}

struct GeminiModelsResponse: Codable {
    struct Model: Codable { let name: String }
    let models: [Model]
}

struct ShortcutConfig: Codable, Equatable {
    var key: String
    var modifiers: NSEvent.ModifierFlags
    
    enum CodingKeys: String, CodingKey {
        case key
        case modifiers
    }
    
    init(key: String, modifiers: NSEvent.ModifierFlags) {
        self.key = key
        self.modifiers = modifiers
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        key = try container.decode(String.self, forKey: .key)
        let rawModifiers = try container.decode(UInt.self, forKey: .modifiers)
        modifiers = NSEvent.ModifierFlags(rawValue: rawModifiers)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(key, forKey: .key)
        try container.encode(modifiers.rawValue, forKey: .modifiers)
    }
    
    var eventModifiers: EventModifiers {
        var mods: EventModifiers = []
        if modifiers.contains(.command) { mods.insert(.command) }
        if modifiers.contains(.shift) { mods.insert(.shift) }
        if modifiers.contains(.option) { mods.insert(.option) }
        if modifiers.contains(.control) { mods.insert(.control) }
        return mods
    }
    
    var displayString: String {
        var str = ""
        if modifiers.contains(.control) { str += "⌃" }
        if modifiers.contains(.option) { str += "⌥" }
        if modifiers.contains(.shift) { str += "⇧" }
        if modifiers.contains(.command) { str += "⌘" }
        str += key.uppercased()
        return str
    }
}


// Simple interactive recorder for the shortcut
struct ShortcutRecorderView: View {
    @Binding var shortcut: ShortcutConfig
    @State private var isRecording = false
    
    var body: some View {
        Button(action: { isRecording.toggle() }) {
            Text(isRecording ? "Press Keys..." : shortcut.displayString)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .tint(isRecording ? .blue : .secondary)
        .background(ShortcutField(shortcut: $shortcut, isRecording: $isRecording))
    }
}

// Helper to capture raw key events
struct ShortcutField: NSViewRepresentable {
    @Binding var shortcut: ShortcutConfig
    @Binding var isRecording: Bool
    
    func makeNSView(context: Context) -> NSView {
        let view = ShortcutNSView()
        view.onShortcutRecorded = { key, mods in
            shortcut = ShortcutConfig(key: key, modifiers: mods)
            isRecording = false
        }
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {
        if isRecording {
            nsView.window?.makeFirstResponder(nsView)
        }
    }
    
    class ShortcutNSView: NSView {
        var onShortcutRecorded: ((String, NSEvent.ModifierFlags) -> Void)?
        
        override var acceptsFirstResponder: Bool { true }
        
        override func keyDown(with event: NSEvent) {
            guard let characters = event.charactersIgnoringModifiers, !characters.isEmpty else {
                return
            }
            
            // Ignore just modifier keys
            let key = characters.lowercased()
            let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            
            if !modifiers.isEmpty {
                onShortcutRecorded?(key, modifiers)
            }
        }
    }
}

struct IntegrationRow: View {
    let name: String
    let isInstalled: Bool
    let action: () -> Void
    
    @State private var showingAlert = false
    
    var body: some View {
        GridRow {
            Text(name).font(.body)
            HStack {
                Spacer()
                Button(action: {
                    if isInstalled {
                        // Already installed, maybe show info or just re-run
                        action()
                    } else {
                        showingAlert = true
                    }
                }) {
                    HStack(spacing: 4) {
                        if isInstalled {
                            Image(systemName: "checkmark.circle.fill")
                            Text("Implemented")
                        } else {
                            Image(systemName: "arrow.down.circle")
                            Text("Implement")
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                }
                .buttonStyle(.bordered)
                .tint(isInstalled ? .green : .accentColor)
                .alert("Implementation Required", isPresented: $showingAlert) {
                    Button("Proceed") { action() }
                    Button("Cancel", role: .cancel) { }
                } message: {
                    Text("This will configure \(name) on your system. Grant permission to write configuration files?")
                }
            }
        }
    }
}
