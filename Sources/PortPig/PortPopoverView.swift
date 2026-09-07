import AppKit
import SwiftUI
import PortPigCore

private enum FilterScreen {
    case manager
    case editor(SavedPortFilter, isNew: Bool)
}

struct PortPopoverView: View {
    @ObservedObject var viewModel: PortListViewModel
    @StateObject private var launchAtLogin = LaunchAtLoginController()
    @State private var filterScreen: FilterScreen?
    let onQuit: () -> Void
    let onSettingsMenuClosed: () -> Void

    var body: some View {
        Group {
            switch filterScreen {
            case .manager:
                FilterManagerView(
                    filters: viewModel.savedFilters,
                    selectedFilterID: viewModel.selectedFilterID,
                    onBack: { filterScreen = nil },
                    onNew: {
                        filterScreen = .editor(
                            SavedPortFilter(name: L10n.newFilter, isPinned: true),
                            isNew: true
                        )
                    },
                    onSelect: { id in
                        viewModel.selectFilter(id: id)
                        filterScreen = nil
                    },
                    onEdit: { filter in filterScreen = .editor(filter, isNew: false) },
                    onSetPinned: viewModel.setFilterPinned,
                    onDelete: viewModel.deleteFilter
                )
            case let .editor(filter, isNew):
                FilterEditorView(
                    initialFilter: filter,
                    isNew: isNew,
                    onCancel: { filterScreen = .manager },
                    onSave: { filter in
                        viewModel.saveFilter(filter)
                        filterScreen = nil
                    }
                )
            case nil:
                portList
            }
        }
        .frame(width: 420, height: 488)
        .onAppear {
            launchAtLogin.refreshStatus()
        }
    }

    private var portList: some View {
        VStack(spacing: 0) {
            header
            searchBar
            Divider()
            content
            errorFooter
            Divider()
            footer
        }
    }

    private var header: some View {
        ZStack {
            filterBar

            HStack(spacing: 10) {
                HStack(spacing: 6) {
                    Image(nsImage: MenuBarIcon.image)
                        .resizable()
                        .frame(width: 18, height: 18)
                        .accessibilityHidden(true)

                    Text(L10n.appName)
                        .font(.headline)
                }

                Spacer(minLength: 8)

                SettingsMenuButton(
                    isLaunchAtLoginEnabled: launchAtLogin.isEnabled,
                    onToggleLaunchAtLogin: { isEnabled in
                        launchAtLogin.setEnabled(isEnabled)
                    },
                    onQuit: onQuit,
                    onMenuClosed: onSettingsMenuClosed
                )
                .frame(width: 24, height: 24)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private var filterBar: some View {
        HStack(spacing: 2) {
            filterButton(
                title: L10n.allFilter,
                isSelected: viewModel.isAllFilterSelected,
                action: viewModel.selectAllFilter
            )

            ForEach(viewModel.visibleSavedFilters) { filter in
                filterButton(
                    title: filter.name,
                    isSelected: viewModel.selectedFilterID == filter.id,
                    action: { viewModel.selectFilter(id: filter.id) }
                )
            }

            Divider()
                .frame(height: 18)

            Button {
                filterScreen = .manager
            } label: {
                Image(systemName: "plus")
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.plain)
            .help(L10n.filters)
        }
        .padding(3)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 7))
        .fixedSize(horizontal: true, vertical: false)
    }

    private func filterButton(
        title: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.callout)
                .lineLimit(1)
                .frame(minWidth: 36, maxWidth: 72)
                .padding(.horizontal, 5)
                .padding(.vertical, 3)
                .contentShape(Rectangle())
                .foregroundStyle(isSelected ? Color.white : Color.primary)
                .background(
                    isSelected ? Color.accentColor : Color.clear,
                    in: RoundedRectangle(cornerRadius: 5)
                )
        }
        .buttonStyle(.plain)
    }

    private var searchBar: some View {
        PortSearchField(
            text: $viewModel.portSearchText,
            placeholder: L10n.searchPlaceholder
        )
        .frame(height: 26)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.ports.isEmpty {
            VStack(spacing: 10) {
                if viewModel.isLoading {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 28))
                        .foregroundStyle(.secondary)
                }

                Text(viewModel.isLoading ? L10n.lookingForPorts : viewModel.emptyStateMessage)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List(viewModel.ports) { entry in
                PortRowView(
                    entry: entry,
                    isKilling: viewModel.killingPIDs.contains(entry.pid),
                    protectionReason: viewModel.protectionReason(for: entry),
                    onKill: {
                        Task {
                            await viewModel.kill(entry)
                        }
                    }
                )
            }
            .listStyle(.inset(alternatesRowBackgrounds: true))
        }
    }

    @ViewBuilder
    private var errorFooter: some View {
        if let errorMessage = viewModel.errorMessage ?? launchAtLogin.errorMessage {
            Divider()

            Label(errorMessage, systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(.red)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Button {
                Task {
                    await viewModel.refresh()
                }
            } label: {
                ZStack {
                    if viewModel.isLoading {
                        ProgressView()
                            .controlSize(.small)
                            .transition(
                                .scale(scale: 0.65)
                                    .combined(with: .opacity)
                            )
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .transition(
                                .scale(scale: 0.65)
                                    .combined(with: .opacity)
                            )
                    }
                }
                .frame(width: 16, height: 16)
                .animation(
                    .easeInOut(duration: 0.18),
                    value: viewModel.isLoading
                )
            }
            .buttonStyle(.borderless)
            .disabled(viewModel.isLoading)
            .help(L10n.refresh)

            Spacer()

            Text(viewModel.footerStatus)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

private struct FilterManagerView: View {
    let filters: [SavedPortFilter]
    let selectedFilterID: UUID?
    let onBack: () -> Void
    let onNew: () -> Void
    let onSelect: (UUID) -> Void
    let onEdit: (SavedPortFilter) -> Void
    let onSetPinned: (UUID, Bool) -> Void
    let onDelete: (UUID) -> Void
    @State private var filterPendingDeletion: SavedPortFilter?

    var body: some View {
        VStack(spacing: 0) {
            navigationHeader
            Divider()

            if filters.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                        .font(.system(size: 30))
                        .foregroundStyle(.secondary)
                    Text(L10n.noSavedFilters)
                        .foregroundStyle(.secondary)
                    Button(L10n.newFilter, action: onNew)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(filters) { filter in
                    filterRow(filter)
                }
                .listStyle(.inset(alternatesRowBackgrounds: true))
            }

            Divider()
            Text(L10n.filterPinLimit)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
        }
        .alert(
            L10n.deleteFilterTitle,
            isPresented: Binding(
                get: { filterPendingDeletion != nil },
                set: { isPresented in
                    if !isPresented {
                        filterPendingDeletion = nil
                    }
                }
            ),
            presenting: filterPendingDeletion
        ) { filter in
            Button(L10n.cancel, role: .cancel) {}
            Button(L10n.delete, role: .destructive) {
                onDelete(filter.id)
                filterPendingDeletion = nil
            }
        } message: { filter in
            Text(L10n.deleteFilterMessage(filter.name))
        }
    }

    private var navigationHeader: some View {
        HStack {
            Button(action: onBack) {
                Label(L10n.back, systemImage: "chevron.left")
            }
            .buttonStyle(.borderless)

            Spacer()
            Text(L10n.filters)
                .font(.headline)
            Spacer()

            Button(action: onNew) {
                Label(L10n.newFilter, systemImage: "plus")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.borderless)
            .help(L10n.newFilter)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private func filterRow(_ filter: SavedPortFilter) -> some View {
        HStack(spacing: 10) {
            Button {
                onSelect(filter.id)
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: selectedFilterID == filter.id ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(selectedFilterID == filter.id ? Color.accentColor : Color.secondary)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(filter.name)
                            .font(.body.weight(.medium))
                            .lineLimit(1)
                        Text(filterSummary(filter))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Spacer()

            Button {
                onSetPinned(filter.id, !filter.isPinned)
            } label: {
                Image(systemName: filter.isPinned ? "pin.fill" : "pin")
            }
            .buttonStyle(.borderless)
            .help(filter.isPinned ? L10n.unpin : L10n.pin)

            Button {
                onEdit(filter)
            } label: {
                Image(systemName: "pencil")
            }
            .buttonStyle(.borderless)
            .help(L10n.editFilter)

            Button(role: .destructive) {
                filterPendingDeletion = filter
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help(L10n.delete)
        }
        .padding(.vertical, 4)
    }

    private func filterSummary(_ filter: SavedPortFilter) -> String {
        var parts: [String] = []

        if filter.categories.isEmpty {
            parts.append(L10n.filterAnyCategories)
        } else {
            let names = filter.categories
                .sorted { $0.rawValue < $1.rawValue }
                .prefix(3)
                .map(L10n.categoryName)
            parts.append(names.joined(separator: ", "))
        }

        if filter.ownership != .any {
            parts.append(L10n.ownershipName(filter.ownership))
        }
        if filter.termination != .any {
            parts.append(L10n.terminationName(filter.termination))
        }
        if filter.exposure != .any {
            parts.append(L10n.exposureName(filter.exposure))
        }

        return parts.joined(separator: " · ")
    }
}

private struct FilterEditorView: View {
    @State private var filter: SavedPortFilter
    @State private var minimumPortText: String
    @State private var maximumPortText: String
    let isNew: Bool
    let onCancel: () -> Void
    let onSave: (SavedPortFilter) -> Void

    init(
        initialFilter: SavedPortFilter,
        isNew: Bool,
        onCancel: @escaping () -> Void,
        onSave: @escaping (SavedPortFilter) -> Void
    ) {
        _filter = State(initialValue: initialFilter)
        _minimumPortText = State(initialValue: initialFilter.minimumPort.map(String.init) ?? "")
        _maximumPortText = State(initialValue: initialFilter.maximumPort.map(String.init) ?? "")
        self.isNew = isNew
        self.onCancel = onCancel
        self.onSave = onSave
    }

    var body: some View {
        VStack(spacing: 0) {
            navigationHeader
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 7) {
                        Text(L10n.filterNameLabel)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextField(L10n.filterNameLabel, text: $filter.name)
                            .textFieldStyle(.roundedBorder)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text(L10n.filterCategories)
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        LazyVGrid(
                            columns: [GridItem(.flexible()), GridItem(.flexible())],
                            alignment: .leading,
                            spacing: 8
                        ) {
                            ForEach(PortCategory.allCases, id: \.self) { category in
                                Toggle(
                                    L10n.categoryName(category),
                                    isOn: categoryBinding(category)
                                )
                                .toggleStyle(.checkbox)
                            }
                        }
                    }

                    VStack(spacing: 12) {
                        rulePicker(
                            title: L10n.filterOwnership,
                            selection: $filter.ownership,
                            values: PortOwnershipScope.allCases,
                            name: L10n.ownershipName
                        )
                        rulePicker(
                            title: L10n.filterTermination,
                            selection: $filter.termination,
                            values: PortTerminationScope.allCases,
                            name: L10n.terminationName
                        )
                        rulePicker(
                            title: L10n.filterExposure,
                            selection: $filter.exposure,
                            values: PortExposureScope.allCases,
                            name: L10n.exposureName
                        )
                    }

                    VStack(alignment: .leading, spacing: 7) {
                        Text(L10n.filterProcessQuery)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextField(L10n.filterProcessQuery, text: $filter.processQuery)
                            .textFieldStyle(.roundedBorder)
                    }

                    VStack(alignment: .leading, spacing: 7) {
                        Text(L10n.filterPortRange)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        HStack {
                            TextField(L10n.filterMinimumPort, text: $minimumPortText)
                            Text("–")
                                .foregroundStyle(.secondary)
                            TextField(L10n.filterMaximumPort, text: $maximumPortText)
                        }
                        .textFieldStyle(.roundedBorder)
                    }

                    Toggle(L10n.filterPinned, isOn: $filter.isPinned)
                        .toggleStyle(.checkbox)
                }
                .padding(16)
            }
        }
    }

    private var navigationHeader: some View {
        HStack {
            Button(L10n.cancel, action: onCancel)
                .buttonStyle(.borderless)

            Spacer()
            Text(isNew ? L10n.newFilter : L10n.editFilter)
                .font(.headline)
            Spacer()

            Button(L10n.save) {
                filter.minimumPort = Int(minimumPortText)
                filter.maximumPort = Int(maximumPortText)
                onSave(filter)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(!isValid)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var isValid: Bool {
        !filter.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && isValidPortText(minimumPortText)
            && isValidPortText(maximumPortText)
            && portRangeIsOrdered
    }

    private var portRangeIsOrdered: Bool {
        guard let minimum = Int(minimumPortText),
              let maximum = Int(maximumPortText) else {
            return true
        }

        return minimum <= maximum
    }

    private func isValidPortText(_ text: String) -> Bool {
        text.isEmpty || Int(text).map { (1...65_535).contains($0) } == true
    }

    private func categoryBinding(_ category: PortCategory) -> Binding<Bool> {
        Binding(
            get: { filter.categories.contains(category) },
            set: { isSelected in
                if isSelected {
                    filter.categories.insert(category)
                } else {
                    filter.categories.remove(category)
                }
            }
        )
    }

    private func rulePicker<Value: Hashable>(
        title: String,
        selection: Binding<Value>,
        values: [Value],
        name: @escaping (Value) -> String
    ) -> some View {
        HStack {
            Text(title)
            Spacer()
            Picker(title, selection: selection) {
                ForEach(values, id: \.self) { value in
                    Text(name(value)).tag(value)
                }
            }
            .labelsHidden()
            .frame(width: 170)
        }
    }
}

private struct SettingsMenuButton: NSViewRepresentable {
    let isLaunchAtLoginEnabled: Bool
    let onToggleLaunchAtLogin: (Bool) -> Void
    let onQuit: () -> Void
    let onMenuClosed: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton()
        button.image = NSImage(
            systemSymbolName: "gearshape",
            accessibilityDescription: L10n.settings
        )
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyDown
        button.isBordered = false
        button.toolTip = L10n.settings
        button.setAccessibilityLabel(L10n.settings)
        button.target = context.coordinator
        button.action = #selector(Coordinator.showMenu(_:))
        return button
    }

    func updateNSView(_ button: NSButton, context: Context) {
        context.coordinator.parent = self
        button.toolTip = L10n.settings
        button.setAccessibilityLabel(L10n.settings)
    }

    @MainActor
    final class Coordinator: NSObject, NSMenuDelegate {
        var parent: SettingsMenuButton
        private var activeMenu: NSMenu?

        init(_ parent: SettingsMenuButton) {
            self.parent = parent
        }

        @objc func showMenu(_ sender: NSButton) {
            let menu = NSMenu()
            menu.autoenablesItems = false
            menu.minimumWidth = 230
            menu.delegate = self

            let launchAtLoginItem = NSMenuItem(
                title: L10n.launchAtLogin,
                action: #selector(toggleLaunchAtLogin(_:)),
                keyEquivalent: ""
            )
            launchAtLoginItem.target = self
            launchAtLoginItem.state = parent.isLaunchAtLoginEnabled ? .on : .off
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

            activeMenu = menu
            menu.update()
            let menuSize = menu.size
            menu.popUp(
                positioning: nil,
                at: NSPoint(
                    x: sender.bounds.maxX + 8,
                    y: sender.bounds.minY - menuSize.height - 6
                ),
                in: sender
            )
        }

        @objc private func toggleLaunchAtLogin(_ sender: NSMenuItem) {
            parent.onToggleLaunchAtLogin(!parent.isLaunchAtLoginEnabled)
        }

        @objc private func quit(_ sender: NSMenuItem) {
            parent.onQuit()
        }

        func menuDidClose(_ menu: NSMenu) {
            guard menu === activeMenu else {
                return
            }

            activeMenu = nil
            let onMenuClosed = parent.onMenuClosed
            DispatchQueue.main.async {
                onMenuClosed()
            }
        }
    }
}

private struct PortSearchField: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeNSView(context: Context) -> NSSearchField {
        let searchField = NSSearchField()
        searchField.placeholderString = placeholder
        searchField.sendsSearchStringImmediately = true
        searchField.delegate = context.coordinator
        return searchField
    }

    func updateNSView(_ searchField: NSSearchField, context: Context) {
        context.coordinator.text = $text
        searchField.placeholderString = placeholder

        if searchField.stringValue != text {
            searchField.stringValue = text
        }
    }

    final class Coordinator: NSObject, NSSearchFieldDelegate {
        var text: Binding<String>

        init(text: Binding<String>) {
            self.text = text
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let searchField = notification.object as? NSSearchField else {
                return
            }

            text.wrappedValue = searchField.stringValue
        }
    }
}

private struct PortRowView: View {
    let entry: PortEntry
    let isKilling: Bool
    let protectionReason: ProcessProtectionReason?
    let onKill: () -> Void
    @State private var isShowingKillConfirmation = false
    @State private var isShowingProtectionExplanation = false
    @State private var copyFeedbackID: UUID?

    private var classification: PortClassification {
        entry.classification
    }

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 12) {
                ServiceIconView(classification: classification)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(String(entry.port))
                            .font(.system(.title3, design: .monospaced).weight(.semibold))

                        Text(entry.protocolName)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    HStack(spacing: 5) {
                        Text(L10n.localizedProcessName(entry.processName))
                            .font(.subheadline)
                            .lineLimit(1)

                        Text("·")
                            .foregroundStyle(.tertiary)

                        Text(L10n.classificationName(classification.displayName))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .help(L10n.classificationReason(classification.reason))
                    }
                }

                Spacer(minLength: 12)

                VStack(alignment: .trailing, spacing: 4) {
                    Text(L10n.pid(entry.pid))
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)

                    if canOpenInBrowser {
                        Button(action: openInBrowser) {
                            endpointLabel
                        }
                        .buttonStyle(.plain)
                        .help(L10n.openInBrowserHelp(browserURL?.absoluteString ?? ""))
                    } else {
                        endpointLabel
                    }
                }
            }

            Button(action: copyAddress) {
                Image(systemName: copyFeedbackID == nil ? "doc.on.doc" : "checkmark.circle.fill")
                    .foregroundStyle(copyFeedbackID == nil ? Color.secondary : Color.green)
            }
            .buttonStyle(.borderless)
            .help(copyFeedbackID == nil ? L10n.copyAddressHelp(addressToCopy) : L10n.addressCopied)

            if canOpenInBrowser {
                Button(action: openInBrowser) {
                    Image(systemName: "safari")
                }
                .buttonStyle(.borderless)
                .help(L10n.openInBrowserHelp(browserURL?.absoluteString ?? ""))
            }

            Button(role: protectionReason == nil ? .destructive : nil) {
                if protectionReason == nil {
                    isShowingKillConfirmation = true
                } else {
                    isShowingProtectionExplanation = true
                }
            } label: {
                if isKilling {
                    ProgressView()
                        .controlSize(.small)
                } else if protectionReason != nil {
                    Image(systemName: "lock.shield.fill")
                } else {
                    Image(systemName: "xmark.circle.fill")
                }
            }
            .buttonStyle(.borderless)
            .disabled(isKilling)
            .help(
                protectionReason == nil
                    ? L10n.killHelp(processName: entry.processName, pid: entry.pid)
                    : L10n.protectedProcessHelp(processName: entry.processName, pid: entry.pid)
            )
        }
        .padding(.vertical, 4)
        .alert(
            L10n.terminateProcessTitle,
            isPresented: $isShowingKillConfirmation
        ) {
            Button(L10n.cancel, role: .cancel) {}
            Button(L10n.terminate, role: .destructive, action: onKill)
        } message: {
            Text(
                L10n.terminateProcessMessage(
                    processName: entry.processName,
                    pid: entry.pid,
                    port: entry.port
                )
            )
        }
        .alert(
            L10n.protectedProcessTitle,
            isPresented: $isShowingProtectionExplanation
        ) {
            Button(L10n.ok) {}
        } message: {
            if let protectionReason {
                Text(
                    L10n.protectedProcessMessage(
                        processName: entry.processName,
                        pid: entry.pid,
                        reason: protectionReason
                    )
                )
            }
        }
    }

    private var browserURL: URL? {
        classification.isWebServer ? entry.browserURL : nil
    }

    private var canOpenInBrowser: Bool {
        browserURL != nil
    }

    private var addressToCopy: String {
        browserURL?.absoluteString ?? entry.endpoint
    }

    private var endpointLabel: some View {
        Text(entry.endpoint)
            .font(.caption2)
            .foregroundStyle(canOpenInBrowser ? .secondary : .tertiary)
            .lineLimit(1)
    }

    private func copyAddress() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(addressToCopy, forType: .string)

        let feedbackID = UUID()
        withAnimation(.easeInOut(duration: 0.15)) {
            copyFeedbackID = feedbackID
        }

        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.5))
            guard copyFeedbackID == feedbackID else {
                return
            }

            withAnimation(.easeInOut(duration: 0.15)) {
                copyFeedbackID = nil
            }
        }
    }

    private func openInBrowser() {
        guard let url = browserURL else {
            return
        }

        NSWorkspace.shared.open(url)
    }
}

private struct ServiceIconView: View {
    let classification: PortClassification
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Group {
            if let image = brandImage {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .padding(needsContrastBackground ? 2 : 0)
                    .background {
                        if needsContrastBackground {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(.white.opacity(0.92))
                        }
                    }
            } else {
                Image(systemName: fallbackSymbolName)
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 22, height: 22)
        .accessibilityHidden(true)
        .help(L10n.classificationReason(classification.reason))
    }

    private var brandImage: NSImage? {
        if let applicationBundlePath = classification.applicationBundlePath,
           FileManager.default.fileExists(atPath: applicationBundlePath) {
            return NSWorkspace.shared.icon(forFile: applicationBundlePath)
        }

        guard let iconName = classification.iconName else {
            return nil
        }

        let iconURL = AppResources.bundle.url(
            forResource: iconName,
            withExtension: "svg",
            subdirectory: "ServiceIcons"
        ) ?? AppResources.bundle.url(forResource: iconName, withExtension: "svg")

        guard let iconURL else {
            return nil
        }

        return NSImage(contentsOf: iconURL)
    }

    private var fallbackSymbolName: String {
        switch classification.category {
        case .web: "globe"
        case .database: "cylinder"
        case .cache: "memorychip"
        case .messaging: "arrow.left.arrow.right"
        case .container: "shippingbox"
        case .mobile: "iphone"
        case .development: "hammer"
        case .system: "gearshape"
        case .other: "questionmark.circle"
        }
    }

    private var needsContrastBackground: Bool {
        guard colorScheme == .dark, let iconName = classification.iconName else {
            return false
        }

        return ["deno", "gradle", "kafka", "mysql", "nextjs", "openai"]
            .contains(iconName)
    }
}
