import Foundation

struct OllamaRequest: Encodable {
    let model: String
    let prompt: String
    let stream: Bool
}

struct OllamaResponse: Decodable {
    let response: String?
}

public actor OllamaService: LLMService {
    private let session = URLSession.shared
    
    public init() {}
    
    public func generateTags(for text: String, configuration: LLMConfiguration) async throws -> (summary: String, keywords: [String]) {
        let host = configuration.host ?? "http://localhost:11434"
        let endpoint = URL(string: "\(host)/api/generate")!
        
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let truncatedText = String(text.prefix(5000)) // Local models usually have smaller context windows
        let prompt = """
        Analyze the following file content. Provide:
        1. A concise summary (max 2 sentences).
        2. A list of 5-10 relevant keywords/tags (comma-separated).
        
        Format the output exactly like this:
        Summary: [Your summary here]
        Tags: [tag1, tag2, tag3]
        
        Content:
        \(truncatedText)
        """
        
        let payload = OllamaRequest(model: configuration.model, prompt: prompt, stream: false)
        request.httpBody = try JSONEncoder().encode(payload)
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
             throw URLError(.badServerResponse)
        }
        
        let ollamaResponse = try JSONDecoder().decode(OllamaResponse.self, from: data)
        guard let responseText = ollamaResponse.response else {
            throw URLError(.cannotParseResponse)
        }
        
        return parseResponse(responseText)
    }
    
    private func parseResponse(_ text: String) -> (summary: String, keywords: [String]) {
        var summary = ""
        var keywords: [String] = []
        
        let lines = text.split(separator: "\n")
        for line in lines {
            if line.lowercased().starts(with: "summary:") {
                summary = String(line.dropFirst(8)).trimmingCharacters(in: .whitespacesAndNewlines)
            } else if line.lowercased().starts(with: "tags:") {
                let tagsPart = String(line.dropFirst(5))
                    .replacingOccurrences(of: "[", with: "")
                    .replacingOccurrences(of: "]", with: "")
                keywords = tagsPart.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            }
        }
        
        if summary.isEmpty && !text.isEmpty {
            summary = String(text.prefix(200))
        }
        
        return (summary, keywords)
    }
}
