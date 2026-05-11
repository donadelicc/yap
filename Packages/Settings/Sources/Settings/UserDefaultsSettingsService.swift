import Foundation

public final class UserDefaultsSettingsService: SettingsService, @unchecked Sendable {
    private static let storageKey = "AppSettings.v1"

    private let defaults: UserDefaults
    private let lock = NSLock()
    private var settings: AppSettings
    private var continuations: [UUID: AsyncStream<AppSettings>.Continuation] = [:]

    public var current: AppSettings {
        lock.withLock {
            settings
        }
    }

    public var changes: AsyncStream<AppSettings> {
        AsyncStream { continuation in
            let id = UUID()
            continuation.onTermination = { [weak self] _ in
                self?.removeContinuation(id)
            }

            let currentSettings = lock.withLock {
                continuations[id] = continuation
                return settings
            }

            continuation.yield(currentSettings)
        }
    }

    public init(suiteName: String = "com.donadelicc.yap") {
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            preconditionFailure("Unable to create UserDefaults suite named \(suiteName)")
        }

        self.defaults = defaults

        if let data = defaults.data(forKey: Self.storageKey),
           let settings = try? JSONDecoder().decode(AppSettings.self, from: data) {
            self.settings = settings
        } else {
            let settings = AppSettings()
            self.settings = settings
            Self.write(settings, to: defaults)
        }
    }

    public func update(_ change: (inout AppSettings) -> Void) {
        let result = lock.withLock {
            change(&settings)
            Self.write(settings, to: defaults)
            return (settings, Array(continuations.values))
        }

        for continuation in result.1 {
            continuation.yield(result.0)
        }
    }

    private func removeContinuation(_ id: UUID) {
        lock.withLock {
            continuations[id] = nil
        }
    }

    private static func write(_ settings: AppSettings, to defaults: UserDefaults) {
        let data = try? JSONEncoder().encode(settings)
        defaults.set(data, forKey: storageKey)
    }
}
