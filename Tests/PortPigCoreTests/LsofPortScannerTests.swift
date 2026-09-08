import Foundation
import XCTest
@testable import PortPigCore

final class LsofPortScannerTests: XCTestCase {
    func testParseFieldOutputDeduplicatesRepeatedFileDescriptors() {
        let output = """
        p100
        cnode
        f10
        PTCP
        n*:3000
        f11
        PTCP
        n*:3000
        p200
        cpython3.13
        f4
        PTCP
        n127.0.0.1:8000
        """

        let ports = LsofPortScanner.parse(output)

        XCTAssertEqual(ports.count, 2)
        XCTAssertEqual(ports.map(\.port), [3000, 8000])
        XCTAssertEqual(ports[0].processName, "node")
        XCTAssertEqual(ports[0].pid, 100)
    }

    func testParseFieldOutputHandlesIPv6Endpoints() {
        let output = """
        p300
        cnode
        f31
        PTCP
        n[::1]:5273
        """

        let ports = LsofPortScanner.parse(output)

        XCTAssertEqual(ports.count, 1)
        XCTAssertEqual(ports[0].port, 5273)
        XCTAssertEqual(ports[0].endpoint, "[::1]:5273")
    }

    func testParseFieldOutputIgnoresMalformedPorts() {
        let output = """
        p400
        cservice
        f8
        PTCP
        n127.0.0.1:not-a-port
        """

        XCTAssertTrue(LsofPortScanner.parse(output).isEmpty)
    }

    func testParseFieldOutputCapturesParentAndUserIDs() {
        let output = """
        p700
        R650
        cproject-api
        u501
        PTCP
        n127.0.0.1:4000
        """

        let entry = try! XCTUnwrap(LsofPortScanner.parse(output).first)

        XCTAssertEqual(entry.parentPID, 650)
        XCTAssertEqual(entry.userID, 501)
    }

    func testAppliesExecutablePathAndBoundedProcessAncestry() {
        let entry = PortEntry(
            processName: "project-api",
            pid: 700,
            port: 4000,
            protocolName: "TCP",
            endpoint: "127.0.0.1:4000",
            parentPID: 650,
            userID: 501
        )
        let processList = """
          700   650   501 /projects/demo/target/debug/project-api
          650   600   501 /Users/dev/.cargo/bin/cargo
          600     1   501 /bin/zsh
        """

        let enriched = LsofPortScanner.applyingProcessMetadata(
            to: [entry],
            processListOutput: processList
        )
        let result = try! XCTUnwrap(enriched.first)

        XCTAssertEqual(result.executablePath, "/projects/demo/target/debug/project-api")
        XCTAssertEqual(
            result.ancestorExecutablePaths,
            ["/Users/dev/.cargo/bin/cargo", "/bin/zsh"]
        )
    }

    func testExtractsSanitizedWebToolHintFromCommandLine() {
        let entry = entry(processName: "node", pid: 700, port: 24_321, parentPID: 650)
        let processList = """
          700   650   501 /opt/homebrew/bin/node
          650     1   501 /bin/zsh
        """
        let commandList = """
          700 /opt/homebrew/bin/node /projects/site/node_modules/astro/bin/astro.mjs dev --port 24321
          650 /bin/zsh
        """

        let result = LsofPortScanner.applyingProcessMetadata(
            to: [entry],
            processListOutput: processList,
            commandListOutput: commandList
        ).first

        XCTAssertEqual(result?.webDevelopmentTool, .astro)
    }

    func testUsesParentCommandHintWhenListenerCommandIsGeneric() {
        let entry = entry(processName: "node", pid: 700, port: 16_006, parentPID: 650)
        let processList = """
          700   650   501 /opt/homebrew/bin/node
          650     1   501 /opt/homebrew/bin/node
        """
        let commandList = """
          700 /opt/homebrew/bin/node server.js
          650 /opt/homebrew/bin/node /projects/ui/node_modules/@storybook/core/bin/index.cjs dev
        """

        let result = LsofPortScanner.applyingProcessMetadata(
            to: [entry],
            processListOutput: processList,
            commandListOutput: commandList
        ).first

        XCTAssertEqual(result?.webDevelopmentTool, .storybook)
    }

    func testDoesNotInferToolFromProjectDirectoryName() {
        XCTAssertNil(
            LsofPortScanner.webDevelopmentTool(
                in: "/opt/homebrew/bin/node /projects/my-astro-site/server.js"
            )
        )
    }

    func testRecognizesSupportedWebToolCommandSignatures() {
        let cases: [(String, WebDevelopmentTool)] = [
            ("node /app/node_modules/@angular/cli/bin/ng.js serve", .angular),
            ("node /app/node_modules/astro/bin/astro.mjs dev", .astro),
            ("python /venv/lib/python3.13/site-packages/gradio/cli.py app.py", .gradio),
            ("node /app/node_modules/next/dist/bin/next dev", .nextJS),
            ("node /app/node_modules/nuxt/bin/nuxt.mjs dev", .nuxt),
            ("node /app/node_modules/parcel/lib/bin.js index.html", .parcel),
            ("node /app/node_modules/@storybook/core/bin/index.cjs dev", .storybook),
            ("node /app/node_modules/vite/bin/vite.js", .vite)
        ]

        for (command, expectedTool) in cases {
            XCTAssertEqual(LsofPortScanner.webDevelopmentTool(in: command), expectedTool)
        }
    }

    func testRecognizesProjectFrameworksAndMetaFrameworkPrecedence() throws {
        let cases: [([String], WebProjectFramework)] = [
            (["react", "next"], .nextJS),
            (["vue", "nuxt"], .nuxt),
            (["svelte", "@sveltejs/kit"], .svelteKit),
            (["solid-js", "@solidjs/start"], .solidStart),
            (["react", "@remix-run/react"], .remix),
            (["react", "gatsby"], .gatsby),
            (["react", "@docusaurus/core"], .docusaurus),
            (["@builder.io/qwik"], .qwik),
            (["astro", "react"], .astro),
            (["@angular/core"], .angular),
            (["svelte"], .svelte),
            (["vue"], .vue),
            (["react"], .react),
            (["preact"], .preact),
            (["solid-js"], .solid),
            (["lit"], .lit)
        ]

        for (dependencies, expectedFramework) in cases {
            let package = [
                "dependencies": Dictionary(uniqueKeysWithValues: dependencies.map { ($0, "latest") })
            ]
            let data = try JSONSerialization.data(withJSONObject: package)

            XCTAssertEqual(
                LsofPortScanner.webProjectFramework(inPackageJSON: data),
                expectedFramework
            )
        }
    }

    func testEnrichesEntryWithFrameworkWithoutRetainingWorkingDirectory() throws {
        let projectDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: projectDirectory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: projectDirectory) }

        let package = """
        {"dependencies":{"svelte":"^5.0.0","@sveltejs/kit":"^2.0.0","vite":"^7.0.0"}}
        """
        try Data(package.utf8).write(to: projectDirectory.appendingPathComponent("package.json"))

        let result = LsofPortScanner.applyingProcessMetadata(
            to: [entry(processName: "node", pid: 700, port: 5173)],
            processListOutput: "700 1 501 /opt/homebrew/bin/node",
            commandListOutput: "700 node /project/node_modules/vite/bin/vite.js",
            workingDirectoryListOutput: "p700\nfcwd\nn\(projectDirectory.path)"
        ).first

        XCTAssertEqual(result?.webProjectFramework, .svelteKit)
        XCTAssertEqual(result?.webDevelopmentTool, .vite)
    }

    func testBrowserURLUsesLocalhostForWildcardAddresses() {
        XCTAssertEqual(
            browserURL(endpoint: "*:3000", port: 3000)?.absoluteString,
            "http://localhost:3000/"
        )
        XCTAssertEqual(
            browserURL(endpoint: "0.0.0.0:8080", port: 8080)?.absoluteString,
            "http://localhost:8080/"
        )
        XCTAssertEqual(
            browserURL(endpoint: "[::]:5173", port: 5173)?.absoluteString,
            "http://localhost:5173/"
        )
    }

    func testBrowserURLPreservesSpecificIPv4AndIPv6Addresses() {
        XCTAssertEqual(
            browserURL(endpoint: "127.0.0.1:8000", port: 8000)?.absoluteString,
            "http://127.0.0.1:8000/"
        )
        XCTAssertEqual(
            browserURL(endpoint: "[::1]:5273", port: 5273)?.absoluteString,
            "http://[::1]:5273/"
        )
    }

    func testBrowserURLUsesHTTPSForCommonSecureDevelopmentPorts() {
        XCTAssertEqual(
            browserURL(endpoint: "*:443", port: 443)?.absoluteString,
            "https://localhost:443/"
        )
        XCTAssertEqual(
            browserURL(endpoint: "localhost:8443", port: 8443)?.absoluteString,
            "https://localhost:8443/"
        )
    }

    private func browserURL(endpoint: String, port: Int) -> URL? {
        PortEntry(
            processName: "server",
            pid: 100,
            port: port,
            protocolName: "TCP",
            endpoint: endpoint
        ).browserURL
    }

    private func entry(
        processName: String,
        pid: Int32,
        port: Int,
        parentPID: Int32? = nil
    ) -> PortEntry {
        PortEntry(
            processName: processName,
            pid: pid,
            port: port,
            protocolName: "TCP",
            endpoint: "127.0.0.1:\(port)",
            parentPID: parentPID,
            userID: 501
        )
    }
}
