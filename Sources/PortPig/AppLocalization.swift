import Foundation
import PortPigCore

enum AppResources {
    static var bundle: Bundle {
        #if SWIFT_PACKAGE
        Bundle.module
        #else
        Bundle.main
        #endif
    }
}

enum L10n {
    static var appName: String { string("app.name") }
    static var refresh: String { string("action.refresh") }
    static var settings: String { string("action.settings") }
    static var cancel: String { string("action.cancel") }
    static var terminate: String { string("action.terminate") }
    static var ok: String { string("action.ok") }
    static var filter: String { string("label.filter") }
    static var port: String { string("label.port") }
    static var searchPlaceholder: String { string("search.placeholder") }
    static var clear: String { string("action.clear") }
    static var lookingForPorts: String { string("status.looking_for_ports") }
    static var quit: String { string("action.quit") }
    static var refreshing: String { string("status.refreshing") }
    static var notRefreshed: String { string("status.not_refreshed") }
    static var noMatchingPorts: String { string("empty.no_matches") }
    static var noWebPorts: String { string("empty.no_web_ports") }
    static var noDevelopmentPorts: String { string("empty.no_development_ports") }
    static var noListeningPorts: String { string("empty.no_listening_ports") }
    static var noFilterMatches: String {
        string("empty.no_filter_matches", fallback: "No ports match this filter")
    }
    static var launchAtLogin: String { string("setting.launch_at_login") }
    static var launchAtLoginRequiresApproval: String {
        string("status.launch_at_login_requires_approval")
    }
    static var terminateProcessTitle: String { string("confirmation.kill.title") }
    static var protectedProcessTitle: String { string("protected.title") }

    static var allFilter: String { string("filter.all") }
    static var filters: String { string("filters.title", fallback: "Filters") }
    static var newFilter: String { string("filters.new", fallback: "New Filter") }
    static var editFilter: String { string("filters.edit", fallback: "Edit Filter") }
    static var save: String { string("action.save", fallback: "Save") }
    static var delete: String { string("action.delete", fallback: "Delete") }
    static var back: String { string("action.back", fallback: "Back") }
    static var pin: String { string("action.pin", fallback: "Pin") }
    static var unpin: String { string("action.unpin", fallback: "Unpin") }
    static var filterNameLabel: String { string("filters.field.name", fallback: "Name") }
    static var filterCategories: String { string("filters.field.categories", fallback: "Categories") }
    static var filterAnyCategories: String {
        string("filters.categories.any", fallback: "Any category")
    }
    static var filterOwnership: String { string("filters.field.ownership", fallback: "Owner") }
    static var filterTermination: String { string("filters.field.termination", fallback: "Termination") }
    static var filterExposure: String { string("filters.field.exposure", fallback: "Exposure") }
    static var filterProcessQuery: String { string("filters.field.process", fallback: "Process or app contains") }
    static var filterPortRange: String { string("filters.field.port_range", fallback: "Port range") }
    static var filterMinimumPort: String { string("filters.field.minimum_port", fallback: "From") }
    static var filterMaximumPort: String { string("filters.field.maximum_port", fallback: "To") }
    static var filterPinned: String { string("filters.field.pinned", fallback: "Show in the top bar") }
    static var filterPinLimit: String {
        string("filters.pin_limit", fallback: "Up to two saved filters appear in the top bar.")
    }
    static var noSavedFilters: String {
        string("filters.empty", fallback: "No saved filters")
    }
    static var deleteFilterTitle: String {
        string("filters.delete.title", fallback: "Delete Filter?")
    }

    static func deleteFilterMessage(_ name: String) -> String {
        format("filters.delete.message", fallback: "Delete “%@”?", name)
    }

    static func categoryName(_ category: PortCategory) -> String {
        string("filters.category.\(category.rawValue)", fallback: category.rawValue.capitalized)
    }

    static func ownershipName(_ scope: PortOwnershipScope) -> String {
        string("filters.ownership.\(scope.rawValue)", fallback: scope.rawValue)
    }

    static func terminationName(_ scope: PortTerminationScope) -> String {
        string("filters.termination.\(scope.rawValue)", fallback: scope.rawValue)
    }

    static func exposureName(_ scope: PortExposureScope) -> String {
        string("filters.exposure.\(scope.rawValue)", fallback: scope.rawValue)
    }

    static func updated(at time: String) -> String {
        format("status.updated", time)
    }

    static func pid(_ pid: Int32) -> String {
        format("process.pid", Int64(pid))
    }

    static func killHelp(processName: String, pid: Int32) -> String {
        format("action.kill_process", localizedProcessName(processName), Int64(pid))
    }

    static func copyAddressHelp(_ address: String) -> String {
        format("action.copy_address", fallback: "Copy %@", address)
    }

    static func openInBrowserHelp(_ url: String) -> String {
        format("action.open_in_browser", fallback: "Open %@ in browser", url)
    }

    static var addressCopied: String {
        string("status.address_copied", fallback: "Address copied")
    }

    static func protectedProcessHelp(processName: String, pid: Int32) -> String {
        format("action.protected_process", localizedProcessName(processName), Int64(pid))
    }

    static func protectedProcessMessage(
        processName: String,
        pid: Int32,
        reason: ProcessProtectionReason
    ) -> String {
        format(
            "protected.message",
            localizedProcessName(processName),
            Int64(pid),
            protectionReason(reason)
        )
    }

    static func protectionReason(_ reason: ProcessProtectionReason) -> String {
        switch reason {
        case .coreSystemProcess: string("protected.reason.core_system")
        case .currentApplication: string("protected.reason.current_application")
        case .macOSService: string("protected.reason.macos_service")
        case .unknownOwner: string("protected.reason.unknown_owner")
        case .administratorOwned: string("protected.reason.administrator_owned")
        case .anotherUser: string("protected.reason.another_user")
        }
    }

    static func launchAtLoginError(_ message: String) -> String {
        format("error.launch_at_login", message)
    }

    static func terminateProcessMessage(
        processName: String,
        pid: Int32,
        port: Int
    ) -> String {
        format(
            "confirmation.kill.message",
            localizedProcessName(processName),
            Int64(pid),
            Int64(port)
        )
    }

    static func localizedProcessName(_ processName: String) -> String {
        processName == "Unknown" ? string("process.unknown") : processName
    }

    static func classificationName(_ name: String) -> String {
        string("classification.name.\(name)", fallback: name)
    }

    static func classificationReason(_ reason: String) -> String {
        let dynamicReasons = [
            ("Recognized process: ", "classification.reason.recognized_process"),
            ("Recognized runtime on known web port: ", "classification.reason.runtime_known_web_port"),
            ("Recognized runtime on common web port: ", "classification.reason.runtime_common_web_port"),
            ("Known service port: ", "classification.reason.known_service_port"),
            ("Recognized development process: ", "classification.reason.recognized_development_process"),
            ("Rust target executable: ", "classification.reason.rust_target_executable"),
            ("Executable: ", "classification.reason.executable")
        ]

        for (prefix, key) in dynamicReasons where reason.hasPrefix(prefix) {
            return format(key, String(reason.dropFirst(prefix.count)))
        }

        return string("classification.reason.\(reason)", fallback: reason)
    }

    static func string(_ key: String, fallback: String? = nil) -> String {
        AppResources.bundle.localizedString(forKey: key, value: fallback, table: nil)
    }

    static func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(
            format: string(key),
            locale: Locale.current,
            arguments: arguments
        )
    }

    static func format(
        _ key: String,
        fallback: String,
        _ arguments: CVarArg...
    ) -> String {
        String(
            format: string(key, fallback: fallback),
            locale: Locale.current,
            arguments: arguments
        )
    }
}
