import Foundation

enum ClaudeStatus: Equatable {
    case none
    case active
    case toolRunning
    case waitingPermission
    case idle
    case ended

    var label: String {
        switch self {
        case .none: return ""
        case .active: return "Active"
        case .toolRunning: return "Tool Running"
        case .waitingPermission: return "Waiting Permission"
        case .idle: return "Idle"
        case .ended: return "Ended"
        }
    }

    var color: String {
        switch self {
        case .none: return ""
        case .active: return "green"
        case .toolRunning: return "blue"
        case .waitingPermission: return "red"
        case .idle: return "orange"
        case .ended: return "gray"
        }
    }

    var iconName: String {
        switch self {
        case .none: return ""
        case .active: return "bolt.fill"
        case .toolRunning: return "gearshape.fill"
        case .waitingPermission: return "exclamationmark.circle.fill"
        case .idle: return "pause.circle.fill"
        case .ended: return "checkmark.circle"
        }
    }

    /// Lower value = higher priority in sort order
    var sortPriority: Int {
        switch self {
        case .waitingPermission: return 0
        case .active: return 1
        case .toolRunning: return 2
        case .idle: return 3
        case .ended: return 4
        case .none: return 5
        }
    }

    /// Whether Claude is actively working (processing or running tools)
    var isWorking: Bool {
        self == .active || self == .toolRunning
    }
}

struct Worktree: Identifiable {
    let id: String
    let path: String
    let branch: String
    let isMain: Bool
    let isDetached: Bool
    let headSHA: String
    var isDirty: Bool = false
    var ahead: Int = 0
    var behind: Int = 0
    var lastCommitDate: Date? = nil
    var claudeStatus: ClaudeStatus = .none
}
