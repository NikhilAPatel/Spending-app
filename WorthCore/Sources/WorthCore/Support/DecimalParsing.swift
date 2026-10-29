import Foundation

extension Decimal {
    /// Parses a decimal from an API string such as "-33.29" or "1.5e+21".
    /// Uses a POSIX locale so a device set to e.g. German doesn't misread the dot.
    public init?(apiString: String) {
        let trimmed = apiString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let value = Decimal(string: trimmed, locale: Locale(identifier: "en_US_POSIX")) else {
            return nil
        }
        self = value
    }

    /// Converts a Double without the binary noise `Decimal(Double)` introduces (0.1 -> 0.1000000000000000512).
    public init(exactly double: Double) {
        self = Decimal(apiString: String(double)) ?? Decimal(double)
    }

    /// Divides by 10^places, e.g. lamports -> SOL or satoshis -> BTC.
    public func shifted(byDecimalPlaces places: Int) -> Decimal {
        var result = self
        var divisor = Decimal(1)
        for _ in 0..<max(places, 0) { divisor *= 10 }
        result /= divisor
        return result
    }

    public func rounded(_ scale: Int = 2) -> Decimal {
        var input = self
        var output = Decimal()
        NSDecimalRound(&output, &input, scale, .plain)
        return output
    }

    public var doubleValue: Double { NSDecimalNumber(decimal: self).doubleValue }
}

/// Decodes a number that APIs send either as a JSON string ("12.5") or a JSON number (12.5).
public struct FlexibleDecimal: Decodable, Sendable, Hashable {
    public let value: Decimal

    public init(_ value: Decimal) { self.value = value }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let string = try? container.decode(String.self) {
            guard let value = Decimal(apiString: string) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Not a number: \(string)")
            }
            self.value = value
        } else if let int = try? container.decode(Int64.self) {
            self.value = Decimal(int)
        } else {
            self.value = Decimal(exactly: try container.decode(Double.self))
        }
    }
}

extension KeyedDecodingContainer {
    /// Returns nil for missing keys, nulls, and values that aren't numbers (e.g. Ethplorer's `"price": false`).
    func lenientDecimal(forKey key: Key) -> Decimal? {
        (try? decodeIfPresent(FlexibleDecimal.self, forKey: key))?.value
    }
}
