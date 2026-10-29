import SwiftUI

@main
struct StocksApp: App {
    @State private var market = MarketStore()
    var body: some Scene {
        WindowGroup {
            ContentView().environment(market).preferredColorScheme(nil)
        }
    }
}