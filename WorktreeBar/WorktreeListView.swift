import SwiftUI

struct WorktreeListView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            // Title bar
            HStack {
                Image(systemName: "arrow.triangle.branch")
                    .foregroundColor(.green)
                Text("WorktreeBar")
                    .font(.headline)

                Spacer()

                if appState.isLoading {
                    ProgressView()
                        .scaleEffect(0.6)
                        .frame(width: 16, height: 16)
                } else {
                    Button(action: { appState.refresh() }) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.plain)
                    .help("Refresh")
                }

                Menu {
                    Button("Change Repo...") {
                        appState.pickRepo()
                    }
                    Divider()
                    Button("Quit WorktreeBar") {
                        NSApplication.shared.terminate(nil)
                    }
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 12))
                }
                .menuStyle(.borderlessButton)
                .frame(width: 20)

                Button(action: { appState.showCreateSheet = true }) {
                    Image(systemName: "plus")
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .help("Create Worktree")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            if !appState.hasRepo {
                // No repo selected
                VStack(spacing: 12) {
                    Image(systemName: "folder.badge.questionmark")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text("No repository selected")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Button("Select Repository") {
                        appState.pickRepo()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
                .frame(maxWidth: .infinity, minHeight: 150)
                .padding()
            } else if appState.worktrees.isEmpty && !appState.isLoading {
                VStack(spacing: 8) {
                    Image(systemName: "tray")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text("No worktrees found")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 150)
                .padding()
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(appState.worktrees) { worktree in
                            WorktreeRow(worktree: worktree)
                            if worktree.id != appState.worktrees.last?.id {
                                Divider()
                                    .padding(.horizontal, 10)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
                .frame(maxHeight: 500)
            }

            // Error banner
            if let error = appState.errorMessage {
                Divider()
                HStack {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundColor(.orange)
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                    Spacer()
                    Button(action: { appState.errorMessage = nil }) {
                        Image(systemName: "xmark")
                            .font(.caption2)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            }

            Divider()

            // Footer
            HStack {
                if appState.hasRepo {
                    Text(appState.repoPath)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundColor(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
        .frame(width: 380)
        .onAppear {
            appState.refresh()
        }
        .sheet(isPresented: $appState.showCreateSheet) {
            CreateWorktreeView()
                .environmentObject(appState)
        }
    }
}
