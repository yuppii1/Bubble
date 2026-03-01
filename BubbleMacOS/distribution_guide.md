# App Store Distribution Guide

To release AITagger on the Mac App Store, follow these steps:

## 1. Prerequisites
- **Apple Developer Account:** Enrollment in the Apple Developer Program.
- **Xcode:** Latest stable version installed.
- **App Icon:** A complete `AppIcon.appiconset` with all required sizes (16x16 up to 1024x1024).

## 2. Xcode Configuration
1. **Open AITagger:** Open the `AITagger` folder in Xcode.
2. **Project Settings:**
   - Select the **AITagger** target.
   - Go to **Signing & Capabilities**.
   - Ensure **App Sandbox** is enabled.
   - Verify that **Incoming Connections** and **User Selected File Access** (Read/Write) are checked.
3. **Bundle Identifier:** Ensure your Bundle ID (e.g., `com.yourname.AITagger`) is unique and configured in App Store Connect.

## 3. Sandboxing & Entitlements
AITagger uses the `AITagger.entitlements` file provided in this repository. In Xcode, ensure this file is linked under **Build Settings > Code Signing Entitlements**.

## 4. Archiving and Submission
1. Set the build destination to **Any Mac (Apple Silicon, Intel)**.
2. Go to **Product > Archive**.
3. Once the archive is complete, click **Validate App** to check for common issues.
4. Click **Distribute App** and follow the prompts to upload to App Store Connect.

## 5. App Store Connect Metadata
- **Privacy Policy URL:** Host the `PRIVACY_POLICY.md` content on your website or use a GitHub gist.
- **Description:** Use the description from the root `README.md`.
- **Keywords:** AI, productivity, organization, file manager, tags, metadata.

---
> [!IMPORTANT]
> Apple requires Mac App Store apps to be sandboxed. If AITagger cannot access certain folders, ensure the user selects the folder via a `NSOpenPanel` so the sandbox "Powerbox" grants temporary permission.
