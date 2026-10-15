import Foundation
import Combine

/// 域名规则存储：App 内手动添加/删除/启停，持久化到 UserDefaults（JSON）
final class DomainRuleStore: ObservableObject {
    @Published private(set) var rules: [DomainRule] = [] {
        didSet { persist() }
    }

    /// 最近拦截日志（倒序，最多保留 100 条）
    @Published private(set) var logs: [FilterLogEntry] = [] {
        didSet { persistLogs() }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
    }

    // MARK: - 规则管理

    /// 添加规则；返回是否成功（空域名/重复则失败）
    @discardableResult
    func add(domain: String, action: FilterAction, note: String = "") -> Bool {
        let normalized = DomainRule(domain: domain, action: action).normalizedDomain
        guard !normalized.isEmpty else { return false }
        // 重复检测：同域名同动作视为重复
        let exists = rules.contains { $0.normalizedDomain == normalized && $0.action == action }
        guard !exists else { return false }
        rules.append(DomainRule(domain: normalized, action: action, note: note))
        return true
    }

    func remove(id: UUID) {
        rules.removeAll { $0.id == id }
    }

    func setEnabled(id: UUID, enabled: Bool) {
        guard let idx = rules.firstIndex(where: { $0.id == id }) else { return }
        rules[idx].isEnabled = enabled
    }

    func setAction(id: UUID, action: FilterAction) {
        guard let idx = rules.firstIndex(where: { $0.id == id }) else { return }
        rules[idx].action = action
    }

    func clearAll() {
        rules.removeAll()
    }

    /// 查询给定 host 命中的启用规则；无命中返回 nil
    func rule(matching host: String) -> DomainRule? {
        for rule in rules where rule.isEnabled {
            if rule.matches(host: host) {
                return rule
            }
        }
        return nil
    }

    // MARK: - 日志

    func record(host: String, url: String, action: FilterAction, rule: DomainRule?) {
        let entry = FilterLogEntry(
            host: host,
            url: url,
            action: action,
            ruleDomain: rule?.domain,
            at: Date()
        )
        logs.insert(entry, at: 0)
        if logs.count > 100 {
            logs = Array(logs.prefix(100))
        }
    }

    func clearLogs() {
        logs.removeAll()
    }

    // MARK: - 持久化

    private func load() {
        if let data = defaults.data(forKey: AppConfig.rulesStorageKey),
           let decoded = try? JSONDecoder().decode([DomainRule].self, from: data) {
            rules = decoded
        }
        if let data = defaults.data(forKey: AppConfig.logsStorageKey),
           let decoded = try? JSONDecoder().decode([FilterLogEntry].self, from: data) {
            logs = decoded
        }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(rules) {
            defaults.set(data, forKey: AppConfig.rulesStorageKey)
        }
    }

    private func persistLogs() {
        if let data = try? JSONEncoder().encode(logs) {
            defaults.set(data, forKey: AppConfig.logsStorageKey)
        }
    }
}

/// 一条拦截日志
struct FilterLogEntry: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var host: String
    var url: String
    var action: FilterAction
    var ruleDomain: String?
    var at: Date
}
