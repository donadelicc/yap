import Foundation

enum OnboardingStep: Int, CaseIterable, Identifiable {
    case welcome
    case microphone
    case accessibility
    case inputMonitoring
    case models
    case done

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .welcome:
            "Welcome"
        case .microphone:
            "Microphone"
        case .accessibility:
            "Accessibility"
        case .inputMonitoring:
            "Input Monitoring"
        case .models:
            "Models"
        case .done:
            "Done"
        }
    }
}
