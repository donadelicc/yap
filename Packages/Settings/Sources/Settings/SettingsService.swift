public protocol SettingsService: Sendable {
    var current: AppSettings { get }
    func update(_ change: (inout AppSettings) -> Void)
    var changes: AsyncStream<AppSettings> { get }
}
