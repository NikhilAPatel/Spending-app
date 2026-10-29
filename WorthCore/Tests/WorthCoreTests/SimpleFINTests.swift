import Foundation
import Testing
@testable import WorthCore

@Suite struct SimpleFINTests {
    @Test func setupTokenDecodesToClaimURL() throws {
        let claim = "https://beta-bridge.simplefin.org/simplefin/claim/DEMO-v2-abc123"
        let token = Data(claim.utf8).base64EncodedString()
        #expect(try SimpleFINClient.claimURL(fromSetupToken: "  \(token)\n").absoluteString == claim)
        #expect(throws: SimpleFINError.invalidSetupToken) { try SimpleFINClient.claimURL(fromSetupToken: "not a token") }
        let http = Data("http://insecure.example.com/claim".utf8).base64EncodedString()
        #expect(throws: SimpleFINError.invalidSetupToken) { try SimpleFINClient.claimURL(fromSetupToken: http) }
    }

    @Test func accessURLSplitsCredentials() throws {
        let parts = try SimpleFINClient.parseAccessURL(Fixtures.accessURL)
        #expect(parts.baseURL.absoluteString == "https://beta-bridge.simplefin.org/simplefin")
        let expected = "Basic " + Data("demo-user:s3cr3t".utf8).base64EncodedString()
        #expect(parts.authorizationHeader == expected)
        #expect(throws: SimpleFINError.invalidAccessURL) { try SimpleFINClient.parseAccessURL("https://no-creds.example.com/simplefin") }
    }

    @Test func claimReturnsAccessURL() async throws {
        let http = MockHTTP()
        http.on(url: "/claim/", body: Fixtures.accessURL + "\n")
        let token = Data("https://beta-bridge.simplefin.org/simplefin/claim/XYZ".utf8).base64EncodedString()
        let access = try await SimpleFINClient(http: http).claim(setupToken: token)
        #expect(access == Fixtures.accessURL)
        #expect(http.requests.first?.method == .post)
    }

    @Test func claimRejectedToken() async throws {
        let http = MockHTTP()
        http.on(url: "/claim/", status: 403, body: "Forbidden")
        let token = Data("https://beta-bridge.simplefin.org/simplefin/claim/XYZ".utf8).base64EncodedString()
        await #expect(throws: SimpleFINError.tokenAlreadyClaimed) {
            try await SimpleFINClient(http: http).claim(setupToken: token)
        }
    }

    @Test func fetchSendsAuthAndClampsStartDate() async throws {
        let http = MockHTTP()
        http.on(url: "/simplefin/accounts", body: Fixtures.simpleFINAccounts())
        let now = date("2025-10-28")
        let result = try await SimpleFINClient(http: http).fetchAccounts(
            accessURL: Fixtures.accessURL,
            startDate: now.addingTimeInterval(-400 * 86_400),
            now: now
        )
        let request = try #require(http.requests.first)
        #expect(request.url.user == nil)
        #expect(request.headers["Authorization"]?.hasPrefix("Basic ") == true)
        let query = URLComponents(url: request.url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        #expect(query.contains(URLQueryItem(name: "pending", value: "1")))
        let start = try #require(query.first { $0.name == "start-date" }?.value.flatMap(Double.init))
        #expect(abs(start - now.addingTimeInterval(-90 * 86_400).timeIntervalSince1970) < 1)

        #expect(result.accounts.count == 3)
        #expect(result.errors == ["Wells Fargo needs you to reauthenticate"])
        let amex = try #require(result.accounts.first { $0.id == "ACT-amex" })
        #expect(amex.balance == dec("-2310.44"))
        #expect(amex.institutionName == "American Express")
        #expect(amex.transactions.last?.pending == true)
        let robinhood = try #require(result.accounts.first { $0.id == "ACT-rh" })
        #expect(robinhood.balance == dec("15000.25"))
        #expect(robinhood.holdings.first?.marketValue == dec("12000.00"))
    }

    @Test func fetchMapsAuthAndPaymentErrors() async {
        let http = MockHTTP()
        http.on(url: "/accounts", status: 403, body: "")
        await #expect(throws: SimpleFINError.authenticationFailed) {
            try await SimpleFINClient(http: http).fetchAccounts(accessURL: Fixtures.accessURL, startDate: nil)
        }
        let unpaid = MockHTTP()
        unpaid.on(url: "/accounts", status: 402, body: "")
        await #expect(throws: SimpleFINError.paymentRequired) {
            try await SimpleFINClient(http: unpaid).fetchAccounts(accessURL: Fixtures.accessURL, startDate: nil)
        }
    }

    @Test func mergeCreatesAccountsWithGuessedKinds() throws {
        let response = try JSONDecoder().decode(SimpleFINAccountSet.self, from: Data(Fixtures.simpleFINAccounts().utf8))
        let result = SimpleFINSync.merge(accounts: [], transactions: [], with: response, windowStart: date("2025-10-01"), now: date("2025-10-28"))
        let kinds = Dictionary(uniqueKeysWithValues: result.accounts.map { ($0.id, $0.kind) })
        #expect(kinds == ["ACT-wf-checking": .cash, "ACT-amex": .creditCard, "ACT-rh": .investment])
        #expect(result.accounts.first { $0.id == "ACT-rh" }?.includeInSpending == false)
        #expect(result.transactions.count == 6)
        #expect(result.transactions.contains { $0.id == "ACT-amex|TRN-pend" && $0.isPending })
    }

    @Test func mergeReplacesPendingAndKeepsSettings() throws {
        let first = try JSONDecoder().decode(SimpleFINAccountSet.self, from: Data(Fixtures.simpleFINAccounts().utf8))
        var state = SimpleFINSync.merge(accounts: [], transactions: [], with: first, windowStart: date("2025-10-01"), now: date("2025-10-28"))
        // User renames the card and excludes checking from net worth.
        state.accounts[1].nickname = "Amex Plat"
        state.accounts[0].includeInNetWorth = false
        // An older transaction outside the next window must survive.
        let old = BankTransaction(id: "ACT-amex|OLD", accountId: "ACT-amex", date: date("2025-09-01"), amount: -10, description: "OLD")
        state.transactions.append(old)

        // Next sync: the pending pizza charge posted under a new id.
        let secondJSON = Fixtures.simpleFINAccounts(includePending: false)
            .replacingOccurrences(of: #"{"id": "TRN-a0""#, with: #"{"id": "TRN-posted-pizza", "posted": 1761609600, "amount": "-15.00", "description": "SQ *JOES PIZZA"},{"id": "TRN-a0""#)
        let second = try JSONDecoder().decode(SimpleFINAccountSet.self, from: Data(secondJSON.utf8))
        let merged = SimpleFINSync.merge(accounts: state.accounts, transactions: state.transactions, with: second, windowStart: date("2025-10-20"), now: date("2025-10-29"))

        #expect(merged.accounts.first { $0.id == "ACT-amex" }?.nickname == "Amex Plat")
        #expect(merged.accounts.first { $0.id == "ACT-wf-checking" }?.includeInNetWorth == false)
        #expect(!merged.transactions.contains { $0.isPending })
        #expect(merged.transactions.filter { $0.description == "SQ *JOES PIZZA" }.count == 1)
        #expect(merged.transactions.contains(old))
        #expect(Set(merged.transactions.map(\.id)).count == merged.transactions.count)
    }

    @Test func mergeDoesNotWipeHistoryWhenBankErrors() throws {
        let json = """
        {"errors": ["Chase connection failed"], "accounts": [
          {"org": {"name": "Chase"}, "id": "ACT-c", "name": "Sapphire", "currency": "USD", "balance": "-50", "balance-date": 1761609600, "transactions": []}
        ]}
        """
        let response = try JSONDecoder().decode(SimpleFINAccountSet.self, from: Data(json.utf8))
        let existing = BankTransaction(id: "ACT-c|1", accountId: "ACT-c", date: date("2025-10-25"), amount: -20, description: "LUNCH")
        let account = BankAccount(id: "ACT-c", name: "Sapphire", institution: "Chase", balance: -40, balanceDate: date("2025-10-25"), kind: .creditCard)
        let merged = SimpleFINSync.merge(accounts: [account], transactions: [existing], with: response, windowStart: date("2025-10-20"), now: date("2025-10-28"))
        #expect(merged.transactions == [existing])
        #expect(merged.accounts.first?.balance == -50)
    }
}
