import Foundation

/// 隧道规则加载与日志写入（App Group 共享 UserDefaults）
enum TunnelRuleLoader {
    /// 规则缓存（2 秒内复用，避免高频 decode）
    private static var cachedRules: [DomainRule] = []
    private static var lastLoad = Date.distantPast
    private static let cacheTTL: TimeInterval = 2.0

    /// 加载主 App 下发的启用规则（entitlement 缺失时返回空规则）
    static func load() -> [DomainRule] {
        let now = Date()
        if now.timeIntervalSince(lastLoad) < cacheTTL {
            return cachedRules
        }
        lastLoad = now

        var rules: [DomainRule] = []
        if let suite = UserDefaults(suiteName: AppConfig.appGroupID),
           let data = suite.data(forKey: AppConfig.sharedRulesKey),
           let decoded = try? JSONDecoder().decode([DomainRule].self, from: data) {
            rules = decoded
        }
        cachedRules = rules
        return rules
    }

    /// 写一条隧道拦截日志到 App Group（主 App 读取展示）
    static func recordTunnelLog(host: String, action: FilterAction, rule: String?) {
        guard let suite = UserDefaults(suiteName: AppConfig.appGroupID) else { return }
        var entries: [TunnelLogEntry] = []
        if let data = suite.data(forKey: AppConfig.tunnelLogsKey),
           let decoded = try? JSONDecoder().decode([TunnelLogEntry].self, from: data) {
            entries = decoded
        }
        entries.insert(TunnelLogEntry(host: host, action: action, ruleDomain: rule, at: Date()), at: 0)
        if entries.count > 100 {
            entries = Array(entries.prefix(100))
        }
        if let data = try? JSONEncoder().encode(entries) {
            suite.set(data, forKey: AppConfig.tunnelLogsKey)
        }
    }
}
