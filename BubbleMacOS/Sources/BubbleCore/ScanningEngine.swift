import Foundation
import CoreServices

// MARK: - Models for Summary Persistence

public struct FileSummary: Codable, Equatable {
    public let summary: String
    public let keywords: [String]
    public let lastProcessed: Date
    public let fileSize: Int64
    public let modificationDate: Date
}

public struct ProjectSummary: Codable {
    public var files: [String: FileSummary] = [:]
}

public actor ScanningEngine {
    private let fileManager = FileManager.default
    private let processingQueue = DispatchQueue(label: "com.gemini.ai.scanner", qos: .utility)
    
    public init() {}
    
    // Ignore patterns
    private let ignoreExtensions = ["app", "dSYM", "framework", "xctest", "o", "a", "dylib", "so", "dll", "class", "pyc", "png", "jpg", "jpeg", "gif", "pdf", "zip", "tar", "gz"]
    private let ignoreDirectories = [".git", ".svn", "node_modules", "build", "dist", ".gemini", ".bubble"]
    
    public func scanAndTag(folder: URL, provider: LLMProvider, configuration: LLMConfiguration, onProgress: @escaping (String) -> Void) async {
        let enumerator = fileManager.enumerator(at: folder, includingPropertiesForKeys: [.isRegularFileKey, .isHiddenKey, .contentModificationDateKey, .fileSizeKey], options: [.skipsHiddenFiles, .skipsPackageDescendants])
        
        let service: LLMService
        switch provider {
        case .gemini: service = GeminiService()
        case .openAI: service = OpenAIService()
        case .anthropic: service = AnthropicService()
        case .ollama: service = OllamaService()
        }
        
        // Load existing summaries
        let bubbleDir = folder.appendingPathComponent(".bubble")
        let summariesURL = bubbleDir.appendingPathComponent("summaries.json")
        var projectSummary = ProjectSummary()
        
        if let data = try? Data(contentsOf: summariesURL),
           let decoded = try? JSONDecoder().decode(ProjectSummary.self, from: data) {
            projectSummary = decoded
        }
        
        var filesToProcess: [URL] = []
        var filesToSkip: Int = 0
        
        while let fileURL = enumerator?.nextObject() as? URL {
            if fileURL.hasDirectoryPath {
                 if ignoreDirectories.contains(fileURL.lastPathComponent) {
                     enumerator?.skipDescendants()
                 }
                 continue
             }
            
            guard shouldProcess(fileURL) else { continue }
            
            let relativePath = fileURL.path.replacingOccurrences(of: folder.path + "/", with: "")
            
            // Check if we already have a valid summary
            if let existing = projectSummary.files[relativePath] {
                let attrs = try? fileManager.attributesOfItem(atPath: fileURL.path)
                let modDate = attrs?[.modificationDate] as? Date ?? Date.distantPast
                let size = attrs?[.size] as? Int64 ?? 0
                
                if existing.modificationDate == modDate && existing.fileSize == size {
                    filesToSkip += 1
                    continue
                }
            }
            
            filesToProcess.append(fileURL)
        }
        
        onProgress("Found \(filesToProcess.count) new/updated files (skipped \(filesToSkip)).")
        
        if filesToProcess.isEmpty {
            onProgress("Scan Complete (Everything up to date)!")
            return
        }
        
        for (index, fileURL) in filesToProcess.enumerated() {
            if Task.isCancelled { break }
            
            onProgress("Processing \(index + 1)/\(filesToProcess.count): \(fileURL.lastPathComponent)")
            
            do {
                let content = try String(contentsOf: fileURL, encoding: .utf8)
                
                if provider == .gemini {
                    try await Task.sleep(nanoseconds: 1_000_000_000) 
                }
                
                let (summary, keywords) = try await service.generateTags(for: content, configuration: configuration)
                
                try writeMetadata(to: fileURL, summary: summary, keywords: keywords)
                
                // Update persistent cache
                let relativePath = fileURL.path.replacingOccurrences(of: folder.path + "/", with: "")
                let attrs = try? fileManager.attributesOfItem(atPath: fileURL.path)
                let modDate = attrs?[.modificationDate] as? Date ?? Date.distantPast
                let size = attrs?[.size] as? Int64 ?? 0
                
                projectSummary.files[relativePath] = FileSummary(
                    summary: summary,
                    keywords: keywords,
                    lastProcessed: Date(),
                    fileSize: size,
                    modificationDate: modDate
                )
                
                // Save periodically (every 5 files) or at the end
                if (index + 1) % 5 == 0 || index == filesToProcess.count - 1 {
                    try saveSummaries(projectSummary, to: summariesURL)
                }
                
                print("Tagged: \(fileURL.lastPathComponent)")
            } catch {
                print("Failed to process \(fileURL.lastPathComponent): \(error)")
            }
        }
        
        onProgress("Scan Complete!")
    }
    
    private func saveSummaries(_ summary: ProjectSummary, to url: URL) throws {
        let bubbleDir = url.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: bubbleDir.path) {
            try fileManager.createDirectory(at: bubbleDir, withIntermediateDirectories: true)
            // Try to make it hidden on macOS
            var urlWithHidden = bubbleDir
            var resourceValues = URLResourceValues()
            resourceValues.isHidden = true
            try urlWithHidden.setResourceValues(resourceValues)
        }
        
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(summary)
        try data.write(to: url)
    }
    
    private func shouldProcess(_ url: URL) -> Bool {
        if ignoreExtensions.contains(url.pathExtension.lowercased()) { return false }
        return true
    }
    
    private func writeMetadata(to url: URL, summary: String, keywords: [String]) throws {
        let summaryData = summary.data(using: .utf8)!
        let keywordsData = keywords.joined(separator: ", ").data(using: .utf8)!
        let timestampData = ISO8601DateFormatter().string(from: Date()).data(using: .utf8)!
        
        try url.setExtendedAttribute(data: summaryData, forName: "com.gemini.ai.summary")
        try url.setExtendedAttribute(data: keywordsData, forName: "com.gemini.ai.keywords")
        try url.setExtendedAttribute(data: timestampData, forName: "com.gemini.ai.last_processed")
        
        do {
            let plistData = try PropertyListSerialization.data(fromPropertyList: keywords, format: .binary, options: 0)
            try url.setExtendedAttribute(data: plistData, forName: "com.apple.metadata:_kMDItemUserTags")
        } catch {
            print("Warning: Failed to encode native Finder tags for \(url.lastPathComponent) - \(error)")
        }
    }
}

extension URL {
    func setExtendedAttribute(data: Data, forName name: String) throws {
        try self.withUnsafeFileSystemRepresentation { fileSystemPath in
            guard let fileSystemPath = fileSystemPath else { return }
            let result = setxattr(fileSystemPath, name, (data as NSData).bytes, data.count, 0, 0)
            if result < 0 {
                throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno), userInfo: nil)
            }
        }
    }
}
