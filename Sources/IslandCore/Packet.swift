import Foundation

public struct Packet: Equatable, Sendable {
    public enum ParseError: Error, Equatable {
        case noFrontMatter
        case missing(String)
    }

    public var id: String
    public var model: String
    public var effort: String
    public var acceptance: String
    public var scope: [String]
    public var title: String?
    public var text: String

    public static let defaultModel = "gemini-4-hydrogen"
    public static let defaultEffort = "high"

    /// `agy models` lists slugs with the effort baked in (gemini-4-hydrogen-high), so the packet's model and effort are joined here.
    public var modelSlug: String { Self.slug(model: model, effort: effort) }

    public static func slug(model: String, effort: String) -> String {
        let efforts = ["low", "medium", "high", "xhigh", "max"]
        if efforts.contains(where: { model.hasSuffix("-\($0)") }) { return model }
        return "\(model)-\(effort)"
    }

    public static func parse(_ text: String) throws -> Packet {
        let lines = text.components(separatedBy: "\n")
        guard lines.first == "---", let end = lines.dropFirst().firstIndex(of: "---") else { throw ParseError.noFrontMatter }
        var fields: [String: String] = [:]
        for line in lines[1..<end] {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = line[..<colon].trimmingCharacters(in: .whitespaces)
            fields[key] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        guard let id = fields["id"], !id.isEmpty else { throw ParseError.missing("id") }
        guard let acceptance = fields["acceptance"], !acceptance.isEmpty else { throw ParseError.missing("acceptance") }
        let scope = (fields["scope"] ?? "")
            .trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return Packet(
            id: id,
            model: fields["model"] ?? defaultModel,
            effort: fields["effort"] ?? defaultEffort,
            acceptance: acceptance,
            scope: scope,
            title: fields["title"],
            text: text
        )
    }
}
