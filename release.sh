#!/bin/bash

# Bubble Build & Release Script
# Generates optimized, statically-linked binaries for multiple platforms.

PROJECT_NAME="bubble"
BUILD_DIR="./releases"
SOURCE_DIR="./BubbleLinuxGo"

# Create releases directory
mkdir -p $BUILD_DIR

echo "🚀 Starting builds for $PROJECT_NAME..."

# Build binaries
cd $SOURCE_DIR
PROJECT_NAME="bubble"
# Use absolute path for BUILD_DIR relative to script origin or just path it
BUILD_DIR_ABS="../releases"

# 1. Linux AMD64
echo "🐧 Building Linux AMD64..."
CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -ldflags="-s -w" -o $BUILD_DIR_ABS/${PROJECT_NAME}-linux-amd64 .

# 2. Linux ARM64
echo "🍓 Building Linux ARM64..."
CGO_ENABLED=0 GOOS=linux GOARCH=arm64 go build -ldflags="-s -w" -o $BUILD_DIR_ABS/${PROJECT_NAME}-linux-arm64 .

# 3. macOS ARM64
echo "🍏 Building macOS ARM64 CLI..."
CGO_ENABLED=0 GOOS=darwin GOARCH=arm64 go build -ldflags="-s -w" -o $BUILD_DIR_ABS/${PROJECT_NAME}-darwin-arm64 .

# 4. Windows AMD64
echo "🪟 Building Windows AMD64..."
CGO_ENABLED=0 GOOS=windows GOARCH=amd64 go build -ldflags="-s -w" -o $BUILD_DIR_ABS/${PROJECT_NAME}-windows-amd64.exe .
cd ..

echo "✅ All builds complete! Binaries are in the $BUILD_DIR directory."
ls -lh $BUILD_DIR
