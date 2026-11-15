import Foundation
import TriageCore

/// Feature switches for things that are built but not shown yet.
enum Features {
    /// "Always allow" on the approval card. Off until the card shows the rule it will save: Claude
    /// Code's suggestions are often broad wildcards (for example `gh repo *`).
    static let alwaysAllow = false
}

enum Pref {
    static let hoverOpen = "hoverOpen"
    static let hoverDelay = "hoverDelay"
    static let autoOpenOnAttention = "autoOpenOnAttention"
    static let autoCollapseSeconds = "autoCollapseSeconds"
    static let holdWhenFocused = "holdWhenFocused"
    static let pillWidth = "pillWidth"
    static let pillSide = "pillSide"
    static let rotateSeconds = "rotateSeconds"
    static let pillNudge = "pillNudge"
    static let hooksReconnectDeclined = TriagePaths.hooksDeclinedKey
    static let showTerminals = "showTerminals"
    static let showIdleTerminals = "showIdleTerminals"
    static let showCommandArguments = "showCommandArguments"
    static let rowsPerSection = "rowsPerSection"
    static let cardLayout = "cardLayout"
    static let avoidMenuIcons = "avoidMenuIcons"
    static let approvalTimeout = "approvalTimeout"
}
