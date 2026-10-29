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
struct StockSearchResult: Identifiable, Hashable, Sendable {
    let symbol: String
    let name: String
    let exchange: String
    var id: String { symbol }
}
enum ChartRange: String, CaseIterable, Identifiable, Sendable {
    case day = "1D", week = "1W", month = "1M", sixMonths = "6M", year = "1Y", fiveYears = "5Y"
    var id: String { rawValue }
    var queryRange: String {
        switch self { case .day: "1d"; case .week: "5d"; case .month: "1mo"; case .sixMonths: "6mo"; case .year: "1y"; case .fiveYears: "5y" }
    }
    var interval: String {
        switch self { case .day: "5m"; case .week: "30m"; case .month, .sixMonths: "1d"; case .year: "1wk"; case .fiveYears: "1mo" }
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
    var symbols: [String] {
        get { UserDefaults.standard.stringArray(forKey: "watchlist.symbols") ?? ["AAPL", "NVDA", "MSFT", "GOOGL", "AMZN", "META", "TSLA"] }
        set { UserDefaults.standard.set(newValue, forKey: "watchlist.symbols") }
    }
    func quote(for symbol: String) -> StockQuote? { quotes[symbol] }
    func loadWatchlist() async {
        isRefreshing = true
        defer { isRefreshing = false }
        await withTaskGroup(of: (String, StockQuote?).self) { group in
            for symbol in symbols { group.addTask { (symbol, try? await YahooFinanceClient.fetchQuote(symbol: symbol, range: .day)) } }
            for await (symbol, quote) in group { if let quote { quotes[symbol] = quote } }
        }
        lastUpdated = Date()
    }
    func refresh(symbol: String, range: ChartRange = .day) async {
        do { quotes[symbol] = try await YahooFinanceClient.fetchQuote(symbol: symbol, range: range); errorMessage = nil }
        catch { errorMessage = error.localizedDescription }
    }
    func search(_ query: String) async {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { searchResults = []; return }
        isSearching = true
        defer { isSearching = false }
        do { searchResults = try await YahooFinanceClient.search(query: query) }
        catch { searchResults = []; errorMessage = error.localizedDescription }
    }
    func add(_ result: StockSearchResult) async {
        guard !symbols.contains(result.symbol) else { return }
        symbols.append(result.symbol)
        await refresh(symbol: result.symbol)
    }
    func remove(_ symbol: String) { symbols.removeAll { $0 == symbol }; quotes.removeValue(forKey: symbol) }
    func move(from source: IndexSet, to destination: Int) {
        var reordered = symbols
        reordered.move(fromOffsets: source, toOffset: destination)
        symbols = reordered
    }
}
enum YahooFinanceClient {
    private static let allowedExchanges: Set<String> = ["NMS", "NGM", "NCM", "NYQ", "ASE", "PCX", "BTS", "BATS", "NAS", "NASDAQ", "NYSE"]
    static func fetchQuote(symbol: String, range: ChartRange) async throws -> StockQuote {
        guard let escaped = symbol.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "https://query1.finance.yahoo.com/v8/finance/chart/\(escaped)?range=\(range.queryRange)&interval=\(range.interval)&includePrePost=true") else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.setValue("StocksReplica/1.0", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let chart = root["chart"] as? [String: Any],
              let result = (chart["result"] as? [[String: Any]])?.first,
              let meta = result["meta"] as? [String: Any] else { throw URLError(.badServerResponse) }
        let price = (meta["regularMarketPrice"] as? NSNumber)?.doubleValue ?? 0
        let previous = (meta["previousClose"] as? NSNumber)?.doubleValue ?? (meta["chartPreviousClose"] as? NSNumber)?.doubleValue ?? price
        let timestamps = result["timestamp"] as? [TimeInterval] ?? []
        let quoteData = ((result["indicators"] as? [String: Any])?["quote"] as? [[String: Any]])?.first
        let closes = quoteData?["close"] as? [Any] ?? []
        let points = zip(timestamps, closes).compactMap { stamp, value -> ChartPoint? in
            guard let number = value as? NSNumber, number.doubleValue > 0 else { return nil }
            return ChartPoint(date: Date(timeIntervalSince1970: stamp), value: number.doubleValue)
        }
        return StockQuote(symbol: symbol,
            name: (meta["longName"] as? String) ?? (meta["shortName"] as? String) ?? symbol,
            exchange: (meta["fullExchangeName"] as? String) ?? (meta["exchangeName"] as? String) ?? "US Market",
            price: price, previousClose: previous, currency: (meta["currency"] as? String) ?? "USD",
            points: points, marketTime: (meta["regularMarketTime"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue) })
    }
    static func search(query: String) async throws -> [StockSearchResult] {
        var components = URLComponents(string: "https://query1.finance.yahoo.com/v1/finance/search")!
        components.queryItems = [URLQueryItem(name: "q", value: query), URLQueryItem(name: "quotesCount", value: "12"), URLQueryItem(name: "newsCount", value: "0")]
        let (data, response) = try await URLSession.shared.data(from: components.url!)
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = root["quotes"] as? [[String: Any]] else { throw URLError(.badServerResponse) }
        return items.compactMap { item in
            guard let symbol = item["symbol"] as? String, let exchange = item["exchange"] as? String,
                  allowedExchanges.contains(exchange.uppercased()), (item["quoteType"] as? String) == "EQUITY" else { return nil }
            return StockSearchResult(symbol: symbol, name: (item["shortname"] as? String) ?? (item["longname"] as? String) ?? symbol, exchange: exchange)
        }
    }
}