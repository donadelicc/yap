# yap

Local voice dictation for people who code with AI agents.
Push to talk, hold the hotkey, dictate, release — text appears
in your terminal or editor.

**Status:** pre-alpha, under construction.

## Privacy
- 100% local. Zero telemetry.
- Network is used only to download models from HuggingFace on first launch.
- No mic data, transcript, or LLM I/O ever leaves your device.

## Building from source

This project uses [XcodeGen](https://github.com/yonaskolb/XcodeGen) so the
Xcode project is generated from `project.yml` (and not checked into git).

```bash
./bootstrap.sh        # installs xcodegen if missing, then generates yap.xcodeproj
open yap.xcodeproj
```

Requirements: macOS 13+, Xcode 15+, Homebrew.

## Project layout
- `App/` — the Xcode app target sources
- `Packages/` — Swift Package Manager modules (each a `Packages/<Name>/`)
- `docs/` — design specs and architecture notes
- `project.yml` — XcodeGen project definition (source of truth for the Xcode project)

## License
MIT. See `LICENSE`.
