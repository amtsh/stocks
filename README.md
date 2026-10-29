# Stocks for iOS

A native SwiftUI stock-research app for US-listed equities, using Apple's public Stocks app screens as a UI reference.

## Features
- Watchlist with ticker/company name, quote, daily change, and sparkline.
- Search, add/remove, and reorder symbols; watchlist persists locally.
- Interactive historical charts: 1D, 1W, 1M, 6M, 1Y, 2Y, 5Y, and 10Y.
- Trading context: previous close, day range, 52-week range, volume, exchange, and provider market timestamp when available.
- Technical research calculated locally from one year of daily closes: RSI (14), SMA (20/50/200), MACD (12, 26), and MACD signal (9).
- Data validation rejects non-finite/non-positive prices and sorts historical points chronologically.
- Data-source caveats and timestamp visibility in the stock detail view.

## Data reliability audit

**Current reliability level: suitable for exploration/prototyping, not execution-quality trading.**

| Area | Current behavior | Limitation / action |
|---|---|---|
| Provider | Yahoo Finance unofficial chart/search endpoints | No supported API contract or real-time SLA; endpoints can change or be throttled |
| Freshness | Shows the provider's market timestamp when available | Timestamp is not proof of real-time delivery; app does not independently verify exchange feed latency |
| Polling | Watchlist polls every 60 seconds while open | Too aggressive for an unofficial endpoint; rate limits and request failures are possible |
| Price validation | Rejects invalid/non-positive quote prices and filters invalid chart closes | No independent second-source cross-check; stale-but-valid prices can still pass |
| Daily change | Uses provider regular market price and previous close metadata | May not represent an executable live bid/ask; pre/post-market semantics are not explicit |
| Historical data | Uses chart endpoint intervals per selected range | Missing bars, adjusted-price behavior, and provider corrections are not audited against an independent feed |
| Technical indicators | Calculated locally from daily close history | RSI implementation is a simple-window approximation; indicators are not trading recommendations |
| Alerts | Not implemented | Reliable background alerts require persisted rules, delivery handling, and a dependable quote/trigger strategy |

### Before relying on this for trading
1. Use a provider with documented US market-data entitlements, timestamp/latency definitions, and a supported API.
2. Add explicit market-session state and stale-data thresholds; never label a quote “real-time” without evidence.
3. Test prices and historical bars against a second trusted source across regular hours, pre/post-market, weekends, splits, and missing-data cases.
4. Reduce polling and add backoff for HTTP 429/5xx responses.
5. Add unit tests for indicator calculations and data-quality edge cases.
6. For price alerts, define whether triggers use last trade, bid/ask, or delayed close, and surface that choice to users.

No market data is guaranteed real-time. This app is for informational research only, not investment advice.

## Market data implementation notes
- Search: `/v1/finance/search`, filtered to equity results.
- Quotes/history: `/v8/finance/chart/{symbol}`.
- No API key or account is required.
- The watchlist currently refreshes every 60 seconds while the app is open. This is polling, not streaming, and should be reduced before broad use.
- Market capitalization is not shown as a real value because the chart endpoint does not reliably provide it.

## Requirements and run
- Xcode 27+ with the iOS 27 SDK
- iOS 27+ device or simulator
- Internet access

1. Clone the repository.
2. Open `Stocks.xcodeproj` in Xcode.
3. Select the Stocks scheme and an iOS 27 simulator or connected iPhone.
4. Set a development team under Signing if prompted.
5. Build and run.

## Project structure
- `Stocks/StocksApp.swift` — app entry point
- `Stocks/ContentView.swift` — watchlist, search, sparklines
- `Stocks/StockData.swift` — models, indicator calculations, Yahoo Finance client
- `Stocks/StockDetailView.swift` — interactive charts, technical indicators, quote metrics
- `Stocks/MassiveSettingsView.swift` — market-data information screen

## UI reference
- https://support.apple.com/guide/iphone/check-stocks-iph1ac0b1bc/27/ios
- https://support.apple.com/guide/iphone/manage-watchlists-iph4fff7afb5/27/ios
- https://developer.apple.com/design/resources/

This is a native-style recreation, not Apple's original source code or proprietary assets.
