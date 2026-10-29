# Stocks for iOS

A native SwiftUI recreation of the Apple Stocks watchlist experience, focused on US-listed equities.

## Features
- Native iPhone/iPad interface using SwiftUI and current system navigation/material conventions.
- Watchlist with quotes, daily change, percentage change, and sparklines.
- Search US-listed stocks, add/remove symbols, and reorder the watchlist.
- Stock detail charts for 1D, 1W, 1M, 6M, 1Y, and 5Y, plus key quote details.
- Local watchlist persistence, light/dark appearance, automatic 30-second refresh while open.

## Market-data limitation
The app uses Yahoo Finance's public chart/search endpoints. This is **not a guaranteed real-time feed**: delays, availability, refresh limits, and exchange coverage are controlled by Yahoo and may vary. The UI identifies this limitation. Do not use it for trading decisions.

For contractually real-time US exchange quotes, integrate a licensed provider whose plan explicitly includes real-time US equities. Keep provider credentials server-side, never in a distributed iOS app.

Search filters to US equity exchange codes and excludes ETFs, indices, currencies, and other instrument types.

## Requirements and run
- Xcode 27+ with the iOS 27 SDK
- iOS 27+ device or simulator
- Internet connection

1. Clone the repository.
2. Open `Stocks.xcodeproj` in Xcode.
3. Select the Stocks scheme and an iOS 27 simulator or connected iPhone.
4. Set a development team under Signing if prompted.
5. Build and run.

No API key is required for the current public Yahoo integration. The endpoint is unofficial and can change or rate-limit requests.

## Structure
- `Stocks/StocksApp.swift` — app entry point
- `Stocks/ContentView.swift` — watchlist and search
- `Stocks/StockData.swift` — models, persistence, market-data client
- `Stocks/StockDetailView.swift` — chart and quote details

## Design reference
Based on public Apple Stocks user-guide patterns: symbol/name, sparkline, quote and change; searchable symbols; chart ranges and detail metrics. Apple's proprietary assets are not bundled.

- https://support.apple.com/guide/iphone/check-stocks-iph1ac0b1bc/27/ios
- https://support.apple.com/guide/iphone/manage-watchlists-iph4fff7afb5/27/ios
