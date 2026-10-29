import Foundation
import Testing
@testable import WorthCore

@Suite struct CategorizerTests {
    let categorizer = Categorizer()

    func category(_ description: String) -> String? {
        categorizer.match(description)?.category
    }

    @Test func normalizeStripsPunctuation() {
        #expect(Categorizer.normalize("SQ *Blue Bottle #12") == "SQ BLUE BOTTLE 12")
        #expect(Categorizer.normalize("  AT&T*BILL  ") == "AT T BILL")
        #expect(Categorizer.normalize("") == "")
    }

    @Test func commonMerchants() {
        #expect(category("WHOLEFDS MKT #10234 NEW YORK NY") == "Groceries")
        #expect(category("AplPay TRADER JOE S #552") == "Groceries")
        #expect(category("UBER *EATS PENDING") == "Dining")
        #expect(category("UBER *TRIP HELP.UBER.COM") == "Transportation")
        #expect(category("TST* JOE'S PIZZA") == "Dining")
        #expect(category("PURCHASE AUTHORIZED ON 10/26 BLUE BOTTLE COFFEE SAN FRANCISCO CA S3842 CARD 1234") == "Dining")
        #expect(category("NETFLIX.COM") == "Subscriptions")
        #expect(category("AMZN Mktp US*2K4") == "Shopping")
        #expect(category("Amazon Prime*1A2B3") == "Subscriptions")
        #expect(category("DELTA AIR LINES ATLANTA") == "Travel")
        #expect(category("CON ED OF NY") == "Utilities")
        #expect(category("ACME CORP PAYROLL PPD ID: 123") == "Paycheck")
        #expect(category("AUTOPAY PAYMENT - THANK YOU") == SpendingCategory.cardPayment)
        #expect(category("CHASE CREDIT CRD AUTOPAY 251026") == SpendingCategory.cardPayment)
        #expect(category("INTEREST CHARGE ON PURCHASES") == "Fees & Interest")
        #expect(category("ZELLE TO JOHN SMITH ON 10/12") == "Venmo & Zelle")
        #expect(category("ROBINHOOD DEBITS") == "Investment Transfer")
    }

    @Test func shortPatternsOnlyMatchWholeWords() {
        #expect(category("REI 123 SEATTLE") == "Shopping")
        #expect(category("EXPENSE REIMBURSEMENT") != "Shopping")
        #expect(category("ATT*BILL PAYMENT") == "Utilities")
        #expect(category("ATTORNEY SERVICES LLP") == nil)
        #expect(category("KITCHENAID STORE") != "Dining")
        #expect(category("ZOOM.COM 888-799") != "Entertainment")
        #expect(category("HOAGIE HAVEN") == nil)
        #expect(category("ONLINE PAYMENT TO CON ED") == "Utilities")
    }

    @Test func userRulesBeatBuiltIns() {
        let rules = [CategoryRule(pattern: "Blue Bottle", category: "Business")]
        let custom = Categorizer(userRules: rules)
        #expect(custom.match("BLUE BOTTLE COFFEE")?.category == "Business")
        #expect(custom.match("BLUE BOTTLE COFFEE")?.isUserRule == true)
        #expect(custom.match("STARBUCKS")?.category == "Dining")
    }

    @Test func overridesAndFallbacks() {
        let checking = BankAccount(id: "chk", name: "Checking", institution: "WF", balance: 100, balanceDate: Date(), kind: .cash)
        let card = BankAccount(id: "card", name: "Card", institution: "Chase", balance: -100, balanceDate: Date(), kind: .creditCard)
        let txs = [
            Transaction(id: "1", accountId: "chk", date: date("2025-10-01"), amount: -40, description: "MYSTERY MERCHANT"),
            Transaction(id: "2", accountId: "chk", date: date("2025-10-02"), amount: 900, description: "WIRE FROM CAP TABLE LLC"),
            Transaction(id: "3", accountId: "card", date: date("2025-10-03"), amount: -12, description: "STARBUCKS"),
        ]
        let result = Categorizer(overrides: ["3": "Business"]).categorize(txs, accounts: [checking, card])
        #expect(result[0].category == SpendingCategory.uncategorized)
        #expect(result[0].spendingAmount == 40)
        #expect(result[1].category == SpendingCategory.otherIncome)
        #expect(result[1].incomeAmount == 900)
        #expect(result[2].category == "Business")
        #expect(result[2].source == .override)
    }

    @Test func pairsCardPaymentsAndTransfers() {
        let checking = BankAccount(id: "chk", name: "Checking", institution: "WF", balance: 100, balanceDate: Date(), kind: .cash)
        let savings = BankAccount(id: "sav", name: "Savings", institution: "WF", balance: 100, balanceDate: Date(), kind: .cash)
        let card = BankAccount(id: "amex", name: "Platinum", institution: "Amex", balance: -100, balanceDate: Date(), kind: .creditCard)
        let txs = [
            // Card payment where neither side has a recognizable description.
            Transaction(id: "p1", accountId: "chk", date: date("2025-10-01"), amount: dec("-1204.18"), description: "ACH DEBIT AMERICAN EXPRESS"),
            Transaction(id: "p2", accountId: "amex", date: date("2025-10-03"), amount: dec("1204.18"), description: "CREDIT ADJ"),
            // Unlabeled checking -> savings move.
            Transaction(id: "t1", accountId: "chk", date: date("2025-10-05"), amount: -500, description: "WF WEB 12345"),
            Transaction(id: "t2", accountId: "sav", date: date("2025-10-05"), amount: 500, description: "WF WEB 12345"),
            // Same amount but too far apart: not a transfer.
            Transaction(id: "x1", accountId: "chk", date: date("2025-10-01"), amount: -75, description: "THING"),
            Transaction(id: "x2", accountId: "amex", date: date("2025-10-20"), amount: 75, description: "OTHER THING"),
            // Labeled on the card side only.
            Transaction(id: "l1", accountId: "chk", date: date("2025-10-10"), amount: -300, description: "AMEX ACH"),
            Transaction(id: "l2", accountId: "amex", date: date("2025-10-11"), amount: 300, description: "PAYMENT RECEIVED - THANK YOU"),
        ]
        let byID = Dictionary(uniqueKeysWithValues: Categorizer().categorize(txs, accounts: [checking, savings, card]).map { ($0.id, $0) })
        #expect(byID["p1"]?.category == SpendingCategory.cardPayment)
        #expect(byID["p2"]?.kind == .transfer)
        #expect(byID["t1"]?.category == SpendingCategory.transfer)
        #expect(byID["t2"]?.category == SpendingCategory.transfer)
        #expect(byID["x1"]?.kind == .expense)
        #expect(byID["x2"]?.kind == .expense)
        #expect(byID["l1"]?.category == SpendingCategory.cardPayment)
        #expect(byID["l1"]?.source == .matchedTransfer)
        #expect(byID["l2"]?.source == .builtInRule)
    }

    @Test func suggestedPatternRemovesBankBoilerplate() {
        let wf = Transaction(id: "1", accountId: "a", date: Date(), amount: -5, description: "PURCHASE AUTHORIZED ON 10/12 BLUE BOTTLE COFFEE SAN FRANCISCO CA S384286027381843 CARD 1234")
        #expect(AppModel.suggestedPattern(for: wf) == "BLUE BOTTLE COFFEE")
        let square = Transaction(id: "2", accountId: "a", date: Date(), amount: -5, description: "SQ *JOES PIZZA #42")
        #expect(AppModel.suggestedPattern(for: square) == "JOES PIZZA")
        let payee = Transaction(id: "3", accountId: "a", date: Date(), amount: -5, description: "UBER *EATS 8005928996", payee: "Uber Eats")
        #expect(AppModel.suggestedPattern(for: payee) == "UBER EATS")
    }
}

@Suite struct ReportTests {
    let checking = BankAccount(id: "chk", name: "Checking", institution: "WF", balance: 5000, balanceDate: Date(), kind: .cash)
    let card = BankAccount(id: "card", name: "Sapphire", institution: "Chase", balance: 800, balanceDate: Date(), kind: .creditCard)
    let brokerage = BankAccount(id: "rh", name: "Individual", institution: "Robinhood", balance: 15000, balanceDate: Date(), kind: .investment)

    @Test func monthlySummaryNetsRefundsAndSkipsTransfers() {
        let txs = [
            Transaction(id: "1", accountId: "card", date: date("2025-10-03"), amount: -100, description: "AMAZON.COM"),
            Transaction(id: "2", accountId: "card", date: date("2025-10-09"), amount: 30, description: "AMAZON.COM REFUND"),
            Transaction(id: "3", accountId: "card", date: date("2025-10-10"), amount: -50, description: "STARBUCKS"),
            Transaction(id: "4", accountId: "chk", date: date("2025-10-15"), amount: 4000, description: "ACME PAYROLL"),
            Transaction(id: "5", accountId: "chk", date: date("2025-10-20"), amount: -800, description: "CHASE CREDIT CRD AUTOPAY"),
            Transaction(id: "6", accountId: "card", date: date("2025-10-21"), amount: 800, description: "AUTOMATIC PAYMENT - THANK YOU"),
            Transaction(id: "7", accountId: "card", date: date("2025-09-28"), amount: -999, description: "STARBUCKS"),
            Transaction(id: "8", accountId: "rh", date: date("2025-10-05"), amount: -2000, description: "BUY VTI"),
        ]
        let categorized = Categorizer().categorize(txs, accounts: [checking, card, brokerage])
        let summary = SpendingReport.summary(
            for: MonthKey(year: 2025, month: 10),
            transactions: categorized,
            accountIDs: ["chk", "card"],
            catalog: CategoryCatalog(),
            calendar: utcCalendar
        )
        #expect(summary.spending == 120)
        #expect(summary.income == 4000)
        #expect(summary.categories.map(\.category.name) == ["Shopping", "Dining"])
        #expect(summary.categories.first?.amount == 70)
        #expect(summary.net == 3880)
    }

    @Test func trendCoversRequestedMonthsOldestFirst() {
        let trend = SpendingReport.trend(endingAt: MonthKey(year: 2025, month: 2), count: 3, transactions: [], accountIDs: [], catalog: CategoryCatalog())
        #expect(trend.map(\.month) == [MonthKey(year: 2024, month: 12), MonthKey(year: 2025, month: 1), MonthKey(year: 2025, month: 2)])
    }

    @Test func netWorthTreatsDebtAsNegativeEitherSign() {
        let positiveOwed = BankAccount(id: "c1", name: "Card", institution: "X", balance: 800, balanceDate: Date(), kind: .creditCard)
        let negativeOwed = BankAccount(id: "c2", name: "Card", institution: "Y", balance: -200, balanceDate: Date(), kind: .creditCard)
        var hidden = checking
        hidden.id = "hidden"
        hidden.includeInNetWorth = false
        let wallet = CryptoWallet(source: .bitcoin, label: "Cold", address: "bc1q", holdings: [CryptoHolding(symbol: "BTC", quantity: dec("0.5"), priceUSD: 100_000)])
        let assets = [
            ManualAsset(name: "Seed deal", kind: .privateCompany, value: 25_000),
            ManualAsset(name: "Painting", kind: .art, value: 8_000),
            ManualAsset(name: "Car loan", kind: .loan, value: 12_000),
        ]
        let breakdown = NetWorthCalculator.breakdown(accounts: [checking, brokerage, positiveOwed, negativeOwed, hidden], wallets: [wallet], manualAssets: assets)
        #expect(breakdown.total(for: .cash) == 5000)
        #expect(breakdown.total(for: .investments) == 40_000)
        #expect(breakdown.total(for: .crypto) == 50_000)
        #expect(breakdown.total(for: .otherAssets) == 8_000)
        #expect(breakdown.total(for: .debt) == -13_000)
        #expect(breakdown.total == 90_000)
        #expect(breakdown.liabilities == 13_000)
    }

    @Test func snapshotsKeepOnePerDay() {
        let breakdown = NetWorthBreakdown(lines: [
            NetWorthLine(source: .manual(UUID()), name: "A", detail: "", group: .cash, value: 100, asOf: nil),
        ])
        var snapshots = NetWorthCalculator.recording(breakdown, at: date("2025-10-01"), into: [], calendar: utcCalendar)
        snapshots = NetWorthCalculator.recording(breakdown, at: date("2025-10-01").addingTimeInterval(3600), into: snapshots, calendar: utcCalendar)
        snapshots = NetWorthCalculator.recording(breakdown, at: date("2025-10-02"), into: snapshots, calendar: utcCalendar)
        #expect(snapshots.count == 2)
        #expect(snapshots.first?.byGroup["cash"] == 100)
    }

    @Test func accountKindGuesses() {
        #expect(AccountKind.guess(name: "Everyday Checking", institution: "Wells Fargo", balance: 10, hasHoldings: false) == .cash)
        #expect(AccountKind.guess(name: "Active Cash Visa", institution: "Wells Fargo", balance: -10, hasHoldings: false) == .creditCard)
        #expect(AccountKind.guess(name: "Sapphire Reserve", institution: "Chase", balance: 10, hasHoldings: false) == .creditCard)
        #expect(AccountKind.guess(name: "Gold Card", institution: "American Express", balance: 10, hasHoldings: false) == .creditCard)
        #expect(AccountKind.guess(name: "High Yield Savings", institution: "American Express", balance: 10, hasHoldings: false) == .cash)
        #expect(AccountKind.guess(name: "Individual", institution: "Robinhood", balance: 10, hasHoldings: false) == .investment)
        #expect(AccountKind.guess(name: "Home Mortgage", institution: "Chase", balance: -10, hasHoldings: false) == .loan)
    }

    @Test func manualAssetHistoryOnePointPerDay() {
        var asset = ManualAsset(name: "Deal", kind: .privateCompany, value: 10_000, updatedAt: date("2025-01-01"))
        asset.setValue(12_000, on: date("2025-06-01"), calendar: utcCalendar)
        asset.setValue(15_000, on: date("2025-06-01"), calendar: utcCalendar)
        #expect(asset.history.map(\.value) == [10_000, 15_000])
        #expect(asset.value == 15_000)
    }

    @Test func decimalParsing() {
        #expect(Decimal(apiString: "-33.29") == Decimal(string: "-33.29"))
        #expect(Decimal(apiString: "abc") == nil)
        #expect(Decimal(exactly: 0.1) == Decimal(string: "0.1"))
        #expect(Decimal(150_000_000).shifted(byDecimalPlaces: 8) == dec("1.5"))
        #expect(dec("1.005").rounded(2) == dec("1.01"))
    }
}
