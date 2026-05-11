import SwiftUI

struct AboutTab: View {
    private let version: String

    init(bundle: Bundle = .main) {
        let shortVersion = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String

        switch (shortVersion, build) {
        case let (shortVersion?, build?):
            self.version = "\(shortVersion) (\(build))"
        case let (shortVersion?, nil):
            self.version = shortVersion
        default:
            self.version = "Unknown"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("yap")
                    .font(.title2)
                Text("Version \(version)")
                    .foregroundStyle(.secondary)
            }

            Text("GitHub: https://github.com/donadelicc/yap")
                .textSelection(.enabled)

            Text("Released under the MIT License.")

            Text("Privacy: yap records audio only while the configured hotkey is held, processes transcription and cleanup locally, and does not send recordings, transcripts, or model data to a remote service.")
                .fixedSize(horizontal: false, vertical: true)

            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(24)
    }
}
