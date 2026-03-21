import SwiftUI
import Combine

@main
@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private let appState = AppState()
    private var cancellables = Set<AnyCancellable>()

    override init() {
        super.init()
    }

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 1. Create status item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(
                systemSymbolName: "arrow.triangle.branch",
                accessibilityDescription: "WorktreeBar"
            )
            button.imagePosition = .imageLeading
            button.action = #selector(togglePopover)
            button.target = self
        }

        // 2. Popover hosts existing SwiftUI view (zero changes to views)
        let hostingController = NSHostingController(
            rootView: WorktreeListView().environmentObject(appState)
        )
        popover.contentViewController = hostingController
        popover.behavior = .transient

        // 3. Subscribe to AppState changes → update badge
        appState.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                // objectWillChange fires before the change, so defer to next run loop
                DispatchQueue.main.async { self?.updateBadge() }
            }
            .store(in: &cancellables)

        // 4. Notification setup
        NotificationManager.shared.setup()

        // 5. Initial badge
        updateBadge()
    }

    private func updateBadge() {
        guard let button = statusItem.button else { return }
        let badge = appState.menuBarBadge
        button.title = badge.isEmpty ? "" : " \(badge)"
    }

    @objc private func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
        } else if let button = statusItem.button {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }
}
