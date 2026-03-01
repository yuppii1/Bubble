import Foundation
import CoreServices

public actor ScanningEngine {
    private let fileManager = FileManager.default
    private let processingQueue = DispatchQueue(label: "com.gemini.ai.scanner", qos: .utility)
    
    public init() {}
    
    // Ignore patterns
    private let ignoreExtensions = ["app", "dSYM", "framework", "xctest", "o", "a", "dylib", "so", "dll", "class", "pyc", "png", "jpg", "jpeg", "gif", "pdf", "zip", "tar", "gz"]
    private let ignoreDirectories = [".git", ".svn", "node_modules", "build", "dist", ".gemini"]
    
    public func scanAndTag(folder: URL, provider: LLMProvider, configuration: LLMConfiguration, onProgress: @escaping (String) -> Void) async {
        let enumerator = fileManager.enumerator(at: folder, includingPropertiesForKeys: [.isRegularFileKey, .isHiddenKey, .contentModificationDateKey], options: [.skipsHiddenFiles, .skipsPackageDescendants])
        
        let service: LLMService
        switch provider {
        case .gemini: service = GeminiService()
        case .openAI: service = OpenAIService()
        case .anthropic: service = AnthropicService()
        case .ollama: service = OllamaService()
        }
        
        var filesToProcess: [URL] = []
        
        while let fileURL = enumerator?.nextObject() as? URL {
            if fileURL.hasDirectoryPath {
                 if ignoreDirectories.contains(fileURL.lastPathComponent) {
                     enumerator?.skipDescendants()
                 }
                 continue
            }
            
            guard shouldProcess(fileURL) else { continue }
            filesToProcess.append(fileURL)
        }
        
        onProgress("Found \(filesToProcess.count) eligible files.")
        
        for (index, fileURL) in filesToProcess.enumerated() {
            if Task.isCancelled { break }
            
            onProgress("Processing \(index + 1)/\(filesToProcess.count): \(fileURL.lastPathComponent)")
            
            do {
                let content = try String(contentsOf: fileURL, encoding: .utf8)
                
                // Gemini might need more delay than local Ollama, but let's keep it safe.
                if provider == .gemini {
                    try await Task.sleep(nanoseconds: 1_000_000_000) 
                }
                
                let (summary, keywords) = try await service.generateTags(for: content, configuration: configuration)
                
                try writeMetadata(to: fileURL, summary: summary, keywords: keywords)
                
                print("Tagged: \(fileURL.lastPathComponent)")
            } catch {
                print("Failed to process \(fileURL.lastPathComponent): \(error)")
            }
        }
        
        onProgress("Scan Complete!")
    }
    
    private func shouldProcess(_ url: URL) -> Bool {
        // Extension check
        if ignoreExtensions.contains(url.pathExtension.lowercased()) { return false }
        
        // Check if already processed recently?
        // For MVP, we'll re-process if the file modification date > last processed date.
        // But for now, let's just check if it has the xattr already to save API calls.
        // If the user wants to force re-scan, they can clear xattrs manually or we add a force flag.
        
        // Check if file is text readable (simple heuristic)
        // rigorous check would use UTType but let's trust extension + try-read
        
        return true
    }
    
    private func writeMetadata(to url: URL, summary: String, keywords: [String]) throws {
        let summaryData = summary.data(using: .utf8)!
        let keywordsData = keywords.joined(separator: ", ").data(using: .utf8)!
        let timestampData = ISO8601DateFormatter().string(from: Date()).data(using: .utf8)!
        
        try url.setExtendedAttribute(data: summaryData, forName: "com.gemini.ai.summary")
        try url.setExtendedAttribute(data: keywordsData, forName: "com.gemini.ai.keywords")
        try url.setExtendedAttribute(data: timestampData, forName: "com.gemini.ai.last_processed")
        
        // Write to native macOS Finder Tags (Spotlight searchable)
        // Finder tags are stored as a binary plist array of strings in the `com.apple.metadata:_kMDItemUserTags` xattr
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
