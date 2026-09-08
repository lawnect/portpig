import Foundation

public enum DevelopmentPortFilter {
    private struct Service {
        let category: PortCategory
        let name: String
        let iconName: String?

        init(category: PortCategory, name: String, iconName: String? = nil) {
            self.category = category
            self.name = name
            self.iconName = iconName
        }
    }

    private static let excludedProcessNames: Set<String> = [
        "airplayxpchelper", "apsd", "assistantd", "bluetoothd", "callservicesd",
        "controlcenter", "coreduetd", "coreservicesuiagent", "distnoted",
        "identityservicesd", "imagent", "ipnextension", "locationd",
        "mdnsresponder", "nearbyd", "rapportd", "remoted", "sharingd",
        "siriactionsd", "softwareupdated", "systemuiserver", "trustd",
        "universalaccessd", "usernoted"
    ]

    private static let knownServices: [Int: Service] = [
        80: Service(category: .web, name: "HTTP"),
        443: Service(category: .web, name: "HTTPS"),
        2375: Service(category: .container, name: "Docker", iconName: "docker"),
        2376: Service(category: .container, name: "Docker TLS", iconName: "docker"),
        3000: Service(category: .web, name: "Web server"),
        3001: Service(category: .web, name: "Web server"),
        3306: Service(category: .database, name: "MySQL", iconName: "mysql"),
        3333: Service(category: .web, name: "Web server"),
        4000: Service(category: .web, name: "Web server"),
        4200: Service(category: .web, name: "Web server"),
        4321: Service(category: .web, name: "Web server"),
        4369: Service(category: .development, name: "Erlang Port Mapper", iconName: "erlang"),
        5000: Service(category: .web, name: "Web server"),
        5001: Service(category: .web, name: "Web server"),
        5037: Service(category: .mobile, name: "Android Debug Bridge", iconName: "android"),
        5173: Service(category: .web, name: "Web server"),
        5174: Service(category: .web, name: "Web server"),
        5432: Service(category: .database, name: "PostgreSQL", iconName: "postgresql"),
        5601: Service(category: .development, name: "Kibana", iconName: "kibana"),
        5672: Service(category: .messaging, name: "RabbitMQ", iconName: "rabbitmq"),
        5984: Service(category: .database, name: "CouchDB", iconName: "couchdb"),
        6379: Service(category: .cache, name: "Redis", iconName: "redis"),
        6380: Service(category: .cache, name: "Redis", iconName: "redis"),
        7000: Service(category: .development, name: "Development service"),
        8000: Service(category: .web, name: "Web server"),
        8001: Service(category: .web, name: "Web server"),
        8080: Service(category: .web, name: "HTTP alternate"),
        8081: Service(category: .web, name: "HTTP alternate"),
        8443: Service(category: .web, name: "HTTPS alternate"),
        8888: Service(category: .web, name: "Web server"),
        9000: Service(category: .web, name: "Development server"),
        9092: Service(category: .messaging, name: "Kafka", iconName: "kafka"),
        9200: Service(category: .database, name: "Elasticsearch", iconName: "elasticsearch"),
        9300: Service(category: .database, name: "Elasticsearch transport", iconName: "elasticsearch"),
        11211: Service(category: .cache, name: "Memcached", iconName: "memcached"),
        15672: Service(category: .messaging, name: "RabbitMQ management", iconName: "rabbitmq"),
        27017: Service(category: .database, name: "MongoDB", iconName: "mongodb"),
        27018: Service(category: .database, name: "MongoDB", iconName: "mongodb"),
        27019: Service(category: .database, name: "MongoDB", iconName: "mongodb")
    ]

    private static let candidateWebPortRanges: [ClosedRange<Int>] = [
        3000...3999, 4200...4299, 5000...5001, 5173...5179, 8000...8999
    ]

    private static let candidateDevelopmentPortRanges: [ClosedRange<Int>] = [
        3000...10999
    ]

    public static func classify(_ entry: PortEntry) -> PortClassification {
        let processName = normalizedProcessName(entry.processName)

        if let applicationService = applicationService(entry, processName: processName) {
            return applicationService
        }

        if excludedProcessNames.contains(processName) {
            return PortClassification(
                category: .system,
                displayName: "macOS service",
                reason: "Known macOS background process"
            )
        }

        if let toolingHelper = toolingHelperClassification(entry) {
            return toolingHelper
        }

        if isSystemExecutable(entry.executablePath) {
            return PortClassification(
                category: .system,
                displayName: "macOS service",
                reason: "Executable is part of macOS"
            )
        }

        let namedProcessService = service(forProcessName: processName)

        if isLikelyPhoenix(entry, processName: processName) {
            return PortClassification(
                category: .web,
                displayName: "Phoenix / Elixir",
                reason: "BEAM runtime listening on a common web port",
                iconName: "phoenix"
            )
        }

        // A process name is stronger evidence than a conventional port. For example,
        // PostgreSQL listening on 8080 is still a database, not a web server.
        if let service = namedProcessService,
           service.category != .development,
           service.category != .web {
            return PortClassification(
                category: service.category,
                displayName: service.name,
                reason: classificationReason(for: entry, fallback: "Recognized process: \(entry.processName)"),
                iconName: service.iconName
            )
        }

        if let webProjectFramework = entry.webProjectFramework {
            let service = service(for: webProjectFramework)
            return PortClassification(
                category: service.category,
                displayName: service.name,
                secondaryDisplayName: secondaryDisplayName(
                    for: entry,
                    primaryService: service
                ),
                reason: "Recognized project dependency: \(service.name)",
                iconName: service.iconName
            )
        }

        if let service = namedProcessService, service.category == .web {
            return PortClassification(
                category: service.category,
                displayName: service.name,
                reason: classificationReason(for: entry, fallback: "Recognized process: \(entry.processName)"),
                iconName: service.iconName
            )
        }

        if let webDevelopmentTool = entry.webDevelopmentTool {
            let service = service(for: webDevelopmentTool)
            return PortClassification(
                category: service.category,
                displayName: service.name,
                reason: "Recognized development command: \(service.name)",
                iconName: service.iconName
            )
        }

        let processService = namedProcessService ?? serviceFromExecutionContext(entry)

        if let processService,
           processService.category == .development,
           isCandidateWebPort(entry.port) {
            return PortClassification(
                category: .web,
                displayName: webServerName(for: processService),
                reason: classificationReason(
                    for: entry,
                    fallback: "Recognized runtime on common web port: \(entry.port)"
                ),
                iconName: processService.iconName
            )
        }

        if let service = knownServices[entry.port] {
            return PortClassification(
                category: service.category,
                displayName: service.name,
                reason: "Known service port: \(entry.port)",
                iconName: service.iconName
            )
        }

        if let service = processService {
            return PortClassification(
                category: service.category,
                displayName: service.name,
                reason: classificationReason(
                    for: entry,
                    fallback: "Recognized development process: \(entry.processName)"
                ),
                iconName: service.iconName
            )
        }

        if isBundledApplicationHelper(entry.executablePath) {
            return PortClassification(
                category: .other,
                displayName: "App helper",
                reason: "Listener belongs to a bundled macOS application",
                applicationBundlePath: applicationBundlePath(in: entry.executablePath)
            )
        }

        if let userID = entry.userID, userID < 500 {
            return PortClassification(
                category: .other,
                displayName: "Background service",
                reason: "Listener is owned by a system service account"
            )
        }

        if candidateWebPortRanges.contains(where: { $0.contains(entry.port) }) {
            return PortClassification(
                category: .web,
                displayName: "Possible web server",
                reason: "Common local web port range"
            )
        }

        if candidateDevelopmentPortRanges.contains(where: { $0.contains(entry.port) }) {
            return PortClassification(
                category: .development,
                displayName: "Possible dev service",
                reason: "Common development port range"
            )
        }

        return PortClassification(
            category: .other,
            displayName: "Other service",
            reason: "No known development signal"
        )
    }

    public static func includes(_ entry: PortEntry) -> Bool {
        classify(entry).isDevelopmentRelated
    }

    public static func includesWebServer(_ entry: PortEntry) -> Bool {
        classify(entry).isWebServer
    }

    private static func normalizedProcessName(_ processName: String) -> String {
        URL(fileURLWithPath: processName).lastPathComponent.lowercased()
    }

    private static func isCandidateWebPort(_ port: Int) -> Bool {
        knownServices[port]?.category == .web
            || candidateWebPortRanges.contains(where: { $0.contains(port) })
    }

    private static func isLikelyPhoenix(_ entry: PortEntry, processName: String) -> Bool {
        guard isCandidateWebPort(entry.port) else {
            return false
        }

        if ["elixir", "iex", "mix"].contains(processName) {
            return true
        }

        guard processName == "beam.smp" else {
            return false
        }

        if entry.port == 4000 {
            return true
        }

        let ancestorNames = entry.ancestorExecutablePaths.map(normalizedProcessName)
        return ancestorNames.contains(where: { ["elixir", "iex", "mix"].contains($0) })
    }

    private static func serviceFromExecutionContext(_ entry: PortEntry) -> Service? {
        let executablePath = entry.executablePath?.lowercased() ?? ""
        let ancestorPaths = entry.ancestorExecutablePaths.map { $0.lowercased() }
        let ancestorNames = ancestorPaths.map(normalizedProcessName)

        if executablePath.contains("/target/debug/")
            || executablePath.contains("/target/release/")
            || ancestorNames.contains("cargo") {
            return Service(category: .development, name: "Rust application", iconName: "rust")
        }

        if executablePath.contains("/go-build/") || ancestorNames.contains("go") {
            return Service(category: .development, name: "Go application", iconName: "go")
        }

        if executablePath.contains("/.build/")
            && ancestorNames.contains(where: { ["swift", "swift-run", "swift-build"].contains($0) }) {
            return Service(category: .development, name: "Swift application", iconName: "swift")
        }

        if executablePath.contains("/node_modules/") {
            return Service(category: .development, name: "Node.js application", iconName: "node")
        }

        if executablePath.contains("/.venv/")
            || executablePath.contains("/venv/")
            || executablePath.contains("/virtualenvs/") {
            return Service(category: .development, name: "Python application", iconName: "python")
        }

        return nil
    }

    private static func applicationService(
        _ entry: PortEntry,
        processName: String
    ) -> PortClassification? {
        let paths = executionPaths(for: entry)

        if processName == "ipnextension",
           let bundlePath = applicationBundlePath(matching: "tailscale.app", in: paths) {
            return PortClassification(
                category: .other,
                displayName: "Tailscale Network Extension",
                reason: "Private network service managed by Tailscale",
                applicationBundlePath: bundlePath
            )
        }

        if processName == "zed",
           let bundlePath = applicationBundlePath(matching: "zed.app", in: paths) {
            return PortClassification(
                category: .other,
                displayName: "Zed Local Service",
                reason: "Local service managed by the Zed editor",
                applicationBundlePath: bundlePath
            )
        }

        return nil
    }

    private static func toolingHelperClassification(_ entry: PortEntry) -> PortClassification? {
        let executablePath = entry.executablePath?.lowercased() ?? ""
        let paths = executionPaths(for: entry)
        let normalizedPaths = paths.map { $0.lowercased() }

        if executablePath.contains("/dia.app/contents/resources/agent-server-resources/"),
           let bundlePath = applicationBundlePath(matching: "dia.app", in: paths) {
            return PortClassification(
                category: .other,
                displayName: "Dia AI Agent",
                reason: "Local AI agent managed by the Dia browser",
                applicationBundlePath: bundlePath
            )
        }

        if executablePath.contains("/.local/share/uv/tools/serena-agent/") {
            if normalizedPaths.contains(where: { $0.contains("/codex-acp/") }) {
                return PortClassification(
                    category: .other,
                    displayName: "Serena MCP · Codex",
                    reason: "Serena MCP server launched by Codex",
                    iconName: "openai"
                )
            }

            if let bundlePath = applicationBundlePath(matching: "zed.app", in: paths) {
                return PortClassification(
                    category: .other,
                    displayName: "Serena MCP · Zed",
                    reason: "Serena MCP server launched by Zed",
                    applicationBundlePath: bundlePath
                )
            }

            return PortClassification(
                category: .other,
                displayName: "Serena MCP Server",
                reason: "Local coding-assistant context server"
            )
        }

        if executablePath.contains("/figmaagent.app/contents/"),
           let bundlePath = applicationBundlePath(in: entry.executablePath) {
            return PortClassification(
                category: .other,
                displayName: "Figma Agent",
                reason: "Local helper managed by Figma",
                applicationBundlePath: bundlePath
            )
        }

        if normalizedPaths.contains(where: { $0.contains("/codex-acp/") }) {
            return PortClassification(
                category: .other,
                displayName: "Codex ACP Agent",
                reason: "Codex agent connected to an editor",
                iconName: "openai"
            )
        }

        if normalizedPaths.contains(where: { $0.contains("/application support/zed/external_agents/") }) {
            return PortClassification(
                category: .other,
                displayName: "Zed External Agent",
                reason: "External coding agent managed by Zed",
                applicationBundlePath: applicationBundlePath(matching: "zed.app", in: paths)
            )
        }

        if executablePath.contains("/visual studio code.app/contents/resources/app/extensions/"),
           let bundlePath = applicationBundlePath(matching: "visual studio code.app", in: paths) {
            return PortClassification(
                category: .other,
                displayName: "VS Code Extension Host",
                reason: "Local extension service managed by Visual Studio Code",
                applicationBundlePath: bundlePath
            )
        }

        if executablePath.contains("/cursor.app/contents/resources/app/extensions/"),
           let bundlePath = applicationBundlePath(matching: "cursor.app", in: paths) {
            return PortClassification(
                category: .other,
                displayName: "Cursor Extension Host",
                reason: "Local extension service managed by Cursor",
                applicationBundlePath: bundlePath
            )
        }

        return nil
    }

    private static func executionPaths(for entry: PortEntry) -> [String] {
        [entry.executablePath].compactMap { $0 } + entry.ancestorExecutablePaths
    }

    private static func applicationBundlePath(
        matching applicationName: String,
        in paths: [String]
    ) -> String? {
        paths.lazy
            .filter { $0.localizedCaseInsensitiveContains(applicationName) }
            .compactMap { applicationBundlePath(in: $0) }
            .first
    }

    private static func applicationBundlePath(in executablePath: String?) -> String? {
        guard let executablePath,
              let appRange = executablePath.range(of: ".app", options: .caseInsensitive) else {
            return nil
        }

        return String(executablePath[..<appRange.upperBound])
    }

    private static func isSystemExecutable(_ executablePath: String?) -> Bool {
        guard let path = executablePath?.lowercased() else {
            return false
        }

        return path.hasPrefix("/system/library/") || path.hasPrefix("/usr/libexec/")
    }

    private static func isBundledApplicationHelper(_ executablePath: String?) -> Bool {
        executablePath?.lowercased().contains(".app/contents/") == true
    }

    private static func webServerName(for service: Service) -> String {
        switch service.iconName {
        case "python": "Python web server"
        case "node": "Node.js web server"
        case "rust": "Rust web server"
        case "go": "Go web server"
        case "ruby", "rails": "Ruby web server"
        case "java", "spring": "Java web server"
        case "dotnet": ".NET web server"
        case "php": "PHP web server"
        case "bun": "Bun web server"
        case "deno": "Deno web server"
        case "swift": "Swift web server"
        case "dart", "flutter": "Dart web server"
        default: "Development web server"
        }
    }

    private static func classificationReason(for entry: PortEntry, fallback: String) -> String {
        guard let executablePath = entry.executablePath else {
            return fallback
        }

        if executablePath.lowercased().contains("/target/") {
            return "Rust target executable: \(URL(fileURLWithPath: executablePath).lastPathComponent)"
        }

        if entry.ancestorExecutablePaths.map(normalizedProcessName).contains("cargo") {
            return "Parent process ancestry includes Cargo"
        }

        return "Executable: \(URL(fileURLWithPath: executablePath).lastPathComponent)"
    }

    private static func service(forProcessName processName: String) -> Service? {
        switch processName {
        case "nginx", "nginx-debug":
            return Service(category: .web, name: "Nginx", iconName: "nginx")
        case "httpd", "apache2":
            return Service(category: .web, name: "Apache", iconName: "apache")
        case "caddy":
            return Service(category: .web, name: "Caddy", iconName: "caddy")
        case "astro":
            return Service(category: .web, name: "Astro", iconName: "astro")
        case "gradio":
            return Service(category: .web, name: "Gradio", iconName: "gradio")
        case "vite":
            return Service(category: .web, name: "Vite", iconName: "vite")
        case "next", "next-server":
            return Service(category: .web, name: "Next.js", iconName: "nextjs")
        case "nuxt":
            return Service(category: .web, name: "Nuxt", iconName: "nuxt")
        case "parcel":
            return Service(category: .web, name: "Parcel", iconName: "parcel")
        case "storybook":
            return Service(category: .web, name: "Storybook", iconName: "storybook")
        case "hugo":
            return Service(category: .web, name: "Hugo", iconName: "hugo")
        case "gunicorn":
            return Service(category: .web, name: "Gunicorn", iconName: "gunicorn")
        case "uvicorn":
            return Service(category: .web, name: "Uvicorn", iconName: "python")
        case "puma":
            return Service(category: .web, name: "Puma", iconName: "ruby")
        case "postgres", "postmaster":
            return Service(category: .database, name: "PostgreSQL", iconName: "postgresql")
        case "mysqld":
            return Service(category: .database, name: "MySQL", iconName: "mysql")
        case "mariadbd":
            return Service(category: .database, name: "MariaDB", iconName: "mariadb")
        case "mongod", "mongos":
            return Service(category: .database, name: "MongoDB", iconName: "mongodb")
        case "couchdb":
            return Service(category: .database, name: "CouchDB", iconName: "couchdb")
        case "elasticsearch":
            return Service(category: .database, name: "Elasticsearch", iconName: "elasticsearch")
        case "kibana":
            return Service(category: .development, name: "Kibana", iconName: "kibana")
        case "redis-server", "redis-sentinel":
            return Service(category: .cache, name: "Redis", iconName: "redis")
        case "valkey-server":
            return Service(category: .cache, name: "Valkey", iconName: "valkey")
        case "memcached":
            return Service(category: .cache, name: "Memcached", iconName: "memcached")
        case "kafka":
            return Service(category: .messaging, name: "Kafka", iconName: "kafka")
        case "rabbitmq-server":
            return Service(category: .messaging, name: "RabbitMQ", iconName: "rabbitmq")
        case "docker", "dockerd", "docker-proxy", "com.docker.backend", "com.docker.vpnkit", "vpnkit":
            return Service(category: .container, name: "Container service", iconName: "docker")
        case "colima":
            return Service(category: .container, name: "Colima")
        case "adb":
            return Service(category: .mobile, name: "Android Debug Bridge", iconName: "android")
        case "node", "nodejs":
            return Service(category: .development, name: "Node.js runtime", iconName: "node")
        case "npm", "npx":
            return Service(category: .development, name: "npm", iconName: "npm")
        case "pnpm":
            return Service(category: .development, name: "pnpm", iconName: "pnpm")
        case "yarn":
            return Service(category: .development, name: "Yarn", iconName: "yarn")
        case "bun", "bunx":
            return Service(category: .development, name: "Bun runtime", iconName: "bun")
        case "deno":
            return Service(category: .development, name: "Deno runtime", iconName: "deno")
        case "java":
            return Service(category: .development, name: "Java runtime", iconName: "java")
        case "dotnet":
            return Service(category: .development, name: ".NET runtime", iconName: "dotnet")
        case "go", "air":
            return Service(category: .development, name: "Go runtime", iconName: "go")
        case "cargo":
            return Service(category: .development, name: "Rust runtime", iconName: "rust")
        case "ruby":
            return Service(category: .development, name: "Ruby runtime", iconName: "ruby")
        case "rails":
            return Service(category: .development, name: "Rails server", iconName: "rails")
        case "php", "php-fpm":
            return Service(category: .development, name: "PHP runtime", iconName: "php")
        case "gradle":
            return Service(category: .development, name: "Gradle", iconName: "gradle")
        case "spring":
            return Service(category: .development, name: "Spring", iconName: "spring")
        case "swift", "swift-run", "swift-build":
            return Service(category: .development, name: "Swift runtime", iconName: "swift")
        case "kubectl":
            return Service(category: .container, name: "Kubernetes port forward", iconName: "kubernetes")
        case "dart":
            return Service(category: .development, name: "Dart runtime", iconName: "dart")
        case "flutter":
            return Service(category: .development, name: "Flutter tool", iconName: "flutter")
        case "elixir", "iex", "mix":
            return Service(category: .development, name: "Elixir / Erlang runtime", iconName: "elixir")
        case "beam.smp", "erl", "erlexec":
            return Service(category: .development, name: "Erlang / BEAM runtime", iconName: "erlang")
        case "epmd":
            return Service(category: .development, name: "Erlang Port Mapper", iconName: "erlang")
        default:
            if processName.hasPrefix("next-server") {
                return Service(category: .web, name: "Next.js", iconName: "nextjs")
            }
            if processName.hasPrefix("python") {
                return Service(category: .development, name: "Python runtime", iconName: "python")
            }
            if processName.hasPrefix("ruby") {
                return Service(category: .development, name: "Ruby runtime", iconName: "ruby")
            }
            if processName.hasPrefix("php") {
                return Service(category: .development, name: "PHP runtime", iconName: "php")
            }

            return nil
        }
    }

    private static func service(for tool: WebDevelopmentTool) -> Service {
        switch tool {
        case .angular:
            Service(category: .web, name: "Angular", iconName: "angular")
        case .astro:
            Service(category: .web, name: "Astro", iconName: "astro")
        case .gradio:
            Service(category: .web, name: "Gradio", iconName: "gradio")
        case .nextJS:
            Service(category: .web, name: "Next.js", iconName: "nextjs")
        case .nuxt:
            Service(category: .web, name: "Nuxt", iconName: "nuxt")
        case .parcel:
            Service(category: .web, name: "Parcel", iconName: "parcel")
        case .storybook:
            Service(category: .web, name: "Storybook", iconName: "storybook")
        case .vite:
            Service(category: .web, name: "Vite", iconName: "vite")
        }
    }

    private static func service(for framework: WebProjectFramework) -> Service {
        switch framework {
        case .angular:
            Service(category: .web, name: "Angular", iconName: "angular")
        case .astro:
            Service(category: .web, name: "Astro", iconName: "astro")
        case .docusaurus:
            Service(category: .web, name: "Docusaurus", iconName: "docusaurus")
        case .gatsby:
            Service(category: .web, name: "Gatsby", iconName: "gatsby")
        case .lit:
            Service(category: .web, name: "Lit", iconName: "lit")
        case .nextJS:
            Service(category: .web, name: "Next.js", iconName: "nextjs")
        case .nuxt:
            Service(category: .web, name: "Nuxt", iconName: "nuxt")
        case .preact:
            Service(category: .web, name: "Preact", iconName: "preact")
        case .qwik:
            Service(category: .web, name: "Qwik", iconName: "qwik")
        case .react:
            Service(category: .web, name: "React", iconName: "react")
        case .remix:
            Service(category: .web, name: "Remix", iconName: "remix")
        case .solid:
            Service(category: .web, name: "Solid", iconName: "solid")
        case .solidStart:
            Service(category: .web, name: "SolidStart", iconName: "solid")
        case .svelte:
            Service(category: .web, name: "Svelte", iconName: "svelte")
        case .svelteKit:
            Service(category: .web, name: "SvelteKit", iconName: "svelte")
        case .vue:
            Service(category: .web, name: "Vue", iconName: "vue")
        }
    }

    private static func secondaryDisplayName(
        for entry: PortEntry,
        primaryService: Service
    ) -> String? {
        if let tool = entry.webDevelopmentTool {
            let toolService = service(for: tool)
            if toolService.name != primaryService.name {
                return toolService.name
            }
        }

        switch normalizedProcessName(entry.processName) {
        case "node", "nodejs", "npm", "npx", "pnpm", "yarn":
            return "Node.js"
        case "bun", "bunx":
            return "Bun"
        case "deno":
            return "Deno"
        default:
            return nil
        }
    }
}
