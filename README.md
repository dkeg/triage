# triage

A menu-bar app that shows your **Claude Code** sessions around the MacBook Pro's Dynamic Island,
and lets you approve or deny permission requests from there.

- **A small status pill** next to the island: "All clear", "N working", and a red flashing
  "N pending" when something is waiting on you.
- **Approve, deny or "always allow"** from an expanded card that shows the full command, the tool's
  description, a before/after preview for edits, and the project and branch.
- **See what each session is doing** ("Editing X.swift", "Running: swift build") with a timer.
- **Jump to a session** in the app that hosts it: Subspace, Ghostty, Kaku, iTerm2, Terminal.app
  and others.
- Works with sessions in terminals, in Subspace, and in the Claude Code desktop app.

> **Status: early (0.1).** Built and tested on a 16" MacBook Pro with a Dynamic Island on macOS 27.
> It needs macOS 14 or later. On a Mac with a notch, or without one, it falls back to a floating
> pill, but that hasn't been tried.

## Install

```
brew install --cask dkeg/triage/triage
```

Or download `Triage-<version>.zip` from the [releases](https://github.com/dkeg/triage/releases),
unzip it and drag `Triage.app` to Applications.

On first launch triage offers to **connect to Claude Code** (adds hook entries to
`~/.claude/settings.json`) and to **start at login**. You can do both later in Settings.

## How it works

Claude Code runs a small helper, `triage-hook`, on events such as a permission request, a tool
finishing or a turn ending. The helper forwards the event over a Unix socket
(`~/Library/Application Support/Triage/triage.sock`, owner-only) to the app. For a permission
request the helper waits for your answer and prints it for Claude Code.

- **If triage isn't running, the helper does nothing**, and Claude Code behaves exactly as before.
- Everything stays on your Mac. triage makes no network requests.
- The installer only adds and removes its own entries in `settings.json`. It keeps a one-time backup
  next to the file (`settings.json.triage-backup`) and leaves other tools' hooks alone.

```
triage-hook install      # add the hooks (the app also offers this on first launch)
triage-hook uninstall    # remove them
triage-hook status
```

### Where approvals go

| Session runs in | Behavior |
|---|---|
| A terminal (Terminal, iTerm2, Ghostty, Kaku, Warp, kitty, Alacritty, WezTerm) | If that terminal is in front, triage stays out of the way and you answer in Claude's own prompt. Otherwise the request appears in the island, and **Skip** hands it back. |
| Subspace, the Claude Code desktop app, anything else | Always shown in the island. Answering in the app's own prompt also clears it here. |

An empty answer to a permission hook is treated as a denial by some hosts, so triage only steps
aside for hosts known to show their own prompt.

Tested so far: Kaku, Subspace and the Claude Code desktop app. The other terminals use the same
rule as Kaku but haven't been tried; please open an issue if one misbehaves.

## Permissions

| Permission | Why | Needed? |
|---|---|---|
| Automation (Terminal.app, iTerm2) | Select the right tab when you jump to a session | Only for those two apps |
| Screen Recording | **Auto** pill width measures a thin strip at the top of the screen to see how wide the system island is. Nothing is stored or sent. | Only if you choose Auto |

## Settings

Open from the menu-bar icon: hover and open behavior, which side of the island the pill sits on,
how often it cycles, vertical position, collapsed width (Compact, Wide or Auto), how long an
auto-opened card stays, and start at login.

## Build from source

```
swift build
swift test
scripts/bundle.sh debug        # build/Triage.app, signed with a development identity if you have one
```

Release builds (universal, hardened runtime, notarized):

```
SIGN_IDENTITY="Developer ID Application: …" NOTARY_PROFILE=… scripts/release.sh
```

Developer flags: `--demo-attention`, `--demo-pending`, `--open-settings`. The debug log is at
`~/Library/Logs/Triage/triage.log`.

## Uninstall

```
brew uninstall --cask triage     # also removes the Claude Code hooks it added
```

or run `triage-hook uninstall` and delete the app.

## License

MIT. See [LICENSE](LICENSE).
