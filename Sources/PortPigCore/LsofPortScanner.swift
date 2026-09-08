import Foundation

public struct LsofPortScanner: Sendable {
    private let lsofPath: String
    private let psPath: String

    public init(lsofPath: String = "/usr/sbin/lsof", psPath: String = "/bin/ps") {
        self.lsofPath = lsofPath
        self.psPath = psPath
    }

    public func listeningPorts() async throws -> [PortEntry] {
        let arguments = ["-nP", "-iTCP", "-sTCP:LISTEN", "-F", "pcPRun"]
        let result = try await Shell.run(executablePath: lsofPath, arguments: arguments)

        if result.exitCode != 0 && result.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if result.exitCode == 1 {
                return []
            }

            throw ShellCommandError.nonZeroExit(
                executable: lsofPath,
                arguments: arguments,
                exitCode: result.exitCode,
                stderr: result.standardError
            )
        }

        let entries = Self.parse(result.standardOutput)

        guard !entries.isEmpty else {
            return []
        }

        let processResult = try? await Shell.run(
            executablePath: psPath,
            arguments: ["-axo", "pid=,ppid=,uid=,comm="]
        )
        let processListOutput = processResult?.exitCode == 0
            ? processResult?.standardOutput ?? ""
            : ""
        let relevantPIDs = Self.relevantProcessIDs(
            for: entries,
            processListOutput: processListOutput
        )
        async let commandResult = relevantPIDs.isEmpty ? nil : try? Shell.run(
            executablePath: psPath,
            arguments: [
                "-p", relevantPIDs.map(String.init).joined(separator: ","),
                "-o", "pid=,command="
            ]
        )
        let listenerPIDs = Set(entries.map(\.pid)).sorted()
        async let workingDirectoryResult = listenerPIDs.isEmpty ? nil : try? Shell.run(
            executablePath: lsofPath,
            arguments: [
                "-a", "-p", listenerPIDs.map(String.init).joined(separator: ","),
                "-d", "cwd", "-Fn"
            ]
        )
        let (resolvedCommandResult, resolvedWorkingDirectoryResult) = await (
            commandResult,
            workingDirectoryResult
        )
        let commandListOutput = resolvedCommandResult?.exitCode == 0
            ? resolvedCommandResult?.standardOutput ?? ""
            : ""
        let workingDirectoryListOutput = resolvedWorkingDirectoryResult?.exitCode == 0
            ? resolvedWorkingDirectoryResult?.standardOutput ?? ""
            : ""

        guard !processListOutput.isEmpty
                || !commandListOutput.isEmpty
                || !workingDirectoryListOutput.isEmpty else {
            return entries
        }

        return Self.applyingProcessMetadata(
            to: entries,
            processListOutput: processListOutput,
            commandListOutput: commandListOutput,
            workingDirectoryListOutput: workingDirectoryListOutput
        )
    }

    public static func parse(_ output: String) -> [PortEntry] {
        var currentPID: Int32?
        var currentParentPID: Int32?
        var currentUserID: UInt32?
        var currentProcessName = "Unknown"
        var currentProtocol = "TCP"
        var ports: [PortEntry] = []
        var seen = Set<String>()

        for rawLine in output.split(whereSeparator: \.isNewline) {
            guard let field = rawLine.first else {
                continue
            }

            let value = String(rawLine.dropFirst())

            switch field {
            case "p":
                currentPID = Int32(value)
                currentParentPID = nil
                currentUserID = nil
                currentProcessName = "Unknown"
                currentProtocol = "TCP"
            case "R":
                currentParentPID = Int32(value)
            case "u":
                currentUserID = UInt32(value)
            case "c":
                currentProcessName = value.isEmpty ? "Unknown" : value
            case "P":
                currentProtocol = value.isEmpty ? "TCP" : value
            case "n":
                guard let pid = currentPID, let port = extractPort(from: value) else {
                    continue
                }

                let dedupeKey = "\(pid)-\(currentProtocol)-\(port)"
                guard !seen.contains(dedupeKey) else {
                    continue
                }

                seen.insert(dedupeKey)
                ports.append(
                    PortEntry(
                        processName: currentProcessName,
                        pid: pid,
                        port: port,
                        protocolName: currentProtocol,
                        endpoint: value,
                        parentPID: currentParentPID,
                        userID: currentUserID
                    )
                )
            default:
                continue
            }
        }

        return ports.sorted {
            if $0.port != $1.port {
                return $0.port < $1.port
            }

            if $0.processName != $1.processName {
                return $0.processName.localizedCaseInsensitiveCompare($1.processName) == .orderedAscending
            }

            return $0.pid < $1.pid
        }
    }

    static func applyingProcessMetadata(
        to entries: [PortEntry],
        processListOutput: String,
        commandListOutput: String = "",
        workingDirectoryListOutput: String = ""
    ) -> [PortEntry] {
        let processTable = parseProcessList(processListOutput)
        let commandHints = parseWebDevelopmentToolHints(commandListOutput)
        let workingDirectories = parseWorkingDirectories(workingDirectoryListOutput)

        return entries.map { entry in
            let record = processTable[entry.pid]
            let parentPID = entry.parentPID ?? record?.parentPID
            var ancestorPaths: [String] = []
            var webDevelopmentTool = commandHints[entry.pid]
            var visited = Set<Int32>()
            var nextPID = parentPID

            while let pid = nextPID, pid > 1, visited.insert(pid).inserted, ancestorPaths.count < 8 {
                guard let ancestor = processTable[pid] else {
                    break
                }

                if !ancestor.executablePath.isEmpty {
                    ancestorPaths.append(ancestor.executablePath)
                }
                if webDevelopmentTool == nil {
                    webDevelopmentTool = commandHints[pid]
                }
                nextPID = ancestor.parentPID
            }

            return PortEntry(
                processName: entry.processName,
                pid: entry.pid,
                port: entry.port,
                protocolName: entry.protocolName,
                endpoint: entry.endpoint,
                parentPID: parentPID,
                userID: entry.userID ?? record?.userID,
                executablePath: record?.executablePath,
                ancestorExecutablePaths: ancestorPaths,
                webDevelopmentTool: webDevelopmentTool,
                webProjectFramework: workingDirectories[entry.pid]
                    .flatMap(webProjectFramework(inWorkingDirectory:))
            )
        }
    }

    private struct ProcessRecord {
        let parentPID: Int32
        let userID: UInt32
        let executablePath: String
    }

    private static func parseProcessList(_ output: String) -> [Int32: ProcessRecord] {
        var records: [Int32: ProcessRecord] = [:]

        for line in output.split(whereSeparator: \.isNewline) {
            let fields = line.split(maxSplits: 3, whereSeparator: \.isWhitespace)
            guard fields.count == 4,
                  let pid = Int32(fields[0]),
                  let parentPID = Int32(fields[1]),
                  let userID = UInt32(fields[2]) else {
                continue
            }

            records[pid] = ProcessRecord(
                parentPID: parentPID,
                userID: userID,
                executablePath: String(fields[3])
            )
        }

        return records
    }

    private static func relevantProcessIDs(
        for entries: [PortEntry],
        processListOutput: String
    ) -> [Int32] {
        let processTable = parseProcessList(processListOutput)
        var processIDs = Set(entries.map(\.pid))

        for entry in entries {
            var visited = Set<Int32>()
            var nextPID = entry.parentPID ?? processTable[entry.pid]?.parentPID

            while let pid = nextPID, pid > 1, visited.insert(pid).inserted, visited.count <= 8 {
                processIDs.insert(pid)
                nextPID = processTable[pid]?.parentPID
            }
        }

        return processIDs.sorted()
    }

    private static func parseWebDevelopmentToolHints(
        _ output: String
    ) -> [Int32: WebDevelopmentTool] {
        var hints: [Int32: WebDevelopmentTool] = [:]

        for line in output.split(whereSeparator: \.isNewline) {
            let fields = line.split(maxSplits: 1, whereSeparator: \.isWhitespace)
            guard fields.count == 2,
                  let pid = Int32(fields[0]),
                  let hint = webDevelopmentTool(in: String(fields[1])) else {
                continue
            }

            hints[pid] = hint
        }

        return hints
    }

    private static func parseWorkingDirectories(_ output: String) -> [Int32: String] {
        var workingDirectories: [Int32: String] = [:]
        var currentPID: Int32?

        for line in output.split(whereSeparator: \.isNewline) {
            guard let field = line.first else {
                continue
            }

            let value = String(line.dropFirst())
            switch field {
            case "p":
                currentPID = Int32(value)
            case "n":
                if let currentPID, !value.isEmpty {
                    workingDirectories[currentPID] = value
                }
            default:
                continue
            }
        }

        return workingDirectories
    }

    private static func webProjectFramework(
        inWorkingDirectory workingDirectory: String
    ) -> WebProjectFramework? {
        let packageURL = URL(fileURLWithPath: workingDirectory)
            .appendingPathComponent("package.json", isDirectory: false)

        guard let attributes = try? FileManager.default.attributesOfItem(atPath: packageURL.path),
              let fileSize = attributes[.size] as? NSNumber,
              fileSize.intValue <= 1_048_576,
              let data = try? Data(contentsOf: packageURL) else {
            return nil
        }

        return webProjectFramework(inPackageJSON: data)
    }

    static func webProjectFramework(inPackageJSON data: Data) -> WebProjectFramework? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        let dependencySections = [
            "dependencies", "devDependencies", "peerDependencies", "optionalDependencies"
        ]
        let dependencies = dependencySections.reduce(into: Set<String>()) { names, section in
            guard let values = object[section] as? [String: Any] else {
                return
            }
            names.formUnion(values.keys.map { $0.lowercased() })
        }

        let signatures: [(WebProjectFramework, [String])] = [
            (.nextJS, ["next"]),
            (.nuxt, ["nuxt", "nuxt3"]),
            (.svelteKit, ["@sveltejs/kit"]),
            (.solidStart, ["@solidjs/start"]),
            (.remix, ["@remix-run/react"]),
            (.gatsby, ["gatsby"]),
            (.docusaurus, ["@docusaurus/core"]),
            (.qwik, ["@builder.io/qwik", "@builder.io/qwik-city"]),
            (.astro, ["astro"]),
            (.angular, ["@angular/core"]),
            (.svelte, ["svelte"]),
            (.vue, ["vue"]),
            (.react, ["react"]),
            (.preact, ["preact"]),
            (.solid, ["solid-js"]),
            (.lit, ["lit"])
        ]

        return signatures.first { _, packages in
            packages.contains(where: dependencies.contains)
        }?.0
    }

    static func webDevelopmentTool(in commandLine: String) -> WebDevelopmentTool? {
        let command = commandLine.lowercased().replacingOccurrences(of: "\\", with: "/")

        let signatures: [(WebDevelopmentTool, [String])] = [
            (.angular, ["/node_modules/@angular/cli/", "/node_modules/.bin/ng "]),
            (.astro, ["/node_modules/astro/", "/node_modules/.bin/astro "]),
            (.gradio, ["/site-packages/gradio/", "/bin/gradio "]),
            (.nextJS, ["/node_modules/next/dist/bin/next", "/node_modules/.bin/next "]),
            (.nuxt, ["/node_modules/nuxt/bin/", "/node_modules/.bin/nuxt "]),
            (.parcel, ["/node_modules/parcel/lib/bin", "/node_modules/.bin/parcel "]),
            (.storybook, [
                "/node_modules/@storybook/", "/node_modules/storybook/bin/",
                "/node_modules/.bin/storybook "
            ]),
            (.vite, ["/node_modules/vite/bin/vite", "/node_modules/.bin/vite "])
        ]

        return signatures.first { _, patterns in
            patterns.contains(where: command.contains)
        }?.0
    }

    private static func extractPort(from endpoint: String) -> Int? {
        let firstSegment = endpoint
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: " ")
            .first

        guard let firstSegment, let separatorIndex = firstSegment.lastIndex(of: ":") else {
            return nil
        }

        let portValue = firstSegment[firstSegment.index(after: separatorIndex)...]
        return Int(portValue)
    }
}
