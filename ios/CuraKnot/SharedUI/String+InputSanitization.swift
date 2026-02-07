import Foundation

extension String {
    /// Trims whitespace and limits to a maximum character count,
    /// also ensuring UTF-8 byte length stays within the limit.
    func trimmedAndLimited(to maxLength: Int) -> String {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        // Fast path: if trimmed + prefixed string is already within UTF-8 byte limit
        let result = String(trimmed.prefix(maxLength))
        guard result.utf8.count > maxLength else { return result }
        // Slow path: find the longest prefix whose UTF-8 byte count fits.
        // Use binary search on character count to avoid O(n) dropLast loop.
        var low = 0
        var high = result.count
        while low < high {
            let mid = (low + high + 1) / 2
            if String(trimmed.prefix(mid)).utf8.count <= maxLength {
                low = mid
            } else {
                high = mid - 1
            }
        }
        return String(trimmed.prefix(low))
    }

    /// Trims, limits, and returns nil if empty.
    func trimmedLimitedOrNil(to maxLength: Int) -> String? {
        let result = trimmedAndLimited(to: maxLength)
        return result.isEmpty ? nil : result
    }
}
