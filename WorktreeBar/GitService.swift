import Foundation

struct GitService {

    // MARK: - Run git command

    static func run(_ args: [String], at directory: String? = nil) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = args
        if let directory {
            process.currentDirectoryURL = URL(fileURLWithPath: directory)
        }
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }
        guard process.terminationStatus == 0 else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - List worktrees

    static func listWorktrees(repoPath: String) -> [Worktree] {
        guard let output = run(["worktree", "list", "--porcelain"], at: repoPath) else {
            return []
        }
        return parsePorcelain(output, repoPath: repoPath)
    }

    private static func parsePorcelain(_ output: String, repoPath: String) -> [Worktree] {
        var worktrees: [Worktree] = []
        // Split by double newline to get each worktree block
        // But the last block may not have a trailing newline
        let blocks = output.components(separatedBy: "\n\n").filter { !$0.isEmpty }

        for block in blocks {
            let lines = block.components(separatedBy: "\n")
            var path = ""
            var sha = ""
            var branch = ""
            var isDetached = false
            var isBare = false

            for line in lines {
                if line.hasPrefix("worktree ") {
                    path = String(line.dropFirst("worktree ".count))
                } else if line.hasPrefix("HEAD ") {
                    sha = String(line.dropFirst("HEAD ".count))
                } else if line.hasPrefix("branch ") {
                    let fullRef = String(line.dropFirst("branch ".count))
                    // Strip refs/heads/ prefix
                    branch = fullRef.replacingOccurrences(of: "refs/heads/", with: "")
                } else if line == "detached" {
                    isDetached = true
                } else if line == "bare" {
                    isBare = true
                }
            }

            guard !path.isEmpty, !isBare else { continue }

            let isMain = path == repoPath ||
                         path == repoPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))

            if isDetached && branch.isEmpty {
                branch = String(sha.prefix(7)) + " (detached)"
            }

            let wt = Worktree(
                id: path,
                path: path,
                branch: branch.isEmpty ? "(unknown)" : branch,
                isMain: isMain,
                isDetached: isDetached,
                headSHA: sha
            )
            worktrees.append(wt)
        }

        return worktrees
    }

    // MARK: - Status queries

    static func isDirty(at path: String) -> Bool {
        guard let output = run(["status", "--porcelain"], at: path) else { return false }
        return !output.isEmpty
    }

    static func aheadBehind(at path: String) -> (ahead: Int, behind: Int) {
        guard let output = run(["rev-list", "--left-right", "--count", "HEAD...@{upstream}"], at: path) else {
            return (0, 0)
        }
        let parts = output.split(separator: "\t")
        guard parts.count == 2,
              let ahead = Int(parts[0]),
              let behind = Int(parts[1]) else {
            return (0, 0)
        }
        return (ahead, behind)
    }

    static func lastCommitDate(at path: String) -> Date? {
        guard let output = run(["log", "-1", "--format=%ci"], at: path), !output.isEmpty else {
            return nil
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss Z"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.date(from: output)
    }

    // MARK: - Claude session detection

    /// Reads status files written by worktreebar-hook.sh to determine Claude session state.
    /// Files are in ~/.worktreebar-claude-status/<encoded-path>.json
    /// Uses the `event` field for fine-grained status:
    ///   - PermissionRequest → .waitingPermission (until next event overrides)
    ///   - PreToolUse → .toolRunning (120s timeout, tools can run long)
    ///   - PostToolUse/Notification/other → .active (30s timeout)
    ///   - Stop → .idle if process alive, .ended if process gone
    static func claudeSessionMap() -> [String: ClaudeStatus] {
        let statusDir = NSHomeDirectory() + "/.worktreebar-claude-status"
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(atPath: statusDir) else { return [:] }

        var result: [String: ClaudeStatus] = [:]
        let now = Date()
        let staleThreshold: TimeInterval = 60

        for file in files where file.hasSuffix(".json") {
            let filePath = statusDir + "/" + file
            guard let data = try? Data(contentsOf: URL(fileURLWithPath: filePath)),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let path = json["path"] as? String,
                  let timestamp = json["time"] as? TimeInterval else { continue }

            let event = json["event"] as? String ?? ""
            let age = now.timeIntervalSince1970 - timestamp

            // Stale file (>60s) and process gone → clean up
            if age > staleThreshold && !isClaudeProcessRunning(at: path) {
                try? fm.removeItem(atPath: filePath)
                continue
            }

            let status: ClaudeStatus
            switch event {
            case "Stop":
                status = isClaudeProcessRunning(at: path) ? .idle : .ended

            case "PermissionRequest":
                // Waiting state within 120s; after that, fall back to process check
                if age <= 120 {
                    status = .waitingPermission
                } else {
                    status = isClaudeProcessRunning(at: path) ? .active : .ended
                }

            case "PreToolUse":
                // Tools can run long (e.g. Bash), 120s timeout
                status = age <= 120 ? .toolRunning : .idle

            default:
                // PostToolUse, Notification, and others → active with 30s timeout
                status = age <= 30 ? .active : .idle
            }

            result[path] = status
        }

        return result
    }

    // MARK: - Claude process detection

    /// Check if any claude process has its cwd set to the given path
    private static func isClaudeProcessRunning(at path: String) -> Bool {
        let pids = claudePIDs()
        for pid in pids {
            if let cwd = getCwd(for: pid), cwd == path {
                return true
            }
        }
        return false
    }

    /// Get all PIDs of running claude processes
    private static func claudePIDs() -> [String] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        process.arguments = ["-x", "claude"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return []
        }
        guard process.terminationStatus == 0 else { return [] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else { return [] }
        return output.split(separator: "\n").map(String.init)
    }

    /// Get the current working directory of a process via lsof
    private static func getCwd(for pid: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        process.arguments = ["-a", "-p", pid, "-d", "cwd", "-Fn"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }
        guard process.terminationStatus == 0 else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else { return nil }
        // lsof -Fn outputs lines like "p1234\nn/path/to/dir"
        for line in output.split(separator: "\n") {
            if line.hasPrefix("n") && !line.hasPrefix("n ") {
                return String(line.dropFirst())
            }
        }
        return nil
    }

    // MARK: - Worktree operations

    static func createWorktree(repoPath: String, branchName: String, createNewBranch: Bool) -> (success: Bool, message: String) {
        // Determine worktree path: sibling directory to repo
        let repoURL = URL(fileURLWithPath: repoPath)
        let parentDir = repoURL.deletingLastPathComponent().path
        let worktreePath = parentDir + "/" + branchName.replacingOccurrences(of: "/", with: "-")

        var args = ["worktree", "add"]
        if createNewBranch {
            args += ["-b", branchName, worktreePath]
        } else {
            args += [worktreePath, branchName]
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = args
        process.currentDirectoryURL = URL(fileURLWithPath: repoPath)

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return (false, error.localizedDescription)
        }

        if process.terminationStatus == 0 {
            return (true, "Created worktree at \(worktreePath)")
        } else {
            let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
            let errStr = String(data: errData, encoding: .utf8) ?? "Unknown error"
            return (false, errStr)
        }
    }

    static func removeWorktree(repoPath: String, worktreePath: String) -> (success: Bool, message: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["worktree", "remove", worktreePath]
        process.currentDirectoryURL = URL(fileURLWithPath: repoPath)

        let errPipe = Pipe()
        process.standardOutput = Pipe()
        process.standardError = errPipe

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return (false, error.localizedDescription)
        }

        if process.terminationStatus == 0 {
            return (true, "Removed worktree")
        } else {
            let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
            let errStr = String(data: errData, encoding: .utf8) ?? "Unknown error"
            return (false, errStr)
        }
    }
}
