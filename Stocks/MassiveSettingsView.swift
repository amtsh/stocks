import SwiftUI

struct MassiveSettingsView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Label("Yahoo Finance", systemImage: "chart.line.uptrend.xyaxis")
                        .font(.headline)
                    Text("The app uses Yahoo Finance’s publicly accessible, unofficial search and chart endpoints. No API key or account is required.")
                        .font(.footnote)
                } header: {
                    Text("Market data")
                }
                Section {
                    Label("Search US-listed stocks by company name or ticker.", systemImage: "magnifyingglass")
                    Label("Quotes and historical charts are fetched on demand.", systemImage: "chart.xyaxis.line")
                    Label("Prices may be delayed. Requests can be rate-limited, and Yahoo may change these endpoints without notice.", systemImage: "exclamationmark.triangle")
                }
                Section {
                    Link(destination: URL(string: "https://finance.yahoo.com/")!) {
                        Label("Open Yahoo Finance", systemImage: "arrow.up.right.square")
                    }
                    Link(destination: URL(string: "https://github.com/ranaroussi/yfinance")!) {
                        Label("Unofficial API notes", systemImage: "doc.text")
                    }
                }
            }
            .navigationTitle("Market Data")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
