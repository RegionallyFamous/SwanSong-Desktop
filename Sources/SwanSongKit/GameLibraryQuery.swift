import Foundation

public enum GameLibraryFilter: Sendable {
    case all
    case favorites
    case recentlyPlayed
}

public enum GameLibrarySortOrder: String, CaseIterable, Identifiable, Sendable {
    case title = "Title"
    case recentlyAdded = "Recently Added"
    case recentlyPlayed = "Recently Played"

    public var id: Self { self }
}

public struct GameLibraryQuery: Sendable {
    public init() {}

    public func games(
        in games: [GameRecord],
        filter: GameLibraryFilter = .all,
        matching searchText: String = "",
        sortedBy sortOrder: GameLibrarySortOrder = .title
    ) -> [GameRecord] {
        var importOrder: [GameRecord.ID: Int] = [:]
        for (index, game) in games.enumerated() {
            importOrder[game.id] = index
        }

        let terms = searchText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: \Character.isWhitespace)
            .map(String.init)

        let filtered = games.filter { game in
            let isIncluded: Bool
            switch filter {
            case .all:
                isIncluded = true
            case .favorites:
                isIncluded = game.isFavorite
            case .recentlyPlayed:
                isIncluded = game.lastPlayedAt != nil
            }
            guard isIncluded else { return false }
            guard !terms.isEmpty else { return true }

            let platform = game.metadata.isColor ? "WonderSwan Color WSC" : "WonderSwan WS"
            let searchableText = "\(game.title) \(game.fileURL.lastPathComponent) \(platform)"
            return terms.allSatisfy(searchableText.localizedStandardContains)
        }

        return filtered.sorted { left, right in
            switch sortOrder {
            case .title:
                return Self.compareTitles(left, right)
            case .recentlyAdded:
                let leftIndex = importOrder[left.id] ?? 0
                let rightIndex = importOrder[right.id] ?? 0
                switch (left.addedAt, right.addedAt) {
                case let (leftDate?, rightDate?):
                    if leftDate != rightDate { return leftDate > rightDate }
                    return leftIndex == rightIndex
                        ? Self.compareTitles(left, right)
                        : leftIndex > rightIndex
                case (_?, nil):
                    return true
                case (nil, _?):
                    return false
                case (nil, nil):
                    return leftIndex == rightIndex
                        ? Self.compareTitles(left, right)
                        : leftIndex > rightIndex
                }
            case .recentlyPlayed:
                switch (left.lastPlayedAt, right.lastPlayedAt) {
                case let (leftDate?, rightDate?):
                    return leftDate == rightDate
                        ? Self.compareTitles(left, right)
                        : leftDate > rightDate
                case (_?, nil):
                    return true
                case (nil, _?):
                    return false
                case (nil, nil):
                    return Self.compareTitles(left, right)
                }
            }
        }
    }

    private static func compareTitles(_ left: GameRecord, _ right: GameRecord) -> Bool {
        let comparison = left.title.localizedStandardCompare(right.title)
        if comparison == .orderedSame {
            return left.fileURL.path.localizedStandardCompare(right.fileURL.path) == .orderedAscending
        }
        return comparison == .orderedAscending
    }
}
