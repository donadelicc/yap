import Core
@testable import Permissions
import XCTest

final class PermissionsTests: XCTestCase {
    func testMicrophoneStatusReturnsSensibleValue() {
        let service = SystemPermissionsService()

        switch service.status(for: .microphone) {
        case .granted, .denied, .undetermined:
            break
        }
    }

    func testRequestPollerStopsWhenStatusMatches() async {
        final class State: @unchecked Sendable {
            var statuses: [PermissionStatus] = [.denied, .denied, .granted, .denied]
            var statusCalls = 0
            var sleepCalls = 0
        }

        let state = State()
        let poller = PermissionRequestPoller<PermissionStatus>(
            maxAttempts: 60,
            sleep: {
                state.sleepCalls += 1
            }
        )

        let result = await poller.poll(
            status: {
                defer { state.statusCalls += 1 }
                return state.statuses[state.statusCalls]
            },
            shouldStop: { $0 == .granted }
        )

        XCTAssertEqual(result, .granted)
        XCTAssertEqual(state.statusCalls, 3)
        XCTAssertEqual(state.sleepCalls, 2)
    }

    func testRequestPollerReturnsCurrentStatusWhenPollingEnds() async {
        final class State: @unchecked Sendable {
            var statuses: [PermissionStatus] = [.denied, .denied, .undetermined, .denied]
            var statusCalls = 0
            var sleepCalls = 0
        }

        let state = State()
        let poller = PermissionRequestPoller<PermissionStatus>(
            maxAttempts: 3,
            sleep: {
                state.sleepCalls += 1
            }
        )

        let result = await poller.poll(
            status: {
                defer { state.statusCalls += 1 }
                return state.statuses[state.statusCalls]
            },
            shouldStop: { $0 == .granted }
        )

        XCTAssertEqual(result, .denied)
        XCTAssertEqual(state.statusCalls, 4)
        XCTAssertEqual(state.sleepCalls, 3)
    }
}
