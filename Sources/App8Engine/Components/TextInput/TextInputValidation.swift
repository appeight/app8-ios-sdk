//
//  TextInputValidation.swift
//  App8Engine
//
//  Pure functions for text input validation and formatting.
//  Extracted for testability.
//

import Foundation

/// Helper functions for text input validation and formatting
enum TextInputValidation {

    // MARK: - Input Mask

    /// Format text according to mask pattern
    /// - Parameters:
    ///   - text: The input text to format
    ///   - mask: The mask pattern where `#` represents a digit
    /// - Returns: Formatted text with mask applied
    static func formatWithMask(text: String, mask: String) -> String {
        let digits = text.filter { $0.isNumber }
        var result = ""
        var digitIndex = digits.startIndex

        for char in mask {
            guard digitIndex < digits.endIndex else { break }
            if char == "#" {
                result.append(digits[digitIndex])
                digitIndex = digits.index(after: digitIndex)
            } else {
                result.append(char)
            }
        }

        return result
    }

    /// Extract raw digits from masked text
    /// - Parameter text: The masked text
    /// - Returns: Only the digit characters
    static func extractDigits(_ text: String) -> String {
        text.filter { $0.isNumber }
    }

    // MARK: - Character Filtering

    /// Check if input is allowed based on constraints
    /// - Parameters:
    ///   - input: The new characters being inserted
    ///   - range: The range being replaced
    ///   - currentText: The current text in the field
    ///   - maxLength: Optional maximum length constraint
    ///   - allowedPattern: Optional regex pattern for allowed characters
    /// - Returns: Whether the input should be allowed
    static func isInputAllowed(
        _ input: String,
        in range: NSRange,
        currentText: String,
        maxLength: Int?,
        allowedPattern: String?
    ) -> Bool {
        // Check max length
        if let maxLength = maxLength {
            let newLength = currentText.count + input.count - range.length
            if newLength > maxLength {
                return false
            }
        }

        // Check allowed characters pattern
        if let pattern = allowedPattern, !input.isEmpty {
            guard let regex = try? NSRegularExpression(pattern: pattern) else {
                return true // Invalid regex - allow all characters
            }
            let matchRange = NSRange(input.startIndex..., in: input)
            return regex.firstMatch(in: input, range: matchRange) != nil
        }

        return true
    }
}
