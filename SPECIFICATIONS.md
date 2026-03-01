# AI Metadata Tagger - Project Specifications & Plan

This document outlines the architecture, data schema, and development instructions for the AI Metadata Tagger macOS application.

## 1. Overview
The AI Metadata Tagger is a macOS Menu Bar application designed to enhance file discoverability for both humans and AI agents. It scans local directories, analyzes file content using Large Language Models (LLMs), and embeds the resulting metadata directly into the file's filesystem attributes.

## 2. Technical Architecture

### Core Components
- **AITagger (App):** A SwiftUI/AppKit-based Menu Bar extra. Manages user configuration (API keys, provider selection, target folders) and provides status updates.
- **AITaggerCore (Library):** The business logic layer.
    - **ScanningEngine:** Handles recursive file enumeration, filtering (ignoring binary/hidden files), and the processing pipeline.
    - **LLMService (Protocol):** Defines the interface for inference.
    - **GeminiService:** Remote LLM inference via Google Generative AI API.
    - **OllamaService:** Local LLM inference via Ollama API.
- **AITaggerCLI (Executable):** A lightweight command-line interface for headless scanning and debugging.

### Data Flow
1. **User Input:** User selects a provider (Gemini or Ollama) and a folder.
2. **Enumeration:** `ScanningEngine` performs a recursive crawl.
3. **Analysis:** For each eligible file, the selected `LLMService` (Gemini or Ollama) generates a summary and keywords.
4. **Injection:** The engine writes the results back to the file using the `setxattr` system call.

## 3. Metadata Schema (Extended Attributes)
The app uses the following keys for storage:

| Key | Description | Format |
| :--- | :--- | :--- |
| `com.gemini.ai.summary` | A 1-2 sentence description of the file content. | UTF-8 String |
| `com.gemini.ai.keywords` | Comma-separated list of 5-10 tags. | UTF-8 String |
| `com.gemini.ai.last_processed` | Timestamp of the last successful AI scan. | ISO 8601 String |

## 4. Development & Build Instructions

### Prerequisites
- **macOS:** 13.0+
- **Swift:** 5.9+
- **Ollama (Optional):** Required for local inference. Install from [ollama.com](https://ollama.com/).

### Build via Swift Package Manager (Terminal)
```bash
# Clone/Navigate to the directory
cd AITagger

# Build all targets
swift build

# Run the CLI version (Gemini)
swift run AITaggerCLI --scan /path/to/folder --api-key YOUR_KEY

# Run the CLI version (Ollama)
swift run AITaggerCLI --scan /path/to/folder --provider ollama --model llama3

# Run the Menu Bar App
./.build/debug/AITagger
```

### IDE Specific Instructions

#### Xcode
1. Open Xcode.
2. Select **File > Open**.
3. Select the `Package.swift` file in the `AITagger` directory.
4. Select the `AITagger` scheme and click **Run**.

#### VS Code / Cursor / Zed
1. Install the **Swift** extension.
2. Open the `AITagger` folder.
3. The IDE should automatically detect the `Package.swift` and provide build/run options.

## 5. Implementation Status
- [x] Project scaffolding (SwiftPM)
- [x] Menu Bar UI skeleton
- [x] File Scanning Engine (with ignore patterns)
- [x] Gemini API Integration
- [x] Ollama Local Inference Integration
- [x] Provider switching UI
- [x] Xattr writing logic
- [x] Shared library architecture (`AITaggerCore`)
- [x] CLI testing utility
- [ ] Security-scoped bookmarks (Persistence for sandboxed app - *Planned for v2*)
- [ ] Progress bar / Detailed queue view (*Planned for v2*)
