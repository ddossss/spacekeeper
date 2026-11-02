import Foundation

public enum AppLanguage: String, Codable, CaseIterable, Sendable, Identifiable {
    case korean = "ko", japanese = "ja", english = "en"
    public var id: String { rawValue }
    public var name: String {
        switch self { case .korean: return "한국어"; case .japanese: return "日本語"; case .english: return "English" }
    }
    public var locale: Locale { Locale(identifier: rawValue) }
    public static var systemDefault: AppLanguage {
        for identifier in Locale.preferredLanguages {
            if let language = AppLanguage(rawValue: String(identifier.prefix(2))) { return language }
        }
        return .english
    }
}

/// Retain keys and arguments so scan results and persisted history can change language too.
public struct LocalizedMessage: Codable, Sendable, ExpressibleByStringLiteral, ExpressibleByStringInterpolation {
    public var key: String
    public var arguments: [Argument]
    public var verbatim: Bool
    public indirect enum Argument: Codable, Sendable {
        case text(String), message(LocalizedMessage), integer(Int64)
        func render(_ language: AppLanguage) -> String {
            switch self {
            case .text(let text): return text
            case .message(let message): return message.render(in: language)
            case .integer(let number): return number.formatted(.number.locale(language.locale))
            }
        }
    }
    public init(key: String, arguments: [Argument] = [], verbatim: Bool = false) {
        self.key = key; self.arguments = arguments; self.verbatim = verbatim
    }
    public init(stringLiteral value: String) { self.init(key: value) }
    public init(stringInterpolation: StringInterpolation) { self.init(key: stringInterpolation.key, arguments: stringInterpolation.arguments) }
    public struct StringInterpolation: StringInterpolationProtocol {
        var key = ""
        var arguments: [Argument] = []
        public init(literalCapacity: Int, interpolationCount: Int) { key.reserveCapacity(literalCapacity) }
        public mutating func appendLiteral(_ literal: String) { key += literal }
        private mutating func append(_ value: Argument) {
            key += "{\(arguments.count)}"; arguments.append(value)
        }
        public mutating func appendInterpolation(_ value: LocalizedMessage) { append(.message(value)) }
        public mutating func appendInterpolation(_ value: Int) { append(.integer(Int64(value))) }
        public mutating func appendInterpolation(_ value: Int64) { append(.integer(value)) }
        public mutating func appendInterpolation<T>(_ value: T) { append(.text(String(describing: value))) }
    }
    public var rendered: String { render(in: L10n.language) }
    public func render(in language: AppLanguage) -> String {
        if verbatim { return key }
        let template = L10n.text(key, language: language)
        // Replace placeholders in the template once; never reinterpret braces inside filenames.
        let regex = try! NSRegularExpression(pattern: #"\{([0-9]+)\}"#)
        var result = ""; var cursor = template.startIndex
        for match in regex.matches(in: template, range: NSRange(template.startIndex..., in: template)) {
            guard let range = Range(match.range, in: template), let numberRange = Range(match.range(at: 1), in: template),
                  let index = Int(template[numberRange]), arguments.indices.contains(index) else { continue }
            result += template[cursor..<range.lowerBound]
            result += arguments[index].render(language)
            cursor = range.upperBound
        }
        result += template[cursor...]
        return result
    }
    public static func error(_ error: Error) -> LocalizedMessage {
        (error as? KeeperError)?.message ?? LocalizedMessage(key: error.localizedDescription, verbatim: true)
    }
    public static func joined(_ messages: [LocalizedMessage], separator: String = "\n") -> LocalizedMessage {
        LocalizedMessage(key: messages.indices.map { "{\($0)}" }.joined(separator: separator), arguments: messages.map { .message($0) })
    }
}

public func L(_ message: LocalizedMessage) -> String { message.rendered }

public enum L10n {
    private static let lock = NSLock()
    private static var selected = AppLanguage.systemDefault
    public static var language: AppLanguage {
        get { lock.lock(); defer { lock.unlock() }; return selected }
        set { lock.lock(); selected = newValue; lock.unlock() }
    }
    public static var locale: Locale { language.locale }
    public static let catalog: [String: [String: String]] = {
        #if SWIFT_PACKAGE
        let url = Bundle.module.url(forResource: "translations", withExtension: "json")
        #else
        let url: URL? = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Resources/translations.json")
        #endif
        guard let url, let data = try? Data(contentsOf: url),
              let value = try? JSONDecoder().decode([String: [String: String]].self, from: data) else { return [:] }
        return value
    }()
    public static func text(_ key: String, language: AppLanguage = L10n.language) -> String {
        language == .korean ? key : catalog[key]?[language.rawValue] ?? key
    }
    public static func date(_ date: Date, includeDate: Bool = true) -> String {
        let formatter = DateFormatter(); formatter.locale = locale
        formatter.dateStyle = includeDate ? .medium : .none; formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    public static func bytes(_ bytes: Int64) -> String {
        let units = ["B", "KB", "MB", "GB", "TB", "PB"]
        var value = Double(bytes); var index = 0
        while abs(value) >= 1000 && index < units.count - 1 { value /= 1000; index += 1 }
        let formatter = NumberFormatter(); formatter.locale = locale; formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = index == 0 ? 0 : 2
        return "\(formatter.string(from: NSNumber(value: value)) ?? String(value)) \(units[index])"
    }
}

extension Store {
    private struct Preferences: Codable { var language: AppLanguage }
    public func language() throws -> AppLanguage {
        let url = root.appendingPathComponent("preferences.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return .systemDefault }
        return try JSONDecoder().decode(Preferences.self, from: Data(contentsOf: url)).language
    }
    public func save(language: AppLanguage) throws {
        try withLock {
            try JSONEncoder().encode(Preferences(language: language)).write(to: root.appendingPathComponent("preferences.json"), options: .atomic)
        }
    }
}
