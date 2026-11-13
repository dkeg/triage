cask "triage" do
  version "0.1.0"
  sha256 "REPLACED_BY_RELEASE_WORKFLOW"

  url "https://github.com/dkeg/triage/releases/download/v#{version}/Triage-#{version}.zip"
  name "triage"
  desc "Dynamic Island status and approvals for Claude Code sessions"
  homepage "https://github.com/dkeg/triage"

  depends_on macos: ">= :sonoma"

  app "Triage.app"
  # `triage-hook install | uninstall | status` manages the Claude Code hooks from a terminal.
  binary "#{appdir}/Triage.app/Contents/MacOS/triage-hook"

  # Remove triage's entries from ~/.claude/settings.json (other tools' hooks are left alone).
  uninstall_preflight do
    system_command "#{appdir}/Triage.app/Contents/MacOS/triage-hook",
                   args:         ["uninstall"],
                   must_succeed: false
  end

  uninstall quit: "io.github.dkeg.triage"

  zap trash: [
    "~/Library/Application Support/Triage",
    "~/Library/Logs/Triage",
    "~/Library/Preferences/io.github.dkeg.triage.plist",
  ]

  caveats <<~EOS
    On first launch triage offers to connect to Claude Code. That adds hook entries to
    ~/.claude/settings.json (a backup is saved next to it). You can also run:

      triage-hook install

    Uninstalling the cask removes those entries again.
  EOS
end
