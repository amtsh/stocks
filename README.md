# Stocks for iOS

A native SwiftUI Stocks-style app for US-listed equities, using Apple's public Stocks app screens as the UI reference.

## Features
- Watchlist layout inspired by Apple's current Stocks app: date heading, My Symbols, ticker/company, sparkline, quote, and change badge.
- Search US common stocks, add/remove symbols, and reorder the watchlist.
- Stock detail charts with interactive selection and ranges: 1D, 1W, 1M, 6M, 1Y, 2Y, 5Y, and 10Y.
- Details include previous close, day range, volume, market cap when available, exchange, and last trade time.
- Massive market-data integration. API key is stored in iOS Keychain; never embedded in source.
- Automatic refresh while app is open; watchlist persists locally.

## Real-time data: important setup
This app integrates Massive's US equities API. **A live quote is only available if your Massive account has the appropriate real-time entitlement.** The provider lists Stocks Advanced at $199/month for individual, non-professional use; lower tiers may return 15-minute delayed data. Check current terms, exchange entitlements, and your use classification before subscribing.

1. Create a Massive account and choose a plan that explicitly includes real-time US stock data: https://massive.com/stocks
2. Create an API key in the provider dashboard.
3. Run the app, tap the gear icon, and paste the key into Market Data settings. The key is saved in this device's Keychain.
4. Confirm that your subscription grants the real-time snapshot endpoint. A valid API key by itself does not guarantee real-time prices.

The app uses REST snapshots and historical aggregates, refreshing the watchlist every 15 seconds while active. It does not claim exchange-grade streaming tick updates; this implementation is real-time REST polling, subject to provider latency and plan terms. Quotes are for informational use only.

## Requirements and run
- Xcode 27+ with the iOS 27 SDK
- iOS 27+ device or simulator
- Internet access
- Massive API key with an appropriate plan for real-time quotes

1. Clone the repository.
2. Open `Stocks.xcodeproj` in Xcode.
3. Select the Stocks scheme and an iOS 27 simulator or connected iPhone.
4. Set a development team under Signing if prompted.
5. Build and run.

## Project structure
- `Stocks/StocksApp.swift` — app entry point
- `Stocks/ContentView.swift` — watchlist, search, sparklines
- `Stocks/StockData.swift` — models, Keychain, Massive API client
- `Stocks/StockDetailView.swift` — interactive charts and quote metrics
- `Stocks/MassiveSettingsView.swift` — secure API-key setup

## UI reference screenshots
Reviewed Apple Support's current iOS Stocks guide and screenshots for the watchlist, symbol search, interactive chart, and stock detail flow:
- https://support.apple.com/guide/iphone/check-stocks-iph1ac0b1bc/27/ios
- https://support.apple.com/guide/iphone/manage-watchlists-iph4fff7afb5/27/ios
- https://developer.apple.com/design/resources/

This is a faithful native-style recreation, not Apple's original source code or proprietary assets.
