import SwiftUI

struct ContentView: View {
    @Environment(MarketStore.self) private var market
    @State private var searchText = ""
    @State private var isSearchPresented = false
    @State private var searchTask: Task<Void, Never>?
    @FocusState private var searchFocused: Bool
    @State private var showEdit = false

    private var searchMatches: [StockSearchResult] { market.searchResults.filter { !market.symbols.contains($0.symbol) } }

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
        Date.now.formatted(.dateTime.day().month(.wide).locale(Locale(identifier: "en_GB")) )
    }

    var body: some View {
        NavigationStack {
            List {
                if isSearchPresented {
                    searchSection
                } else if market.symbols.isEmpty {
                    Section {
                        VStack(spacing: 14) {
                            Image(systemName: "chart.line.uptrend.xyaxis")
                                .font(.system(size: 42, weight: .light))
                                .foregroundStyle(.secondary)
                            Text("Your watchlist is empty")
                                .font(.title3.weight(.semibold))
                            Text("Search for companies and add only the stocks you want to follow.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: 280)
                            Button {
                                withAnimation(.snappy) { isSearchPresented = true }
                                searchFocused = true
                            } label: {
                                Label("Find stocks", systemImage: "magnifyingglass")
                                    .font(.headline)
                                    .padding(.horizontal, 18)
                                    .padding(.vertical, 10)
                                    .background(Color.accentColor, in: Capsule())
                                    .foregroundStyle(.white)
                            }
                            .buttonStyle(.plain)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 56)
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                    }
                } else {
                    Section {
                        HStack(spacing: 6) {
                            Text("Yahoo Finance · Quotes may be delayed")
                                .font(.subheadline).foregroundStyle(.secondary)
                            Spacer()
                            Text("USD").font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                            if market.isRefreshing { ProgressView().controlSize(.small) }
                        }
                        .padding(.vertical, 4)
                        .listRowSeparator(.hidden, edges: .all)
                        .listRowBackground(Color.clear)
                    }
                    Section {
                        ForEach(market.symbols, id: \.self) { symbol in
                            if let stock = market.quote(for: symbol) {
                                NavigationLink(value: symbol) {
                                    StockRow(stock: stock)
                                }
                                .listRowInsets(EdgeInsets(top: 9, leading: 0, bottom: 9, trailing: 0))
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button(role: .destructive) { market.remove(symbol) } label: { Label("Remove", systemImage: "trash") }
                                }
                            } else {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(symbol).font(.system(size: 17, weight: .semibold))
                                        Text("Waiting for quote…")
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if market.isRefreshing { ProgressView().controlSize(.small) }
                                }.padding(.vertical, 10).listRowSeparator(.hidden)
                            }
                        }.onMove(perform: market.move)
                    } header: {
                        HStack {
                            Text("MY SYMBOLS")
                            Spacer()
                            Text("PRICE")
                        }
                        .font(.caption2.weight(.semibold)).tracking(0.7)
                        .foregroundStyle(.secondary).textCase(nil).padding(.top, 6)
                    }
                    Section {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Quotes by Yahoo Finance · US equities").font(.caption2)
                            Text("Unofficial Yahoo Finance data. Prices may be delayed, and endpoints can change or be rate-limited.")
                                .font(.caption2)
                            if let updated = market.lastUpdated {
                                Text("Last refreshed \(updated.formatted(date: .omitted, time: .shortened))").font(.caption2)
                            }
                            if let error = market.errorMessage { Text(error).font(.caption2).foregroundStyle(.red) }
                        }
                        .foregroundStyle(.tertiary).padding(.vertical, 12)
                        .listRowSeparator(.hidden, edges: .all)
                        .listRowBackground(Color.clear)
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Color(uiColor: .systemBackground))
            .safeAreaInset(edge: .top, spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Search", text: $searchText)
                        .focused($searchFocused)
                        .textInputAutocapitalization(.characters).autocorrectionDisabled()
                        .onChange(of: searchText) { _, query in
                            if !query.isEmpty { isSearchPresented = true }
                            searchTask?.cancel()
                            searchTask = Task {
                                try? await Task.sleep(for: .milliseconds(250))
                                guard !Task.isCancelled else { return }
                                await market.search(query)
                            }
                        }
                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                            market.clearSearch()
                            searchFocused = true
                        } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                            .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 14).padding(.vertical, 11)
                .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .padding(.horizontal, 16).padding(.bottom, 8)
                .background(.bar)
            }
            .navigationTitle(isSearchPresented ? "Search" : headerDate)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    if !isSearchPresented {
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
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        withAnimation(.snappy(duration: 0.22)) {
                            isSearchPresented.toggle()
                            searchText = ""
                            market.clearSearch()
                        }
                    } label: {
                        Image(systemName: isSearchPresented ? "xmark" : "magnifyingglass")
                            .font(.system(size: 17, weight: .semibold))
                    }.accessibilityLabel(isSearchPresented ? "Close search" : "Search stocks")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { market.isSettingsPresented = true } label: { Image(systemName: "gearshape") }
                        .accessibilityLabel("Market data settings")
                }
                if !isSearchPresented { ToolbarItem(placement: .topBarTrailing) { EditButton() } }
            }
            .navigationDestination(for: String.self) { symbol in StockDetailView(symbol: symbol) }
            .sheet(isPresented: Binding(get: { market.isSettingsPresented }, set: { market.isSettingsPresented = $0 })) { MarketDataSettingsView() }
            .task {
                await market.loadWatchlist()
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(60))
                    if !Task.isCancelled { await market.loadWatchlist() }
                }
            }
        }.tint(.primary)
    }

    @ViewBuilder private var searchSection: some View {
        Section {
            if market.isSearching {
                HStack { Spacer(); ProgressView(); Spacer() }.listRowSeparator(.hidden)
            } else if searchText.isEmpty {
                ContentUnavailableView("Find a stock", systemImage: "magnifyingglass", description: Text("Search US-listed companies by name or ticker using Yahoo Finance."))
                    .listRowSeparator(.hidden)
            } else if searchMatches.isEmpty {
                ContentUnavailableView.search(text: searchText).listRowSeparator(.hidden)
            } else {
                ForEach(searchMatches) { result in
                    Button {
                        Task { await market.add(result) }
                        withAnimation(.snappy) { isSearchPresented = false; searchText = "" }
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(result.symbol).font(.headline).foregroundStyle(.primary)
                                Text(result.name).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer()
                            Text(result.exchange).font(.caption).foregroundStyle(.tertiary)
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
            }
            Spacer(minLength: 6)
            Sparkline(points: stock.points, positive: stock.isPositive).frame(width: 76, height: 34)
            VStack(alignment: .trailing, spacing: 5) {
                Text(stock.formattedPrice)
                    .font(.system(size: 16, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(.primary)
                Text("\(stock.change >= 0 ? "+" : "−")\(abs(stock.change).formatted(.number.precision(.fractionLength(2))))")
                    .font(.system(size: 12, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(stock.isPositive ? Color.green : Color.red, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
            }.frame(minWidth: 94, alignment: .trailing)
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
                Path { path in
                    path.move(to: CGPoint(x: 0, y: geometry.size.height * 0.65))
                    path.addLine(to: CGPoint(x: geometry.size.width, y: geometry.size.height * 0.35))
                }.stroke(Color.secondary.opacity(0.5), lineWidth: 1.5)
            }
        }
    }
}