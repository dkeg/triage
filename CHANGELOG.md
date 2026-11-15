# Changelog

## Unreleased

- Scripted demo mode and recording scripts for the README/website animations (approval story, the pill
  alone, a Live Activity making room) and the social image (`--demo-story`; does nothing unless passed).

## 0.2.0

**New**
- Running terminals are listed next to your agent sessions: the folder, the command and how long it has
  been running. Secret-looking arguments (tokens, passwords, URL credentials) are masked, and arguments
  can be turned off. Terminals that are running an agent aren't listed twice.
- The open card shows Agents and Terminals side by side or in one column (Settings > Sessions), with a
  row limit per section and a "+N more" line. It always fits its panel, and it is narrower than before.
- The Agents header shows how many sessions are active (working or waiting on you).
- The idle pill always cycles between "All clear" and "N active", even when N is 0.
- Settings are organized in four tabs.

**Changed**
- "Always allow" is hidden for now. Claude Code's suggested rules are often broad wildcards (for example
  `gh repo *`), and the card didn't show what would be saved.

**Fixed**
- `brew upgrade` removed triage's Claude Code hooks. The cask now leaves them alone (`brew uninstall --zap`
  removes them), and the app offers to reconnect if its helper exists but the hooks are gone. People
  upgrading from 0.1.x will see this offer once, because their installed cask still removes the hooks.
- `triage-hook install` failed when run by name from PATH.
- Agent sessions with high process ids were missed, so some sessions never appeared.
- Pill position: the island's width is measured by its own black extent, which works on dark
  wallpapers and ignores Live Activity album art; the pill moves aside at once when the island widens.
- Hover/click regions, flat look (no drop shadow), and the pill is always visible.

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
