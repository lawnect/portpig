import Darwin
import Foundation
import PortPigCore

struct PortSummary: Equatable {
    let total: Int
    let development: Int
    let appsAndHelpers: Int
    let system: Int
}

@MainActor
final class PortListViewModel: ObservableObject {
    @Published private var allPorts: [PortEntry] = []
    @Published private(set) var isLoading = false
    @Published private(set) var killingPIDs = Set<Int32>()
    @Published private(set) var savedFilters: [SavedPortFilter]
    @Published private(set) var selectedFilterID: UUID?
    @Published var portSearchText = ""
    @Published var errorMessage: String?

    private let scanner: LsofPortScanner
    private let killer: ProcessPortKiller
    private var lastUpdated: Date?
    private var isRefreshing = false
    private let currentUserID: UInt32
    private let currentProcessID: Int32
    private let userDefaults: UserDefaults

    private static let savedFiltersKey = "savedPortFilters.v1"
    private static let selectedFilterKey = "selectedPortFilterID.v1"
    private static let maximumVisibleSavedFilters = 2

    init(
        scanner: LsofPortScanner = LsofPortScanner(),
        killer: ProcessPortKiller = ProcessPortKiller(),
        currentUserID: UInt32 = getuid(),
        currentProcessID: Int32 = getpid(),
        userDefaults: UserDefaults = .standard
    ) {
        self.scanner = scanner
        self.killer = killer
        self.currentUserID = currentUserID
        self.currentProcessID = currentProcessID
        self.userDefaults = userDefaults

        if let data = userDefaults.data(forKey: Self.savedFiltersKey),
           let filters = try? JSONDecoder().decode([SavedPortFilter].self, from: data) {
            savedFilters = filters
        } else {
            savedFilters = [.development(name: L10n.string("filter.development"))]
        }

        if let selectedIDValue = userDefaults.string(forKey: Self.selectedFilterKey),
           let selectedID = UUID(uuidString: selectedIDValue),
           savedFilters.contains(where: { $0.id == selectedID }) {
            selectedFilterID = selectedID
        } else {
            selectedFilterID = nil
        }
    }

    var ports: [PortEntry] {
        let filteredPorts = selectedFilter.map { filter in
            allPorts.filter { entry in
                filter.matches(
                    entry,
                    currentUserID: currentUserID,
                    currentProcessID: currentProcessID
                )
            }
        } ?? allPorts

        let searchText = normalizedPortSearchText

        guard !searchText.isEmpty else {
            return filteredPorts
        }

        return filteredPorts.filter { entry in
            matchesSearch(entry, query: searchText)
        }
    }

    var visibleSavedFilters: [SavedPortFilter] {
        var filters = savedFilters.filter(\.isPinned)

        if let selectedFilter,
           !filters.contains(where: { $0.id == selectedFilter.id }) {
            if filters.count >= Self.maximumVisibleSavedFilters {
                filters.removeLast()
            }
            filters.append(selectedFilter)
        }

        return Array(filters.prefix(Self.maximumVisibleSavedFilters))
    }

    var selectedFilter: SavedPortFilter? {
        guard let selectedFilterID else {
            return nil
        }

        return savedFilters.first(where: { $0.id == selectedFilterID })
    }

    var isAllFilterSelected: Bool {
        selectedFilterID == nil
    }

    var portSummary: PortSummary? {
        guard lastUpdated != nil else {
            return nil
        }

        return PortSummary(
            total: allPorts.count,
            development: allPorts.count(where: { $0.classification.isDevelopmentRelated }),
            appsAndHelpers: allPorts.count(where: { $0.classification.category == .other }),
            system: allPorts.count(where: { $0.classification.category == .system })
        )
    }

    var footerStatus: String {
        guard let lastUpdated else {
            return L10n.notRefreshed
        }

        let updatedText = L10n.updated(
            at: lastUpdated.formatted(date: .omitted, time: .standard)
        )
        let detail: String?

        if let selectedFilter {
            let hiddenCount = max(allPorts.count - ports.count, 0)

            if !normalizedPortSearchText.isEmpty {
                detail = L10n.format(
                    "status.saved_filter_matches",
                    fallback: "%@ · %lld matches",
                    selectedFilter.name,
                    Int64(ports.count)
                )
            } else if hiddenCount == 0 {
                detail = L10n.format(
                    "status.saved_filter_count",
                    fallback: "%@ · %lld ports",
                    selectedFilter.name,
                    Int64(ports.count)
                )
            } else {
                detail = L10n.format(
                    "status.saved_filter_hidden",
                    fallback: "%@ · %lld shown · %lld hidden",
                    selectedFilter.name,
                    Int64(ports.count),
                    Int64(hiddenCount)
                )
            }
        } else if !normalizedPortSearchText.isEmpty {
            detail = L10n.format("status.all_matches", Int64(ports.count))
        } else {
            detail = nil
        }

        guard let detail else {
            return updatedText
        }

        return "\(updatedText) · \(detail)"
    }

    var emptyStateMessage: String {
        if !normalizedPortSearchText.isEmpty {
            return L10n.noMatchingPorts
        }

        return selectedFilter == nil ? L10n.noListeningPorts : L10n.noFilterMatches
    }

    private var normalizedPortSearchText: String {
        portSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func matchesSearch(_ entry: PortEntry, query: String) -> Bool {
        let classification = entry.classification
        var searchableValues = [
            String(entry.port),
            String(entry.pid),
            entry.processName,
            L10n.localizedProcessName(entry.processName),
            entry.protocolName,
            entry.endpoint,
            classification.displayName,
            L10n.classificationName(classification.displayName),
            classification.secondaryDisplayName ?? "",
            classification.reason,
            L10n.classificationReason(classification.reason)
        ]

        if let parentPID = entry.parentPID {
            searchableValues.append(String(parentPID))
        }

        if let userID = entry.userID {
            searchableValues.append(String(userID))
        }

        if let executablePath = entry.executablePath {
            searchableValues.append(executablePath)
        }

        searchableValues.append(contentsOf: entry.ancestorExecutablePaths)
        let searchableText = searchableValues.joined(separator: "\n")
        let terms = query.split(whereSeparator: \.isWhitespace)

        return terms.allSatisfy { term in
            searchableText.localizedCaseInsensitiveContains(String(term))
        }
    }

    func refresh(showsActivity: Bool = true) async {
        guard !isRefreshing else {
            return
        }

        isRefreshing = true

        if showsActivity {
            isLoading = true
        }

        errorMessage = nil
        defer {
            isRefreshing = false

            if showsActivity {
                isLoading = false
            }
        }

        do {
            allPorts = try await scanner.listeningPorts()

            if let selectedFilterID,
               !savedFilters.contains(where: { $0.id == selectedFilterID }) {
                selectAllFilter()
            }

            lastUpdated = Date()
        } catch {
            errorMessage = error.localizedDescription
        }

    }

    func selectAllFilter() {
        selectedFilterID = nil
        userDefaults.removeObject(forKey: Self.selectedFilterKey)
    }

    func selectFilter(id: UUID) {
        guard savedFilters.contains(where: { $0.id == id }) else {
            return
        }

        selectedFilterID = id
        userDefaults.set(id.uuidString, forKey: Self.selectedFilterKey)
    }

    func saveFilter(_ filter: SavedPortFilter) {
        var filter = filter
        filter.name = filter.name.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !filter.name.isEmpty else {
            return
        }

        if let index = savedFilters.firstIndex(where: { $0.id == filter.id }) {
            savedFilters[index] = filter
        } else {
            savedFilters.append(filter)
        }

        enforcePinnedFilterLimit(preferredFilterID: filter.id)
        persistFilters()
        selectFilter(id: filter.id)
    }

    func deleteFilter(id: UUID) {
        savedFilters.removeAll(where: { $0.id == id })

        if selectedFilterID == id {
            selectAllFilter()
        }

        persistFilters()
    }

    func setFilterPinned(id: UUID, isPinned: Bool) {
        guard let index = savedFilters.firstIndex(where: { $0.id == id }) else {
            return
        }

        savedFilters[index].isPinned = isPinned

        if isPinned {
            enforcePinnedFilterLimit(preferredFilterID: id)
        }

        persistFilters()
    }

    private func enforcePinnedFilterLimit(preferredFilterID: UUID) {
        let pinnedIDs = savedFilters.filter(\.isPinned).map(\.id)
        guard pinnedIDs.count > Self.maximumVisibleSavedFilters else {
            return
        }

        let idsToKeep = [preferredFilterID] + pinnedIDs.filter { $0 != preferredFilterID }
        let keptIDs = Set(idsToKeep.prefix(Self.maximumVisibleSavedFilters))

        for index in savedFilters.indices where savedFilters[index].isPinned {
            savedFilters[index].isPinned = keptIDs.contains(savedFilters[index].id)
        }
    }

    private func persistFilters() {
        guard let data = try? JSONEncoder().encode(savedFilters) else {
            return
        }

        userDefaults.set(data, forKey: Self.savedFiltersKey)
    }

    func protectionReason(for entry: PortEntry) -> ProcessProtectionReason? {
        ProcessTerminationPolicy.protectionReason(
            for: entry,
            currentUserID: currentUserID,
            currentProcessID: currentProcessID
        )
    }

    func ownerDescription(for entry: PortEntry) -> String {
        guard let userID = entry.userID else {
            return L10n.unknownValue
        }

        let owner: String
        if userID == currentUserID {
            owner = L10n.currentUser
        } else if userID == 0 {
            owner = L10n.administrator
        } else {
            owner = L10n.otherUser
        }

        return "\(owner) · \(L10n.uid(userID))"
    }

    func kill(_ entry: PortEntry) async {
        guard protectionReason(for: entry) == nil else {
            return
        }

        killingPIDs.insert(entry.pid)
        errorMessage = nil

        do {
            try await killer.kill(pid: entry.pid)
            try? await Task.sleep(for: .milliseconds(200))
        } catch {
            errorMessage = error.localizedDescription
        }

        killingPIDs.remove(entry.pid)
        await refresh()
    }
}
