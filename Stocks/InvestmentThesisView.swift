import SwiftUI

/// A transparent, editable scenario model. Financial inputs are deliberately user-supplied:
/// the current market-data adapter does not provide reliable fundamental estimates.
struct InvestmentAssumptions: Codable, Equatable {
    var freeCashFlowPerShare = 5.0
    var discountRate = 0.10
    var terminalGrowthRate = 0.025
    var years = 5
    var bearGrowth = 0.02
    var baseGrowth = 0.12
    var bullGrowth = 0.22
    var bearExitMultiple = 15.0
    var baseExitMultiple = 25.0
    var bullExitMultiple = 35.0
    var thesis = ""
    var catalysts = ""
    var risks = ""
    var sourceURL = ""
    var sourceDate = ""

    static func load(for symbol: String) -> InvestmentAssumptions {
        guard let data = UserDefaults.standard.data(forKey: "thesis.assumptions.\(symbol)"),
              let value = try? JSONDecoder().decode(InvestmentAssumptions.self, from: data) else {
            return InvestmentAssumptions()
        }
        return value
    }

    func save(for symbol: String) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults.standard.set(data, forKey: "thesis.assumptions.\(symbol)")
    }
}

private struct ReturnScenario: Identifiable {
    let name: String
    let growth: Double
    let exitMultiple: Double
    let color: Color
    var id: String { name }

    func targetPrice(fcfPerShare: Double, years: Int) -> Double {
        fcfPerShare * pow(1 + growth, Double(years)) * exitMultiple
    }

    func annualizedReturn(currentPrice: Double, fcfPerShare: Double, years: Int) -> Double {
        guard currentPrice > 0 else { return 0 }
        return pow(targetPrice(fcfPerShare: fcfPerShare, years: years) / currentPrice, 1 / Double(years)) - 1
    }
}

struct InvestmentThesisView: View {
    let symbol: String
    let companyName: String
    let currentPrice: Double
    let currency: String
    let quoteTimestamp: Date?

    @State private var assumptions: InvestmentAssumptions
    @State private var showAssumptions = true

    init(symbol: String, companyName: String, currentPrice: Double, currency: String, quoteTimestamp: Date?) {
        self.symbol = symbol
        self.companyName = companyName
        self.currentPrice = currentPrice
        self.currency = currency
        self.quoteTimestamp = quoteTimestamp
        _assumptions = State(initialValue: InvestmentAssumptions.load(for: symbol))
    }

    private var scenarios: [ReturnScenario] {
        [
            ReturnScenario(name: "Bear", growth: assumptions.bearGrowth, exitMultiple: assumptions.bearExitMultiple, color: .red),
            ReturnScenario(name: "Base", growth: assumptions.baseGrowth, exitMultiple: assumptions.baseExitMultiple, color: .orange),
            ReturnScenario(name: "Bull", growth: assumptions.bullGrowth, exitMultiple: assumptions.bullExitMultiple, color: .green)
        ]
    }

    private var impliedGrowth: Double? {
        guard currentPrice > 0, assumptions.freeCashFlowPerShare > 0,
              assumptions.discountRate > assumptions.terminalGrowthRate,
              assumptions.terminalGrowthRate >= 0 else { return nil }
        func value(at growth: Double) -> Double {
            let r = assumptions.discountRate
            let n = assumptions.years
            var presentValue = 0.0
            for year in 1...n {
                let cashFlow = assumptions.freeCashFlowPerShare * pow(1 + growth, Double(year))
                presentValue += cashFlow / pow(1 + r, Double(year))
            }
            let terminalCashFlow = assumptions.freeCashFlowPerShare * pow(1 + growth, Double(n)) * (1 + assumptions.terminalGrowthRate)
            let terminalValue = terminalCashFlow / (r - assumptions.terminalGrowthRate)
            return presentValue + terminalValue / pow(1 + r, Double(n))
        }
        var low = -0.90
        var high = 2.0
        guard value(at: low) <= currentPrice, value(at: high) >= currentPrice else { return nil }
        for _ in 0..<100 {
            let mid = (low + high) / 2
            if value(at: mid) < currentPrice { low = mid } else { high = mid }
        }
        return (low + high) / 2
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                impliedExpectationsCard
                scenariosCard
                assumptionsCard
                thesisNotesCard
                sourcesCard
                Text("Research aid, not a forecast or investment recommendation. Model output is only as good as the inputs; it excludes dilution, debt changes, dividends, buybacks, taxes and uncertainty in valuation multiples. Never treat the scenario returns as probabilities.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            .padding(20)
        }
        .background(Color(uiColor: .systemBackground))
        .navigationTitle("Investment thesis")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: assumptions) { _, newValue in newValue.save(for: symbol) }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(companyName).font(.subheadline).foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(symbol).font(.title2.bold())
                Spacer()
                Text(currentPrice.formatted(.currency(code: currency))).font(.title2.bold().monospacedDigit())
            }
            Text("Price reference: " + (quoteTimestamp?.formatted(date: .abbreviated, time: .shortened) ?? "timestamp unavailable"))
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var impliedExpectationsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("WHAT MUST GO RIGHT?", systemImage: "scope")
                .font(.caption.weight(.bold)).tracking(0.7).foregroundStyle(.secondary)
            if let growth = impliedGrowth {
                Text("The price implies roughly \(growth, format: .percent.precision(.fractionLength(1))) annual FCF/share growth for \(assumptions.years) years.")
                    .font(.title3.weight(.semibold))
                Text("This reverse-DCF estimate assumes \(assumptions.freeCashFlowPerShare.formatted(.currency(code: currency))) current free cash flow per share, a \(assumptions.discountRate, format: .percent.precision(.fractionLength(1))) discount rate and \(assumptions.terminalGrowthRate, format: .percent.precision(.fractionLength(1))) perpetual growth. Change these inputs to test what the current price requires.")
                    .font(.subheadline).foregroundStyle(.secondary)
                if growth > assumptions.baseGrowth {
                    Label("Price requires more growth than your base case.", systemImage: "exclamationmark.triangle")
                        .font(.subheadline.weight(.medium)).foregroundStyle(.orange)
                } else {
                    Label("Your base growth assumption meets or exceeds implied growth.", systemImage: "checkmark.circle")
                        .font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                }
            } else {
                Text("Enter positive free cash flow per share and valid discount / terminal growth assumptions to estimate implied growth.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18))
    }

    private var scenariosCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("\(assumptions.years)-YEAR RETURN SCENARIOS")
                .font(.caption.weight(.bold)).tracking(0.7).foregroundStyle(.secondary)
            ForEach(scenarios) { scenario in
                let target = scenario.targetPrice(fcfPerShare: assumptions.freeCashFlowPerShare, years: assumptions.years)
                let annualReturn = scenario.annualizedReturn(currentPrice: currentPrice, fcfPerShare: assumptions.freeCashFlowPerShare, years: assumptions.years)
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(scenario.name).font(.headline)
                        Spacer()
                        Text(annualReturn.formatted(.percent.precision(.fractionLength(1))))
                            .font(.headline.monospacedDigit()).foregroundStyle(scenario.color)
                    }
                    HStack {
                        Text("Illustrative target")
                        Spacer()
                        Text(target.formatted(.currency(code: currency))).monospacedDigit()
                    }.font(.subheadline).foregroundStyle(.secondary)
                    Text("\(scenario.growth, format: .percent.precision(.fractionLength(0))) FCF growth · \(scenario.exitMultiple, format: .number.precision(.fractionLength(0)))× exit FCF")
                        .font(.caption).foregroundStyle(.tertiary)
                }
                if scenario.id != scenarios.last?.id { Divider() }
            }
        }
        .padding(16).background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18))
    }

    private var assumptionsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Button { withAnimation(.snappy) { showAssumptions.toggle() } } label: {
                HStack {
                    Text("EDIT ASSUMPTIONS").font(.caption.weight(.bold)).tracking(0.7)
                    Spacer()
                    Image(systemName: showAssumptions ? "chevron.up" : "chevron.down")
                }.foregroundStyle(.primary)
            }.buttonStyle(.plain)
            if showAssumptions {
                Text("Starter values are placeholders, not company data. Replace FCF/share with the latest reported figure and cite the filing below.")
                    .font(.caption).foregroundStyle(.secondary)
                numberField("Current FCF per share", value: $assumptions.freeCashFlowPerShare, suffix: currency)
                numberField("Discount rate", value: $assumptions.discountRate, isPercent: true)
                numberField("Perpetual growth", value: $assumptions.terminalGrowthRate, isPercent: true)
                HStack {
                    Text("Forecast horizon")
                    Spacer()
                    Picker("Forecast horizon", selection: $assumptions.years) {
                        ForEach([3, 5, 7, 10], id: \.self) { Text("\($0) years").tag($0) }
                    }.labelsHidden()
                }
                Divider()
                Text("BEAR CASE").font(.caption.weight(.bold)).foregroundStyle(.secondary)
                numberField("FCF/share growth", value: $assumptions.bearGrowth, isPercent: true)
                numberField("Exit FCF multiple", value: $assumptions.bearExitMultiple, suffix: "×")
                Text("BASE CASE").font(.caption.weight(.bold)).foregroundStyle(.secondary)
                numberField("FCF/share growth", value: $assumptions.baseGrowth, isPercent: true)
                numberField("Exit FCF multiple", value: $assumptions.baseExitMultiple, suffix: "×")
                Text("BULL CASE").font(.caption.weight(.bold)).foregroundStyle(.secondary)
                numberField("FCF/share growth", value: $assumptions.bullGrowth, isPercent: true)
                numberField("Exit FCF multiple", value: $assumptions.bullExitMultiple, suffix: "×")
                Button("Reset to starter assumptions", role: .destructive) {
                    assumptions = InvestmentAssumptions()
                }.font(.subheadline)
            }
        }.padding(16).background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18))
    }

    private var thesisNotesCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("THESIS, CATALYSTS & RISKS").font(.caption.weight(.bold)).tracking(0.7).foregroundStyle(.secondary)
            noteField("What needs to go right?", text: $assumptions.thesis, prompt: "e.g. maintain margins while growing revenue")
            noteField("Upcoming catalysts (include dates)", text: $assumptions.catalysts, prompt: "e.g. earnings on YYYY-MM-DD — add source URL")
            noteField("Thesis breakers / risks", text: $assumptions.risks, prompt: "e.g. margin compression, regulation, customer concentration")
            Text("These notes are yours to verify and update. Catalysts and risks are not automatically discovered or independently verified.")
                .font(.caption2).foregroundStyle(.secondary)
        }.padding(16).background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18))
    }

    private var sourcesCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("SOURCES & FRESHNESS").font(.caption.weight(.bold)).tracking(0.7).foregroundStyle(.secondary)
            Label("Price: Yahoo Finance (unofficial; may be delayed)", systemImage: "chart.line.uptrend.xyaxis")
                .font(.subheadline)
            Link("Open quote source", destination: URL(string: "https://finance.yahoo.com/quote/\(symbol)/")!)
                .font(.subheadline)
            Link("Search SEC company filings", destination: URL(string: "https://www.sec.gov/edgar/search/")!)
                .font(.subheadline)
            Text("Financial assumptions are user-entered, not live reported data. Record the filing date and source URL for the numbers you use.")
                .font(.caption).foregroundStyle(.secondary)
            TextField("Financial data as-of / filing date", text: $assumptions.sourceDate)
                .textInputAutocapitalization(.never).textFieldStyle(.roundedBorder)
            TextField("Source URL (optional)", text: $assumptions.sourceURL)
                .textInputAutocapitalization(.never).keyboardType(.URL).autocorrectionDisabled()
                .textFieldStyle(.roundedBorder)
            if let url = URL(string: assumptions.sourceURL), ["https", "http"].contains(url.scheme?.lowercased() ?? ""), url.host != nil {
                Link("Open your source", destination: url).font(.subheadline)
            }
        }.padding(16).background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18))
    }

    private func numberField(_ title: String, value: Binding<Double>, suffix: String? = nil, isPercent: Bool = false) -> some View {
        HStack {
            Text(title).font(.subheadline)
            Spacer(minLength: 8)
            TextField(title, value: isPercent ? Binding(get: { value.wrappedValue * 100 }, set: { value.wrappedValue = $0 / 100 }) : value, format: .number.precision(.fractionLength(0...3)))
                .keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 100)
            if let suffix { Text(suffix).font(.caption).foregroundStyle(.secondary) }
            else if isPercent { Text("%").font(.caption).foregroundStyle(.secondary) }
        }
    }

    private func noteField(_ title: String, text: Binding<String>, prompt: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.subheadline.weight(.medium))
            TextEditor(text: text).frame(minHeight: 70).scrollContentBackground(.hidden)
                .overlay(alignment: .topLeading) {
                    if text.wrappedValue.isEmpty {
                        Text(prompt).font(.subheadline).foregroundStyle(.tertiary).padding(.top, 8).padding(.leading, 5).allowsHitTesting(false)
                    }
                }
                .padding(6).background(Color(uiColor: .systemBackground), in: RoundedRectangle(cornerRadius: 10))
        }
    }
}
