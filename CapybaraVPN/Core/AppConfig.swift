import Foundation

/// 全局配置（无设备授权、无登录服务器）
enum AppConfig {
    /// 过滤引擎开关：App 启动后是否自动注册 NSURLProtocol 拦截
    static let filterAutoStart = true

    /// 未命中任何规则时的默认动作（放行 / 阻断 / 仅记录）
    static let defaultAction: FilterAction = .allow

    /// 是否允许拦截 HTTPS 流量（NSURLProtocol 对 HTTPS 生效有限，见 README 说明）
    static let interceptHTTPS = true

    /// VPN 扩展 Bundle ID（与 tunnel target 一致）
    static let tunnelBundleID = "com.yourteam.capybaravpn.VPNTunnel"

    /// App Group（主 App 与 VPN 扩展共享规则/日志，需在签名 entitlements 中声明）
    static let appGroupID = "group.com.yourteam.capybaravpn"
    /// App Group 共享规则 Key（隧道扩展读取用）
    static let sharedRulesKey = "capybara.domainRules.v1.shared"
    /// App Group 隧道日志 Key（扩展写入、主 App 展示用）
    static let tunnelLogsKey = "capybara.tunnelLogs.v1"

    /// 规则存储 Key（UserDefaults）
    static let rulesStorageKey = "capybara.domainRules.v1"
    /// 拦截日志存储 Key（UserDefaults）
    static let logsStorageKey = "capybara.filterLogs.v1"
}
