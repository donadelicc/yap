import Core

public enum PermissionStatus: Sendable {
    case granted
    case denied
    case undetermined
}

public protocol PermissionsService: Sendable {
    func status(for: Permission) -> PermissionStatus
    func request(_: Permission) async -> PermissionStatus
    var changes: AsyncStream<(Permission, PermissionStatus)> { get }
}
