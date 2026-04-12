import Foundation

// MARK: - Date Filterable

public protocol DateFilterable {
    func dateField(_ field: PRDateField) -> String?
}

public enum PRDateField {
    case created
    case updated
    case merged
    case closed
}

// MARK: - PR Filtering

public struct PRFilter: Sendable {
    public var authorLogin: String?
    public var baseBranch: String?
    public var dateFilter: PRDateFilter?
    public var headRefNamePrefix: String?
    public var state: PRState?

    public init(
        authorLogin: String? = nil,
        baseBranch: String? = nil,
        dateFilter: PRDateFilter? = nil,
        headRefNamePrefix: String? = nil,
        state: PRState? = nil
    ) {
        self.authorLogin = authorLogin
        self.baseBranch = baseBranch
        self.dateFilter = dateFilter
        self.headRefNamePrefix = headRefNamePrefix
        self.state = state
    }

    public func matches(_ metadata: PRMetadata) -> Bool {
        if let prState = state {
            if PRState(rawValue: metadata.state.uppercased()) != prState { return false }
        }
        if let baseBranch, !baseBranch.isEmpty {
            if metadata.baseRefName != baseBranch { return false }
        }
        if let authorLogin, !authorLogin.isEmpty {
            if metadata.author.login != authorLogin { return false }
        }
        if let headRefNamePrefix, !headRefNamePrefix.isEmpty {
            if !metadata.headRefName.hasPrefix(headRefNamePrefix) { return false }
        }
        if let dateFilter {
            let since = dateFilter.date
            if let dateString = dateFilter.extractDate(metadata),
               !dateString.isEmpty,
               let date = Self.parseDate(dateString) {
                if date < since { return false }
            }
        }
        return true
    }

    private static let fractionalDateFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let standardDateFormatter = ISO8601DateFormatter()

    private static func parseDate(_ string: String) -> Date? {
        fractionalDateFormatter.date(from: string) ?? standardDateFormatter.date(from: string)
    }

}

public enum PRDateFilter: Sendable {
    case createdSince(Date)
    case updatedSince(Date)
    case mergedSince(Date)
    case closedSince(Date)

    public var date: Date {
        switch self {
        case .createdSince(let d), .updatedSince(let d),
             .mergedSince(let d), .closedSince(let d):
            return d
        }
    }

    public var fieldLabel: String {
        switch self {
        case .createdSince: return "created"
        case .updatedSince: return "updated"
        case .mergedSince: return "merged"
        case .closedSince: return "closed"
        }
    }

    public var sortsByCreated: Bool {
        switch self {
        case .createdSince: return true
        case .updatedSince, .mergedSince, .closedSince: return false
        }
    }

    public var requiresClosedAPIState: Bool {
        switch self {
        case .createdSince, .updatedSince: return false
        case .mergedSince, .closedSince: return true
        }
    }

    public var dateField: PRDateField {
        switch self {
        case .createdSince: return .created
        case .updatedSince: return .updated
        case .mergedSince: return .merged
        case .closedSince: return .closed
        }
    }

    public var earlyStopField: PRDateField {
        switch self {
        case .createdSince: return .created
        case .updatedSince, .mergedSince, .closedSince: return .updated
        }
    }

    public func extractDate<T: DateFilterable>(_ value: T) -> String? {
        value.dateField(dateField)
    }

    public func extractEarlyStopDate<T: DateFilterable>(_ value: T) -> String? {
        value.dateField(earlyStopField)
    }
}

// MARK: - PR State

public enum PRState: String, Codable, Sendable, CaseIterable {
    case open = "OPEN"
    case closed = "CLOSED"
    case merged = "MERGED"
    case draft = "DRAFT"
    
    public var displayName: String {
        switch self {
        case .open: return "Open"
        case .closed: return "Closed"
        case .merged: return "Merged"
        case .draft: return "Draft"
        }
    }
    
    public var filterValue: String {
        switch self {
        case .open, .draft: return "open"
        case .closed: return "closed"
        case .merged: return "merged"
        }
    }

    /// The GitHub API state parameter value. The API only accepts "open", "closed", or "all".
    /// Draft PRs are open with `isDraft=true`; merged PRs are closed with `mergedAt != nil`.
    public var apiStateValue: String {
        switch self {
        case .open, .draft: return "open"
        case .closed, .merged: return "closed"
        }
    }

    public static func fromCLIString(_ value: String) -> PRState? {
        switch value.lowercased() {
        case "open": return .open
        case "draft": return .draft
        case "closed": return .closed
        case "merged": return .merged
        default: return nil
        }
    }
}

public struct PRMetadata: Sendable, Identifiable, Hashable {
    public var id: Int { number }

    public let number: Int
    public var displayNumber: String { "#\(number)" }
    public let title: String
    public let body: String?
    public let author: Author
    public let state: String
    public let headRefName: String
    public let baseRefName: String
    public let createdAt: String
    public let updatedAt: String?
    public let mergedAt: String?
    public let closedAt: String?
    public let url: String?
    public var githubComments: GitHubPullRequestComments?
    public var reviews: [GitHubReview]?
    public var checkRuns: [GitHubCheckRun]?
    public var isMergeable: Bool?

    public init(
        number: Int,
        title: String,
        body: String? = nil,
        author: Author,
        state: String,
        headRefName: String,
        baseRefName: String,
        createdAt: String,
        updatedAt: String? = nil,
        mergedAt: String? = nil,
        closedAt: String? = nil,
        url: String? = nil,
        githubComments: GitHubPullRequestComments? = nil,
        reviews: [GitHubReview]? = nil,
        checkRuns: [GitHubCheckRun]? = nil,
        isMergeable: Bool? = nil
    ) {
        self.number = number
        self.title = title
        self.body = body
        self.author = author
        self.state = state
        self.headRefName = headRefName
        self.baseRefName = baseRefName
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.mergedAt = mergedAt
        self.closedAt = closedAt
        self.url = url
        self.githubComments = githubComments
        self.reviews = reviews
        self.checkRuns = checkRuns
        self.isMergeable = isMergeable
    }

    public static func fallback(number: Int) -> PRMetadata {
        PRMetadata(
            number: number,
            title: "PR #\(number)",
            author: Author(login: "", name: ""),
            state: "",
            headRefName: "",
            baseRefName: "",
            createdAt: ""
        )
    }

    public struct Author: Sendable, Hashable {
        public let login: String
        public let name: String
        public let avatarURL: String?

        public init(login: String, name: String, avatarURL: String? = nil) {
            self.login = login
            self.name = name
            self.avatarURL = avatarURL
        }
    }
}

extension PRMetadata: Equatable {
    public static func == (lhs: PRMetadata, rhs: PRMetadata) -> Bool {
        lhs.number == rhs.number
    }

    /// Encodes enrichment state for use as a SwiftUI view identity.
    /// Changes when enrichment data arrives so List rows refresh without scrolling.
    public var contentID: String {
        "\(number)"
        + "|\(reviews?.count ?? -1)"
        + "|\(checkRuns?.count ?? -1)"
        + "|\(githubComments?.comments.count ?? -1)"
        + "|\(githubComments?.reviewComments.count ?? -1)"
    }
}

extension PRMetadata {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(number)
    }
}

extension PRMetadata: DateFilterable {
    public func dateField(_ field: PRDateField) -> String? {
        switch field {
        case .created: return createdAt
        case .updated: return updatedAt
        case .merged: return mergedAt
        case .closed: return closedAt
        }
    }
}
