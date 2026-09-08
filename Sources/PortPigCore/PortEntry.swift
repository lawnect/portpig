import Foundation

public enum WebDevelopmentTool: String, Hashable, Sendable {
    case angular
    case astro
    case gradio
    case nextJS
    case nuxt
    case parcel
    case storybook
    case vite
}

public struct PortEntry: Identifiable, Hashable, Sendable {
    public let processName: String
    public let pid: Int32
    public let port: Int
    public let protocolName: String
    public let endpoint: String
    public let parentPID: Int32?
    public let userID: UInt32?
    public let executablePath: String?
    public let ancestorExecutablePaths: [String]
    public let webDevelopmentTool: WebDevelopmentTool?

    public var id: String {
        "\(pid)-\(protocolName)-\(port)"
    }

    public var classification: PortClassification {
        DevelopmentPortFilter.classify(self)
    }

    public var browserURL: URL? {
        guard (1...65_535).contains(port) else {
            return nil
        }

        var components = URLComponents()
        components.scheme = [443, 8443, 9443].contains(port) ? "https" : "http"
        components.host = browserHost
        components.port = port
        components.path = "/"
        return components.url
    }

    public init(
        processName: String,
        pid: Int32,
        port: Int,
        protocolName: String,
        endpoint: String,
        parentPID: Int32? = nil,
        userID: UInt32? = nil,
        executablePath: String? = nil,
        ancestorExecutablePaths: [String] = [],
        webDevelopmentTool: WebDevelopmentTool? = nil
    ) {
        self.processName = processName
        self.pid = pid
        self.port = port
        self.protocolName = protocolName
        self.endpoint = endpoint
        self.parentPID = parentPID
        self.userID = userID
        self.executablePath = executablePath
        self.ancestorExecutablePaths = ancestorExecutablePaths
        self.webDevelopmentTool = webDevelopmentTool
    }

    private var browserHost: String {
        let address = endpoint
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: \.isWhitespace)
            .first
            .map(String.init) ?? ""
        let portSuffix = ":\(port)"

        guard address.hasSuffix(portSuffix) else {
            return "localhost"
        }

        let host = String(address.dropLast(portSuffix.count))

        if host.isEmpty || ["*", "0.0.0.0", "::", "[::]"].contains(host) {
            return "localhost"
        }

        return host
    }
}
