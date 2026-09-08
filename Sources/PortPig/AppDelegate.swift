import AppKit
import SwiftUI
import PortPigCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private let viewModel = PortListViewModel()
    private let launchAtLogin = LaunchAtLoginController()
    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private var autoRefreshTask: Task<Void, Never>?

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        configureStatusItem()
        configurePopover()
        startAutoRefresh()
    }

    func applicationWillTerminate(_ notification: Notification) {
        autoRefreshTask?.cancel()
    }

    private func configureStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        guard let button = statusItem?.button else {
            return
        }

        button.image = MenuBarIcon.image
        button.toolTip = L10n.appName
        button.setAccessibilityLabel(L10n.appName)
        button.target = self
        button.action = #selector(handleStatusItemClick(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    private func configurePopover() {
        popover.behavior = .transient
        popover.contentSize = NSSize(width: 420, height: 460)
        popover.delegate = self
        popover.contentViewController = NSHostingController(
            rootView: PortPopoverView(
                viewModel: viewModel,
                launchAtLogin: launchAtLogin,
                onShowAbout: { [weak self] in
                    self?.showAbout(nil)
                },
                onQuit: { NSApp.terminate(nil) },
                onSettingsMenuClosed: { [weak self] in
                    self?.popover.close()
                }
            )
        )
    }

    private func startAutoRefresh() {
        autoRefreshTask?.cancel()
        autoRefreshTask = Task { [weak self] in
            var showsActivity = true

            while !Task.isCancelled {
                guard let self else {
                    return
                }

                await self.viewModel.refresh(showsActivity: showsActivity)
                showsActivity = false

                do {
                    try await Task.sleep(for: .seconds(3))
                } catch {
                    return
                }
            }
        }
    }

    @objc private func handleStatusItemClick(_ sender: Any?) {
        guard NSApp.currentEvent?.type == .rightMouseUp else {
            togglePopover(sender)
            return
        }

        showContextMenu()
    }

    private func togglePopover(_ sender: Any?) {
        if popover.isShown {
            popover.performClose(sender)
        } else {
            showPopover()
        }
    }

    private func showContextMenu() {
        guard let button = statusItem?.button, let event = NSApp.currentEvent else {
            return
        }

        if popover.isShown {
            popover.performClose(nil)
        }

        launchAtLogin.refreshStatus()

        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.appearance = NSApp.effectiveAppearance

        addPortSummaryItems(to: menu)
        menu.addItem(.separator())

        let openItem = NSMenuItem(
            title: L10n.openPortPig,
            action: #selector(openPopover(_:)),
            keyEquivalent: ""
        )
        openItem.target = self
        openItem.image = NSImage(
            systemSymbolName: "macwindow",
            accessibilityDescription: L10n.openPortPig
        )
        menu.addItem(openItem)

        let aboutItem = NSMenuItem(
            title: L10n.aboutPortPig,
            action: #selector(showAbout(_:)),
            keyEquivalent: ""
        )
        aboutItem.target = self
        menu.addItem(aboutItem)
        menu.addItem(.separator())

        let launchAtLoginItem = NSMenuItem(
            title: L10n.launchAtLogin,
            action: #selector(toggleLaunchAtLogin(_:)),
            keyEquivalent: ""
        )
        launchAtLoginItem.target = self
        launchAtLoginItem.state = launchAtLogin.isEnabled ? .on : .off
        menu.addItem(launchAtLoginItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: L10n.quit,
            action: #selector(quit(_:)),
            keyEquivalent: "q"
        )
        quitItem.target = self
        quitItem.keyEquivalentModifierMask = .command
        menu.addItem(quitItem)

        NSMenu.popUpContextMenu(menu, with: event, for: button)
    }

    private func addPortSummaryItems(to menu: NSMenu) {
        guard let summary = viewModel.portSummary else {
            let title = viewModel.isLoading ? L10n.scanningPorts : L10n.portCountsUnavailable
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
            return
        }

        let titles = [
            L10n.totalPorts(summary.total),
            L10n.developmentPorts(summary.development),
            L10n.appsAndHelpersPorts(summary.appsAndHelpers),
            L10n.systemPorts(summary.system)
        ]

        for title in titles {
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        }
    }

    @objc private func openPopover(_ sender: Any?) {
        DispatchQueue.main.async { [weak self] in
            self?.showPopover()
        }
    }

    @objc private func toggleLaunchAtLogin(_ sender: Any?) {
        launchAtLogin.setEnabled(!launchAtLogin.isEnabled)
    }

    @objc private func showAbout(_ sender: Any?) {
        let companyURL = "https://inc.lawnect.com/"
        let sourceURL = "https://github.com/lawnect/portpig"
        let credits = NSMutableAttributedString(
            string: "\(companyURL)\n\(sourceURL)\n\nMIT License"
        )
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        credits.addAttributes(
            [
                .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
                .paragraphStyle: paragraphStyle
            ],
            range: NSRange(location: 0, length: credits.length)
        )

        for address in [companyURL, sourceURL] {
            guard let url = URL(string: address) else {
                continue
            }

            credits.addAttributes(
                [
                    .foregroundColor: NSColor.linkColor,
                    .link: url
                ],
                range: (credits.string as NSString).range(of: address)
            )
        }

        NSApp.orderFrontStandardAboutPanel(
            options: [
                .credits: credits
            ]
        )
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func quit(_ sender: Any?) {
        NSApp.terminate(sender)
    }

    private func showPopover() {
        guard let button = statusItem?.button else {
            return
        }

        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()

        Task {
            await viewModel.refresh()
        }
    }
}
