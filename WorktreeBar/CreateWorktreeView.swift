import SwiftUI

struct CreateWorktreeView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var branchName: String = ""
    @State private var createNewBranch: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Create Worktree")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                Text("Branch name:")
                    .font(.subheadline)
                TextField("feature/my-feature", text: $branchName)
                    .textFieldStyle(.roundedBorder)

                Toggle("Create new branch", isOn: $createNewBranch)
                    .font(.subheadline)
            }

            HStack {
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("Create") {
                    guard !branchName.isEmpty else { return }
                    appState.createWorktree(branch: branchName, createNew: createNewBranch)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(branchName.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 340)
    }
}
