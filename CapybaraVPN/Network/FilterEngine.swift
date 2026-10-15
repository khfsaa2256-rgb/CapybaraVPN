import Foundation

/// 过滤引擎：注册/注销 NSURLProtocol，并向协议提供规则查询
final class FilterEngine {
    /// 全局单例（URLFilterProtocol 通过它查规则）
    static let shared = FilterEngine()

    /// 规则源（由 App 入口注入 DomainRuleStore）
    weak var store: DomainRuleStore?

    /// 是否已注册
    private(set) var isRegistered = false

    /// 注册拦截协议
    func register() {
        guard !isRegistered else { return }
        URLProtocol.registerClass(URLFilterProtocol.self)
        isRegistered = true
    }

    /// 注销拦截协议
    func unregister() {
        guard isRegistered else { return }
        URLProtocol.unregisterClass(URLFilterProtocol.self)
        isRegistered = false
    }

    /// 判断请求是否需要拦截
    /// - Returns: (needIntercept, action, rule)；allow 或未命中时 needIntercept = false
    func decision(for request: URLRequest) -> (needIntercept: Bool, action: FilterAction, rule: DomainRule?) {
        guard let url = request.url, let host = url.host else {
            return (false, .allow, nil)
        }
        // 仅处理 http/https
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || (scheme == "https" && AppConfig.interceptHTTPS) else {
            return (false, .allow, nil)
        }
        guard let rule = store?.rule(matching: host) else {
            return (false, .allow, nil)
        }
        if rule.action == .allow {
            return (false, .allow, rule)
        }
        return (true, rule.action, rule)
    }
}
