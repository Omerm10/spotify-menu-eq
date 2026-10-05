import Foundation
import Darwin

/// Text protocol is confined to worker control threads, never audio render callbacks.
enum WorkerProtocol {
    private static let outputLock = NSLock()

    static func send(_ line: String) {
        outputLock.lock()
        defer { outputLock.unlock() }
        print(line.replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "\r", with: " "))
        fflush(stdout)
    }

    static func watchParent(_ expectedParent: pid_t) {
        guard expectedParent > 1, getppid() == expectedParent else { _exit(1) }
        Thread.detachNewThread {
            while getppid() == expectedParent { Thread.sleep(forTimeInterval: 0.5) }
            // Kernel cleanup releases process-owned Core Audio resources even if HAL is stuck.
            _exit(1)
        }
    }
}
