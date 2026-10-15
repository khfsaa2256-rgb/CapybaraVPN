import SwiftUI

@main
struct CapybaraApp: App {
    @StateObject private var store = DomainRuleStore()

    init() {
        // 协议注册在 App 启动时完成；规则库注入在 ContentView 初始化时完成
        if AppConfig.filterAutoStart {
            FilterEngine.shared.register()
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView(store: store)
        }
    }
}
