import XCTest
@testable import PortPigCore

final class DevelopmentPortFilterTests: XCTestCase {
    func testIncludesCommonDevelopmentServer() {
        XCTAssertTrue(
            DevelopmentPortFilter.includes(
                entry(processName: "node", port: 3000)
            )
        )
    }

    func testIncludesProjectSpecificProcessOnCommonDevPort() {
        XCTAssertTrue(
            DevelopmentPortFilter.includes(
                entry(processName: "glb-api", port: 8080)
            )
        )
    }

    func testIncludesCommonDatabasePort() {
        XCTAssertTrue(
            DevelopmentPortFilter.includes(
                entry(processName: "mongod", port: 27017)
            )
        )
    }

    func testWebFilterIncludesCommonWebServer() {
        XCTAssertTrue(
            DevelopmentPortFilter.includesWebServer(
                entry(processName: "node", port: 5173)
            )
        )
    }

    func testWebFilterIncludesProjectWebApiPort() {
        XCTAssertTrue(
            DevelopmentPortFilter.includesWebServer(
                entry(processName: "glb-api", port: 8080)
            )
        )
    }

    func testAstroDefaultPortAloneDoesNotIdentifyAstro() {
        let classification = DevelopmentPortFilter.classify(
            entry(processName: "node", port: 4321)
        )

        XCTAssertTrue(DevelopmentPortFilter.includesWebServer(entry(processName: "node", port: 4321)))
        XCTAssertEqual(classification.displayName, "Node.js web server")
        XCTAssertEqual(classification.iconName, "node")
    }

    func testRecognizesAstroCommandOnCustomPort() {
        let classification = DevelopmentPortFilter.classify(
            entry(processName: "node", port: 24_321, webDevelopmentTool: .astro)
        )

        XCTAssertEqual(classification.category, .web)
        XCTAssertEqual(classification.displayName, "Astro")
        XCTAssertEqual(classification.iconName, "astro")
    }

    func testProcessRoleWinsOverAstroDefaultPort() {
        let classification = DevelopmentPortFilter.classify(
            entry(processName: "postgres", port: 4321, webDevelopmentTool: .astro)
        )

        XCTAssertEqual(classification.category, .database)
        XCTAssertEqual(classification.displayName, "PostgreSQL")
    }

    func testRecognizesViteCommandOnCustomPort() {
        let classification = DevelopmentPortFilter.classify(
            entry(processName: "node", port: 24_322, webDevelopmentTool: .vite)
        )

        XCTAssertEqual(classification.category, .web)
        XCTAssertEqual(classification.displayName, "Vite")
        XCTAssertEqual(classification.iconName, "vite")
    }

    func testWebFilterExcludesAndroidDebugBridge() {
        XCTAssertFalse(
            DevelopmentPortFilter.includesWebServer(
                entry(processName: "cadb", port: 5037)
            )
        )
    }

    func testWebFilterExcludesDatabasePort() {
        XCTAssertFalse(
            DevelopmentPortFilter.includesWebServer(
                entry(processName: "postgres", port: 5432)
            )
        )
    }

    func testExcludesKnownMacOSProcessOnCommonPort() {
        XCTAssertFalse(
            DevelopmentPortFilter.includes(
                entry(processName: "ControlCenter", port: 5000)
            )
        )
    }

    func testExcludesEditorInternalHighPort() {
        XCTAssertFalse(
            DevelopmentPortFilter.includes(
                entry(processName: "zed", port: 44438)
            )
        )
    }

    func testDoesNotUseRiskySubstringMatchingForShortRuntimeNames() {
        XCTAssertFalse(
            DevelopmentPortFilter.includes(
                entry(processName: "goggles-helper", port: 44_438)
            )
        )

        XCTAssertFalse(
            DevelopmentPortFilter.includes(
                entry(processName: "airport-helper", port: 44_439)
            )
        )
    }

    func testRecognizesVersionedPythonAsDevelopmentRuntime() {
        let classification = DevelopmentPortFilter.classify(
            entry(processName: "python3.13", port: 24_282)
        )

        XCTAssertEqual(classification.category, .development)
        XCTAssertEqual(classification.displayName, "Python runtime")
        XCTAssertEqual(classification.iconName, "python")
    }

    func testGenericRuntimeNeedsAWebPortToAppearInWebFilter() {
        let highNodePort = entry(processName: "node", port: 24_283)
        let vitePort = entry(processName: "node", port: 5173)

        XCTAssertTrue(DevelopmentPortFilter.includes(highNodePort))
        XCTAssertFalse(DevelopmentPortFilter.includesWebServer(highNodePort))
        XCTAssertTrue(DevelopmentPortFilter.includesWebServer(vitePort))
        XCTAssertEqual(DevelopmentPortFilter.classify(vitePort).displayName, "Node.js web server")
        XCTAssertEqual(DevelopmentPortFilter.classify(vitePort).iconName, "node")
    }

    func testProcessRoleWinsWhenPortUsuallyMeansWeb() {
        let entry = entry(processName: "postgres", port: 8080)

        XCTAssertFalse(DevelopmentPortFilter.includesWebServer(entry))
        XCTAssertEqual(DevelopmentPortFilter.classify(entry).category, .database)
    }

    func testClassifiesKnownServicesWithUsefulNames() {
        XCTAssertEqual(
            DevelopmentPortFilter.classify(entry(processName: "cadb", port: 5037)).displayName,
            "Android Debug Bridge"
        )
        XCTAssertEqual(
            DevelopmentPortFilter.classify(entry(processName: "cadb", port: 5037)).iconName,
            "android"
        )
        XCTAssertEqual(
            DevelopmentPortFilter.classify(entry(processName: "custom-api", port: 5173)).displayName,
            "Web server"
        )
        XCTAssertEqual(
            DevelopmentPortFilter.classify(entry(processName: "custom-db", port: 5432)).displayName,
            "PostgreSQL"
        )
    }

    func testUsesDedicatedLogosWhenAvailable() {
        let cases = [
            (processName: "custom-kibana", port: 5601, iconName: "kibana"),
            (processName: "memcached", port: 11211, iconName: "memcached"),
            (processName: "next", port: 3000, iconName: "nextjs"),
            (processName: "gunicorn", port: 8000, iconName: "gunicorn"),
            (processName: "custom-rabbit", port: 15672, iconName: "rabbitmq")
        ]

        for testCase in cases {
            let classification = DevelopmentPortFilter.classify(
                entry(processName: testCase.processName, port: testCase.port)
            )

            XCTAssertEqual(classification.iconName, testCase.iconName)
        }
    }

    func testUsesDedicatedPackageManagerLogos() {
        let cases = [
            (processName: "npm", displayName: "npm", iconName: "npm"),
            (processName: "npx", displayName: "npm", iconName: "npm"),
            (processName: "pnpm", displayName: "pnpm", iconName: "pnpm"),
            (processName: "yarn", displayName: "Yarn", iconName: "yarn"),
            (processName: "bunx", displayName: "Bun runtime", iconName: "bun")
        ]

        for testCase in cases {
            let classification = DevelopmentPortFilter.classify(
                entry(processName: testCase.processName, port: 24_500)
            )

            XCTAssertEqual(classification.displayName, testCase.displayName)
            XCTAssertEqual(classification.iconName, testCase.iconName)
        }
    }

    func testExactProcessIdentityWinsOverGenericExecutionContext() {
        let next = DevelopmentPortFilter.classify(
            entry(
                processName: "next",
                port: 3000,
                executablePath: "/Users/dev/project/node_modules/.bin/next"
            )
        )
        let gunicorn = DevelopmentPortFilter.classify(
            entry(
                processName: "gunicorn",
                port: 8000,
                executablePath: "/Users/dev/project/.venv/bin/gunicorn"
            )
        )

        XCTAssertEqual(next.displayName, "Next.js")
        XCTAssertEqual(next.iconName, "nextjs")
        XCTAssertEqual(gunicorn.displayName, "Gunicorn")
        XCTAssertEqual(gunicorn.iconName, "gunicorn")
    }

    func testNonJavaScriptRuntimeOnVitePortKeepsRuntimeLogo() {
        let classification = DevelopmentPortFilter.classify(
            entry(processName: "python3.13", port: 5173)
        )

        XCTAssertEqual(classification.displayName, "Python web server")
        XCTAssertEqual(classification.iconName, "python")
    }

    func testUsesSpecificInfrastructureProcessLogos() {
        let cases: [(String, PortCategory, String?)] = [
            ("elasticsearch", .database, "elasticsearch"),
            ("kibana", .development, "kibana"),
            ("kafka", .messaging, "kafka"),
            ("rabbitmq-server", .messaging, "rabbitmq"),
            ("redis-sentinel", .cache, "redis"),
            ("valkey-server", .cache, "valkey"),
            ("mongos", .database, "mongodb"),
            ("couchdb", .database, "couchdb"),
            ("nginx-debug", .web, "nginx"),
            ("colima", .container, nil)
        ]

        for (processName, category, iconName) in cases {
            let classification = DevelopmentPortFilter.classify(
                entry(processName: processName, port: 24_501)
            )

            XCTAssertEqual(classification.category, category)
            XCTAssertEqual(classification.iconName, iconName)
        }
    }

    func testIdentifiesToolingHelpersByProduct() {
        let cases: [(path: String, name: String, iconName: String?, bundlePath: String?)] = [
            (
                "/Users/dev/codex-acp/server",
                "Codex ACP Agent",
                "openai",
                nil
            ),
            (
                "/Applications/Visual Studio Code.app/Contents/Resources/app/extensions/helper",
                "VS Code Extension Host",
                nil,
                "/Applications/Visual Studio Code.app"
            ),
            (
                "/Applications/Cursor.app/Contents/Resources/app/extensions/helper",
                "Cursor Extension Host",
                nil,
                "/Applications/Cursor.app"
            ),
            (
                "/Users/dev/Applications/FigmaAgent.app/Contents/MacOS/figma_agent",
                "Figma Agent",
                nil,
                "/Users/dev/Applications/FigmaAgent.app"
            )
        ]

        for testCase in cases {
            let classification = DevelopmentPortFilter.classify(
                entry(
                    processName: "helper",
                    port: 24_502,
                    executablePath: testCase.path
                )
            )

            XCTAssertEqual(classification.category, .other)
            XCTAssertEqual(classification.displayName, testCase.name)
            XCTAssertEqual(classification.iconName, testCase.iconName)
            XCTAssertEqual(classification.applicationBundlePath, testCase.bundlePath)
        }
    }

    func testIdentifiesDiaAgentAndUsesInstalledApplicationIcon() {
        let classification = DevelopmentPortFilter.classify(
            entry(
                processName: "agent-server",
                port: 63_655,
                executablePath: "/Applications/Dia.app/Contents/Resources/agent-server-resources/dist/agent-server"
            )
        )

        XCTAssertEqual(classification.displayName, "Dia AI Agent")
        XCTAssertEqual(classification.applicationBundlePath, "/Applications/Dia.app")
    }

    func testDistinguishesSerenaLaunchedByCodexAndZed() {
        let executablePath = "/Users/dev/.local/share/uv/tools/serena-agent/bin/python"
        let codex = DevelopmentPortFilter.classify(
            entry(
                processName: "python3.13",
                port: 24_282,
                executablePath: executablePath,
                ancestorExecutablePaths: [
                    "/Users/dev/Library/Application Support/Zed/external_agents/codex-acp/bin/codex",
                    "/Applications/Zed.app/Contents/MacOS/zed"
                ]
            )
        )
        let zed = DevelopmentPortFilter.classify(
            entry(
                processName: "python3.13",
                port: 24_283,
                executablePath: executablePath,
                ancestorExecutablePaths: ["/Applications/Zed.app/Contents/MacOS/zed"]
            )
        )

        XCTAssertEqual(codex.displayName, "Serena MCP · Codex")
        XCTAssertEqual(codex.iconName, "openai")
        XCTAssertEqual(zed.displayName, "Serena MCP · Zed")
        XCTAssertEqual(zed.applicationBundlePath, "/Applications/Zed.app")
    }

    func testIdentifiesTailscaleBeforeGenericSystemProcessRule() {
        let classification = DevelopmentPortFilter.classify(
            entry(
                processName: "IPNExtension",
                port: 49_299,
                executablePath: "/Applications/Tailscale.app/Contents/PlugIns/IPNExtension.appex/Contents/MacOS/IPNExtension"
            )
        )

        XCTAssertEqual(classification.category, .other)
        XCTAssertEqual(classification.displayName, "Tailscale Network Extension")
        XCTAssertEqual(classification.applicationBundlePath, "/Applications/Tailscale.app")
    }

    func testIdentifiesZedLocalService() {
        let classification = DevelopmentPortFilter.classify(
            entry(
                processName: "zed",
                port: 44_438,
                executablePath: "/Applications/Zed.app/Contents/MacOS/zed"
            )
        )

        XCTAssertEqual(classification.displayName, "Zed Local Service")
        XCTAssertEqual(classification.applicationBundlePath, "/Applications/Zed.app")
    }

    func testGenericBeamRuntimeDoesNotAssumePhoenix() {
        let classification = DevelopmentPortFilter.classify(
            entry(processName: "beam.smp", port: 8080)
        )

        XCTAssertNotEqual(classification.displayName, "Phoenix / Elixir")
        XCTAssertEqual(classification.iconName, "erlang")
    }

    func testRecognizesErlangBeamRuntime() {
        let classification = DevelopmentPortFilter.classify(
            entry(processName: "beam.smp", port: 24_290)
        )

        XCTAssertEqual(classification.category, .development)
        XCTAssertEqual(classification.displayName, "Erlang / BEAM runtime")
        XCTAssertEqual(classification.iconName, "erlang")
    }

    func testRecognizesPhoenixRunningOnBeam() {
        let classification = DevelopmentPortFilter.classify(
            entry(processName: "beam.smp", port: 4000)
        )

        XCTAssertEqual(classification.category, .web)
        XCTAssertEqual(classification.displayName, "Phoenix / Elixir")
        XCTAssertEqual(classification.iconName, "phoenix")
    }

    func testRecognizesErlangPortMapper() {
        let classification = DevelopmentPortFilter.classify(
            entry(processName: "epmd", port: 4369)
        )

        XCTAssertEqual(classification.category, .development)
        XCTAssertEqual(classification.displayName, "Erlang Port Mapper")
        XCTAssertEqual(classification.iconName, "erlang")
    }

    func testRecognizesCompiledRustExecutableByTargetPath() {
        let classification = DevelopmentPortFilter.classify(
            entry(
                processName: "my-api",
                port: 24_300,
                executablePath: "/Users/dev/project/target/debug/my-api"
            )
        )

        XCTAssertEqual(classification.category, .development)
        XCTAssertEqual(classification.displayName, "Rust application")
        XCTAssertEqual(classification.iconName, "rust")
    }

    func testRecognizesRustWebServerByCargoAncestry() {
        let classification = DevelopmentPortFilter.classify(
            entry(
                processName: "my-api",
                port: 3000,
                executablePath: "/Users/dev/bin/my-api",
                ancestorExecutablePaths: ["/Users/dev/.cargo/bin/cargo", "/bin/zsh"]
            )
        )

        XCTAssertEqual(classification.category, .web)
        XCTAssertEqual(classification.displayName, "Rust web server")
        XCTAssertEqual(classification.iconName, "rust")
    }

    func testHidesCodingAssistantPythonListener() {
        let entry = entry(
            processName: "python3.13",
            port: 24_282,
            executablePath: "/Users/dev/.local/share/uv/tools/serena-agent/bin/python"
        )

        XCTAssertFalse(DevelopmentPortFilter.includes(entry))
        XCTAssertEqual(DevelopmentPortFilter.classify(entry).displayName, "Serena MCP Server")
    }

    func testRuntimeIdentityIsPreservedOnGenericWebPort() {
        let classification = DevelopmentPortFilter.classify(
            entry(processName: "python3.13", port: 8000)
        )

        XCTAssertEqual(classification.category, .web)
        XCTAssertEqual(classification.displayName, "Python web server")
        XCTAssertEqual(classification.iconName, "python")
    }

    func testSystemExecutableDoesNotBecomeWebServerFromPortAlone() {
        let entry = entry(
            processName: "new-system-helper",
            port: 5173,
            executablePath: "/System/Library/PrivateFrameworks/NewService"
        )

        XCTAssertFalse(DevelopmentPortFilter.includes(entry))
        XCTAssertEqual(DevelopmentPortFilter.classify(entry).category, .system)
    }

    func testGenericRuntimeOnCandidateWebRangeBecomesWebServer() {
        let classification = DevelopmentPortFilter.classify(
            entry(processName: "node", port: 3334)
        )

        XCTAssertEqual(classification.category, .web)
        XCTAssertEqual(classification.displayName, "Node.js web server")
        XCTAssertEqual(classification.iconName, "node")
    }

    func testRecognizesSwiftPMExecutableFromAncestry() {
        let classification = DevelopmentPortFilter.classify(
            entry(
                processName: "api",
                port: 8080,
                executablePath: "/Users/dev/api/.build/arm64-apple-macosx/debug/api",
                ancestorExecutablePaths: ["/usr/bin/swift-run", "/bin/zsh"]
            )
        )

        XCTAssertEqual(classification.category, .web)
        XCTAssertEqual(classification.displayName, "Swift web server")
        XCTAssertEqual(classification.iconName, "swift")
    }

    func testRecognizesKubernetesPortForward() {
        let classification = DevelopmentPortFilter.classify(
            entry(processName: "kubectl", port: 54_321)
        )

        XCTAssertEqual(classification.category, .container)
        XCTAssertEqual(classification.displayName, "Kubernetes port forward")
        XCTAssertEqual(classification.iconName, "kubernetes")
    }

    private func entry(
        processName: String,
        port: Int,
        executablePath: String? = nil,
        ancestorExecutablePaths: [String] = [],
        webDevelopmentTool: WebDevelopmentTool? = nil
    ) -> PortEntry {
        PortEntry(
            processName: processName,
            pid: 123,
            port: port,
            protocolName: "TCP",
            endpoint: "127.0.0.1:\(port)",
            executablePath: executablePath,
            ancestorExecutablePaths: ancestorExecutablePaths,
            webDevelopmentTool: webDevelopmentTool
        )
    }
}
