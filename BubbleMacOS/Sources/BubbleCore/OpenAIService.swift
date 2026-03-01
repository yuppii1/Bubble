import Foundation

struct OpenAIRequest: Encodable {
    let model: String
    let messages: [Message]
    
    struct Message: Encodable {
        let role: String
        let content: String
    }
}

struct OpenAIResponse: Decodable {
    let choices: [Choice]?
    
    struct Choice: Decodable {
        let message: Message?
        
        struct Message: Decodable {
            let content: String?
        }
    }
}

public actor OpenAIService: LLMService {
    private let session = URLSession.shared
    private let baseURL = URL(string: "https://api.openai.com/v1/chat/completions")!

    public init() {}
    
    public func generateTags(for text: String, configuration: LLMConfiguration) async throws -> (summary: String, keywords: [String]) {
        var request = URLRequest(url: baseURL)
        request.httpMethod = "POST"
        request.addValue("Bearer \(configuration.apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let truncatedText = String(text.prefix(15000))
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
        
        let payload = OpenAIRequest(
            model: configuration.model.isEmpty ? "gpt-4o" : configuration.model,
            messages: [.init(role: "user", content: prompt)]
        )
        request.httpBody = try JSONEncoder().encode(payload)
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            if let errorText = String(data: data, encoding: .utf8) {
                print("OpenAI API Error: \(errorText)")
            }
            throw URLError(.badServerResponse)
        }
        
        let openAIResponse = try JSONDecoder().decode(OpenAIResponse.self, from: data)
        guard let responseText = openAIResponse.choices?.first?.message?.content else {
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
