import SwiftUI

struct WorktreeRow: View {
    let worktree: Worktree
    @EnvironmentObject var appState: AppState
    @State private var isHovering = false
    @State private var showRemoveConfirm = false

    private func claudeStatusColor(_ status: ClaudeStatus) -> Color {
        switch status {
        case .active: return .green
        case .toolRunning: return .blue
        case .waitingPermission: return .red
        case .idle: return .orange
        case .ended: return .gray
        case .none: return .clear
        }
    }

    private var relativeTime: String {
        guard let date = worktree.lastCommitDate else { return "" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return "Last commit: " + formatter.localizedString(for: date, relativeTo: Date())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Row 1: branch name + claude badge + status tag + dirty tag
            HStack(spacing: 8) {
                // Branch name
                Text(worktree.branch)
                    .font(.system(.body, design: .monospaced))
                    .fontWeight(worktree.isMain ? .semibold : .regular)
                    .lineLimit(1)

                // Claude session indicator
                if worktree.claudeStatus != .none && worktree.claudeStatus != .ended {
                    let badgeColor = claudeStatusColor(worktree.claudeStatus)
                    HStack(spacing: 3) {
                        Image(systemName: worktree.claudeStatus.iconName)
                            .font(.system(size: 8))
                            .foregroundColor(badgeColor)
                        Text(worktree.claudeStatus.label)
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .foregroundColor(badgeColor)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(badgeColor.opacity(0.15))
                    )
                }

                Spacer()

                // Main repo tag
                if worktree.isMain {
                    Text("Main")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.purple)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.purple.opacity(0.15))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(Color.purple.opacity(0.3), lineWidth: 0.5)
                        )
                }

                // Dirty/clean tag
                Text(worktree.isDirty ? "Dirty" : "Clean")
                    .font(.caption)
                    .foregroundColor(worktree.isDirty ? .orange : .green)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(worktree.isDirty ? Color.orange.opacity(0.15) : Color.green.opacity(0.15))
                    )
            }

            // Row 2: ahead/behind + relative time
            HStack(spacing: 8) {
                if worktree.ahead > 0 || worktree.behind > 0 {
                    HStack(spacing: 4) {
                        if worktree.ahead > 0 {
                            Text("\u{2191}\(worktree.ahead) ahead")
                                .foregroundColor(.green)
                        }
                        if worktree.behind > 0 {
                            Text("\u{2193}\(worktree.behind) behind")
                                .foregroundColor(.red)
                        }
                    }
                    .font(.caption)
                }

                if !relativeTime.isEmpty {
                    Text(relativeTime)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()
            }

            // Row 3: action buttons (show on hover) or inline remove confirmation
            if showRemoveConfirm {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                            .font(.caption)
                        Text("Remove this worktree? This cannot be undone.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Text(worktree.path)
                        .font(.caption2)
                        .foregroundColor(.secondary.opacity(0.8))
                        .lineLimit(2)
                        .textSelection(.enabled)
                    HStack(spacing: 8) {
                        Spacer()
                        Button("Cancel") {
                            showRemoveConfirm = false
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)

                        Button("Remove") {
                            showRemoveConfirm = false
                            appState.removeWorktree(worktree)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                        .controlSize(.small)
                    }
                }
            } else if isHovering {
                HStack(spacing: 8) {
                    Button(action: { appState.openTerminal(at: worktree.path) }) {
                        Label("Terminal", systemImage: "terminal")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button(action: { appState.openInAndroidStudio(at: worktree.path) }) {
                        Label("Studio", systemImage: "hammer")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Spacer()

                    if !worktree.isMain {
                        Button(action: { showRemoveConfirm = true }) {
                            Image(systemName: "trash")
                                .foregroundColor(.red)
                                .font(.caption)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isHovering ? Color.primary.opacity(0.05) : Color.clear)
        )
        .onHover { hovering in
            // Keep hover state while remove confirmation is showing
            if !showRemoveConfirm {
                isHovering = hovering
            }
        }
        .contextMenu {
            Button("Open in Terminal") {
                appState.openTerminal(at: worktree.path)
            }
            Button("Open in Android Studio") {
                appState.openInAndroidStudio(at: worktree.path)
            }
            Divider()
            Button("Copy Path") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(worktree.path, forType: .string)
            }
            if !worktree.isMain {
                Divider()
                Button("Remove Worktree", role: .destructive) {
                    showRemoveConfirm = true
                }
            }
        }
    }
}
