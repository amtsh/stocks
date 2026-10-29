import SwiftUI
import Charts

struct StockDetailView: View {
    @Environment(MarketStore.self) private var market
    let symbol: String
    @State private var range: ChartRange = .day
    @State private var selectedPoint: ChartPoint?
    private var stock: StockQuote? { market.quote(for: symbol) }
    private var chartColor: Color { (stock?.isPositive ?? true) ? .green : .red }

    var body: some View {
        ScrollView {
            if let stock {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(stock.name).font(.subheadline).foregroundStyle(.secondary)
                        Text(selectedPoint?.value.formatted(.currency(code: stock.currency).precision(.fractionLength(2))) ?? stock.formattedPrice)
                            .font(.system(size: 38, weight: .bold, design: .rounded)).monospacedDigit()
                            .contentTransition(.numericText())
                        HStack(spacing: 7) {
                            Text(stock.formattedChange).font(.subheadline.weight(.medium))
                            Text("Today").font(.subheadline).foregroundStyle(.secondary)
                        }.foregroundStyle(chartColor)
                        Text("\(stock.exchange) · USD").font(.caption).foregroundStyle(.tertiary)
                    }
                    priceChart(stock).frame(height: 230)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(ChartRange.allCases) { item in
                                Button {
                                    range = item
                                    selectedPoint = nil
                                    Task { await market.refresh(symbol: symbol, range: item) }
                                } label: {
                                    Text(item.rawValue)
                                        .font(.system(size: 13, weight: range == item ? .semibold : .medium))
                                        .foregroundStyle(range == item ? Color.white : Color.secondary)
                                        .padding(.horizontal, 12).padding(.vertical, 8)
                                        .background { if range == item { Capsule().fill(Color.accentColor) } }
                                }.buttonStyle(.plain)
                            }
                        }.padding(.horizontal, 2)
                    }
                    VStack(alignment: .leading, spacing: 14) {
                        Text("STOCK DETAILS").font(.caption.weight(.semibold)).tracking(0.8).foregroundStyle(.secondary)
                        dataRow("Previous close", value: stock.previousClose.formatted(.currency(code: stock.currency)))
                        dataRow("Day range", value: dayRange(stock))
                        dataRow("Volume", value: stock.volume?.formatted() ?? "—")
                        dataRow("Market cap", value: stock.marketCap.map { $0.formatted(.number.notation(.compactName)) } ?? "—")
                        dataRow("Exchange", value: stock.exchange)
                        dataRow("Last trade", value: stock.marketTime?.formatted(date: .omitted, time: .shortened) ?? "—")
                    }.padding(16).background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "info.circle").foregroundStyle(.secondary)
                        Text("Market data from Yahoo Finance. Quotes may be delayed; this unofficial endpoint has no uptime or real-time guarantee.")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }.padding(.horizontal, 20).padding(.top, 16).padding(.bottom, 32)
            } else {
                ContentUnavailableView("Loading quote", systemImage: "chart.line.uptrend.xyaxis", description: Text("Fetching the latest available market data."))
                    .frame(maxWidth: .infinity, minHeight: 400)
            }
        }
        .background(Color(uiColor: .systemBackground))
        .navigationTitle(symbol).navigationBarTitleDisplayMode(.inline)
        .task(id: symbol) { await market.refresh(symbol: symbol, range: range) }
    }

    @ViewBuilder private func priceChart(_ stock: StockQuote) -> some View {
        if stock.points.count > 1 {
            Chart {
                ForEach(stock.points) { point in
                    AreaMark(x: .value("Time", point.date),
                             yStart: .value("Baseline", stock.points.map(\.value).min() ?? point.value),
                             yEnd: .value("Price", point.value))
                        .foregroundStyle(LinearGradient(colors: [chartColor.opacity(0.22), chartColor.opacity(0.01)], startPoint: .top, endPoint: .bottom))
                        .interpolationMethod(.catmullRom)
                    LineMark(x: .value("Time", point.date), y: .value("Price", point.value))
                        .foregroundStyle(chartColor).lineStyle(StrokeStyle(lineWidth: 2)).interpolationMethod(.catmullRom)
                }
                if let selectedPoint {
                    RuleMark(x: .value("Selected time", selectedPoint.date))
                        .foregroundStyle(.secondary.opacity(0.5)).lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    PointMark(x: .value("Selected time", selectedPoint.date), y: .value("Selected price", selectedPoint.value))
                        .foregroundStyle(chartColor).symbolSize(45)
                }
            }
            .chartXAxis(.hidden).chartYAxis(.hidden).chartYScale(domain: chartDomain(stock.points))
            .chartOverlay { proxy in
                GeometryReader { geometry in
                    Rectangle().fill(.clear).contentShape(Rectangle()).gesture(
                        DragGesture(minimumDistance: 0).onChanged { value in
                            guard let frame = proxy.plotFrame else { return }
                            let plot = geometry[frame]
                            if let date: Date = proxy.value(atX: value.location.x - plot.origin.x) {
                                selectedPoint = stock.points.min { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }
                            }
                        }.onEnded { _ in selectedPoint = nil }
                    )
                }
            }
        } else {
            ContentUnavailableView("Chart unavailable", systemImage: "chart.xyaxis.line", description: Text("No history is available for this range."))
        }
    }
    private func chartDomain(_ points: [ChartPoint]) -> ClosedRange<Double> {
        let values = points.map(\.value), low = values.min() ?? 0, high = values.max() ?? 1
        let padding = max((high - low) * 0.12, high * 0.002)
        return (low - padding)...(high + padding)
    }
    private func dayRange(_ stock: StockQuote) -> String {
        guard let low = stock.dayLow, let high = stock.dayHigh else { return "—" }
        return "\(low.formatted(.currency(code: stock.currency))) – \(high.formatted(.currency(code: stock.currency)))"
    }
    private func dataRow(_ title: String, value: String) -> some View {
        HStack { Text(title).foregroundStyle(.secondary); Spacer(minLength: 12); Text(value).fontWeight(.medium).multilineTextAlignment(.trailing) }.font(.subheadline)
    }
}