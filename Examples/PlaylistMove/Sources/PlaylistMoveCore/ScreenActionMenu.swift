import Foundation

/// Binds a generated action choice to the same observation used to offer it.
public struct ScreenActionMenu: Sendable {
    public struct Choice: Sendable, Equatable {
        public let value: String
        public let operation: String
        public let elementID: Int?
    }
    public let choices: [Choice]

    public init(screen: [ScreenText]) {
        let general = ["readSongs", "scrollDown", "scrollUp", "home", "spotlight",
                       "typeText", "enter", "selectAll", "backspace", "wait", "songAdded", "finish", "needHelp"]
        var choices = general.map { Choice(value: $0, operation: $0, elementID: nil) }
        var seen = Set<Int>()
        for item in screen where seen.insert(item.id).inserted {
            let label = item.text.replacingOccurrences(of: "\n", with: " ").prefix(40)
            for operation in ["tap", "hold"] {
                choices.append(Choice(value: "\(operation) #\(item.id): \(label)", operation: operation, elementID: item.id))
            }
        }
        self.choices = choices
    }

    public func choice(for value: String) throws -> Choice {
        guard let choice = choices.first(where: { $0.value == value }) else { throw TransferError.invalidAction }
        return choice
    }
}
