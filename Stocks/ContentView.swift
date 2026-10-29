import SwiftUI

struct ContentView: View {
    @Environment(MarketStore.self) private var market
    @State private var searchText = ""
    @State private var isSearchPresented = false
    @State private var selectedSymbol: String?
    @State private var searchTask: Task<Void, Never>?
    private var searchMatches: [StockSearchResult] { market.searchResults.filter { !market.symbols.contains($0.symbol) } }

    var body: some View {
        NavigationStack {
            List {
                if isSearchPresented { searchSection }
                else {
                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("US Market").font(.headline)
                                Spacer()
                                if market.isRefreshing { ProgressView().controlSize(.small) }
                                else { Text("Updated \(market.lastUpdated?.formatted(date: .omitted, time: .shortened) ?? "—")").font(.caption2).foregroundStyle(.secondary) }
                            }
                            HStack(spacing: 6) {
                                Circle().fill(.green).frame(width: 7, height: 7)
                                Text("US-listed stocks").font(.subheadline).foregroundStyle(.secondary)
                                Spacer()
                                Text("USD").font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                            }
                        }.padding(.vertical, 6).listRowSeparator(.hidden).listRowBackground(Color.clear)
                    }
                    Section {
                        ForEach(market.symbols, id: \.self) { symbol in
                            if let stock = market.quote(for: symbol) {
                                NavigationLink(value: symbol) { StockRow(stock: stock) }
                                    .listRowInsets(EdgeInsets(top: 10, leading: 0, bottom: 10, trailing: 0))
                                    .swipeActions {
                                        Button(role: .destructive) { market.remove(symbol) } label: { Label("Remove", systemImage: "trash") }
                                    }
                            } else {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) { Text(symbol).font(.headline); Text("Loading quote…").font(.caption).foregroundStyle(.secondary) }
                                    Spacer(); ProgressView().controlSize(.small)
                                }.padding(.vertical, 10).listRowSeparator(.hidden)
                            }
                        }.onMove(perform: market.move)
                    } header: {
                        HStack { Text("MY WATCHLIST"); Spacer(); Text("PRICE") }
                            .font(.caption2.weight(.semibold)).tracking(0.7).foregroundStyle(.secondary).textCase(nil).padding(.top, 8)
                    }
                    Section {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Quotes provided by Yahoo Finance.").font(.caption2)
                            Text("Market data may be delayed. Refreshes every 30 seconds while open.").font(.caption2)
                            if let error = market.errorMessage { Text(error).font(.caption2).foregroundStyle(.red) }
                        }.foregroundStyle(.tertiary).padding(.vertical, 12).listRowSeparator(.hidden).listRowBackground(Color.clear)
                    }
                }
            }
            .listStyle(.plain).scrollContentBackground(.hidden).background(Color(uiColor: .systemBackground))
            .navigationTitle(isSearchPresented ? "Search" : "Stocks").navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        withAnimation(.snappy) { isSearchPresented.toggle(); searchText = "" }
                    } label: { Image(systemName: isSearchPresented ? "xmark" : "magnifyingglass").font(.system(size: 17, weight: .semibold)) }
                        .accessibilityLabel(isSearchPresented ? "Close search" : "Search stocks")
                }
                if !isSearchPresented { ToolbarItem(placement: .topBarTrailing) { EditButton() } }
            }
            .navigationDestination(for: String.self) { symbol in StockDetailView(symbol: symbol) }
            .task {
                await market.loadWatchlist()
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(30))
                    if !Task.isCancelled { await market.loadWatchlist() }
                }
            }
        }.tint(.primary)
    }
    private var searchSection: some View {
        Section {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Company or ticker", text: $searchText)
                    .textInputAutocapitalization(.characters).autocorrectionDisabled()
                    .onChange(of: searchText) { _, query in
                        searchTask?.cancel()
                        searchTask = Task {
                            try? await Task.sleep(for: .milliseconds(250))
                            guard !Task.isCancelled else { return }
                            await market.search(query)
                        }
                    }
            }.padding(.vertical, 8)
            if market.isSearching { HStack { Spacer(); ProgressView(); Spacer() }.listRowSeparator(.hidden) }
            else if searchText.isEmpty {
                ContentUnavailableView("Find a stock", systemImage: "magnifyingglass", description: Text("Search US-listed companies by name or ticker.")).listRowSeparator(.hidden)
            } else if searchMatches.isEmpty { ContentUnavailableView.search(text: searchText).listRowSeparator(.hidden) }
            else {
                ForEach(searchMatches) { result in
                    Button {
                        Task { await market.add(result) }
                        withAnimation { isSearchPresented = false; searchText = "" }
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(result.symbol).font(.headline).foregroundStyle(.primary)
                                Text(result.name).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer()
                            Image(systemName: "plus.circle.fill").font(.title3).foregroundStyle(.blue)
                        }.padding(.vertical, 5)
                    }.buttonStyle(.plain)
                }
            }
        }
    }
}
private struct StockRow: View {
    let stock: StockQuote
    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(stock.symbol).font(.system(size: 17, weight: .semibold)).foregroundStyle(.primary)
                Text(stock.name).font(.system(size: 13)).foregroundStyle(.secondary).lineLimit(1)
                Text(stock.formattedChange).font(.system(size: 12, weight: .medium)).foregroundStyle(stock.isPositive ? .green : .red)
            }
            Spacer(minLength: 8)
            Sparkline(points: stock.points, positive: stock.isPositive).frame(width: 72, height: 34)
            VStack(alignment: .trailing, spacing: 4) {
                Text(stock.formattedPrice).font(.system(size: 16, weight: .semibold, design: .rounded).monospacedDigit()).foregroundStyle(.primary)
                Text("\(stock.changePercent >= 0 ? "+" : "")\(stock.changePercent.formatted(.number.precision(.fractionLength(2))))%")
                    .font(.system(size: 12, weight: .medium).monospacedDigit()).foregroundStyle(stock.isPositive ? .green : .red)
            }.frame(minWidth: 95, alignment: .trailing)
        }.contentShape(Rectangle())
    }
}
private struct Sparkline: View {
    let points: [ChartPoint]
    let positive: Bool
    var body: some View {
        GeometryReader { geometry in
            if points.count > 1 {
                let values = points.map(\.value)
                let low = values.min() ?? 0
                let spread = max((values.max() ?? 1) - low, 0.0001)
                Path { path in
                    for (index, point) in points.enumerated() {
                        let x = geometry.size.width * CGFloat(index) / CGFloat(points.count - 1)
                        let y = geometry.size.height * (1 - CGFloat((point.value - low) / spread))
                        if index == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
                    }
                }.stroke(positive ? Color.green : Color.red, style: StrokeStyle(lineWidth: 1.7, lineCap: .round, lineJoin: .round))
            } else {
                Path { path in path.move(to: CGPoint(x: 0, y: geometry.size.height * 0.65)); path.addLine(to: CGPoint(x: geometry.size.width, y: geometry.size.height * 0.35)) }
                    .stroke(Color.secondary.opacity(0.5), lineWidth: 1.5)
            }
        }
    }
}