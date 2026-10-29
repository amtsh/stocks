# Data Reliability Audit

Date: 2026-10-29

## Summary
The current Yahoo Finance integration is useful for a personal research prototype, but it is not suitable as a source of guaranteed real-time prices or for automated trade execution. Yahoo's public chart/search endpoints are unofficial and have no contract-level uptime or latency guarantee.

## Findings

- **High — no real-time guarantee:** quote timestamps are provider metadata; the client cannot verify exchange delivery latency or whether the quote is delayed.
- **High — unofficial endpoint dependency:** the app relies on undocumented endpoints that can be throttled or changed.
- **Medium — aggressive polling:** watchlist refreshes every 15 seconds and fans out requests concurrently. Rate limiting is likely under load.
- **Medium — no cross-source validation:** valid-looking prices can be stale or wrong without an independent comparison.
- **Medium — market-session semantics:** regular-market price and previous close are displayed without a robust regular/pre/post-market state.
- **Medium — incomplete fundamentals:** market capitalization and valuation metrics are not provided by the current chart response.
- **Medium — indicators depend on history quality:** missing bars, splits, and adjustment policy can affect technical indicators. The current RSI is a simple-window approximation rather than Wilder's canonical smoothing.
- **Open — alerts:** no price-alert feature exists; reliable alerts need persisted rules, defined trigger price semantics, and background delivery.

## Implemented in this branch
- Daily-close-based SMA (20/50/200), RSI (14), MACD (12,26), and MACD signal (9) displayed on the detail screen.
- Invalid/non-positive prices are rejected and chart points are sorted chronologically.
- Quote timestamp is surfaced, and unavailable market cap is labeled as unavailable rather than a numeric placeholder.
- README documents the remaining limitations and required production safeguards.

## Recommended next steps
1. Select a licensed provider with documented US equity entitlements and explicit latency guarantees if intraday reliability is a hard requirement.
2. Add a dedicated market-data adapter and provider contract tests before switching providers.
3. Implement request throttling, exponential backoff, stale-quote detection, and observable request/error metrics.
4. Add unit tests using known price series for SMA, RSI, EMA/MACD, invalid bars, and insufficient history.
5. Add fundamentals (P/E, EPS, revenue growth, margins, debt, cash flow, earnings date) only from fields with clear source timestamps and semantics.
6. Add price alerts after quote reliability is addressed; specify last trade vs bid/ask vs delayed close, persistence, and notification behavior.

No market data is guaranteed real-time. This app is for informational research only, not investment advice.
