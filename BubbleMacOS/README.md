# AI Metadata Tagger for macOS

A menu bar application that scans selected folders, analyzes file content using Gemini AI, and tags them with metadata (Extended Attributes) for easier retrieval by AI agents and Spotlight.

## Features
- **AI-Powered Tagging:** Automatically generates summaries and keywords for your files.
- **Native Integration:** Stores tags in macOS Extended Attributes (`com.gemini.ai.summary`, `com.gemini.ai.keywords`).
- **Unobtrusive:** Runs in the menu bar.
- **Privacy-Focused:** Only scans folders you select. API Key stored locally.

## Requirements
- macOS 13.0 or later.
- A Google Gemini API Key (get one from [aistudio.google.com](https://aistudio.google.com/)).

## Installation & Usage

1.  **Build the App:**
    ```bash
    cd AITagger
    swift build -c release
    ```
    The binary will be at `.build/release/AITagger`.

2.  **Run:**
    You can run it directly from terminal to see logs, or wrap it in an App Bundle.
    ```bash
    ./.build/release/AITagger
    ```

3.  **Using the App:**
    - Click the Menu Bar icon (Tag symbol).
    - Go to **Set API Key...** and paste your Gemini API Key.
    - Click **Select Folder to Scan...** and choose a directory containing text/code files.
    - The status will change to "Scanning...".
    - Once finished, files in that folder will have metadata attached.

4.  **Verifying Tags:**
    Open Terminal and check a processed file:
    ```bash
    xattr -l path/to/processed/file.txt
    ```
    You should see:
    ```
    com.gemini.ai.summary: ...
    com.gemini.ai.keywords: ...
    ```

## CLI Usage (Optional)
This project also includes a CLI tool for scripting or testing.

```bash
swift run AITaggerCLI --api-key YOUR_KEY --scan /path/to/folder
```

## Project Structure
- `Sources/AITagger`: Main application entry point and UI.
- `Sources/AITaggerCore`: Core logic (Scanning, AI Service).
