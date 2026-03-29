/// Git diff-filter options for filtering changes by type.
/// Each case maps to a git diff-filter character used in git commands.
public enum DiffFilter: String, CaseIterable {
    /// Added files (A)
    case added = "A"
    
    /// Copied files (C)
    case copied = "C"
    
    /// Deleted files (D)
    case deleted = "D"
    
    /// Modified files (M)
    case modified = "M"
    
    /// Renamed files (R)
    case renamed = "R"
    
    /// Type changed files (T)
    case typeChanged = "T"
    
    /// Unmerged files (U)
    case unmerged = "U"
    
    /// Unknown files (X)
    case unknown = "X"
    
    /// Broken pairing (B)
    case brokenPairing = "B"
}

extension Set where Element == DiffFilter {
    /// Convert a set of DiffFilter cases to a git diff-filter string
    public var gitFilterString: String {
        map(\.rawValue).sorted().joined()
    }
}

extension Array where Element == DiffFilter {
    /// Convert an array of DiffFilter cases to a git diff-filter string
    public var gitFilterString: String {
        Set(self).gitFilterString
    }
}