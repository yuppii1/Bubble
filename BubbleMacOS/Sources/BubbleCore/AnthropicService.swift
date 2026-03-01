import Foundation

struct AnthropicRequest: Encodable {
    let model: String
    let max_tokens: Int
    let messages: [Message]
    
    struct Message: Encodable {
        let role: String
        let content: String
    }
}

struct AnthropicResponse: Decodable {
    let content: [ContentElement]?
    
    struct ContentElement: Decodable {
        let text: String?
    }
}

public actor AnthropicService: LLMService {
    private let session = URLSession.shared
    private let baseURL = URL(string: "https://api.anthropic.com/v1/messages")!

    public init() {}
    
    public func generateTags(for text: String, configuration: LLMConfiguration) async throws -> (summary: String, keywords: [String]) {
        var request = URLRequest(url: baseURL)
        request.httpMethod = "POST"
        request.addValue(configuration.apiKey, forHTTPHeaderField: "x-api-key")
        request.addValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.addValue("application/json", forHTTPHeaderField: "content-type")
        
        // Anthropic models usually have large context windows
        let truncatedText = String(text.prefix(30000))
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
        
        let payload = AnthropicRequest(
            model: configuration.model.isEmpty ? "claude-3-5-sonnet-20241022" : configuration.model,
            max_tokens: 1024,
            messages: [.init(role: "user", content: prompt)]
        )
        request.httpBody = try JSONEncoder().encode(payload)
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            if let errorText = String(data: data, encoding: .utf8) {
                print("Anthropic API Error: \(errorText)")
            }
            throw URLError(.badServerResponse)
        }
        
        let anthropicResponse = try JSONDecoder().decode(AnthropicResponse.self, from: data)
        guard let responseText = anthropicResponse.content?.first?.text else {
            throw URLError(.cannotParseResponse)
        }
        
        return parseResponse(responseText)
    }
    
    private func parseResponse(_ text: String) -> (summary: String, keywords: [String]) {
        var summary = ""
        var keywords: [String] = []
        
        let lines = text.split(separator: "\n")
        for line in lines {
            if line.starts(with: "Summary:") {
                summary = String(line.dropFirst(8)).trimmingCharacters(in: .whitespacesAndNewlines)
            } else if line.starts(with: "Tags:") {
                let tagsPart = String(line.dropFirst(5))
                keywords = tagsPart.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            }
        }
        
        if summary.isEmpty && !text.isEmpty {
            summary = String(text.prefix(200))
        }
        
        return (summary, keywords)
    }
}
