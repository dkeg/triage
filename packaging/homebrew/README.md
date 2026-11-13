# Homebrew tap

The cask lives in a separate public repo, `dkeg/homebrew-triage`, at `Casks/triage.rb`
(copy `triage.rb` from this folder). The release workflow rewrites its `version` and
`sha256` on every tagged release.

```
brew install --cask dkeg/triage/triage
```
