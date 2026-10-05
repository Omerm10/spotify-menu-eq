import AppKit
import ServiceManagement

enum RecoveryAction: Equatable { case retry, openAutomationSettings, openAudioCaptureSettings, openLoginSettings }
enum PlayerIssue: Error, Equatable {
    case automationDenied, automationTimedOut, spotifyUnavailable, automationFailed(String), audioFailed(String)
    var message: String {
        switch self {
        case .automationDenied: "Allow Spotify control in System Settings > Privacy & Security > Automation."
        case .automationTimedOut: "Spotify did not respond. Retry when Spotify is responding."
        case .spotifyUnavailable: "Open Spotify to start."
        case .automationFailed(let detail): "Spotify control failed: \(detail)"
        case .audioFailed(let detail): detail
        }
    }
    var recoveryActions: [RecoveryAction] {
        switch self {
        case .automationDenied: [.openAutomationSettings, .retry]
        case .audioFailed: [.retry, .openAudioCaptureSettings]
        default: [.retry]
        }
    }
}

@MainActor final class LoginItemService: ObservableObject {
    @Published private(set) var status = SMAppService.mainApp.status
    @Published private(set) var errorMessage: String?
    func refresh() { status = SMAppService.mainApp.status }
    func setEnabled(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            errorMessage = nil
        } catch { errorMessage = error.localizedDescription }
        refresh()
    }
    func openSettings() { SMAppService.openSystemSettingsLoginItems() }
}
