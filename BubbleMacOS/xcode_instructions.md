# Getting Started with AITagger in Xcode

AITagger is built as a Swift Package rather than a traditional `.xcodeproj` file. Fortunately, Xcode has native support for Swift Packages and can open, build, and run the project seamlessly.

Here are the step-by-step instructions:

## 1. Opening the Project in Xcode
1. Open **Xcode**.
2. From the welcome screen, click **Open Existing Project...** (or go to **File > Open...** in the menu bar).
3. Navigate to your project folder: `JIMI/Bubble/AITagger`.
4. Select the `AITagger` folder (or the `Package.swift` file inside it) and click **Open**.
5. *Wait a moment* for Xcode to load the package and process the files. You'll see a progress bar at the top as it analyzes the `Package.swift` file.

## 2. Selecting the Target to Run
Your project contains two executable products: the main menu bar app (`AITagger`) and a command-line tool (`AITaggerCLI`).
1. Look at the **top center of the Xcode window** (right next to the Play/Stop buttons). You will see a selector that probably says something like `AITagger > My Mac`.
2. Click on the left part of that selector (the scheme name).
3. Choose **AITagger** from the dropdown list to run the visual menu bar app.
4. Make sure the right side of the selector says **My Mac** (since this is a macOS app).

## 3. Running the App
1. Click the **Play button** (▶️) in the top left corner, or press `Cmd + R`.
2. Xcode will build the project. You'll see a "Build Succeeded" notification.
3. **Important Note:** Because `AITagger` is a menu bar application, you won't see a standard app window pop up in the middle of your screen! Instead, look at the **top right of your Mac's menu bar**. You should see a new **Tag icon** appear there.

## 4. Stopping the App
When you want to stop the app or make changes to your code, return to Xcode and:
* Click the **Stop button** (the square ⏹️ next to Play) or press `Cmd + .`.

## 5. Viewing Logs & Debugging
Since your `README.md` mentions that running it shows logs, you can view these right in Xcode:
* If the bottom panel isn't open, press `Cmd + Shift + Y` (or go to **View > Debug Area > Show Debug Area**).
* Whenever your code prints standard output, it will appear in the bottom-right console as the app runs from Xcode.
