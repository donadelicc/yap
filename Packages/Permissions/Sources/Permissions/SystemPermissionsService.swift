import AppKit
import AVFoundation
import Core
import IOKit.hid

public final class SystemPermissionsService: PermissionsService {
    private let changeMonitor: PermissionChangeMonitor<Permission, PermissionStatus>
    private let requestPoller: PermissionRequestPoller<PermissionStatus>

    public init() {
        changeMonitor = PermissionChangeMonitor(
            values: Permission.allCasesForPermissionsService,
            status: { permission in
                Self.currentStatus(for: permission)
            },
            sleep: {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        )
        requestPoller = PermissionRequestPoller(
            maxAttempts: 60,
            sleep: {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        )
    }

    public func status(for permission: Permission) -> PermissionStatus {
        Self.currentStatus(for: permission)
    }

    public func request(_ permission: Permission) async -> PermissionStatus {
        switch permission {
        case .microphone:
            let granted = await AVCaptureDevice.requestAccess(for: .audio)
            return granted ? .granted : status(for: .microphone)
        case .accessibility:
            openSystemSettingsPane("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
            return await requestPoller.poll(
                status: { Self.currentStatus(for: .accessibility) },
                shouldStop: { $0 == .granted }
            )
        case .inputMonitoring:
            openSystemSettingsPane("x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")
            return await requestPoller.poll(
                status: { Self.currentStatus(for: .inputMonitoring) },
                shouldStop: { $0 == .granted }
            )
        }
    }

    public var changes: AsyncStream<(Permission, PermissionStatus)> {
        changeMonitor.stream()
    }

    private static func currentStatus(for permission: Permission) -> PermissionStatus {
        switch permission {
        case .microphone:
            return microphoneStatus()
        case .accessibility:
            return AXIsProcessTrusted() ? .granted : .denied
        case .inputMonitoring:
            return inputMonitoringStatus()
        }
    }

    private static func microphoneStatus() -> PermissionStatus {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return .granted
        case .denied, .restricted:
            return .denied
        case .notDetermined:
            return .undetermined
        @unknown default:
            return .undetermined
        }
    }

    private static func inputMonitoringStatus() -> PermissionStatus {
        switch IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) {
        case kIOHIDAccessTypeGranted:
            return .granted
        case kIOHIDAccessTypeDenied:
            return .denied
        default:
            return .undetermined
        }
    }

    private func openSystemSettingsPane(_ urlString: String) {
        guard let url = URL(string: urlString) else {
            return
        }

        NSWorkspace.shared.open(url)
    }
}

internal struct PermissionRequestPoller<Status: Sendable>: Sendable {
    private let maxAttempts: Int
    private let sleep: @Sendable () async -> Void

    init(maxAttempts: Int, sleep: @escaping @Sendable () async -> Void) {
        self.maxAttempts = max(0, maxAttempts)
        self.sleep = sleep
    }

    func poll(
        status: @escaping @Sendable () -> Status,
        shouldStop: @escaping @Sendable (Status) -> Bool
    ) async -> Status {
        var current = status()

        guard !shouldStop(current) else {
            return current
        }

        for _ in 0..<maxAttempts {
            await sleep()
            current = status()

            if shouldStop(current) {
                return current
            }
        }

        return current
    }
}

private actor PermissionChangeMonitor<Value: Hashable & Sendable, Status: Equatable & Sendable> {
    private let values: [Value]
    private let status: @Sendable (Value) -> Status
    private let sleep: @Sendable () async -> Void

    private var continuations: [UUID: AsyncStream<(Value, Status)>.Continuation] = [:]
    private var latestStatuses: [Value: Status] = [:]
    private var pollingTask: Task<Void, Never>?

    init(
        values: [Value],
        status: @escaping @Sendable (Value) -> Status,
        sleep: @escaping @Sendable () async -> Void
    ) {
        self.values = values
        self.status = status
        self.sleep = sleep
    }

    nonisolated func stream() -> AsyncStream<(Value, Status)> {
        AsyncStream { continuation in
            let id = UUID()

            Task {
                await self.add(continuation, id: id)
            }

            continuation.onTermination = { _ in
                Task {
                    await self.removeContinuation(id: id)
                }
            }
        }
    }

    private func add(_ continuation: AsyncStream<(Value, Status)>.Continuation, id: UUID) {
        continuations[id] = continuation

        if pollingTask == nil {
            startPolling()
        }
    }

    private func removeContinuation(id: UUID) {
        continuations[id] = nil

        if continuations.isEmpty {
            pollingTask?.cancel()
            pollingTask = nil
            latestStatuses = [:]
        }
    }

    private func startPolling() {
        pollingTask = Task.detached { [sleep] in
            while !Task.isCancelled {
                await self.pollOnce()
                await sleep()
            }
        }
    }

    private func pollOnce() {
        for value in values {
            let currentStatus = status(value)

            if let latestStatus = latestStatuses[value], latestStatus != currentStatus {
                yield((value, currentStatus))
            }

            latestStatuses[value] = currentStatus
        }
    }

    private func yield(_ event: (Value, Status)) {
        for continuation in continuations.values {
            continuation.yield(event)
        }
    }
}

private extension Permission {
    static let allCasesForPermissionsService: [Permission] = [
        .microphone,
        .accessibility,
        .inputMonitoring
    ]
}
