import Foundation
import AITaggerCore

@main
struct AITaggerCLI {
    static func main() async {
        let args = CommandLine.arguments
        
        // Help or usage
        if args.count < 3 {
            print("""
            Usage: AITaggerCLI --scan <folder-path> [options]
            
            Options:
              --provider [gemini|ollama] (default: gemini)
              --api-key <key>           (required for gemini)
              --model <name>             (default: gemini-pro or llama3)
              --host <url>               (default: http://localhost:11434 for ollama)
            """)
            return
        }
        
        // Parsing
        let folderPath = getArgValue(for: "--scan", in: args) ?? ""
        let providerStr = getArgValue(for: "--provider", in: args) ?? "gemini"
        let apiKey = getArgValue(for: "--api-key", in: args) ?? ""
        let model = getArgValue(for: "--model", in: args) ?? (providerStr == "gemini" ? "gemini-pro" : "llama3")
        let host = getArgValue(for: "--host", in: args)
        
        let provider: LLMProvider = providerStr == "ollama" ? .ollama : .gemini
        let folderURL = URL(fileURLWithPath: folderPath)
        
        print("Starting CLI Scan on: \(folderPath) using \(providerStr)")
        
        let config = LLMConfiguration(apiKey: apiKey, model: model, host: host)
        let engine = ScanningEngine()
        
        await engine.scanAndTag(folder: folderURL, provider: provider, configuration: config) { progress in
            print("[Progress] \(progress)")
        }
        
        print("Done.")
    }
    
    private static func getArgValue(for key: String, in args: [String]) -> String? {
        if let idx = args.firstIndex(of: key), idx + 1 < args.count {
            return args[idx + 1]
        }
        return nil
    }
}
