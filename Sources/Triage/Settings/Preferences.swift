import Foundation
import TriageCore

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
