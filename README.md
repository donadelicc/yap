# yap

**yap — local voice dictation for people who code with AI agents.**

## Status

v0, pre-alpha. Expect bugs. [Open issues](https://github.com/donadelicc/yap/issues).

## Screenshot

![yap menu bar icon and transcript pasted into a Claude Code terminal](assets/screenshot.png)

> _Screenshot pending — capture the menu bar icon and a transcript appearing in a Claude Code terminal session, then drop it at `assets/screenshot.png` (≤200KB)._

## What it does

- **Push-to-talk.** Hold a global hotkey to record, release to transcribe and paste.
- **Local Whisper.** Speech-to-text runs on-device via [WhisperKit](https://github.com/argmaxinc/WhisperKit) (Metal/ANE accelerated).
- **Local LLM cleanup.** A small on-device LLM (via [MLX-Swift](https://github.com/ml-explore/mlx-swift)) fixes punctuation, capitalization, and strips fillers — no paraphrasing.
- **Pastes into the focused app.** Clipboard-swap + synthesized `Cmd+V`, so it works in terminals, editors, and chat boxes.
- **All local.** No telemetry, no servers. Network is touched only to download models on first launch.

## Privacy

100% local. Zero telemetry. Network is used only to download models from HuggingFace on first launch. No mic data, transcript, or LLM I/O ever leaves your device.

## Install

### Option 1 — Download from Releases

1. Grab the latest `yap-vX.Y.Z.zip` from [Releases](https://github.com/donadelicc/yap/releases).
2. Unzip and move `yap.app` to `/Applications`.
3. v0 builds are **unsigned**, so macOS Gatekeeper will refuse to open it by double-click. The first time:
   - **Right-click** `yap.app` → **Open**.
   - A dialog will warn that the developer is unidentified. Click **Open** again.
   - Subsequent launches work normally.
4. If you see "yap.app is damaged and can't be opened", run `xattr -dr com.apple.quarantine /Applications/yap.app` once and try again.

### Option 2 — Build from source

Requirements: macOS 13+, Xcode 15+, Homebrew.

```bash
git clone https://github.com/donadelicc/yap.git
cd yap
./bootstrap.sh        # installs xcodegen if missing, generates yap.xcodeproj
open yap.xcodeproj
```

Build and run the `yap` scheme. The project is generated from `project.yml` via [XcodeGen](https://github.com/yonaskolb/XcodeGen); `yap.xcodeproj/` is gitignored.

## First run

On first launch, yap walks you through:

1. **Microphone access** — required to record audio.
2. **Accessibility access** — required to synthesize `Cmd+V` into other apps.
3. **Input Monitoring access** — required to capture the global hotkey while other apps are focused.
4. **Model download** — the default Whisper model (`openai_whisper-small.en`, ~466MB) and LLM (`mlx-community/Qwen2.5-1.5B-Instruct-4bit`, ~1GB) download from HuggingFace into `~/Library/Application Support/yap/Models/`. Expect a few minutes on a typical connection.

![First-run onboarding](assets/onboarding.png)

> _Onboarding screenshot optional — add `assets/onboarding.png` (≤200KB) when available._

Once permissions are granted and models are on disk, the menu bar icon turns into the idle mic and you're ready.

## Usage

**Hold right-option, dictate, release. Text appears in the focused app.**

That's the whole loop. The menu bar icon pulses red while recording, then briefly shows a spinner while transcribing and cleaning up. Releases shorter than 200ms are ignored so a fumbled key doesn't trigger anything.

You can rebind the hotkey under **Settings → Hotkey**.

## Configuration

Open Settings from the menu bar dropdown or with `Cmd+,` when yap is focused.

- **Hotkey** — pick from `fn`, right-option (default), right-command, right-control.
- **Models** — choose the Whisper STT model and the MLX LLM cleanup model. Download buttons show progress; old models can be deleted from disk.
- **LLM cleanup** — toggle the cleanup pass off if you want raw Whisper output. On timeout (3s default) yap falls back to the raw transcript automatically.
- **General** — sound effects, min/max recording duration.
- **Permissions** — current status of mic / accessibility / input monitoring with deep-links to System Settings.

## Hacking on it

- Design spec: [`docs/superpowers/specs/2026-05-10-yap-v0-design.md`](docs/superpowers/specs/2026-05-10-yap-v0-design.md) — the source of truth for architecture, component APIs, and the v0 scope/non-goals.
- The repo is laid out as an SPM workspace under `Packages/`, with the Xcode app target in `App/`. Each package has its own protocol + tests; see the design spec §2 and §4.
- Issues tagged [`agent-hive`](https://github.com/donadelicc/yap/issues?q=label%3Aagent-hive) are scoped tightly enough for an agent to pick up and ship without colliding with other work. Grep that label for a starter task.

## License and credits

MIT — see [`LICENSE`](LICENSE).

Built on:

- [WhisperKit](https://github.com/argmaxinc/WhisperKit) (MIT) — on-device speech recognition.
- [MLX-Swift](https://github.com/ml-explore/mlx-swift) (MIT) — on-device LLM inference on Apple Silicon.
