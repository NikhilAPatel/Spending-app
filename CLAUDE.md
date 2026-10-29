# Worth: notes for Claude

A personal iPhone app (SwiftUI, iOS 17+) for net worth and spending. Read `HANDOFF.md` first: it explains the current state, what's unverified, and the plan.

## Commands

- Logic tests: `cd WorthCore && swift test`
- Live service checks (network, public addresses only): `cd WorthCore && WORTH_LIVE_TESTS=1 swift test --filter LiveAPITests`
- Generate the Xcode project: `xcodegen` (after adding or removing files too)
- Build: `xcodebuild -project Worth.xcodeproj -scheme Worth -destination 'platform=iOS Simulator,name=<iPhone>' build`

## Rules

- **Logic goes in `WorthCore`** and stays UI-free and Linux-buildable. Guard any Apple-only API, like CryptoKit in `KrakenFetcher`, with `#if canImport`.
- **The app target (`App/`) stays thin:** views, Keychain, Face ID.
- **Money is `Decimal`.** Convert to `Double` only at the chart boundary.
- **New network decoders get a fixture-based test.** Keep the fixtures in `TestSupport.swift` matching real responses.
- **Never commit or use credentials.** That covers the owner's SimpleFIN setup token, access URL and Kraken keys. They're entered in the app and live only in the iOS Keychain. Tests use mocks or public addresses.
- **Never price a wallet token by symbol.** Price it by contract or mint address only.
