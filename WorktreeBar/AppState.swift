import Foundation
import SwiftUI
import Combine

@MainActor
class AppState: ObservableObject {
    @Published var worktrees: [Worktree] = []
    @Published var isLoading = false
    @Published var showCreateSheet = false
    @Published var errorMessage: String? = nil

    @AppStorage("repoPath") var repoPath: String = ""

    private var timer: Timer?
    private var fileMonitor: DispatchSourceFileSystemObject?
    private var dirFileDescriptor: Int32 = -1

    var hasRepo: Bool { !repoPath.isEmpty }

    /// Menu bar 顯示的文字 — 優先順序：⚠ > ↑ > !
    var menuBarBadge: String {
        let working = worktrees.filter { $0.claudeStatus.isWorking }.count
        let waiting = worktrees.filter { $0.claudeStatus == .waitingPermission }.count
        let idle = worktrees.filter { $0.claudeStatus == .idle }.count
        var parts: [String] = []
        if waiting > 0 { parts.append("\(waiting)⚠") }
        if working > 0 { parts.append("\(working)↑") }
        if idle > 0 { parts.append("\(idle)!") }
        return parts.joined(separator: " ")
    }

    init() {
        startTimer()
        startClaudeStatusMonitor()
    }

    deinit {
        fileMonitor?.cancel()
        if dirFileDescriptor >= 0 {
            close(dirFileDescriptor)
        }
    }

    // MARK: - Refresh

    func refresh() {
        guard hasRepo else { return }
        isLoading = true

        Task.detached { [repoPath = self.repoPath] in
            var trees = GitService.listWorktrees(repoPath: repoPath)
            // Apply Claude status from files immediately
            let claudeMap = GitService.claudeSessionMap()
            for i in trees.indices {
                trees[i].claudeStatus = claudeMap[trees[i].path] ?? .none
            }
            trees.sort { a, b in
                if a.isMain != b.isMain { return !a.isMain }
                let pa = a.claudeStatus.sortPriority
                let pb = b.claudeStatus.sortPriority
                if pa != pb { return pa < pb }
                return false
            }

            await MainActor.run { [trees] in
                self.worktrees = trees
                self.isLoading = false
            }

            // Phase 2: git status details (parallel, updates in background)
            var detailedTrees = trees
            await withTaskGroup(of: (Int, Bool, Int, Int, Date?).self) { group in
                for (index, wt) in detailedTrees.enumerated() {
                    group.addTask {
                        let dirty = GitService.isDirty(at: wt.path)
                        let ab = GitService.aheadBehind(at: wt.path)
                        let date = GitService.lastCommitDate(at: wt.path)
                        return (index, dirty, ab.ahead, ab.behind, date)
                    }
                }
                for await result in group {
                    let (i, dirty, ahead, behind, date) = result
                    detailedTrees[i].isDirty = dirty
                    detailedTrees[i].ahead = ahead
                    detailedTrees[i].behind = behind
                    detailedTrees[i].lastCommitDate = date
                }
            }

            detailedTrees.sort { a, b in
                if a.isMain != b.isMain { return !a.isMain }
                let pa = a.claudeStatus.sortPriority
                let pb = b.claudeStatus.sortPriority
                if pa != pb { return pa < pb }
                let da = a.lastCommitDate ?? .distantPast
                let db = b.lastCommitDate ?? .distantPast
                return da > db
            }

            await MainActor.run { [detailedTrees] in
                self.worktrees = detailedTrees
            }
        }
    }

    // MARK: - Claude status (lightweight, only reads status files)

    /// Fast update: only refreshes Claude status badges without re-querying git.
    /// Detects state transitions and sends macOS notifications.
    func refreshClaudeStatus() {
        guard hasRepo, !worktrees.isEmpty else { return }
        let claudeMap = GitService.claudeSessionMap()
        for i in worktrees.indices {
            let oldStatus = worktrees[i].claudeStatus
            let newStatus = claudeMap[worktrees[i].path] ?? .none

            // Notify on meaningful transitions from working states
            if oldStatus.isWorking {
                let branch = worktrees[i].branch
                let path = worktrees[i].path
                switch newStatus {
                case .idle:
                    NotificationManager.shared.notify(
                        branch: branch, path: path,
                        title: "Claude 已完成",
                        body: "\(branch) 的 Claude 已完成處理，請查看結果"
                    )
                case .waitingPermission:
                    NotificationManager.shared.notify(
                        branch: branch, path: path,
                        title: "Claude 等待授權",
                        body: "\(branch) 的 Claude 需要授權才能繼續"
                    )
                case .ended:
                    NotificationManager.shared.notify(
                        branch: branch, path: path,
                        title: "Claude Session 已結束",
                        body: "\(branch) 的 Claude 已結束"
                    )
                default:
                    break
                }
            }
            worktrees[i].claudeStatus = newStatus
        }
        sortWorktrees(&worktrees)
    }

    // MARK: - Sorting

    private func sortWorktrees(_ trees: inout [Worktree]) {
        trees.sort { a, b in
            // Main repo always last
            if a.isMain != b.isMain { return !a.isMain }
            // Sort by Claude status priority (active > idle > none)
            let pa = a.claudeStatus.sortPriority
            let pb = b.claudeStatus.sortPriority
            if pa != pb { return pa < pb }
            // Then by last commit date (most recent first)
            let da = a.lastCommitDate ?? .distantPast
            let db = b.lastCommitDate ?? .distantPast
            return da > db
        }
    }

    // MARK: - File system monitor for ~/.worktreebar-claude-status/

    private func startClaudeStatusMonitor() {
        let statusDir = NSHomeDirectory() + "/.worktreebar-claude-status"

        // Ensure directory exists
        try? FileManager.default.createDirectory(atPath: statusDir, withIntermediateDirectories: true)

        dirFileDescriptor = open(statusDir, O_EVTONLY)
        guard dirFileDescriptor >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: dirFileDescriptor,
            eventMask: .write,
            queue: .global(qos: .utility)
        )

        source.setEventHandler { [weak self] in
            // Debounce: wait a tiny bit for file write to complete
            usleep(50_000) // 50ms
            Task { @MainActor [weak self] in
                self?.refreshClaudeStatus()
            }
        }

        source.setCancelHandler { [fd = dirFileDescriptor] in
            close(fd)
        }

        source.resume()
        fileMonitor = source
        dirFileDescriptor = -1  // ownership transferred to cancel handler
    }

    // MARK: - Worktree operations

    func createWorktree(branch: String, createNew: Bool) {
        Task.detached { [repoPath = self.repoPath] in
            let result = GitService.createWorktree(
                repoPath: repoPath,
                branchName: branch,
                createNewBranch: createNew
            )
            await MainActor.run {
                if result.success {
                    self.refresh()
                } else {
                    self.errorMessage = result.message
                }
            }
        }
    }

    func removeWorktree(_ worktree: Worktree) {
        Task.detached { [repoPath = self.repoPath] in
            let result = GitService.removeWorktree(
                repoPath: repoPath,
                worktreePath: worktree.path
            )
            await MainActor.run {
                if result.success {
                    self.refresh()
                } else {
                    self.errorMessage = result.message
                }
            }
        }
    }

    // MARK: - Actions

    func openTerminal(at path: String) {
        Self.openTerminalTab(at: path)
    }

    /// Runs the entire Terminal tab detection + activation via a background osascript process.
    /// This avoids all @MainActor, NSAppleScript threading, and sandbox issues.
    nonisolated static func openTerminalTab(at path: String) {
        let script = """
        tell application "Terminal"
            set targetPath to "\(path.replacingOccurrences(of: "\"", with: "\\\""))"
            set foundTab to false
            repeat with w in windows
                set tabIndex to 0
                repeat with t in tabs of w
                    set tabIndex to tabIndex + 1
                    try
                        set tabTTY to tty of t
                        set shellPID to do shell script "ps -t " & quoted form of tabTTY & " -o pid= | tail -1 | xargs"
                        if shellPID is not "" then
                            set cwdPath to do shell script "lsof -a -p " & shellPID & " -d cwd -Fn 2>/dev/null | tail -1 | cut -c2-"
                            if cwdPath is equal to targetPath then
                                set selected of t to true
                                set index of w to 1
                                set foundTab to true
                                exit repeat
                            end if
                        end if
                    end try
                end repeat
                if foundTab then exit repeat
            end repeat
            activate
            if not foundTab then
                do script "cd " & quoted form of targetPath
            end if
        end tell
        """

        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", script]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try? process.run()
            process.waitUntilExit()
        }
    }

    func openInAndroidStudio(at path: String) {
        let studioPaths = [
            "/Applications/Android Studio.app",
            NSHomeDirectory() + "/Applications/Android Studio.app"
        ]
        guard let studioPath = studioPaths.first(where: { FileManager.default.fileExists(atPath: $0) }) else {
            errorMessage = "Android Studio not found"
            return
        }
        let studioURL = URL(fileURLWithPath: studioPath)
        let folderURL = URL(fileURLWithPath: path)
        NSWorkspace.shared.open(
            [folderURL],
            withApplicationAt: studioURL,
            configuration: NSWorkspace.OpenConfiguration()
        )
    }

    // MARK: - Repo picker

    func pickRepo() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Select the main git repository folder"
        panel.prompt = "Select"

        if panel.runModal() == .OK, let url = panel.url {
            repoPath = url.path
            refresh()
        }
    }

    // MARK: - Timer

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { _ in
            Task { @MainActor [weak self] in
                self?.refresh()
            }
        }
    }
}
