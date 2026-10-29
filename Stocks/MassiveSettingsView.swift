import SwiftUI

struct MassiveSettingsView: View {
    @Environment(MarketStore.self) private var market
    @Environment(\.dismiss) private var dismiss
    @State private var apiKey = APIKeyVault.read() ?? ""
    @State private var isSaving = false
    @State private var message: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("Massive API key", text: $apiKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Text("Stored in this device’s Keychain. It is not committed to the repository.")
                        .font(.footnote).foregroundStyle(.secondary)
                } header: {
                    Text("Market data")
                } footer: {
                    Text("Real-time US equities require a Massive plan that includes real-time access and any applicable exchange entitlements. A valid key alone does not guarantee live data.")
                }
                Section {
                    Link(destination: URL(string: "https://massive.com/stocks")!) {
                        Label("View plans and pricing", systemImage: "arrow.up.right.square")
                    }
                    Link(destination: URL(string: "https://massive.com/docs/rest/stocks/snapshots/single-ticker-snapshot")!) {
                        Label("API documentation", systemImage: "doc.text")
                    }
                }
                if let message {
                    Section { Text(message).font(.footnote).foregroundStyle(message.hasPrefix("Saved") ? .green : .red) }
                }
                if market.apiKeyConfigured {
                    Section {
                        Button("Remove saved API key", role: .destructive) {
                            market.removeAPIKey()
                            apiKey = ""
                            message = "API key removed."
                        }
                    }
                }
            }
            .navigationTitle("Market Data")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveKey() }
                        .disabled(apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func saveKey() {
        do {
            try market.saveAPIKey(apiKey)
            message = "Saved. Checking access…"
            isSaving = true
            Task {
                await market.loadWatchlist()
                isSaving = false
                if market.errorMessage == nil { dismiss() }
                else { message = market.errorMessage }
            }
        } catch {
            message = error.localizedDescription
        }
    }
}
