#!/bin/bash

# Bubble One-Click Installer
# Downloads, builds, and sets up Bubble locally.

echo "🚀 Starting Bubble installation..."

# 1. Check for Go
if ! command -v go &> /dev/null
then
    echo "❌ Error: Go is not installed. Please install it from https://go.dev/dl/"
    exit 1
fi

# 2. Build the CLI
echo "📦 Building Bubble CLI..."
cd BubbleLinuxGo || exit
go build -o bubble main.go

# 3. Create a symbolic link to make it accessible globally (optional/local)
echo "✅ Bubble is ready!"

# 4. Interactive Setup
echo ""
read -p "❓ Would you like to configure your API key now? (y/N): " SETUP_NOW
if [[ "$SETUP_NOW" =~ ^([yY][eE][sS]|[yY])$ ]]; then
    echo "Supported providers: gemini, openai, anthropic"
    read -p "Enter provider: " PROVIDER
    read -p "Enter API Key: " API_KEY
    ./bubble --provider "$PROVIDER" --api-key "$API_KEY" --save
    echo "✅ Configuration saved to ~/.bubble_config.json"
else
    echo "⏭️ Skipping setup. You can configure it later using:"
    echo "   ./bubble --provider <provider> --api-key <key> --save"
fi

echo ""
echo "🚀 Installation complete! Run './bubble --help' for usage."

