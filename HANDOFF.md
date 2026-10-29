# Handoff: Worth (net worth + spending iPhone app)

This was written by Claude Code in a cloud session that had no Xcode and no access to the live services. A Claude Code session on the owner's Mac picks it up from here. Read this whole file first. `README.md` is the user-facing setup guide; this file is the engineering state and the plan.

## What the owner wants

1. **Net worth**, all in one place:
   - **Banks and cards**: Wells Fargo (main bank, where income lands), Chase, Amex. Wells Fargo cards too.
   - **Brokerages**: Robinhood and Morgan Stanley. Morgan Stanley at Work (employer stock plan) can be entered by hand; the owner said that's fine.
   - **Crypto**: Bitcoin, Ethereum, Solana and Hyperliquid wallets, plus a Kraken account.
   - **Assets entered by hand**: private company deals, art, and the like.
2. **Spending**: every bank and card transaction pulled in automatically and categorized. **No manual statement uploads.** The owner was firm that it isn't worth having unless the important parts are automatic.

Apple Card was dropped: the owner rarely uses it, and personal apps can't read it (details below).

## Decisions already made (and why)

| Decision | Why |
|---|---|
| **SimpleFIN Bridge** for banks, not Plaid | Plaid's real-data access is aimed at companies (compliance review; free Limited Production only for teams created before Apr 15, 2026). SimpleFIN is built for individuals: $15/yr, no approval, read-only. The owner chose it. |
| **No Apple Card** | Apple's FinanceKit needs an organization developer account and an app published on the App Store in the Finance category. Not feasible for a personal app. Chase takes over as issuer around early 2028; revisit then. |
| **Native iOS, no backend** | The owner has a Mac. SimpleFIN is designed for apps to call directly, so the phone talks straight to every service. Nothing to host. |
| **Local JSON file + Keychain** | All data is in one `AppData` JSON file (encrypted at rest via file protection, included in device backups). Secrets are in the Keychain, marked "this device only". |
| **Logic in a Swift package (`WorthCore`)** | Lets the logic build and test on Linux, which is all the cloud session had. The app target is thin SwiftUI on top. |
| **XcodeGen** (`project.yml`) | The cloud session couldn't generate a valid `.xcodeproj`. `Worth.xcodeproj` and `App/Info.plist` are generated and gitignored. |
| **Rule-based categorization** | SimpleFIN returns no categories. About 800 built-in merchant patterns, user rules, per-transaction overrides, and transfer/card-payment pairing. |
| **Face ID lock with a 5-minute grace period** | Locking immediately on background wiped half-filled sheets when the user switched to Safari to copy a SimpleFIN token or Kraken key. |

## Current state

Branch `claude/networth-ios-app`. No PR opened yet.

**Verified (Linux, Swift 6.0.3):** `cd WorthCore && swift test` passes 51 tests. That includes SimpleFIN claim, fetch and merge, every crypto fetcher, the categorizer, reports, net worth and AppModel flows. The services are mocked with sample responses written from each API's documented shape. The live tests (below) are skipped by default.

**NOT verified, so this is the job now:**

1. **The SwiftUI app has never been compiled.** An independent read-through found no compile errors, and it fixed several runtime issues in the lock flow, but expect a few Xcode errors.
2. **No real network call has ever been made.** The cloud session's network blocked every service. Each decoder is written to documented response formats, and every one of them is a guess until checked:
   - **Jupiter price API** (`SolanaFetcher.jupiterPrices`): host/version `lite-api.jup.ag/price/v3`. Most likely to have moved or to now require a key. The parser accepts both the v3 shape (`{mint: {usdPrice}}`) and the v2 shape (`{data: {mint: {price}}}`).
   - **Ethplorer** `getAddressInfo` with `apiKey=freekey`: rate limits, and whether `price: false` and `rawBalance` behave as assumed.
   - **Hyperliquid info API**:
     - spot prices are matched through `spotMeta` + `allMids` pair names (`@107`, `PURR/USDC`);
     - the `delegatorSummary` and `userVaultEquities` shapes;
     - portfolio-margin accounts might count spot balances twice (perps `accountValue` plus spot).
   - **blockchain.info** `/balance?active=<xpub>`, used for xpubs. There's no live test, because no public xpub is handy.
   - **Kraken**:
     - private `/0/private/Balance`: the signing is verified against Kraken's documented example (that test only runs where CryptoKit exists, i.e. on the Mac);
     - asset-code normalization (`XXBT`, `ETH2.S`, `.F` suffixes and so on);
     - `Ticker` pair names for newer assets.
   - **SimpleFIN Bridge**:
     - the `holdings` and `errlist` fields (Bridge adds these outside the published protocol);
     - `pending=1`;
     - the 90-day cap and the 24 requests/day guidance;
     - which sign each bank uses for card balances (the app treats debts as `-|balance|`, so either works).

## Plan for the local session

Work roughly in this order. Commit as you go on `claude/networth-ios-app`.

### 1. Make it build
```sh
brew install xcodegen          # if missing
xcodegen                       # generates Worth.xcodeproj from project.yml
cd WorthCore && swift test && cd ..   # macOS also runs the Kraken signature test
xcrun simctl list devices available | grep iPhone   # pick a simulator name
xcodebuild -project Worth.xcodeproj -scheme Worth \
  -destination 'platform=iOS Simulator,name=<iPhone name>' build
```
Fix compile errors in `App/`. Keep `WorthCore` free of UI and Apple-only imports (it must keep building on Linux), and keep its tests green.

### 2. Check the live services
```sh
cd WorthCore && WORTH_LIVE_TESTS=1 swift test --filter LiveAPITests
```
This hits Kraken prices, mempool.space, Ethplorer, the Solana RPC, Jupiter and Hyperliquid, using public addresses: the BTC genesis address, vitalik.eth, and the HLP vault. It prints what came back.

Where a shape differs:
1. Fix the decoder.
2. Update the matching fixture in `Tests/WorthCoreTests/TestSupport.swift`, so the mocked tests describe reality.
3. If an endpoint moved (Jupiter is the prime suspect), update it.

For SimpleFIN, use SimpleFIN's own demo or developer token from their docs at simplefin.org with fake data. **Never the owner's token** (see below).

### 3. Click through it in the Simulator
- Empty states, then add manual assets and public-address wallets.
- Charts in light and dark mode.
- The Face ID flow: in Simulator, Features > Face ID > Enrolled, then Matching Face / Non-matching Face. Check:
  - cancelling the prompt doesn't loop;
  - leaving for under 5 minutes keeps an open sheet;
  - leaving for longer locks.
- Recategorizing with "apply to matching".
- Erase all data.

### 4. Device and real data, with the owner
The owner runs it on their iPhone (README has the signing and Developer Mode steps), then connects SimpleFIN in the app themselves. After the first real sync, ask them about:
- **Account types.** Did each account get the right type (cash / card / investment / loan)? See `AccountKind.guess`.
- **Card payments and transfers.** Were they paired, so nothing is double counted?
- **What's left in "Uncategorized".** The owner can read out or screenshot the descriptions. Turn common ones into `BuiltInRules` entries (with tests), rather than one-off user rules.
- **Wells Fargo description style.** Its descriptions look like `PURCHASE AUTHORIZED ON 10/26 MERCHANT ... CARD 1234`; check that real ones match the patterns.

## Setup token: important

The owner generated a SimpleFIN **setup token** and pasted it into the cloud session's chat. It is single-use: whoever claims it first gets read access to their bank data.

- It is **not** in this repo, and it must never be committed, logged, or used from a script or test.
- The owner pastes it into the app's **Accounts > Connect banks with SimpleFIN** screen on their phone. That claims it and stores the resulting access URL in the Keychain.
- If it gets used up or lost, the owner should be able to create a new one in SimpleFIN Bridge. That's believed to be possible but wasn't confirmed, so check if it comes up.

## Code map

```
App/                          SwiftUI app target (Swift 5 language mode, iOS 17+)
  WorthApp.swift              entry; builds AppModel(FileDataStore, KeychainSecretStore)
  Support/                    Keychain, Face ID LockController + PrivacyCover, Format + colors
  Views/                      RootView (tabs, lock), NetWorthView, SpendingView, TransactionsView
  Views/Accounts/             AccountsView hub, ConnectSimpleFIN, BankAccountDetail, WalletViews,
                              ManualAssetEditor, RulesView (+ APIKeysView in AccountsView.swift)
WorthCore/Sources/WorthCore/  Swift 6 package, no UI
  App/AppModel.swift          @MainActor @Observable; refresh scheduling, persistence, all actions
  SimpleFIN/                  setup-token claim, /accounts fetch, merge (window replacement)
  Crypto/                     Bitcoin, Ethereum, Solana, Hyperliquid, Kraken fetchers;
                              PriceService (Kraken public ticker); CryptoPortfolioService
  Categorization/             BuiltInRules (patterns), Categorizer (rules, overrides, transfer pairing)
  Reports/                    SpendingReport (MonthKey, MonthlySummary), NetWorth (breakdown, snapshots)
  Models/                     BankAccount/BankTransaction, CryptoWallet, ManualAsset, Category, AppData
  Support/                    HTTPClient (mockable), Decimal parsing, DataStore, SecretStore
WorthCore/Tests/WorthCoreTests/  unit tests + fixtures; LiveAPITests (opt-in)
project.yml                   XcodeGen spec (bundle id com.nikhilapatel.worth, DEVELOPMENT_TEAM empty)
```

Behaviors worth knowing before changing things:

- **Bank refresh limits** (`AppModel`): pull-to-refresh fetches banks at most hourly; automatic refresh on app open at most every 6 hours (`manualBankInterval`, `automaticBankInterval`). Each sync re-requests 10 days before the previous one (`bankOverlap`) and replaces that window per account. That window replacement is how pending charges that post under a new id get cleaned up.
- **Crypto prices**:
  - priced by ticker symbol only for native coins and Kraken balances (`CryptoHolding.priceBySymbol`);
  - wallet tokens are priced only by contract or mint address, so spam named "USDC" can't inflate the total. Don't regress this.
- **Debts**: credit card and loan balances always count as `-|balance|`, because banks disagree on the sign.
- **Account edits**: `updateAccount` only applies the user-editable settings, so a stale screen can't revert a sync.
- **Money**: `Decimal` everywhere; convert with `.doubleValue` only for Charts.

## Backlog (after the above works)

- **AI categorization**: opt-in, using the owner's own Claude API key, for whatever the rules leave uncategorized. Cache each answer as a user rule.
- **Background refresh** (`BGAppRefreshTask`) so the net worth history fills in without opening the app.
- **Missing coverage**:
  - Ethereum layer-2s (Base, Arbitrum);
  - natively staked SOL (stake accounts);
  - Bitcoin `zpub`/`ypub` (needs BIP32 derivation);
  - Hyperliquid portfolio-margin check.
- **Morgan Stanley at Work**: a stock-plan asset that auto-prices from a ticker and share count (needs a stock price source).
- **Smaller items**: non-USD accounts (currently treated as USD), CSV export, home-screen widget, budgets, recurring-subscription detection.
