import SwiftUI
import AppKit
import BubbleCore

public class ClipboardService {
    private let fileManager = FileManager.default
    
    public init() {}
    
    public func convertClipboardImageToFile(storageDir: String, sshPrefix: String = "", overridePath: String? = nil) -> String? {
        let pasteboard = NSPasteboard.general
        
        // If we have an override path (e.g. from Remote Sync), we just want to update the clipboard
        // string without saving a new image (or using the existing image data)
        if let override = overridePath {
            augmentClipboard(with: override)
            return override
        }
        
        // 1. Check for image data in clipboard
        // We prefer TIFF then PNG as source
        guard let imageType = pasteboard.availableType(from: [.tiff, .png]),
              let imageData = pasteboard.data(forType: imageType) else {
            return nil
        }
        
        // Check if we already processed this image to avoid loops
        if let existingString = pasteboard.string(forType: .string),
           existingString.contains("bubble_image_") {
            return nil
        }
        
        guard let image = NSImage(data: imageData) else {
            return nil
        }
        
        // 2. Prepare storage directory
        let expandedDir = (storageDir as NSString).expandingTildeInPath
        let dirURL = URL(fileURLWithPath: expandedDir)
        
        do {
            if !fileManager.fileExists(atPath: expandedDir) {
                try fileManager.createDirectory(at: dirURL, withIntermediateDirectories: true)
            }
            
            // 3. Generate filename based on timestamp
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyyMMdd_HHmmss"
            let filename = "bubble_image_\(formatter.string(from: Date())).png"
            let fileURL = dirURL.appendingPathComponent(filename)
            
            // 4. Convert image to PNG and save
            guard let tiffRepresentation = image.tiffRepresentation,
                  let bitmap = NSBitmapImageRep(data: tiffRepresentation),
                  let pngData = bitmap.representation(using: .png, properties: [:]) else {
                return nil
            }
            
            try pngData.write(to: fileURL)
            
            // 5. Build the final path with SSH prefix if provided
            let finalPath: String
            if !sshPrefix.isEmpty {
                finalPath = sshPrefix.appending(filename)
            } else {
                finalPath = fileURL.path
            }
            
            // 6. Augment the clipboard (Non-Destructive)
            augmentClipboard(with: finalPath, originalData: imageData, originalType: imageType)
            
            return finalPath
            
        } catch {
            print("ClipboardService Error: \(error)")
            return nil
        }
    }
    
    private func augmentClipboard(with path: String, originalData: Data? = nil, originalType: NSPasteboard.PasteboardType? = nil) {
        let pasteboard = NSPasteboard.general
        var items: [NSPasteboardItem] = []
        
        if let currentItems = pasteboard.pasteboardItems {
            for item in currentItems {
                let newItem = NSPasteboardItem()
                for type in item.types {
                    if let data = item.data(forType: type) {
                        newItem.setData(data, forType: type)
                    }
                }
                // Add our new path as the primary string representation
                newItem.setString(path, forType: .string)
                items.append(newItem)
            }
        }
        
        if items.isEmpty {
            pasteboard.clearContents()
            if let data = originalData, let type = originalType {
                pasteboard.setData(data, forType: type)
            }
            pasteboard.setString(path, forType: .string)
        } else {
            pasteboard.clearContents()
            pasteboard.writeObjects(items)
        }
    }
}
