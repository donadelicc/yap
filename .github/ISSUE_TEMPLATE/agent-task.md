---
name: Agent task
about: Template for tasks the agent swarm picks up via the agent-hive label.
title: ''
labels: agent-hive
---

## Goal
<one or two sentences>

## Blocked by
<list of issue numbers, or "Nothing">

## Scope
- Create directory: `Packages/<Name>/`
- DO NOT modify files outside `Packages/<Name>/`

## Dependencies (Package.swift)
- Local: <list>
- External: <list with versions>
- Platforms: `.macOS(.v13)`

## Public API
```swift
<exact protocol + types from §4 of the design spec>
```

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
- Design spec: `docs/superpowers/specs/2026-05-10-yap-v0-design.md` §<N>
