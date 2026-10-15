import Foundation

/// 规则动作
enum FilterAction: String, Codable, CaseIterable, Identifiable {
    /// 阻断请求
    case block
    /// 放行请求
    case allow
    /// 仅记录，不干预
    case log

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .block: return "阻断"
        case .allow: return "放行"
        case .log:   return "仅记录"
        }
    }
}

/// 一条域名过滤规则（App 内手动添加）
struct DomainRule: Codable, Identifiable, Equatable {
    /// 唯一 ID
    var id: UUID = UUID()
    /// 规则域名，如 example.com 或 .example.com（含子域）
    var domain: String
    /// 动作
    var action: FilterAction = .block
    /// 是否启用
    var isEnabled: Bool = true
    /// 备注（可选）
    var note: String = ""
    /// 创建时间
    var createdAt: Date = Date()

    /// 规范化域名：去掉协议、路径、端口、首尾空格，统一小写
    var normalizedDomain: String {
        var raw = domain.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let schemeRange = raw.range(of: "://") {
            raw = String(raw[schemeRange.upperBound...])
        }
        if let slashIndex = raw.firstIndex(of: "/") {
            raw = String(raw[..<slashIndex])
        }
        if let colonIndex = raw.lastIndex(of: ":") {
            raw = String(raw[..<colonIndex])
        }
        return raw
    }

    /// 该规则是否匹配给定 host
    /// - 规则以 "." 开头（如 ".example.com"）时匹配该域及所有子域
    /// - 否则精确匹配 host，或 host 以 ".规则域" 结尾（即同样覆盖子域）
    func matches(host: String) -> Bool {
        let h = host.lowercased()
        let d = normalizedDomain
        guard !d.isEmpty else { return false }

        if d.hasPrefix(".") {
            let suffix = String(d.dropFirst())
            return h == suffix || h.hasSuffix("." + suffix)
        }
        return h == d || h.hasSuffix("." + d)
    }
}
