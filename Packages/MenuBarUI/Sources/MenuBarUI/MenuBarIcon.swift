import Core
import SwiftUI
import AppKit

public struct MenuBarIcon: View {
    private let state: RecordingState
    @State private var isPulsing = false

    public init(state: RecordingState) {
        self.state = state
    }

    public var body: some View {
        ZStack(alignment: .topTrailing) {
            Image(systemName: "mic")
                .symbolVariant(isRecording ? .fill : .none)
                .foregroundStyle(isRecording ? .red : .primary)
                .opacity(isRecording && isPulsing ? 0.6 : 1.0)

            if isProcessing {
                ProgressView()
                    .controlSize(.mini)
                    .scaleEffect(0.5)
                    .offset(x: 7, y: -7)
            }

            if isError {
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.red)
                    .background(
                        Circle()
                            .fill(.background)
                    )
                    .offset(x: 6, y: -6)
            }
        }
        .onAppear {
            guard isRecording else { return }
            withAnimation(
                .easeInOut(duration: 0.4)
                    .repeatForever(autoreverses: true)
            ) {
                isPulsing = true
            }
        }
        .onChange(of: isRecording) { recording in
            if recording {
                withAnimation(
                    .easeInOut(duration: 0.4)
                        .repeatForever(autoreverses: true)
                ) {
                    isPulsing = true
                }
            } else {
                isPulsing = false
            }
        }
    }

    private var isRecording: Bool {
        if case .recording = state {
            return true
        }

        return false
    }

    private var isProcessing: Bool {
        switch state {
        case .transcribing, .cleaning, .pasting:
            true
        case .idle, .recording, .error:
            false
        }
    }

    private var isError: Bool {
        if case .error = state {
            return true
        }

        return false
    }
}
