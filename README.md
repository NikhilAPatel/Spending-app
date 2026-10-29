# Worth

A private iPhone app for your net worth and spending. It runs entirely on your phone: no server, no account, no analytics.

- **Net worth**: bank, card and brokerage balances (through [SimpleFIN Bridge](https://bridge.simplefin.org)), crypto wallets, and anything you enter by hand (private deals, stock plans, art, property, loans). The app records a daily history chart.
- **Spending**: transactions from your banks and cards, categorized automatically. Card payments and transfers between your own accounts are detected and left out, so nothing is double counted. Fix a category once and it can apply to every matching transaction.

## Get it running on your iPhone

You need a Mac with Xcode 16 or newer, an iPhone on iOS 17 or newer, and [Homebrew](https://brew.sh).

1. Get the code and generate the Xcode project:

   ```sh
   git clone https://github.com/nikhilapatel/spending-app.git
   cd spending-app
   git checkout claude/networth-ios-app   # until this branch is merged
   brew install xcodegen
   xcodegen
   open Worth.xcodeproj
   ```

   `xcodegen` builds `Worth.xcodeproj` from `project.yml`. Run it again after pulling changes that add or remove files.

2. Set up signing in Xcode. Select the **Worth** target, then **Signing & Capabilities**, and pick your **Team**. Your personal Apple ID works; add it under Xcode > Settings > Accounts if it isn't listed. If Xcode says the bundle identifier is taken, change `com.nikhilapatel.worth` to something unique.

   To avoid re-picking the team after every `xcodegen` run, put your Team ID in `project.yml` under `DEVELOPMENT_TEAM`.

3. Plug in your iPhone, choose it as the run destination, and press **Run** (⌘R). The first time:
   - On the iPhone, turn on **Settings > Privacy & Security > Developer Mode** and restart when asked.
   - If iOS says the developer isn't trusted, go to **Settings > General > VPN & Device Management** and trust your Apple ID.

With a free Apple ID the app stops opening after 7 days; run it from Xcode again to renew it. Your data stays on the phone. A paid Apple Developer account ($99/yr) extends that to a year and enables TestFlight.

## Connect your accounts

All of this happens in the app's **Accounts** tab.

### Banks and cards (SimpleFIN)

1. Sign up at [bridge.simplefin.org](https://bridge.simplefin.org) ($1.50/month or $15/year).
2. In SimpleFIN Bridge, link your institutions: Wells Fargo, Chase, Amex, Robinhood, Morgan Stanley and so on.
3. Create a **setup token** for a new app and copy it.
4. In Worth, tap **Connect banks with SimpleFIN** and paste the token.

Worth exchanges the token for a private access key, stores the key in the iOS keychain, and pulls the last 90 days of transactions. After that it syncs:

- automatically when you open the app, if the last sync was more than 6 hours ago;
- when you pull down to refresh, at most once an hour.

SimpleFIN Bridge only updates from your banks about once a day and asks apps to stay under 24 requests a day, which is why syncing more often wouldn't help.

After the first sync, check each account's **Type** (Checking & Savings, Credit Card, Investment, Loan). Worth guesses from the account name. Credit cards and loans always count as debt, whichever sign the bank uses. Brokerage accounts are left out of spending by default, so trades don't show up as purchases.

### Crypto

Tap **Add wallet or exchange**. Everything is read-only, and wallets need only a public address, never a key.

| Source | What to enter | What's counted |
|---|---|---|
| Bitcoin | A receiving address, or an `xpub` | BTC, including unconfirmed |
| Ethereum | A `0x…` address | ETH plus tokens that have a market price (via Ethplorer) |
| Solana | Your address | SOL plus SPL tokens (prices via Jupiter) |
| Hyperliquid | Your `0x…` address | Perps account value, spot tokens, staked HYPE, vault deposits |
| Kraken | API key + private key | Every balance, including staked and earn |

For Kraken, create the key at kraken.com under **Settings > API** and tick **only "Query Funds"**. That key can see balances but can't trade or withdraw.

Tokens without a market price, usually spam airdrops, are listed under "No price found" and count as $0. Tokens are priced by contract or mint address, never by name, so a fake "USDC" can't inflate your total.

### Entered by hand

Tap **Add asset or debt** for private company stakes, a stock plan (for example Morgan Stanley at Work), art, property, vehicles, loans, or a coin amount. A coin amount is priced automatically, which is handy for staked SOL or chains Worth doesn't read directly. Update the value whenever it changes; each update is kept in the item's value history.

## Categories

About 800 built-in merchant patterns cover groceries, dining, travel, subscriptions, utilities and more. To fix a transaction, open it and tap **Category**. With **Apply to matching transactions** on, Worth saves a rule: "every description containing BLUE BOTTLE COFFEE is Dining". The rule also applies to past and future transactions. You can manage your rules under **Accounts > Category rules**.

Card payments and transfers between your own accounts are recognized two ways: by wording ("PAYMENT THANK YOU", "CHASE CREDIT CRD AUTOPAY") and by matching the same amount leaving one account and arriving in another within 5 days. Both sides become transfers and don't count as spending or income.

## Privacy and security

- Your data is a single file in the app's private storage. It's encrypted while the phone is locked and included in your encrypted device backup.
- Credentials (the SimpleFIN access key and Kraken keys) live in the iOS keychain. They're marked "this device only", so they're not synced or backed up.
- Face ID (or your passcode) is required to open the app. Balances are hidden in the app switcher. You can turn this off in Accounts.
- **Accounts > Erase all data** deletes everything, keys included.
- The app talks only to the services it reads from:
  - `bridge.simplefin.org` (or wherever your SimpleFIN token points)
  - `mempool.space` and `blockchain.info` (Bitcoin)
  - `api.ethplorer.io` (Ethereum)
  - `api.mainnet-beta.solana.com` and `lite-api.jup.ag` (Solana)
  - `api.hyperliquid.xyz`
  - `api.kraken.com` (Kraken balances, and coin prices)

## Known gaps

- **Not yet tested against the live services.** Every integration is unit-tested against sample responses shaped like each service's documented format, but the environment it was built in couldn't reach those services. If something shows an error on first use, the message in the app says which service failed.
- **Apple Card** isn't available to personal apps; Apple only shares it with App Store finance apps.
- **History** starts with SimpleFIN's 90-day window plus whatever accumulates while you use the app.
- **Not yet read automatically:**
  - Ethereum layer-2 networks (Base, Arbitrum, …)
  - natively staked SOL
  - Bitcoin `zpub`/`ypub` keys (add addresses instead)

  Use a hand-entered coin amount for these.
- **Hyperliquid accounts in portfolio-margin mode** could count spot balances twice. Compare with the Hyperliquid app the first time.
- **Non-USD accounts** are shown as if they were USD.

## Project layout

```
App/                 SwiftUI app (screens, keychain, Face ID)
WorthCore/           Swift package with all the logic, no UI
  Sources/WorthCore/
    SimpleFIN/       setup-token claim, account/transaction sync and merge
    Crypto/          Bitcoin, Ethereum, Solana, Hyperliquid, Kraken, prices
    Categorization/  built-in merchant rules and the categorizer
    Reports/         monthly spending summaries, net worth breakdown
    App/AppModel.swift  app state, refresh scheduling, persistence
  Tests/             unit tests with sample API responses
project.yml          XcodeGen spec for Worth.xcodeproj
```

Run the logic tests with `cd WorthCore && swift test`. They also run on Linux.
