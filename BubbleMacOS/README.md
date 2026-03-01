# Bubble for macOS

A menu bar application that scans selected folders, analyzes file content using Gemini AI, and tags them with metadata.

## Features
- **AI-Powered Tagging:** Automatically generates summaries and keywords for your files.
- **Persistent Summaries:** Version 0.0.2 introduces local `.bubble/summaries.json` for massive token savings.
- **Native Integration:** Stores tags in macOS Extended Attributes (`user.summary`, `user.keywords`).
- **Unobtrusive:** Runs in the menu bar.
- **Privacy-Focused:** Only scans folders you select. API Key stored locally.

## Requirements
- macOS 13.0 or later.
- A Google Gemini API Key (get one from [aistudio.google.com](https://aistudio.google.com/)).

## Installation & Usage

1.  **Build the App:**
    ```bash
    ./build_macos.sh
    ```
    The app bundle will be at `build/Bubble.app`.

2.  **Using the App:**
    - Click the Menu Bar icon (Bubble symbol).
    - Select a provider and enter your API Key.
    - Click **Select Folder to Scan...** and choose a directory.

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
