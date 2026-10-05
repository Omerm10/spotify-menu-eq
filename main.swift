import AppKit
import ServiceManagement

@main struct SpotifyMenuEQApp {
    @MainActor static func main() {
        let arguments = CommandLine.arguments
        if arguments.dropFirst().first == "--eq-helper" {
            exit(WorkerRuntime.run(arguments: arguments))
        }
        if arguments.dropFirst().first == "--diagnose-session" {
            guard arguments.count == 3, let seconds = Double(arguments[2]), seconds.isFinite, (2...600).contains(seconds) else {
                fputs("Usage: --diagnose-session <seconds: 2...600>\n", stderr)
                exit(2)
            }
            exit(DiagnosticSession.run(seconds: seconds))
        }
        if arguments.contains("--login-status") {
            print("Login item status: \(SMAppService.mainApp.status.rawValue)")
            return
        }
        if arguments.contains("--register-login") || arguments.contains("--unregister-login") {
            do {
                if arguments.contains("--register-login") { try SMAppService.mainApp.register() }
                else { try SMAppService.mainApp.unregister() }
                print("Login item status: \(SMAppService.mainApp.status.rawValue)")
            } catch {
                fputs("Login item change failed: \(error.localizedDescription)\n", stderr)
                exit(1)
            }
            return
        }
        guard arguments.count == 1 || (arguments.count == 2 && arguments[1] == "--show-controls") else {
            fputs("Unknown option. Supported: --login-status, --register-login, --unregister-login, --show-controls, --diagnose-session <seconds>\n", stderr)
            exit(2)
        }
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
        withExtendedLifetime(delegate) {}
    }
}
