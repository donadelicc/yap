import Core

public protocol TextInjecting: Sendable {
    func paste(_ text: String) async throws
}
