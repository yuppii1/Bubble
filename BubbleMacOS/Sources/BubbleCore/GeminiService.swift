import Foundation

struct GeminiRequest: Encodable {
    let contents: [Content]
    
    struct Content: Encodable {
        let parts: [Part]
    }
    
    struct Part: Encodable {
        let text: String
    }
}

struct GeminiResponse: Decodable {
    let candidates: [Candidate]?
    
    struct Candidate: Decodable {
        let content: Content?
        
        struct Content: Decodable {
            let parts: [Part]?
        }
        
        struct Part: Decodable {
            let text: String?
        }
    }
}

public actor GeminiService: LLMService {
    private let session = URLSession.shared
    public init() {}
    
    public func generateTags(for text: String, configuration: LLMConfiguration) async throws -> (summary: String, keywords: [String]) {
        // Construct the URL dynamically using the provided model name (e.g. gemini-2.5-flash)
        let endpoint = "https://generativelanguage.googleapis.com/v1beta/models/\(configuration.model):generateContent"
        guard let url = URL(string: endpoint) else {
            throw URLError(.badURL)
        }
        
        var request = URLRequest(url: url.appending(queryItems: [URLQueryItem(name: "key", value: configuration.apiKey)]))
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Truncate text to avoid token limits (e.g., first 10,000 chars)
        let truncatedText = String(text.prefix(10000))
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
        
        let payload = GeminiRequest(contents: [.init(parts: [.init(text: prompt)])])
        request.httpBody = try JSONEncoder().encode(payload)
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            if let errorText = String(data: data, encoding: .utf8) {
                print("Gemini API Error: \(errorText)")
            }
            throw URLError(.badServerResponse)
        }
        
        let geminiResponse = try JSONDecoder().decode(GeminiResponse.self, from: data)
        guard let responseText = geminiResponse.candidates?.first?.content?.parts?.first?.text else {
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
        
        // Fallback if parsing fails but text exists (e.g. model didn't follow format strictly)
        if summary.isEmpty && !text.isEmpty {
            summary = String(text.prefix(200)) // First 200 chars as summary
        }
        
        return (summary, keywords)
    }
}
