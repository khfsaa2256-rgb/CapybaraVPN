import Foundation

/// 全局配置（无设备授权、无登录服务器）
enum AppConfig {
    /// 过滤引擎开关：App 启动后是否自动注册 NSURLProtocol 拦截
    static let filterAutoStart = true

    /// 未命中任何规则时的默认动作（放行 / 阻断 / 仅记录）
    static let defaultAction: FilterAction = .allow

    /// 是否允许拦截 HTTPS 流量（NSURLProtocol 对 HTTPS 生效有限，见 README 说明）
    static let interceptHTTPS = true

    /// VPN 扩展 Bundle ID（与 tunnel target 一致；未启用隧道时仅作预留）
    static let tunnelBundleID = "com.yourteam.capybaravpn.VPNTunnel"

    /// 规则存储 Key（UserDefaults）
    static let rulesStorageKey = "capybara.domainRules.v1"
    /// 拦截日志存储 Key（UserDefaults）
    static let logsStorageKey = "capybara.filterLogs.v1"
}
