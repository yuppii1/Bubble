import Foundation

class FolderMonitor {
    var url: URL
    private var source: DispatchSourceFileSystemObject?
    var onFileChange: () -> Void

    init(url: URL, onFileChange: @escaping () -> Void) {
        self.url = url
        self.onFileChange = onFileChange
    }

    func startMonitoring() {
        let fd = open(url.path, O_EVTONLY)
        if fd == -1 {
            print("Failed to open folder for monitoring: \(url.path)")
            return
        }

        source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: .write, queue: .main)

        source?.setEventHandler { [weak self] in
            // When a file is written to the directory (e.g., new file added)
            self?.onFileChange()
        }

        source?.setCancelHandler {
            close(fd)
        }

        source?.resume()
    }

    func stopMonitoring() {
        source?.cancel()
        source = nil
    }
}
