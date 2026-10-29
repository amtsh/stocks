import Foundation
import Observation

struct StockQuote: Identifiable, Hashable, Sendable {
    let symbol: String
    var name: String
    var exchange: String
    var price: Double
    var previousClose: Double
    var currency: String
    var points: [ChartPoint] = []
    var marketTime: Date?
    var dayHigh: Double?
    var dayLow: Double?
    var volume: Int?
    var marketCap: Double?
    var fiftyTwoWeekHigh: Double?
    var fiftyTwoWeekLow: Double?

    var id: String { symbol }
    var change: Double { price - previousClose }
    var changePercent: Double { previousClose == 0 ? 0 : change / previousClose * 100 }
    var isPositive: Bool { change >= 0 }
    var formattedPrice: String { price.formatted(.currency(code: currency).precision(.fractionLength(2))) }
    var formattedChange: String {
        "\(change >= 0 ? "+" : "−")\(abs(change).formatted(.number.precision(.fractionLength(2)))) (\(changePercent >= 0 ? "+" : "−")\(abs(changePercent).formatted(.number.precision(.fractionLength(2)))%)"
    }
}

struct ChartPoint: Identifiable, Hashable, Sendable {
    let date: Date
    let value: Double
    var id: Date { date }
}

/// Indicators are calculated locally from daily closes; they are not provider-supplied signals.
struct TechnicalIndicators: Sendable {
    let sma20: Double?
    let sma50: Double?
    let sma200: Double?
    let rsi14: Double?
    let macd: Double?
    let macdSignal: Double?
    let observationCount: Int

    init(points: [ChartPoint]) {
        let closes = points.sorted { $0.date < $1.date }.map(\.value).filter { $0.isFinite && $0 > 0 }
        observationCount = closes.count
        sma20 = Self.average(closes, period: 20)
        sma50 = Self.average(closes, period: 50)
        sma200 = Self.average(closes, period: 200)
        rsi14 = Self.rsi(closes, period: 14)
        let fast = Self.emaSeries(closes, period: 12)
        let slow = Self.emaSeries(closes, period: 26)
        let macdSeries = zip(fast.dropFirst(14), slow).map { $0.0 - $0.1 }
        macd = macdSeries.last
        macdSignal = Self.emaSeries(macdSeries, period: 9).last
    }

    private static func average(_ values: [Double], period: Int) -> Double? {
        guard values.count >= period else { return nil }
        return values.suffix(period).reduce(0, +) / Double(period)
    }

    private static func emaSeries(_ values: [Double], period: Int) -> [Double] {
        guard values.count >= period else { return [] }
        let multiplier = 2.0 / (Double(period) + 1)
        var result = [values.prefix(period).reduce(0, +) / Double(period)]
        for value in values.dropFirst(period) {
            result.append(value * multiplier + result[result.count - 1] * (1 - multiplier))
        }
        return result
    }

    private static func rsi(_ values: [Double], period: Int) -> Double? {
        guard values.count > period else { return nil }
        let changes = zip(values.dropFirst(), values).map { $0.0 - $0.1 }
        let window = changes.suffix(period)
        let gains = window.filter { $0 > 0 }.reduce(0, +) / Double(period)
        let losses = window.filter { $0 < 0 }.reduce(0) { $0 + abs($1) } / Double(period)
        if losses == 0 { return gains == 0 ? 50 : 100 }
        return 100 - (100 / (1 + gains / losses))
    }
}

struct StockSearchResult: Identifiable, Hashable, Sendable {
    let symbol: String
    let name: String
    let exchange: String
    var id: String { symbol }
}

enum ChartRange: String, CaseIterable, Identifiable, Sendable {
    case day = "1D", week = "1W", month = "1M", sixMonths = "6M", year = "1Y", twoYears = "2Y", fiveYears = "5Y", tenYears = "10Y"
    var id: String { rawValue }

    var yahooRange: String {
        switch self {
        case .day: "1d"
        case .week: "5d"
        case .month: "1mo"
        case .sixMonths: "6mo"
        case .year: "1y"
        case .twoYears: "2y"
        case .fiveYears: "5y"
        case .tenYears: "10y"
        }
    }

    var yahooInterval: String {
        switch self {
        case .day: "1m"
        case .week: "5m"
        case .month: "30m"
        case .sixMonths, .year: "1d"
        case .twoYears, .fiveYears: "1wk"
        case .tenYears: "1mo"
        }
    }
}

enum MarketDataError: LocalizedError {
    case invalidResponse
    case noData
    case provider(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse: "Yahoo Finance returned an unexpected response."
        case .noData: "No quote is available for this symbol."
        case .provider(let message): message
        }
    }
}

@MainActor @Observable
final class MarketStore {
    private(set) var quotes: [String: StockQuote] = [:]
    private(set) var searchResults: [StockSearchResult] = []
    private(set) var isSearching = false
    private(set) var isRefreshing = false
    private(set) var lastUpdated: Date?
    var errorMessage: String?
    var isSettingsPresented = false

    var symbols: [String] {
        get { UserDefaults.standard.stringArray(forKey: "watchlist.symbols") ?? ["AAPL", "NVDA", "MSFT", "GOOGL", "AMZN", "META", "TSLA"] }
        set { UserDefaults.standard.set(newValue, forKey: "watchlist.symbols") }
    }

    func quote(for symbol: String) -> StockQuote? { quotes[symbol] }

    func loadWatchlist() async {
        isRefreshing = true
        defer { isRefreshing = false }
        await withTaskGroup(of: (String, StockQuote?).self) { group in
            for symbol in symbols {
                group.addTask { (symbol, try? await YahooFinanceClient.fetchQuote(symbol: symbol, range: .day)) }
            }
            for await (symbol, quote) in group {
                if let quote { quotes[symbol] = quote }
            }
        }
        lastUpdated = Date()
        if quotes.isEmpty {
            errorMessage = "No quotes loaded. Yahoo Finance may be temporarily unavailable or rate-limiting requests."
        } else {
            errorMessage = nil
        }
    }

    func refresh(symbol: String, range: ChartRange = .day) async {
        do {
            quotes[symbol] = try await YahooFinanceClient.fetchQuote(symbol: symbol, range: range)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func search(_ query: String) async {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { searchResults = []; return }
        isSearching = true
        defer { isSearching = false }
        do {
            searchResults = try await YahooFinanceClient.search(query: query)
        } catch {
            searchResults = []
            errorMessage = error.localizedDescription
        }
    }

    func add(_ result: StockSearchResult) async {
        guard !symbols.contains(result.symbol) else { return }
        symbols.append(result.symbol)
        await refresh(symbol: result.symbol)
    }

    func remove(_ symbol: String) {
        symbols.removeAll { $0 == symbol }
        quotes.removeValue(forKey: symbol)
    }

    func clearSearch() { searchResults = [] }

    func move(from source: IndexSet, to destination: Int) {
        var reordered = symbols
        reordered.move(fromOffsets: source, toOffset: destination)
        symbols = reordered
    }
}

enum YahooFinanceClient {
    private static let base = "https://query1.finance.yahoo.com"

    private static func request(_ url: URL) async throws -> [String: Any] {
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue("StocksPersonalApp/1.0", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw MarketDataError.invalidResponse }
        guard http.statusCode == 200 else {
            if http.statusCode == 429 {
                throw MarketDataError.provider("Yahoo Finance is rate-limiting requests. Wait a moment and try again.")
            }
            throw MarketDataError.provider("Yahoo Finance returned HTTP \(http.statusCode). The unofficial endpoint may be temporarily unavailable.")
        }
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw MarketDataError.invalidResponse
        }
        return object
    }

    static func fetchQuote(symbol: String, range: ChartRange) async throws -> StockQuote {
        var components = URLComponents(string: "\(base)/v8/finance/chart/\(symbol.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? symbol)")!
        components.queryItems = [
            URLQueryItem(name: "range", value: range.yahooRange),
            URLQueryItem(name: "interval", value: range.yahooInterval),
            URLQueryItem(name: "events", value: "div,splits")
        ]
        guard let url = components.url else { throw MarketDataError.invalidResponse }
        let response = try await request(url)
        guard let chart = response["chart"] as? [String: Any] else { throw MarketDataError.invalidResponse }
        if let error = chart["error"], !(error is NSNull) {
            let message = (error as? [String: Any])?["description"] as? String ?? "Unable to find this ticker."
            throw MarketDataError.provider(message)
        }
        guard let result = (chart["result"] as? [[String: Any]])?.first,
              let meta = result["meta"] as? [String: Any] else {
            throw MarketDataError.noData
        }

        let price = (meta["regularMarketPrice"] as? NSNumber)?.doubleValue
            ?? (meta["chartPreviousClose"] as? NSNumber)?.doubleValue
            ?? 0
        guard price.isFinite, price > 0 else { throw MarketDataError.noData }
        let previousClose = (meta["previousClose"] as? NSNumber)?.doubleValue
            ?? (meta["chartPreviousClose"] as? NSNumber)?.doubleValue
            ?? price
        let timestamps = (result["timestamp"] as? [NSNumber] ?? []).map(\.doubleValue)
        let quoteBlock = ((result["indicators"] as? [String: Any])?["quote"] as? [[String: Any]])?.first ?? [:]
        let closes = quoteBlock["close"] as? [Any] ?? []
        let points = zip(timestamps, closes).compactMap { (timestamp, rawValue) -> ChartPoint? in
            guard let value = rawValue as? NSNumber, value.doubleValue.isFinite, value.doubleValue > 0 else { return nil }
            return ChartPoint(date: Date(timeIntervalSince1970: timestamp), value: value.doubleValue)
        }.sorted { $0.date < $1.date }
        let currency = (meta["currency"] as? String).flatMap { $0.count == 3 ? $0 : nil } ?? "USD"
        let marketTime = (meta["regularMarketTime"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue) }
        let name = (meta["longName"] as? String) ?? (meta["shortName"] as? String) ?? symbol
        let exchange = (meta["fullExchangeName"] as? String) ?? (meta["exchangeName"] as? String) ?? "US Market"
        let dayHigh = (meta["regularMarketDayHigh"] as? NSNumber)?.doubleValue
        let dayLow = (meta["regularMarketDayLow"] as? NSNumber)?.doubleValue
        let volume = (meta["regularMarketVolume"] as? NSNumber)?.intValue
        let fiftyTwoWeekHigh = (meta["fiftyTwoWeekHigh"] as? NSNumber)?.doubleValue
        let fiftyTwoWeekLow = (meta["fiftyTwoWeekLow"] as? NSNumber)?.doubleValue

        return StockQuote(
            symbol: symbol.uppercased(),
            name: name,
            exchange: exchange,
            price: price,
            previousClose: previousClose,
            currency: currency,
            points: points,
            marketTime: marketTime,
            dayHigh: dayHigh,
            dayLow: dayLow,
            volume: volume,
            marketCap: nil,
            fiftyTwoWeekHigh: fiftyTwoWeekHigh,
            fiftyTwoWeekLow: fiftyTwoWeekLow
        )
    }

    static func search(query: String) async throws -> [StockSearchResult] {
        var components = URLComponents(string: "\(base)/v1/finance/search")!
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "quotesCount", value: "25"),
            URLQueryItem(name: "newsCount", value: "0"),
            URLQueryItem(name: "enableFuzzyQuery", value: "true")
        ]
        guard let url = components.url else { throw MarketDataError.invalidResponse }
        let response = try await request(url)
        let quotes = response["quotes"] as? [[String: Any]] ?? []
        return quotes.compactMap { item in
            guard let symbol = item["symbol"] as? String,
                  (item["quoteType"] as? String) == "EQUITY" else { return nil }
            let name = (item["longname"] as? String) ?? (item["shortname"] as? String) ?? symbol
            let exchange = (item["exchDisp"] as? String) ?? (item["exchange"] as? String) ?? "US Market"
            return StockSearchResult(symbol: symbol, name: name, exchange: exchange)
        }
    }
}
