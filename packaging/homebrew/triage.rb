cask "triage" do
  version "0.1.0"
  sha256 "REPLACED_BY_RELEASE_WORKFLOW"

  url "https://github.com/dkeg/triage/releases/download/v#{version}/Triage-#{version}.zip"
  name "triage"
  desc "Dynamic Island status and approvals for AI coding agent sessions"
  homepage "https://github.com/dkeg/triage"

  depends_on macos: :sonoma

  app "Triage.app"
  # `triage-hook install | uninstall | status` manages the Claude Code hooks from a terminal.
  binary "#{appdir}/Triage.app/Contents/MacOS/triage-hook"

  uninstall quit: "io.github.dkeg.triage"

  # Plain `brew uninstall` (and `brew upgrade`) leave ~/.claude/settings.json alone, so an upgrade
  # never disconnects triage. `brew uninstall --zap` also removes triage's hook entries.
  zap script: {
        executable:   "#{Dir.home}/Library/Application Support/Triage/bin/triage-hook",
        args:         ["uninstall"],
        must_succeed: false,
      },
      trash:  [
        "~/Library/Application Support/Triage",
        "~/Library/Logs/Triage",
        "~/Library/Preferences/io.github.dkeg.triage.plist",
      ]

  caveats <<~EOS
    On first launch triage offers to connect to Claude Code. That adds hook entries to
    ~/.claude/settings.json (a backup is saved next to it). You can also run:

      triage-hook install

    `brew uninstall --zap triage` removes those entries again; a plain uninstall or upgrade leaves them,
    and they do nothing while the app isn't installed. To remove them by hand: triage-hook uninstall
  EOS
end
