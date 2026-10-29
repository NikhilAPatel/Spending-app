import Foundation
@testable import WorthCore

/// Serves canned responses by matching requests; records every request it sees.
final class MockHTTP: HTTPClient, @unchecked Sendable {
    private struct Route {
        let matches: @Sendable (HTTPRequest) -> Bool
        let response: HTTPResponse
    }

    private let lock = NSLock()
    private var routes: [Route] = []
    private var _requests: [HTTPRequest] = []

    var requests: [HTTPRequest] { lock.withLock { _requests } }

    func on(_ matches: @escaping @Sendable (HTTPRequest) -> Bool, status: Int = 200, body: String) {
        lock.withLock { routes.append(Route(matches: matches, response: HTTPResponse(status: status, body: Data(body.utf8)))) }
    }

    /// Matches on URL substring and, optionally, a substring of the request body.
    func on(url: String, bodyContains: String? = nil, status: Int = 200, body: String) {
        on({ request in
            guard request.url.absoluteString.contains(url) else { return false }
            guard let bodyContains else { return true }
            return String(decoding: request.body ?? Data(), as: UTF8.self).contains(bodyContains)
        }, status: status, body: body)
    }

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        try lock.withLock {
            _requests.append(request)
            guard let route = routes.first(where: { $0.matches(request) }) else {
                throw HTTPError.status(599, "No mock for \(request.method.rawValue) \(request.url)")
            }
            return route.response
        }
    }

    func count(matching url: String) -> Int {
        requests.filter { $0.url.absoluteString.contains(url) }.count
    }
}

func date(_ string: String) -> Date {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withFullDate]
    if let day = formatter.date(from: string) { return day.addingTimeInterval(12 * 3600) }
    return ISO8601DateFormatter().date(from: string)!
}

func dec(_ string: String) -> Decimal { Decimal(apiString: string)! }

var utcCalendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
}

enum Fixtures {
    static let accessURL = "https://demo-user:s3cr3t@beta-bridge.simplefin.org/simplefin"

    /// Shape from the SimpleFIN protocol docs, extended with Bridge's holdings and errlist fields.
    static func simpleFINAccounts(postedChaseId: String = "TRN-a1", includePending: Bool = true) -> String {
        """
        {
          "errors": [],
          "errlist": [{"code": "con.auth", "msg": "Wells Fargo needs you to reauthenticate"}],
          "accounts": [
            {
              "org": {"domain": "wellsfargo.com", "name": "Wells Fargo", "sfin-url": "https://beta-bridge.simplefin.org/simplefin"},
              "id": "ACT-wf-checking",
              "name": "Everyday Checking",
              "currency": "USD",
              "balance": "5200.50",
              "available-balance": "5100.50",
              "balance-date": 1761609600,
              "transactions": [
                {"id": "TRN-w1", "posted": 1761350400, "amount": "4250.00", "description": "ACME CORP PAYROLL PPD ID: 123"},
                {"id": "TRN-w2", "posted": 1761436800, "amount": "-1204.18", "description": "ACH DEBIT AMERICAN EXPRESS"},
                {"id": "TRN-w3", "posted": 1761523200, "amount": "-62.10", "description": "PURCHASE AUTHORIZED ON 10/26 BLUE BOTTLE COFFEE SAN FRANCISCO CA S384286027381843 CARD 1234"}
              ]
            },
            {
              "org": {"domain": "americanexpress.com", "name": "American Express"},
              "id": "ACT-amex",
              "name": "Platinum Card",
              "currency": "USD",
              "balance": "-2310.44",
              "balance-date": 1761609600,
              "transactions": [
                {"id": "TRN-a0", "posted": 1761436800, "amount": "1204.18", "description": "PAYMENT RECEIVED - THANK YOU"},
                {"id": "\(postedChaseId)", "posted": 1761523200, "amount": "-48.20", "description": "UBER *EATS", "payee": "Uber Eats"}
                \(includePending ? #",{"id": "TRN-pend", "posted": 0, "amount": "-15.00", "description": "SQ *JOES PIZZA", "pending": true, "transacted_at": 1761580800}"# : "")
              ]
            },
            {
              "org": {"domain": "robinhood.com", "name": "Robinhood"},
              "id": "ACT-rh",
              "name": "Individual",
              "currency": "USD",
              "balance": 15000.25,
              "balance-date": 1761609600,
              "transactions": [],
              "holdings": [
                {"id": "H1", "symbol": "VTI", "description": "Vanguard Total Stock Market ETF", "shares": "40", "market_value": "12000.00", "cost_basis": "9000.00", "currency": "USD"}
              ]
            }
          ]
        }
        """
    }

    static let mempoolAddress = """
    {"address":"bc1qexample","chain_stats":{"funded_txo_count":3,"funded_txo_sum":150000000,"spent_txo_count":1,"spent_txo_sum":50000000,"tx_count":4},"mempool_stats":{"funded_txo_count":1,"funded_txo_sum":2500000,"spent_txo_count":0,"spent_txo_sum":0,"tx_count":1}}
    """

    static let krakenBTCTicker = """
    {"error":[],"result":{"XXBTZUSD":{"a":["100000.10000","1","1.000"],"b":["99999.90000","2","2.000"],"c":["100000.00000","0.00100000"],"v":["1","2"],"p":["1","2"],"t":[1,2],"l":["1","2"],"h":["1","2"],"o":"99000.0"}}}
    """

    static let krakenUnknownPair = #"{"error":["EQuery:Unknown asset pair"]}"#

    static let ethplorer = """
    {
      "address": "0xd8da6bf26964af9d7eed9e03e53415d37aa96045",
      "ETH": {"price": {"rate": 3500.5, "diff": 1.2, "ts": 1761609600, "currency": "USD"}, "balance": 1.5, "rawBalance": "1500000000000000000"},
      "countTxs": 1000,
      "tokens": [
        {"tokenInfo": {"address": "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48", "name": "USD Coin", "decimals": "6", "symbol": "USDC", "price": {"rate": 0.9998, "currency": "USD"}}, "balance": 2500000000, "rawBalance": "2500000000"},
        {"tokenInfo": {"address": "0xdead00000000000000000000000000000000beef", "name": "USDC Airdrop", "decimals": "18", "symbol": "USDC", "price": false}, "balance": 1.0e+24, "rawBalance": "1000000000000000000000000"}
      ]
    }
    """

    static let solanaBalance = #"{"jsonrpc":"2.0","result":{"context":{"slot":300000000},"value":2500000000},"id":1}"#

    static let solanaTokens = """
    {"jsonrpc":"2.0","result":{"context":{"slot":300000000},"value":[
      {"pubkey":"Acct1","account":{"data":{"parsed":{"info":{"isNative":false,"mint":"EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v","owner":"Owner","state":"initialized","tokenAmount":{"amount":"125000000","decimals":6,"uiAmount":125.0,"uiAmountString":"125"}},"type":"account"},"program":"spl-token","space":165},"executable":false,"lamports":2039280,"owner":"TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA","rentEpoch":0,"space":165}},
      {"pubkey":"Acct2","account":{"data":{"parsed":{"info":{"isNative":false,"mint":"JUPyiwrYJFskUPiHa7hkeR8VUtAeFoSYbKedZNsDvCN","owner":"Owner","state":"initialized","tokenAmount":{"amount":"1000000000","decimals":6,"uiAmount":1000.0,"uiAmountString":"1000"}},"type":"account"},"program":"spl-token","space":165},"executable":false,"lamports":2039280,"owner":"TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA","rentEpoch":0,"space":165}},
      {"pubkey":"Acct3","account":{"data":{"parsed":{"info":{"isNative":false,"mint":"ScamMint1111111111111111111111111111111111","owner":"Owner","state":"initialized","tokenAmount":{"amount":"0","decimals":6,"uiAmount":0.0,"uiAmountString":"0"}},"type":"account"},"program":"spl-token","space":165},"executable":false,"lamports":2039280,"owner":"TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA","rentEpoch":0,"space":165}}
    ]},"id":1}
    """

    static let solanaNoTokens = #"{"jsonrpc":"2.0","result":{"context":{"slot":300000000},"value":[]},"id":1}"#

    static let jupiterV3 = """
    {"JUPyiwrYJFskUPiHa7hkeR8VUtAeFoSYbKedZNsDvCN":{"usdPrice":0.52,"blockId":348004023,"decimals":6,"priceChange24h":1.29}}
    """

    static let krakenSOLTicker = """
    {"error":[],"result":{"SOLUSD":{"a":["180.00","1","1.000"],"b":["179.90","1","1.000"],"c":["180.00","0.5"]}}}
    """

    static let hlClearinghouse = """
    {"marginSummary":{"accountValue":"13109.482328","totalNtlPos":"100.02","totalRawUsd":"13009.46","totalMarginUsed":"4.967826"},"crossMarginSummary":{"accountValue":"13109.482328","totalNtlPos":"100.02","totalRawUsd":"13009.46","totalMarginUsed":"4.967826"},"crossMaintenanceMarginUsed":"2.0","withdrawable":"13104.514502","assetPositions":[{"type":"oneWay","position":{"coin":"ETH","szi":"0.0335","entryPx":"2986.3","positionValue":"100.02","unrealizedPnl":"-0.0134","returnOnEquity":"-0.004","liquidationPx":"2866.27","marginUsed":"4.967826","maxLeverage":50,"leverage":{"type":"cross","value":20}}}],"time":1708622398623}
    """

    static let hlSpotState = """
    {"balances":[{"coin":"USDC","token":0,"hold":"0.0","total":"14.625485","entryNtl":"0.0"},{"coin":"HYPE","token":150,"hold":"0.0","total":"100.0","entryNtl":"2000.0"},{"coin":"PURR","token":1,"hold":"0","total":"0","entryNtl":"0"}]}
    """

    static let hlSpotMeta = """
    {"tokens":[{"name":"USDC","szDecimals":8,"weiDecimals":8,"index":0,"tokenId":"0x6d1e","isCanonical":true},{"name":"PURR","szDecimals":0,"weiDecimals":5,"index":1,"tokenId":"0xc1fb","isCanonical":true},{"name":"HYPE","szDecimals":2,"weiDecimals":8,"index":150,"tokenId":"0x0d01","isCanonical":false}],"universe":[{"name":"PURR/USDC","tokens":[1,0],"index":0,"isCanonical":true},{"name":"@107","tokens":[150,0],"index":107,"isCanonical":false}]}
    """

    static let hlAllMids = #"{"BTC":"100000.0","ETH":"3500.0","HYPE":"39.9","@107":"40.0","PURR/USDC":"0.2"}"#

    static let hlDelegator = #"{"delegated":"50.0","undelegated":"0.0","totalPendingWithdrawal":"0.0","nPendingWithdrawals":0}"#

    static let hlVaults = #"[{"vaultAddress":"0xdfc24b077bc1425ad1dea75bcb6f8158e10df303","equity":"742.5"}]"#
}
