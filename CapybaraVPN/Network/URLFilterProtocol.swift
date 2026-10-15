import Foundation

/// 域名拦截核心：NSURLProtocol 子类
/// - block：直接返回 403 空响应，阻断请求
/// - log  ：记录日志后照常放行（用不带 protocolClasses 的 URLSession 转发，避免递归）
/// - allow：canInit 返回 false，不参与拦截
final class URLFilterProtocol: URLProtocol {

    /// 转发用的 URLSession（不含本协议，防止递归）
    private static let forwardingSession: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = []
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: config)
    }()

    private var forwardingTask: URLSessionDataTask?
    private var blockResponse: URLResponse?

    // MARK: - 拦截判定

    override class func canInit(with request: URLRequest) -> Bool {
        let decision = FilterEngine.shared.decision(for: request)
        return decision.needIntercept
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        return request
    }

    // MARK: - 生命周期

    override func startLoading() {
        guard let request = (request as NSURLRequest).mutableCopy() as? URLRequest else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        let decision = FilterEngine.shared.decision(for: request)

        switch decision.action {
        case .block:
            handleBlock(request: request, rule: decision.rule)
        case .log:
            handleLogThenForward(request: request, rule: decision.rule)
        case .allow:
            // 理论不会走到（allow 不参与拦截）
            client?.urlProtocol(self, didFailWithError: URLError(.unknown))
        }
    }

    override func stopLoading() {
        forwardingTask?.cancel()
        forwardingTask = nil
    }

    // MARK: - 动作处理

    /// 阻断：返回 403 + 空 body
    private func handleBlock(request: URLRequest, rule: DomainRule?) {
        guard let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        FilterEngine.shared.store?.record(host: url.host ?? "", url: url.absoluteString, action: .block, rule: rule)

        let response = HTTPURLResponse(
            url: url,
            statusCode: 403,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "text/plain; charset=utf-8"]
        ) ?? URLResponse(url: url, mimeType: nil, expectedContentLength: 0, textEncodingName: nil)

        blockResponse = response
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        let empty = Data("blocked by capybara".utf8)
        client?.urlProtocol(self, didLoad: empty)
        client?.urlProtocolDidFinishLoading(self)
    }

    /// 记录后放行：用独立 URLSession 转发原请求
    private func handleLogThenForward(request: URLRequest, rule: DomainRule?) {
        guard let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        FilterEngine.shared.store?.record(host: url.host ?? "", url: url.absoluteString, action: .log, rule: rule)

        var forwarded = (request as NSURLRequest).mutableCopy() as! NSMutableURLRequest
        // 标记已转发，避免潜在循环
        URLProtocol.setProperty(true, forKey: "Capybara.forwarded", in: forwarded)

        forwardingTask = Self.forwardingSession.dataTask(with: forwarded as URLRequest) { [weak self] data, response, error in
            guard let self else { return }
            if let error {
                self.client?.urlProtocol(self, didFailWithError: error)
                return
            }
            if let response {
                self.client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .allowed)
            }
            if let data {
                self.client?.urlProtocol(self, didLoad: data)
            }
            self.client?.urlProtocolDidFinishLoading(self)
        }
        forwardingTask?.resume()
    }
}
