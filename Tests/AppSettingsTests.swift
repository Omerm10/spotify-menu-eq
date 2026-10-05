import Foundation

@main struct AppSettingsTests {
    static func main() {
        let suite = "eq.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = SettingsStore(defaults: defaults)
        precondition(store.load() == AppSettings())
        let saved = AppSettings(gains: [3, 1, -1, -1, -2], preset: "Warm", desiredEQEnabled: true)
        store.save(saved)
        precondition(SettingsStore(defaults: defaults).load() == saved)
        store.save(AppSettings(gains: [3, 1, -1, -1, -2], preset: "Flat", desiredEQEnabled: true))
        precondition(store.load().preset == "Custom")
        store.save(AppSettings(gains: [100, 0, 0, 0, 0], preset: "Custom", desiredEQEnabled: true))
        precondition(store.load() == AppSettings())
        store.save(AppSettings(gains: [0, 0], preset: "Flat", desiredEQEnabled: true))
        precondition(store.load() == AppSettings())
        defaults.set(Data("invalid".utf8), forKey: "appSettings.v1")
        precondition(store.load() == AppSettings())
        precondition(AppSettings(version: 99, desiredEQEnabled: true).validated == AppSettings())
        precondition(AppSettings(gains: [.nan, 0, 0, 0, 0]).validated == AppSettings())
        print("Settings persistence, matching preset, malformed data, migration, and finite gain validation passed")
    }
}
