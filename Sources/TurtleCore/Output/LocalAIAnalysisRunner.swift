import Foundation

struct LocalAIAnalysisConfiguration: Sendable {
    var executableURL: URL
    var arguments: [String]

    static func from(environment: [String: String]) -> LocalAIAnalysisConfiguration? {
        guard let executable = environment["TURTLEMECK_LOCAL_AI_EXECUTABLE"], executable.hasPrefix("/") else {
            return nil
        }
        let arguments: [String]
        if let json = environment["TURTLEMECK_LOCAL_AI_ARGUMENTS_JSON"],
           let data = json.data(using: .utf8),
           let decoded = try? JSONDecoder().decode([String].self, from: data) {
            arguments = decoded
        } else {
            arguments = []
        }
        return LocalAIAnalysisConfiguration(executableURL: URL(fileURLWithPath: executable), arguments: arguments)
    }
}

/// 선택적인 local AI 출력 어댑터. 공통 분석 결과를 읽을 뿐 verdict를 반환하지 않는다.
public final class LocalAIAnalysisRunner: @unchecked Sendable {
    private let configuration: LocalAIAnalysisConfiguration?

    public init(environment: [String: String] = ProcessInfo.processInfo.environment) {
        configuration = LocalAIAnalysisConfiguration.from(environment: environment)
    }

    public var isEnabled: Bool { configuration != nil }

    public func run(commonSessionPath: String) {
        guard let configuration else { return }
        let commonURL = URL(fileURLWithPath: commonSessionPath, isDirectory: true)
        guard !commonSessionPath.isEmpty, commonURL.lastPathComponent.range(of: #"^\d{8}-\d{6}$"#, options: .regularExpression) != nil else {
            return
        }
        let localURL = commonURL
            .deletingLastPathComponent()
            .appendingPathComponent("\(commonURL.lastPathComponent)-local", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: localURL, withIntermediateDirectories: true)
            let request = try request(commonURL: commonURL, localURL: localURL)
            let requestURL = localURL.appendingPathComponent("request.md")
            let analysisURL = localURL.appendingPathComponent("analysis.md")
            try request.write(to: requestURL, atomically: true, encoding: .utf8)
            try Data().write(to: analysisURL, options: .atomic)

            let output = try FileHandle(forWritingTo: analysisURL)
            defer { try? output.close() }
            let input = Pipe()
            let process = Process()
            process.executableURL = configuration.executableURL
            process.arguments = configuration.arguments
            process.currentDirectoryURL = localURL
            process.standardInput = input
            process.standardOutput = output
            process.standardError = output
            try process.run()
            try input.fileHandleForWriting.write(contentsOf: Data(request.utf8))
            try input.fileHandleForWriting.close()
            process.waitUntilExit()
        } catch {
            return
        }
    }

    private func request(commonURL: URL, localURL: URL) throws -> String {
        let names = try FileManager.default.contentsOfDirectory(atPath: commonURL.path)
        let captures = names.filter { $0.range(of: #"^capture-\d+\.png$"#, options: .regularExpression) != nil }.sorted(by: numericFileOrder)
        let depths = names.filter { $0.range(of: #"^depth-\d+\.png$"#, options: .regularExpression) != nil }.sorted(by: numericFileOrder)
        let capturesByNumber = Dictionary(uniqueKeysWithValues: captures.map { (number(in: $0), $0) })
        let depthsByNumber = Dictionary(uniqueKeysWithValues: depths.map { (number(in: $0), $0) })
        let pairedNumbers = Set(capturesByNumber.keys).intersection(depthsByNumber.keys).sorted()
        guard !pairedNumbers.isEmpty else {
            throw LocalAnalysisError.missingInputPair
        }
        let captureList = pairedNumbers.compactMap { capturesByNumber[$0] }
            .map { "- \(commonURL.appendingPathComponent($0).path)" }
            .joined(separator: "\n")
        let depthList = pairedNumbers.compactMap { depthsByNumber[$0] }
            .map { "- \(commonURL.appendingPathComponent($0).path)" }
            .joined(separator: "\n")
        return """
        # Local posture analysis request

        Analyze each RGB capture together with the depth image having the same frame number.
        The depth PNG is a visualization of relative inverse depth. It is not centimeters, absolute distance, clinical CVA, or a medical diagnosis.
        Do not modify the input directory. Return only a concise wellness-oriented analysis; the caller writes it to:
        \(localURL.appendingPathComponent("analysis.md").path)

        ## RGB captures
        \(captureList)

        ## Relative depth visualizations
        \(depthList)
        """
    }

    private func numericFileOrder(_ lhs: String, _ rhs: String) -> Bool {
        number(in: lhs) < number(in: rhs)
    }

    private func number(in name: String) -> Int {
        Int(name.split(separator: "-").last?.split(separator: ".").first ?? "") ?? .max
    }
}

private enum LocalAnalysisError: Error {
    case missingInputPair
}
