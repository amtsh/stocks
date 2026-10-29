# Stocks for iOS

A native SwiftUI Stocks-style app for US-listed equities, using Apple's public Stocks app screens as the UI reference.

## Features
- Watchlist layout inspired by Apple's Stocks app: date heading, My Symbols, ticker/company, sparkline, quote, and change badge.
- Search US-listed equities by company name or ticker, add/remove symbols, and reorder the watchlist.
- Stock detail charts with interactive selection and ranges: 1D, 1W, 1M, 6M, 1Y, 2Y, 5Y, and 10Y.
- Details include previous close, day range, volume, exchange, and last trade time when available.
- Yahoo Finance search and chart data integration; no API key or account required.
- Automatic watchlist refresh while the app is open; watchlist persists locally.

## Market data caveats
The app uses Yahoo Finance's **unofficial, undocumented endpoints** for symbol search and chart data. Yahoo does not provide a supported public stock-quotes API. These endpoints are free to access without an API key, but they can change, become rate-limited, or stop working without notice.

**Do not treat quotes as guaranteed real-time data.** The returned price is Yahoo Finance's latest available market price, which may be delayed depending on the security and exchange. The app does not provide an exchange-level real-time guarantee. Yahoo's data is for informational use; review Yahoo's terms and restrictions before relying on or redistributing it.

Implementation notes:
- Symbol search uses /v1/finance/search and filters results to equities.
- Quotes and chart history use /v8/finance/chart/{symbol}.
- The watchlist refreshes every 15 seconds while the app is active. This is polling, not a streaming feed, and Yahoo may rate-limit repeated requests.
- Market capitalization is omitted because the chart endpoint does not reliably provide it.
- No credentials are stored or required.

## Requirements and run
- Xcode 27+ with the iOS 27 SDK
- iOS 27+ device or simulator
- Internet access

1. Clone the repository.
2. Open Stocks.xcodeproj in Xcode.
3. Select the Stocks scheme and an iOS 27 simulator or connected iPhone.
4. Set a development team under Signing if prompted.
5. Build and run.

## Project structure
- Stocks/StocksApp.swift — app entry point
- Stocks/ContentView.swift — watchlist, search, sparklines
- Stocks/StockData.swift — models and Yahoo Finance API client
- Stocks/StockDetailView.swift — interactive charts and quote metrics
- Stocks/MassiveSettingsView.swift — market-data information screen

## UI reference screenshots
Reviewed Apple's Stocks guide and screenshots for the watchlist, symbol search, interactive chart, and stock detail flow:
- https://support.apple.com/guide/iphone/check-stocks-iph1ac0b1bc/27/ios
- https://support.apple.com/guide/iphone/manage-watchlists-iph4fff7afb5/27/ios
- https://developer.apple.com/design/resources/

This is a native-style recreation, not Apple's original source code or proprietary assets.
