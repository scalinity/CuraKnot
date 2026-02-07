import Foundation

extension String {
    /// Trims whitespace and limits to a maximum character count,
    /// also ensuring UTF-8 byte length stays within the limit.
    func trimmedAndLimited(to maxLength: Int) -> String {
        var result = String(trimmingCharacters(in: .whitespacesAndNewlines).prefix(maxLength))
        // Ensure UTF-8 byte length doesn't exceed the limit.
        // Safety bound: at most result.count iterations (one dropLast per iteration).
        var iterations = result.count
        while result.utf8.count > maxLength && iterations > 0 {
            result = String(result.dropLast())
            iterations -= 1
        }
        return result
    }

    /// Trims, limits, and returns nil if empty.
    func trimmedLimitedOrNil(to maxLength: Int) -> String? {
        let result = trimmedAndLimited(to: maxLength)
        return result.isEmpty ? nil : result
    }
}
