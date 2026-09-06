import SwiftUI

@main
struct MiniCityApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .onAppear {
                    // 断られても遊びは止まらない。実績は端末の中で完結している。
                    GameCenter.authenticate()
                }
        }
    }
}
