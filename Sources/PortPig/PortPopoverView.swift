import AppKit
import SwiftUI
import PortPigCore

private enum FilterScreen {
    case manager
    case editor(SavedPortFilter, isNew: Bool)
}

struct PortPopoverView: View {
    @ObservedObject var viewModel: PortListViewModel
    @ObservedObject var launchAtLogin: LaunchAtLoginController
    @State private var filterScreen: FilterScreen?
    @State private var selectedEntry: PortEntry?
    let onShowAbout: () -> Void
    let onQuit: () -> Void
    let onSettingsMenuClosed: () -> Void

    var body: some View {
        Group {
            if let selectedEntry {
                PortDetailsView(
                    entry: selectedEntry,
                    ownerDescription: viewModel.ownerDescription(for: selectedEntry),
                    protectionReason: viewModel.protectionReason(for: selectedEntry),
                    onBack: { self.selectedEntry = nil }
                )
            } else {
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
                    onShowAbout: onShowAbout,
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
                    },
                    onShowDetails: { selectedEntry = entry }
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
                            PortNumberField(
                                value: $filter.minimumPort,
                                placeholder: L10n.filterMinimumPort
                            )
                            Text("–")
                                .foregroundStyle(.secondary)
                            PortNumberField(
                                value: $filter.maximumPort,
                                placeholder: L10n.filterMaximumPort
                            )
                        }
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
            && isValidPort(filter.minimumPort)
            && isValidPort(filter.maximumPort)
            && portRangeIsOrdered
    }

    private var portRangeIsOrdered: Bool {
        guard let minimum = filter.minimumPort,
              let maximum = filter.maximumPort else {
            return true
        }

        return minimum <= maximum
    }

    private func isValidPort(_ port: Int?) -> Bool {
        port.map { (1...65_535).contains($0) } ?? true
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

private struct PortNumberField: View {
    @Binding var value: Int?
    let placeholder: String

    var body: some View {
        HStack(spacing: 4) {
            TextField(placeholder, text: textBinding)
                .textFieldStyle(.roundedBorder)

            Stepper(value: stepperBinding, in: 0...65_535) {
                Text(placeholder)
            }
            .labelsHidden()
            .controlSize(.small)
        }
    }

    private var textBinding: Binding<String> {
        Binding(
            get: { value.map(String.init) ?? "" },
            set: { text in
                let digits = text.filter { character in
                    character >= "0" && character <= "9"
                }
                value = digits.isEmpty ? nil : Int(digits)
            }
        )
    }

    private var stepperBinding: Binding<Int> {
        Binding(
            get: { min(max(value ?? 0, 0), 65_535) },
            set: { value = $0 == 0 ? nil : $0 }
        )
    }
}

private struct SettingsMenuButton: NSViewRepresentable {
    let isLaunchAtLoginEnabled: Bool
    let onToggleLaunchAtLogin: (Bool) -> Void
    let onShowAbout: () -> Void
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

        @objc private func showAbout(_ sender: NSMenuItem) {
            parent.onShowAbout()
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

private struct PortDetailsView: View {
    let entry: PortEntry
    let ownerDescription: String
    let protectionReason: ProcessProtectionReason?
    let onBack: () -> Void
    @State private var addressCopyFeedbackID: UUID?

    private var classification: PortClassification {
        entry.classification
    }

    private var technologySummary: String {
        let labels = technologyLabels(for: entry, classification: classification)
        return [labels.primary, labels.secondary].compactMap { $0 }.joined(separator: " · ")
    }

    var body: some View {
        VStack(spacing: 0) {
            navigationHeader
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    summary
                    Divider()
                    detailSection(L10n.connectionSection) {
                        detailRow(L10n.addressLabel, value: entry.endpoint, monospaced: true)
                        if let browserURL {
                            detailRow(
                                L10n.browserURLLabel,
                                value: browserURL.absoluteString,
                                monospaced: true
                            )
                        }
                        detailRow(L10n.filterExposure, value: exposureDescription)
                    }
                    Divider()
                    detailSection(L10n.processSection) {
                        detailRow(L10n.pidLabel, value: String(entry.pid), monospaced: true)
                        detailRow(L10n.filterOwnership, value: ownerDescription)
                        detailRow(L10n.filterTermination, value: terminationDescription)
                        if let protectionReason {
                            Text(L10n.protectionReason(protectionReason))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.leading, 116)
                        }
                        detailRow(
                            L10n.executableLabel,
                            value: entry.executablePath ?? L10n.unknownValue,
                            monospaced: entry.executablePath != nil
                        )
                        detailRow(
                            L10n.parentPIDLabel,
                            value: entry.parentPID.map(String.init) ?? L10n.unknownValue,
                            monospaced: entry.parentPID != nil
                        )
                        if !entry.ancestorExecutablePaths.isEmpty {
                            DisclosureGroup(L10n.launchChainLabel) {
                                VStack(alignment: .leading, spacing: 6) {
                                    ForEach(
                                        Array(entry.ancestorExecutablePaths.enumerated()),
                                        id: \.offset
                                    ) { _, path in
                                        Text(path)
                                            .font(.system(.caption, design: .monospaced))
                                            .textSelection(.enabled)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                }
                                .padding(.top, 6)
                                .padding(.leading, 12)
                            }
                            .font(.caption)
                            .padding(.top, 4)
                        }
                    }
                    Divider()
                    detailSection(L10n.classificationSection) {
                        detailRow(
                            L10n.serviceLabel,
                            value: L10n.classificationName(classification.displayName)
                        )
                        detailRow(
                            L10n.detectedFromLabel,
                            value: L10n.classificationReason(classification.reason)
                        )
                    }
                }
                .padding(.horizontal, 16)
            }

            Divider()
            actions
        }
    }

    private var navigationHeader: some View {
        ZStack {
            Text(L10n.portDetailsTitle)
                .font(.headline)

            HStack {
                Button(action: onBack) {
                    Label(L10n.back, systemImage: "chevron.left")
                }
                .buttonStyle(.borderless)

                Spacer()
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private var summary: some View {
        HStack(spacing: 12) {
            ServiceIconView(classification: classification, size: 32)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(String(entry.port))
                        .font(.system(.title2, design: .monospaced).weight(.semibold))
                    Text(entry.protocolName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(technologySummary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }

            Spacer()

            Text(exposureDescription)
                .font(.caption2)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(.quaternary, in: Capsule())
        }
        .padding(.vertical, 14)
    }

    private var actions: some View {
        HStack(spacing: 8) {
            Button(action: copyAddress) {
                Label(
                    addressCopyFeedbackID == nil ? L10n.copyAddress : L10n.addressCopied,
                    systemImage: addressCopyFeedbackID == nil
                        ? "doc.on.doc"
                        : "checkmark.circle.fill"
                )
            }
            .buttonStyle(.bordered)

            Button(action: revealExecutable) {
                Label(L10n.revealExecutable, systemImage: "folder")
            }
            .buttonStyle(.bordered)
            .disabled(!canRevealExecutable)

            Spacer(minLength: 0)

            if let browserURL {
                Button {
                    NSWorkspace.shared.open(browserURL)
                } label: {
                    Label(L10n.openInBrowser, systemImage: "safari")
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .controlSize(.small)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private func detailSection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title.uppercased())
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
            content()
        }
        .padding(.vertical, 12)
    }

    private func detailRow(_ label: String, value: String, monospaced: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 104, alignment: .leading)

            Text(value)
                .font(monospaced ? .system(.caption, design: .monospaced) : .caption)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.caption)
    }

    private var browserURL: URL? {
        classification.isWebServer ? entry.browserURL : nil
    }

    private var exposureDescription: String {
        L10n.exposureName(isLocalOnly ? .localOnly : .networkVisible)
    }

    private var isLocalOnly: Bool {
        let endpoint = entry.endpoint.lowercased()
        return endpoint.hasPrefix("127.0.0.1:")
            || endpoint.hasPrefix("[::1]:")
            || endpoint.hasPrefix("localhost:")
    }

    private var terminationDescription: String {
        protectionReason == nil ? L10n.terminationAllowed : L10n.terminationProtected
    }

    private var canRevealExecutable: Bool {
        guard let executablePath = entry.executablePath else {
            return false
        }

        return FileManager.default.fileExists(atPath: executablePath)
    }

    private var addressToCopy: String {
        browserURL?.absoluteString ?? entry.endpoint
    }

    private func copyAddress() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(addressToCopy, forType: .string)

        let feedbackID = UUID()
        withAnimation(.easeInOut(duration: 0.15)) {
            addressCopyFeedbackID = feedbackID
        }

        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.5))
            guard addressCopyFeedbackID == feedbackID else {
                return
            }

            withAnimation(.easeInOut(duration: 0.15)) {
                addressCopyFeedbackID = nil
            }
        }
    }

    private func revealExecutable() {
        guard let executablePath = entry.executablePath else {
            return
        }

        NSWorkspace.shared.activateFileViewerSelecting([
            URL(fileURLWithPath: executablePath)
        ])
    }
}

private struct PortRowView: View {
    let entry: PortEntry
    let isKilling: Bool
    let protectionReason: ProcessProtectionReason?
    let onKill: () -> Void
    let onShowDetails: () -> Void
    @State private var isShowingKillConfirmation = false
    @State private var isShowingProtectionExplanation = false
    @State private var addressCopyFeedbackID: UUID?

    private var classification: PortClassification {
        entry.classification
    }

    private var labels: (primary: String, secondary: String?) {
        technologyLabels(for: entry, classification: classification)
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
                        Text(labels.primary)
                            .font(.subheadline)
                            .lineLimit(1)

                        if let secondary = labels.secondary {
                            Text("·")
                                .foregroundStyle(.tertiary)

                            Text(secondary)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .help(L10n.classificationReason(classification.reason))
                        }
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
                Image(
                    systemName: addressCopyFeedbackID == nil
                        ? "doc.on.doc"
                        : "checkmark.circle.fill"
                )
                    .foregroundStyle(addressCopyFeedbackID == nil ? Color.secondary : Color.green)
            }
            .buttonStyle(.borderless)
            .help(
                addressCopyFeedbackID == nil
                    ? L10n.copyAddressHelp(addressToCopy)
                    : L10n.addressCopied
            )
            .accessibilityLabel(
                addressCopyFeedbackID == nil
                    ? L10n.copyAddressHelp(addressToCopy)
                    : L10n.addressCopied
            )

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

            Button(action: onShowDetails) {
                Image(systemName: "info.circle")
            }
            .buttonStyle(.borderless)
            .help(L10n.showPortDetails(entry.port))
            .accessibilityLabel(L10n.showPortDetails(entry.port))
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
            addressCopyFeedbackID = feedbackID
        }

        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.5))
            guard addressCopyFeedbackID == feedbackID else {
                return
            }

            withAnimation(.easeInOut(duration: 0.15)) {
                addressCopyFeedbackID = nil
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

private func technologyLabels(
    for entry: PortEntry,
    classification: PortClassification
) -> (primary: String, secondary: String?) {
    if entry.webProjectFramework != nil {
        return (
            L10n.classificationName(classification.displayName),
            classification.secondaryDisplayName.map(L10n.classificationName)
        )
    }

    return (
        L10n.localizedProcessName(entry.processName),
        L10n.classificationName(classification.displayName)
    )
}

private struct ServiceIconView: View {
    let classification: PortClassification
    var size: CGFloat = 22
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
        .frame(width: size, height: size)
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
        case .other: "cable.connector"
        }
    }

    private var needsContrastBackground: Bool {
        guard colorScheme == .dark, let iconName = classification.iconName else {
            return false
        }

        return ["deno", "gradle", "kafka", "mysql", "nextjs", "openai", "remix"]
            .contains(iconName)
    }
}
