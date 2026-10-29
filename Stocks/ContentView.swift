import SwiftUI

struct ContentView: View {
    @Environment(MarketStore.self) private var market
    @State private var searchText = ""
    @State private var isSearchPresented = false
    @State private var searchTask: Task<Void, Never>?

    private var searchMatches: [StockSearchResult] {
        market.searchResults.filter { !market.symbols.contains($0.symbol) }
    }

    /// Estimates the regular US equity session in New York time.
    /// This schedule check does not account for exchange holidays or early closes.
    private var isUSMarketOpen: Bool {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York") ?? .current
        let now = Date()
        let weekday = calendar.component(.weekday, from: now)
        let minutes = calendar.component(.hour, from: now) * 60 + calendar.component(.minute, from: now)
        return (2...6).contains(weekday) && minutes >= 9 * 60 + 30 && minutes < 16 * 60
    }

    private var headerDate: String {
        Date.now.formatted(.dateTime.day().month(.wide).locale(Locale(identifier: "en_GB")))
    }

    var body: some View {
        NavigationStack {
            List {
                if isSearchPresented {
                    searchSection
                } else if market.symbols.isEmpty {
                    ContentUnavailableView {
                        Label("Your watchlist is empty", systemImage: "chart.line.uptrend.xyaxis")
                    } description: {
                        Text("Search for a company or ticker to start tracking stocks.")
                    } actions: {
                        Button("Search stocks") {
                            isSearchPresented = true
                        }
                    }
                    .listRowBackground(Color.clear)
                } else {
                    Section {
                        ForEach(market.symbols, id: \.self) { symbol in
                            stockRow(for: symbol)
                        }
                        .onMove(perform: market.move)
                    }

                    Section {
                        if let updated = market.lastUpdated {
                            Text("Last updated \(updated.formatted(date: .omitted, time: .shortened))")
                                .listRowSeparator(.hidden, edges: .all)
                        }
                        if let error = market.errorMessage {
                            Text(error)
                                .foregroundStyle(.red)
                                .listRowSeparator(.hidden, edges: .all)
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .listSectionSeparator(.hidden, edges: .bottom)
                }
            }
            .listStyle(.plain)
            .navigationTitle(headerDate)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 7) {
                        Text(headerDate)
                            .font(.headline)
                        Circle()
                            .fill(isUSMarketOpen ? Color.green : Color.red)
                            .frame(width: 8, height: 8)
                            .accessibilityLabel(isUSMarketOpen ? "US market open" : "US market closed")
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            .navigationDestination(for: String.self) { symbol in
                StockDetailView(symbol: symbol)
            }
            .searchable(
                text: $searchText,
                isPresented: $isSearchPresented,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "Search stocks"
            )
            .onChange(of: searchText) { _, query in
                searchTask?.cancel()
                searchTask = Task {
                    try? await Task.sleep(for: .milliseconds(250))
                    guard !Task.isCancelled else { return }
                    await market.search(query)
                }
            }
            .onChange(of: isSearchPresented) { _, isPresented in
                if !isPresented {
                    searchText = ""
                    market.clearSearch()
                }
            }
            .task {
                await market.loadWatchlist()
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(60))
                    if !Task.isCancelled {
                        await market.loadWatchlist()
                    }
                }
            }
            .onDisappear {
                searchTask?.cancel()
            }
        }
    }

    @ViewBuilder
    private var searchSection: some View {
        Section {
            if market.isSearching {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
            } else if searchText.isEmpty {
                ContentUnavailableView(
                    "Find a stock",
                    systemImage: "magnifyingglass",
                    description: Text("Search by company name or ticker.")
                )
            } else if searchMatches.isEmpty {
                ContentUnavailableView.search(text: searchText)
            } else {
                ForEach(searchMatches) { result in
                    Button {
                        Task {
                            await market.add(result)
                        }
                        isSearchPresented = false
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(result.symbol)
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                                Text(result.name)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            Text(result.exchange)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func stockRow(for symbol: String) -> some View {
        if let stock = market.quote(for: symbol) {
            NavigationLink(value: symbol) {
                StockRow(stock: stock)
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                Button(role: .destructive) {
                    market.remove(symbol)
                } label: {
                    Label("Remove", systemImage: "trash")
                }
            }
        } else {
            HStack {
                Text(symbol)
                    .font(.headline)
                Spacer()
                ProgressView()
            }
        }
    }
}

private struct StockRow: View {
    let stock: StockQuote

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(stock.symbol)
                    .font(.headline)
                Text(stock.name)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 4) {
                Text(stock.formattedPrice)
                    .font(.headline.monospacedDigit())
                Text(stock.formattedChange)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(stock.isPositive ? .green : .red)
            }
        }
        .padding(.vertical, 4)
    }
}