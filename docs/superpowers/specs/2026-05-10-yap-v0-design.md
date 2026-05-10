# yap v0 — Design Spec

**Status:** Approved (sections 1–5, 2026-05-10)
**Author:** brainstormed with Claude (donadelicc)
**Scope:** First end-to-end working version of `yap`, a local-only voice dictation Mac app for people who code with AI agents.

---

## 1. Goal & non-goals

### Goal
Ship a free, open-source, local-only macOS menu bar app that:
1. Records audio while a global hotkey is held (push-to-talk).
2. Transcribes the audio locally with Whisper.
3. Cleans the transcript with a small local LLM (punctuation, capitalization, filler-word removal).
4. Pastes the cleaned text into the focused application.

The v0 target user is a developer who dictates prompts into a coding agent (Claude Code, Codex, Cursor) running in a terminal or editor on macOS.

### Non-goals for v0 (parking lot)
- Repo-aware vocabulary (scanning the active project for symbols/deps to feed Whisper).
- Coding-agent-aware prompt rewriting (detecting target app and reformatting transcripts as structured prompts).
- Screenshot-into-terminal.
- Learning from user corrections.
- Floating HUD near the cursor.
- Multi-language UI (i18n of the app itself; transcription supports any Whisper-supported language).
- App Store distribution.
- Auto-update mechanism (Sparkle).
- Code-signed / notarized distribution. v0 ships unsigned with right-click-Open instructions; signing is a v0.1 task.

### Locked decisions
| Choice | Decision |
|---|---|
| Tech stack | Swift / SwiftUI native, macOS 13+ |
| Hotkey | Configurable; default `right-option`. fn attempted via HIDManager, falls back to right-option if unsupported |
| STT engine | WhisperKit (Swift-native, Metal/ANE accelerated) |
| LLM engine | MLX-Swift |
| Default STT model | `openai_whisper-small.en` (~466MB) |
| Default LLM model | `mlx-community/Qwen2.5-1.5B-Instruct-4bit` (~1GB) |
| Model distribution | Download on first run from HuggingFace; stored in Application Support |
| Privacy | Zero telemetry. Network used only for model downloads from the configured catalog |
| License | MIT |

---

## 2. Architecture

### 2.1 Module layout
A Swift Package Manager workspace with the Xcode app target depending on per-component packages. Each package = one issue's worth of work = one clear public API.

```
yap/
├── App/                      # Xcode app target (.app)
│   ├── yapApp.swift          # @main; wires modules together
│   └── AppCoordinator.swift  # recording state machine
├── Packages/
│   ├── Core/                 # shared types only (no deps)
│   ├── Hotkey/               # global hotkey capture
│   ├── AudioRecorder/        # AVAudioEngine → PCM buffer
│   ├── Transcription/        # PCM → text (WhisperKit)
│   ├── LLMCleanup/           # raw text → cleaned text (MLX-Swift)
│   ├── TextInjector/         # clipboard swap + Cmd+V
│   ├── ModelStore/           # download/store/list/delete models
│   ├── Settings/             # UserDefaults-backed settings
│   ├── MenuBarUI/            # NSStatusItem / MenuBarExtra
│   ├── SettingsUI/           # SwiftUI settings window
│   └── Permissions/          # mic / accessibility / input-monitoring onboarding
├── docs/
│   ├── superpowers/specs/    # design specs
│   └── ARCHITECTURE.md       # pointer to packages + protocols
├── .github/
│   ├── workflows/ci.yml
│   └── ISSUE_TEMPLATE/agent-task.md
├── README.md
├── LICENSE                   # MIT
└── yap.xcodeproj
```

### 2.2 Boundary rules
- Each package exposes a small public protocol.
- Packages depend on protocols, not concrete types, where they cross.
- No package imports another package's internals — only its public protocol(s) and `Core` types.
- The App target is the only place concrete types meet abstract ones (single wiring point).
- Each package has its own tests against its protocol(s).

### 2.3 Tech choices (and rejected alternatives)
| Choice | Rejected alternative | Reason |
|---|---|---|
| WhisperKit | whisper.cpp via C bindings | Swift-native, Metal/ANE accelerated, Argmax-maintained, less build complexity |
| MLX-Swift | llama.cpp Swift bindings | Native Swift, better DX on Apple Silicon |
| SwiftUI MenuBarExtra (macOS 13+) | AppKit NSStatusItem + SwiftUI hosting | Cleaner; macOS 13 is a reasonable floor in 2026 |
| SPM modular workspace | Single monolithic Xcode target | Required for agent-swarm parallel work without file collisions |

---

## 3. Recording lifecycle

### 3.1 State machine
Single source of truth in `AppCoordinator`.

```
       hotkey-down
  idle ────────────► recording
   ▲                    │
   │                    │ hotkey-up
   │                    ▼
   │              ┌─────────────┐
   │              │ transcribing│  ◄── if release < 200ms: discard → idle
   │              └─────────────┘
   │                    │ transcript
   │                    ▼
   │              ┌─────────────┐
   │              │  cleaning   │  ◄── LLM timeout (3s): fall back to raw
   │              └─────────────┘
   │                    │ cleaned (or raw fallback)
   │                    ▼
   │              ┌─────────────┐
   └──────────────│   pasting   │
                  └─────────────┘
```

### 3.2 Async pipeline (in `AppCoordinator`)
```swift
await audioRecorder.start()
// ... user holds hotkey ...
let audio = await audioRecorder.stop()
guard audio.durationMs >= settings.minRecordingMs else { return }   // discard accidents
let transcript = try await transcriber.transcribe(audio, language: settings.language)
let cleaned = (try? await llm.clean(transcript.text, timeout: 3.0)) ?? transcript.text
try await injector.paste(cleaned)
```

### 3.3 Edge cases
| Case | Behavior |
|---|---|
| Press < 200ms | Discard, no paste, no error sound |
| No audio (silence after Whisper) | Skip paste |
| Recording > `maxRecordingMs` (default 60s) | Recorder auto-stops at the cap, pipeline proceeds normally with the truncated buffer. No notification beyond the normal state transition. |
| Hotkey pressed while still processing previous | **Drop the new press** in v0 with subtle "busy" feedback. Queueing is v1. |
| Whisper error | Menu bar → `.error` state, no paste |
| LLM timeout | Fall back to raw transcript, paste it, subtle "cleanup skipped" indicator |
| LLM error | Same as timeout |
| Accessibility permission revoked mid-session | Catch paste failure, route to Permissions UI |
| Mic permission revoked mid-session | Catch record failure, route to Permissions UI |
| Models not yet downloaded on first run | Coordinator emits `.error(.modelMissing)`, menu bar opens Settings → model picker |

### 3.4 Paste mechanism (`TextInjector`)
1. Snapshot current `NSPasteboard.general` contents (all types).
2. Write cleaned text as the new pasteboard contents.
3. Synthesize `Cmd+V` via `CGEvent` (key-down then key-up, posted to `cghidEventTap`).
4. Schedule a restore of the snapshot after 150ms on a background queue.

Trade-off: clobbers clipboard for ~150ms. Rejected alternative: per-character `CGEventCreateKeyboardEvent` typing — too slow, breaks on special characters. Clipboard-swap is the convention for tools in this category (Raycast, TextExpander, Superwhisper).

### 3.5 Visual feedback (`MenuBarUI`)
`MenuBarUI` consumes `RecordingState` and maps multiple states onto a smaller visual vocabulary:

| `RecordingState`              | Icon                                |
|-------------------------------|-------------------------------------|
| `.idle`                       | mic                                 |
| `.recording`                  | red mic, pulsing                    |
| `.transcribing`, `.cleaning`, `.pasting` | mic with spinner overlay |
| `.error(_)`                   | mic with `!` overlay; last error message shown in the dropdown menu |

v0 has **no** floating HUD near the cursor. v0 has **no** start/stop sounds by default (toggleable in settings).

### 3.6 LLM cleanup prompt
```
System:
You clean up speech transcripts. Rules:
- Fix punctuation and capitalization.
- Remove filler words: um, uh, like, you know.
- Do NOT paraphrase. Do NOT add or remove content.
- Output ONLY the cleaned text, no preamble.

User:
{transcript}
```
Generation: `temperature = 0.1`, `max_tokens = input_tokens * 1.5`, timeout 3.0s.

---

## 4. Component public APIs

All types defined in `Core` unless otherwise noted. Each protocol is the exact contract an issue's implementer must satisfy.

### 4.1 Core (shared types)
```swift
public struct AudioBuffer: Sendable {
    public let samples: [Float]
    public let sampleRate: Int
    public let channels: Int
    public var durationMs: Int { (samples.count * 1000) / (sampleRate * channels) }
    public init(samples: [Float], sampleRate: Int = 16_000, channels: Int = 1)
}

public struct Transcript: Sendable {
    public let text: String
    public let language: String?
    public let durationMs: Int
    public init(text: String, language: String?, durationMs: Int)
}

public enum AppError: Error, Sendable {
    case modelMissing(kind: ModelKind)
    case permissionDenied(Permission)
    case transcriptionFailed(String)
    case cleanupTimedOut
    case audioRecordingFailed(String)
    case pasteFailed(String)
}

public enum ModelKind: String, Sendable { case stt, llm }
public enum Permission: String, Sendable { case microphone, accessibility, inputMonitoring }

public enum RecordingState: Equatable, Sendable {
    case idle
    case recording
    case transcribing
    case cleaning
    case pasting
    case error(AppError)
}

public enum HotkeyBinding: String, Codable, Sendable, CaseIterable {
    case fn
    case rightOption
    case rightCommand
    case rightControl
}
```

### 4.2 Hotkey
```swift
public enum HotkeyEvent: Sendable { case pressed, released }

public protocol HotkeyService: Sendable {
    var events: AsyncStream<HotkeyEvent> { get }
    func setBinding(_ binding: HotkeyBinding) throws
    func start() throws
    func stop()
}
```
**Implementation notes:** `CGEventTap` for the right-modifier bindings; `IOHIDManager` for `fn`. If `fn` capture fails on the current macOS version, log a warning and fall back to right-option. Requires Input Monitoring permission (and on macOS 14+, Accessibility).

### 4.3 AudioRecorder
```swift
public protocol AudioRecording: Sendable {
    func start() async throws            // throws AppError.permissionDenied(.microphone) or .audioRecordingFailed
    func stop() async -> AudioBuffer     // 16kHz mono Float32; idempotent
}
```
**Implementation notes:** `AVAudioEngine` with an input tap converting to 16kHz mono Float32. Calling `start()` while already started is a no-op. Calling `stop()` without `start()` returns an empty buffer.

### 4.4 Transcription
```swift
public protocol Transcriber: Sendable {
    func load(modelId: String) async throws
    func transcribe(_ audio: AudioBuffer, language: String?) async throws -> Transcript
}
```
**Implementation notes:** Backed by WhisperKit. Default model id `openai_whisper-small.en`. Model files resolved via `ModelStore.path(for:)`.

### 4.5 LLMCleanup
```swift
public protocol TextCleaner: Sendable {
    func load(modelId: String) async throws
    func clean(_ raw: String, timeout: TimeInterval) async throws -> String
}
```
**Implementation notes:** Backed by MLX-Swift. Default model id `mlx-community/Qwen2.5-1.5B-Instruct-4bit`. Uses the prompt in §3.6. On timeout throws `AppError.cleanupTimedOut` (the caller falls back to raw).

### 4.6 TextInjector
```swift
public protocol TextInjecting: Sendable {
    func paste(_ text: String) async throws    // clipboard swap + Cmd+V
}
```
**Implementation notes:** See §3.4. Requires Accessibility permission. Throws `AppError.pasteFailed(...)` if `CGEventPost` fails.

### 4.7 ModelStore
```swift
public struct ModelDescriptor: Sendable, Equatable, Identifiable {
    public let id: String
    public let kind: ModelKind
    public let displayName: String
    public let sizeBytes: Int
    public let language: String?
    public let installed: Bool
}

public struct DownloadProgress: Sendable {
    public let modelId: String
    public let bytesDownloaded: Int
    public let bytesTotal: Int
    public var fraction: Double { bytesTotal == 0 ? 0 : Double(bytesDownloaded) / Double(bytesTotal) }
}

public protocol ModelStoring: Sendable {
    func availableModels(kind: ModelKind) async -> [ModelDescriptor]
    func download(_ id: String) -> AsyncStream<DownloadProgress>   // stream finishes after the final progress event when the file is on disk; downstream errors thrown via `path(for:)` on subsequent access
    func path(for id: String) async throws -> URL                  // throws .modelMissing if not installed
    func delete(_ id: String) async throws
}
```
**Implementation notes:** Catalog is a hardcoded JSON shipped in the app bundle. Models stored under `~/Library/Application Support/yap/Models/`. Downloads use `URLSession` with resumable downloads.

### 4.8 Settings
```swift
public struct AppSettings: Codable, Equatable, Sendable {
    public var hotkeyBinding: HotkeyBinding = .rightOption
    public var sttModelId: String           = "openai_whisper-small.en"
    public var llmModelId: String           = "mlx-community/Qwen2.5-1.5B-Instruct-4bit"
    public var llmEnabled: Bool             = true
    public var language: String?            = "en"
    public var soundEffectsEnabled: Bool    = false
    public var minRecordingMs: Int          = 200
    public var maxRecordingMs: Int          = 60_000
}

public protocol SettingsService: Sendable {
    var current: AppSettings { get }
    func update(_ change: (inout AppSettings) -> Void)
    var changes: AsyncStream<AppSettings> { get }
}
```
**Implementation notes:** UserDefaults-backed under suite `com.donadelicc.yap`. Encode `AppSettings` as JSON in a single key.

### 4.9 Permissions
```swift
public enum PermissionStatus: Sendable { case granted, denied, undetermined }

public protocol PermissionsService: Sendable {
    func status(for: Permission) -> PermissionStatus
    func request(_: Permission) async -> PermissionStatus
    var changes: AsyncStream<(Permission, PermissionStatus)> { get }
}
```
**Implementation notes:** Microphone uses `AVCaptureDevice.requestAccess`. Accessibility uses `AXIsProcessTrustedWithOptions`. Input Monitoring is checked via `IOHIDCheckAccess`. Cannot be requested programmatically on modern macOS — the request method opens System Settings to the right pane and polls for change.

### 4.10 MenuBarUI
SwiftUI `MenuBarExtra` view. Subscribes to `RecordingState` (provided by `AppCoordinator` via an `AsyncStream` or `@Published`). No public protocol; pure view layer. Menu items: current state, "Open Settings…", "Quit yap".

### 4.11 SettingsUI
SwiftUI `Settings` scene with tabs:
- **General** — sound effects toggle, recording length bounds.
- **Hotkey** — picker over `HotkeyBinding` values.
- **Models** — STT model picker, LLM model picker, download buttons with progress.
- **Permissions** — current status of mic / accessibility / input monitoring; "Open System Settings" buttons.
- **About** — version, links, privacy posture statement.

### 4.12 App / AppCoordinator
- Owns the state machine in §3.1.
- Wires concrete impls into the protocols at startup.
- Exposes `RecordingState` to UI as `@Published` and/or `AsyncStream`.
- Single instance, lives for the lifetime of the app.

---

## 5. Error handling, testing, observability, distribution

### 5.1 Error handling
- All errors typed via `AppError`.
- Three classes:
  1. **Recoverable & silent.** LLM timeout/error → fall back to raw transcript, paste anyway, subtle indicator.
  2. **Recoverable, user-prompted.** Permission denied → menu bar `.error` + open Permissions onboarding.
  3. **User-visible.** Whisper failure, audio failure → menu bar `.error` state, last error in dropdown, no paste. App stays running.
- No crashes on error. Worst case is a no-op paste.

### 5.2 Logging
- `os.Logger` with subsystem `com.donadelicc.yap`, one category per package.
- Default level `.info`; debug toggle in Settings emits `.debug`.
- File log at `~/Library/Logs/yap/yap.log`, rotated at 5MB, 7-day retention.

### 5.3 Privacy
- **Zero network telemetry.** No analytics, no crash reporting.
- Network access permitted only for model downloads from the catalog (HuggingFace + WhisperKit's mirror).
- No mic data, transcript, or LLM I/O ever leaves the device.
- README states this prominently.

### 5.4 Testing
- Each package has `Tests/` with XCTest.
- Coordinator state machine tested with mock services covering every edge case in §3.3.
- WhisperKit and MLX integrations: smoke tests with tiny fixture audio (e.g. 1-second WAV). Slow tests gated behind `--enable-slow-tests`.
- UI: manual verification in v0; no snapshot tests.
- CI on `macos-14` GitHub-hosted runners: build all packages + run fast tests on every PR.

### 5.5 Distribution
- Repo layout: SPM workspace + `yap.xcodeproj` at root. Packages under `Packages/`.
- v0 ships **unsigned** on GitHub Releases as a `.zip` (or `.dmg`). README explains right-click → Open first-launch flow.
- Developer ID Application certificate + notarization is a v0.1 task.
- Release workflow: tag `v0.x.y` → GitHub Actions builds `.app`, zips, attaches to release.
- License: MIT (matches WhisperKit and MLX-Swift). README has clear attribution.

---

## 6. Issue plan for the agent swarm

### 6.1 Waves & dependency graph

| Wave | Issues | Depends on | Parallel? |
|---|---|---|---|
| 1a | `#1 Bootstrap repo` | — | — |
| 1b | `#2 Core package` | #1 | — |
| 2 | `#3 Settings`, `#4 Permissions`, `#5 AudioRecorder`, `#6 TextInjector`, `#7 ModelStore`, `#8 Hotkey` | #2 | yes (all 6 parallel) |
| 3 | `#9 Transcription`, `#10 LLMCleanup` | #2, #7 | yes |
| 4 | `#11 MenuBarUI`, `#12 SettingsUI` | Wave-2 protocols | yes |
| 5 | `#13 AppCoordinator state machine`, `#14 App target wiring` | all packages | sequential |
| 6 | `#15 First-run onboarding`, `#16 CI workflow`, `#17 Release workflow`, `#18 README` | #14 (for #15); #1 for the rest | yes |

Critical path: `#1 → #2 → (Wave 2) → (Wave 3) → #13 → #14`.

### 6.2 Per-issue acceptance pattern

Every issue follows the template below. Agents must satisfy every checkbox.

```markdown
## Scope
- Create directory: `Packages/<Name>/`
- DO NOT modify files outside `Packages/<Name>/`

## Dependencies (Package.swift)
- Local: <list>
- External: <list with versions>
- Platforms: .macOS(.v13)

## Public API
<exact protocol + types from §4 of the design spec, copy-pasted>

## Behavior
- Method-by-method spec, including error cases (from §4)

## Tests required
- <specific cases>

## Acceptance criteria
- [ ] `swift build` succeeds in the package directory
- [ ] `swift test` passes
- [ ] Public API matches the spec exactly
- [ ] No imports outside the listed dependencies

## Out of scope (do NOT implement)
- <features to defer; usually entries from §1 non-goals>

## Reference
- Design spec: `docs/superpowers/specs/2026-05-10-yap-v0-design.md` (sections §<N>)
```

### 6.3 Labels applied to every issue
- `agent-hive` — swarm pickup label (color `#8B5CF6`)
- One wave label: `wave-1` through `wave-6`
- One area label: `area:audio`, `area:stt`, `area:llm`, `area:ui`, `area:infra`, `area:wiring`

### 6.4 Collision protection
- Every issue specifies its `Packages/<Name>/` directory and forbids touching others.
- `App/` is touched only by #1 (skeleton), #13 (coordinator), #14 (wiring).
- `.github/`, root configs touched only by #1, #16, #17, #18.
- Two agents racing on different packages cannot produce a merge conflict.
