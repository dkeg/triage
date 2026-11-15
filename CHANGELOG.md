# Changelog

## Unreleased

- Running terminals are listed next to agent sessions; the open card shows Agents and Terminals
  side by side or in one column, with a row limit.
- "Always allow" is hidden for now (Claude Code's suggested rules are often broad wildcards).
- Settings are in four tabs.
- Fixed: `brew upgrade` removed triage's Claude Code hooks; `triage-hook install` failed when run
  by name; agent sessions with high process ids were missed.

## 0.1.3

- The pill is flat like the hardware island (no drop shadow) and always visible, even with no sessions.
- Fixed the pill sitting at an inconsistent distance from the island: the island's width is now measured
  by its own black extent, so it works on dark wallpapers and ignores Live Activity album art.
- The pill moves aside immediately when the island widens (charging, Music, timers).
- Auto width hides the pill while menu bar icons (for example ones a menu-bar manager reveals) are
  where it would sit. Setting: "Step aside for menu bar icons".

## 0.1.2

- Releases are fully automated: pushing a tag builds, notarizes, publishes and updates the cask.

## 0.1.1

- Release is now built, signed and notarized by GitHub Actions.
- App icon.
- Screen Recording request is asked once, with clearer guidance if macOS doesn't list the app.

## 0.1.0

First release.

- Status pill beside the Dynamic Island with cycling "All clear" / "N working" and a flashing red
  "N pending".
- Approve, deny or always-allow permission requests, with the full command, a tool description, an
  edit preview and project/branch.
- Live activity and elapsed time per session; jump to the app hosting a session.
- Hosts: terminals, Subspace and the Claude Code desktop app.
- Settings for pill side, cycling speed, vertical position, width (Compact / Wide / Auto) and more.
