import Foundation

struct AppSettings: Codable, Equatable {
    var version = 1
    var gains = [Double](repeating: 0, count: 5)
    var preset = "Flat"
    var desiredEQEnabled = false

    var validated: AppSettings {
        guard version == 1, gains.count == EQBand.allCases.count,
              gains.allSatisfy({ $0.isFinite && (-9...9).contains($0) }) else { return AppSettings() }
        var result = self
        result.preset = EQPreset.all.first(where: { $0.name == preset && $0.gains == gains })?.name ?? "Custom"
        return result
    }
}

struct SettingsStore {
    let defaults: UserDefaults
    private let key = "appSettings.v1"
    init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    func load() -> AppSettings {
        guard let data = defaults.data(forKey: key),
              let settings = try? JSONDecoder().decode(AppSettings.self, from: data) else { return AppSettings() }
        return settings.validated
    }
    func save(_ settings: AppSettings) {
        guard let data = try? JSONEncoder().encode(settings.validated) else { return }
        defaults.set(data, forKey: key)
    }
}
