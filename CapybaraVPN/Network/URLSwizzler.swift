import Foundation

/// 复刻原版卡皮巴拉 hkurl.framework 的 NSURL swizzle 机制：
/// 交换 `+[NSURL URLWithString:]`，命中 block 规则的域名时把 host 改写为 `0.0.0.0`
/// （无效地址 → 连接失败即拦截），拦截目标不依赖原版服务器。
final class URLSwizzler {
    // 交换涉及的两个 selector：
    // - 外部调用 +[NSURL URLWithString:] → 进入替换实现 capybara_URLWithString:
    // - 替换实现内调用 capybara_URLWithString: → 命中原始实现（防递归）
    private static let originalSelector = sel_registerName("URLWithString:")
    private static let swizzledSelector = #selector(NSURL.capybara_URLWithString(_:))

    private static let lock = NSLock()
    private static var isInstalled = false

    /// 安装 swizzle（防重入）。返回是否本次实际执行了交换。
    @discardableResult
    static func install() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !isInstalled else { return false }

        guard let originalMethod = class_getClassMethod(NSURL.self, originalSelector),
              let swizzledMethod = class_getClassMethod(NSURL.self, swizzledSelector)
        else { return false }

        method_exchangeImplementations(originalMethod, swizzledMethod)
        isInstalled = true
        return true
    }

    /// 命中 block 规则则改写 host 为 0.0.0.0（保留 scheme/path/query/port）；未命中原样返回
    fileprivate static func rewriteIfNeeded(_ url: NSURL) -> NSURL? {
        guard let host = url.host else { return url }

        let decision = FilterEngine.shared.decision(for: URLRequest(url: url as URL))
        guard decision.action == .block else { return url }

        guard var components = URLComponents(url: url as URL, resolvingAgainstBaseURL: false) else {
            return url
        }
        // 仅当 URLComponents 解析出的 host 与原始 host 一致时才改写，避免异常输入误伤
        guard components.host == host else { return url }

        components.host = "0.0.0.0"
        guard let rewritten = components.url else { return url }
        return rewritten as NSURL
    }
}

/// 替换实现：交换后成为 +[NSURL URLWithString:] 的真正实现
extension NSURL {
    @objc class func capybara_URLWithString(_ string: String) -> NSURL? {
        // 交换后本 selector 指向原始 +[NSURL URLWithString:] 的 IMP，调用即取原始解析结果
        guard let original = capybara_URLWithString(string) else { return nil }
        return URLSwizzler.rewriteIfNeeded(original)
    }
}
