import Foundation

public protocol LLMService: Sendable {
    func generateTags(for text: String, configuration: LLMConfiguration) async throws -> (summary: String, keywords: [String])
}

public enum LLMProvider: String, Codable, CaseIterable {
    case gemini = "Gemini"
    case openAI = "OpenAI"
    case anthropic = "Anthropic"
    case ollama = "Ollama"
}

public struct LLMConfiguration: Sendable {
    public let apiKey: String
    public let model: String
    public let host: String? // Used for Ollama (e.g., http://localhost:11434)
    
    public init(apiKey: String, model: String, host: String? = nil) {
        self.apiKey = apiKey
        self.model = model
        self.host = host
    }
}
