import Foundation

public enum CryptoSource: String, Codable, CaseIterable, Sendable, Identifiable {
    case bitcoin
    case ethereum
    case solana
    case hyperliquid
    case kraken

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .bitcoin: "Bitcoin"
        case .ethereum: "Ethereum"
        case .solana: "Solana"
        case .hyperliquid: "Hyperliquid"
        case .kraken: "Kraken"
        }
    }

    /// Kraken uses an API key instead of a public address.
    public var usesAddress: Bool { self != .kraken }

    public var addressPrompt: String {
        switch self {
        case .bitcoin: "bc1…, 1…, 3… address or xpub"
        case .ethereum: "0x… address"
        case .solana: "Solana address"
        case .hyperliquid: "0x… address"
        case .kraken: ""
        }
    }

    /// Light format check so typos are caught before the first refresh.
    public func validate(address raw: String) -> String? {
        let address = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let base58 = CharacterSet(charactersIn: "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz")
        let hex = CharacterSet(charactersIn: "0123456789abcdefABCDEF")
        switch self {
        case .bitcoin:
            if address.hasPrefix("ypub") || address.hasPrefix("zpub") {
                return "ypub/zpub keys aren't supported yet. Add the wallet's addresses, or its xpub."
            }
            if address.hasPrefix("xpub") { return address.count > 100 ? nil : "That xpub looks too short." }
            let lower = address.lowercased()
            if lower.hasPrefix("bc1") { return (14...90).contains(address.count) ? nil : "That bc1 address looks the wrong length." }
            if address.hasPrefix("1") || address.hasPrefix("3") {
                let ok = (25...35).contains(address.count) && address.unicodeScalars.allSatisfy(base58.contains)
                return ok ? nil : "That doesn't look like a Bitcoin address."
            }
            return "Bitcoin addresses start with bc1, 1 or 3."
        case .ethereum, .hyperliquid:
            let body = address.dropFirst(2)
            let ok = address.hasPrefix("0x") && body.count == 40 && body.unicodeScalars.allSatisfy(hex.contains)
            return ok ? nil : "Expected 0x followed by 40 hex characters."
        case .solana:
            let ok = (32...44).contains(address.count) && address.unicodeScalars.allSatisfy(base58.contains)
            return ok ? nil : "That doesn't look like a Solana address."
        case .kraken:
            return nil
        }
    }
}

public struct CryptoHolding: Codable, Hashable, Sendable, Identifiable {
    public var symbol: String
    public var name: String?
    public var quantity: Decimal
    /// nil when no price source knows the token (often airdropped spam); it then counts as $0.
    public var priceUSD: Decimal?
    /// Set when the source reports a dollar value directly (Hyperliquid perps equity, vaults).
    public var fixedValueUSD: Decimal?
    /// True for native coins and exchange balances, which may be priced by ticker symbol.
    /// Tokens found in a wallet never are: anyone can airdrop a fake "USDC" or "ETH".
    public var priceBySymbol: Bool?

    public var id: String { "\(symbol)|\(name ?? "")|\(quantity)" }

    public init(symbol: String, name: String? = nil, quantity: Decimal, priceUSD: Decimal? = nil, fixedValueUSD: Decimal? = nil, priceBySymbol: Bool = false) {
        self.symbol = symbol
        self.name = name
        self.quantity = quantity
        self.priceUSD = priceUSD
        self.fixedValueUSD = fixedValueUSD
        self.priceBySymbol = priceBySymbol
    }

    public var valueUSD: Decimal? {
        if let fixedValueUSD { return fixedValueUSD }
        guard let priceUSD else { return nil }
        return quantity * priceUSD
    }
}

public struct CryptoWallet: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var source: CryptoSource
    public var label: String
    /// Public address or xpub. Empty for Kraken, whose API key lives in the keychain.
    public var address: String
    public var holdings: [CryptoHolding]
    public var lastUpdated: Date?
    public var lastError: String?

    public init(id: UUID = UUID(), source: CryptoSource, label: String, address: String, holdings: [CryptoHolding] = [], lastUpdated: Date? = nil, lastError: String? = nil) {
        self.id = id
        self.source = source
        self.label = label
        self.address = address.trimmingCharacters(in: .whitespacesAndNewlines)
        self.holdings = holdings
        self.lastUpdated = lastUpdated
        self.lastError = lastError
    }

    public var totalUSD: Decimal {
        holdings.reduce(0) { $0 + ($1.valueUSD ?? 0) }
    }

    public var unpricedHoldings: [CryptoHolding] {
        holdings.filter { $0.valueUSD == nil && $0.quantity > 0 }
    }

    public var shortAddress: String {
        guard address.count > 14 else { return address }
        return "\(address.prefix(6))…\(address.suffix(4))"
    }

    public var keychainKey: String { "kraken.\(id.uuidString)" }
}
