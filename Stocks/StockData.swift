import Foundation
import Observation
import Security

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
    case day = "1D", week = "1W", month = "1M", sixMonths = "6M", year = "1Y", twoYears = "2Y", fiveYears = "5Y", tenYears = "10Y"
    var id: String { rawValue }
    var multiplier: (unit: String, amount: Int) {
        switch self {
        case .day: ("minute", 1)
        case .week: ("minute", 5)
        case .month: ("day", 1)
        case .sixMonths: ("day", 1)
        case .year: ("day", 1)
        case .twoYears: ("week", 1)
        case .fiveYears: ("week", 1)
        case .tenYears: ("month", 1)
        }
    }
    var startDate: Date {
        let calendar = Calendar(identifier: .gregorian)
        switch self {
        case .day: calendar.date(byAdding: .day, value: -1, to: .now)!
        case .week: calendar.date(byAdding: .day, value: -5, to: .now)!
        case .month: calendar.date(byAdding: .month, value: -1, to: .now)!
        case .sixMonths: calendar.date(byAdding: .month, value: -6, to: .now)!
        case .year: calendar.date(byAdding: .year, value: -1, to: .now)!
        case .twoYears: calendar.date(byAdding: .year, value: -2, to: .now)!
        case .fiveYears: calendar.date(byAdding: .year, value: -5, to: .now)!
        case .tenYears: calendar.date(byAdding: .year, value: -10, to: .now)!
        }
    }
}
enum MarketDataError: LocalizedError {
    case missingAPIKey
    case invalidResponse
    case noData
    case unauthorized
    case provider(String)
    var errorDescription: String? {
        switch self {
        case .missingAPIKey: "Add your Massive API key in Settings to load real-time quotes."
        case .invalidResponse: "The market-data provider returned an unexpected response."
        case .noData: "No quote is available for this symbol."
        case .unauthorized: "Massive rejected this API key or plan. Check your subscription and real-time data entitlement."
        case .provider(let message): message
        }
    }
}

enum APIKeyVault {
    private static let service = "com.amtsh.StocksReplica"
    private static let account = "massive-api-key"
    static func read() -> String? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account, kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
    static func save(_ key: String) throws {
        let data = Data(key.trimmingCharacters(in: .whitespacesAndNewlines).utf8)
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
        let update: [String: Any] = [kSecValueData as String: data, kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        let status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        if status == errSecItemNotFound {
            var insert = query
            update.forEach { insert[$0.key] = $0.value }
            let addStatus = SecItemAdd(insert as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw MarketDataError.provider("Could not save API key to Keychain (\(addStatus)).") }
        } else if status != errSecSuccess {
            throw MarketDataError.provider("Could not update API key in Keychain (\(status)).")
        }
    }
    static func delete() {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
        SecItemDelete(query as CFDictionary)
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
    var apiKeyConfigured: Bool { !(APIKeyVault.read() ?? "").isEmpty }
    var symbols: [String] {
        get { UserDefaults.standard.stringArray(forKey: "watchlist.symbols") ?? ["AAPL", "NVDA", "MSFT", "GOOGL", "AMZN", "META", "TSLA"] }
        set { UserDefaults.standard.set(newValue, forKey: "watchlist.symbols") }
    }
    func quote(for symbol: String) -> StockQuote? { quotes[symbol] }
    func saveAPIKey(_ key: String) throws { try APIKeyVault.save(key); errorMessage = nil }
    func removeAPIKey() { APIKeyVault.delete(); quotes = [:]; errorMessage = nil }
    func loadWatchlist() async {
        guard apiKeyConfigured else { isSettingsPresented = true; return }
        isRefreshing = true
        defer { isRefreshing = false }
        await withTaskGroup(of: (String, StockQuote?).self) { group in
            for symbol in symbols { group.addTask { (symbol, try? await MassiveClient.fetchQuote(symbol: symbol, range: .day)) } }
            for await (symbol, quote) in group { if let quote { quotes[symbol] = quote } }
        }
        lastUpdated = Date()
        if quotes.isEmpty { errorMessage = "No quotes loaded. Check your Massive API key and real-time data plan." }
        else { errorMessage = nil }
    }
    func refresh(symbol: String, range: ChartRange = .day) async {
        do { quotes[symbol] = try await MassiveClient.fetchQuote(symbol: symbol, range: range); errorMessage = nil }
        catch { errorMessage = error.localizedDescription }
    }
    func search(_ query: String) async {
        guard apiKeyConfigured else { isSettingsPresented = true; return }
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { searchResults = []; return }
        isSearching = true
        defer { isSearching = false }
        do { searchResults = try await MassiveClient.search(query: query) }
        catch { searchResults = []; errorMessage = error.localizedDescription }
    }
    func add(_ result: StockSearchResult) async {
        guard !symbols.contains(result.symbol) else { return }
        symbols.append(result.symbol)
        await refresh(symbol: result.symbol)
    }
    func remove(_ symbol: String) { symbols.removeAll { $0 == symbol }; quotes.removeValue(forKey: symbol) }
    func clearSearch() { searchResults = [] }
    func move(from source: IndexSet, to destination: Int) {
        var reordered = symbols
        reordered.move(fromOffsets: source, toOffset: destination)
        symbols = reordered
    }
}

enum MassiveClient {
    private static let base = "https://api.massive.com"
    private static func key() throws -> String {
        guard let key = APIKeyVault.read(), !key.isEmpty else { throw MarketDataError.missingAPIKey }
        return key
    }
    private static func request(_ url: URL) async throws -> [String: Any] {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        var items = components.queryItems ?? []
        items.append(URLQueryItem(name: "apiKey", value: try key()))
        components.queryItems = items
        guard let finalURL = components.url else { throw MarketDataError.invalidResponse }
        let (data, response) = try await URLSession.shared.data(from: finalURL)
        guard let http = response as? HTTPURLResponse else { throw MarketDataError.invalidResponse }
        if http.statusCode == 401 || http.statusCode == 403 { throw MarketDataError.unauthorized }
        guard http.statusCode == 200, let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            let body = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
            throw MarketDataError.provider(body)
        }
        return object
    }
    static func fetchQuote(symbol: String, range: ChartRange) async throws -> StockQuote {
        let encoded = symbol.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? symbol
        let snapshotURL = URL(string: "\(base)/v2/snapshot/locale/us/markets/stocks/tickers/\(encoded)")!
        let snapshot = try await request(snapshotURL)
        guard let ticker = snapshot["ticker"] as? [String: Any] else { throw MarketDataError.noData }
        let day = ticker["day"] as? [String: Any] ?? [:]
        let previousDay = ticker["prevDay"] as? [String: Any] ?? [:]
        let lastTrade = ticker["lastTrade"] as? [String: Any] ?? [:]
        let lastQuote = ticker["lastQuote"] as? [String: Any] ?? [:]
        let price = (lastTrade["p"] as? NSNumber)?.doubleValue
            ?? (day["c"] as? NSNumber)?.doubleValue
            ?? ((lastQuote["p"] as? NSNumber)?.doubleValue)
            ?? 0
        guard price > 0 else { throw MarketDataError.noData }
        let previous = (previousDay["c"] as? NSNumber)?.doubleValue ?? price
        let referenceURL = URL(string: "\(base)/v3/reference/tickers/\(encoded)")!
        let reference = (try? await request(referenceURL))?["results"] as? [String: Any] ?? [:]
        let name = (reference["name"] as? String) ?? (ticker["name"] as? String) ?? symbol
        let marketTime = (lastTrade["t"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue / 1_000_000_000) }
        let start = ISO8601DateFormatter().string(from: range.startDate).prefix(10)
        let end = ISO8601DateFormatter().string(from: .now).prefix(10)
        let unit = range.multiplier.unit
        let aggsURL = URL(string: "\(base)/v2/aggs/ticker/\(encoded)/range/\(range.multiplier.amount)/\(unit)/\(start)/\(end)?adjusted=true&sort=asc&limit=5000")!
        let history: [ChartPoint]
        do {
            let aggs = try await request(aggsURL)
            let results = aggs["results"] as? [[String: Any]] ?? []
            history = results.compactMap { row in
                guard let close = (row["c"] as? NSNumber)?.doubleValue, let stamp = (row["t"] as? NSNumber)?.doubleValue else { return nil }
                return ChartPoint(date: Date(timeIntervalSince1970: stamp / 1000), value: close)
            }
        } catch {
            history = []
        }
        let details = reference
        let volume = (day["v"] as? NSNumber)?.intValue
        return StockQuote(symbol: symbol, name: name,
            exchange: (ticker["primary_exchange"] as? String) ?? (ticker["market"] as? String) ?? "US Market",
            price: price, previousClose: previous, currency: "USD", points: history,
            marketTime: marketTime, dayHigh: (day["h"] as? NSNumber)?.doubleValue,
            dayLow: (day["l"] as? NSNumber)?.doubleValue, volume: volume,
            marketCap: (details["market_cap"] as? NSNumber)?.doubleValue)
    }
    static func search(query: String) async throws -> [StockSearchResult] {
        var components = URLComponents(string: "\(base)/v3/reference/tickers")!
        components.queryItems = [
            URLQueryItem(name: "search", value: query),
            URLQueryItem(name: "market", value: "stocks"),
            URLQueryItem(name: "active", value: "true"),
            URLQueryItem(name: "limit", value: "20"),
            URLQueryItem(name: "sort", value: "ticker"),
            URLQueryItem(name: "order", value: "asc")
        ]
        guard let url = components.url else { throw MarketDataError.invalidResponse }
        let response = try await request(url)
        let items = response["results"] as? [[String: Any]] ?? []
        return items.compactMap { item in
            guard let symbol = item["ticker"] as? String,
                  (item["market"] as? String) == "stocks",
                  (item["type"] as? String) == "CS" || (item["type"] as? String) == "ADRC" else { return nil }
            return StockSearchResult(symbol: symbol, name: (item["name"] as? String) ?? symbol,
                exchange: (item["primary_exchange"] as? String) ?? "US Market")
        }
    }
}