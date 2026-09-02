# Security

## Reporting a vulnerability

Please open a [security advisory](https://github.com/ananthasharma/Slicky/security/advisories/new)
rather than a public issue. If you'd rather email, use the address on my GitHub
profile. I'll acknowledge within a week.

## What Slicky can do on your Mac

Worth being explicit, since he is a background app that floats above everything.

**Network.** Exactly one thing: a request to
`api.github.com/repos/ananthasharma/Slicky/releases/latest` a few seconds after
launch, and again if you press *Check Now*. If you install an update, the
release asset is downloaded from GitHub. There is no analytics, no telemetry, no
crash reporting, and no third-party SDK — the project has zero dependencies.

**Updates.** A downloaded update must satisfy three checks before it replaces
the running app: the bundle identifier must match, `codesign --verify --strict`
must pass, and — when the running copy is signed — the download must carry the
**same team identifier**. A valid signature alone only proves a bundle wasn't
altered after signing; anyone can sign a bundle claiming to be Slicky. The team
check is what makes it meaningfully ours. Builds from source are ad-hoc signed,
have no team, and skip that check.

**Input monitoring.** Slicky installs a global monitor for left mouse
down/drag/up events. This needs no permission from macOS and is used for one
purpose: a window that ignores mouse events is not offered to drag sessions, so
the panel has to become event-visible on the mouse-down that precedes a drag.
Event contents are never inspected or stored.

**Accessibility.** Only if you switch on *Get out of the way when I'm typing*,
which is off by default. It is the sole way to read the text caret's position,
and macOS gates global key events behind the same permission. The key handler
ignores its event entirely — only the fact that a key was pressed is used, never
which one. Nothing is recorded and nothing leaves your Mac.

**Files.** He writes to `~/Downloads` when you ask for a selfie, and stores
settings in `UserDefaults` under `com.slicky.desktop`. Nothing else.

**Launching apps.** He opens the apps you bind to him, via `NSWorkspace`. He
can't be made to run arbitrary commands.

## Releases

Releases are built on a Mac with a Developer ID certificate, notarised by Apple
and stapled, then published here. Signing happens locally and by hand — CI has
no access to any certificate or credential, and the workflow never signs or
publishes.

## Supported versions

The latest release. Slicky updates himself.
