---
AIGC:
    Label: "1"
    ContentProducer: 001191440300708461136T1XGW3
    ProduceID: 4b1b7a7f2e80067a82fbd124e3c04ae7_60194a12c87511f18b7f525400393706
    ReservedCode1: wj27ppSKsdVJm0+d1xtK1bPPoSpO7ve1wANuUPMIB97G/cOghwDLj9ee6YsFWb5+dcxINoqQT68z5wGZuamV8GbW4LYSOknKR3G7HfbQ9hLakse+QXDzMdPImPl+ScZ1ekyNrf3QhQx1Lpjja3z76eZxWKL8cwr/nmx/zWeeInSeGdeJrvDDjjDhP/M=
    ContentPropagator: 001191440300708461136T1XGW3
    PropagateID: 4b1b7a7f2e80067a82fbd124e3c04ae7_60194a12c87511f18b7f525400393706
    ReservedCode2: wj27ppSKsdVJm0+d1xtK1bPPoSpO7ve1wANuUPMIB97G/cOghwDLj9ee6YsFWb5+dcxINoqQT68z5wGZuamV8GbW4LYSOknKR3G7HfbQ9hLakse+QXDzMdPImPl+ScZ1ekyNrf3QhQx1Lpjja3z76eZxWKL8cwr/nmx/zWeeInSeGdeJrvDDjjDhP/M=
---

# CapybaraVPN — 域名拦截过滤工具（自研版）

基于对「卡皮巴拉 Automatic v1.2」IPA 的逆向解析，重构的原创 iOS 应用。
**已去除原版的设备授权/登录逻辑**，改为纯本地方案：App 内手动添加域名过滤规则，对 App 内发起的网络请求进行拦截过滤。

## 功能

- 无登录、无设备注册、无服务器依赖，完全离线可用
- App 内手动添加域名规则（输入框 + 动作选择 + 一键添加）
- 三种规则动作：
  - **阻断**：命中后直接返回 403，请求不再发出
  - **放行**：命中后正常放行（白名单）
  - **仅记录**：命中后记录日志，请求照常发出
- 规则支持子域匹配：`example.com` 匹配 `example.com` 及 `*.example.com`；`.example.com` 同理
- 规则可单独启停、删除、清空，全部持久化到 UserDefaults
- 内置拦截日志（最近 100 条），实时查看命中的请求与动作
- 总开关控制过滤引擎（NSURLProtocol）注册/注销

## 架构

```
CapybaraVPN (App, SwiftUI)
├── App
│   ├── CapybaraApp.swift          # 入口：注册过滤引擎
│   └── ContentView.swift          # 域名管理界面（添加/启停/删除/日志）
├── Core
│   ├── AppConfig.swift            # 全局配置（无授权字段）
│   ├── DomainRule.swift           # 规则模型 + 域名匹配逻辑
│   └── DomainRuleStore.swift      # 规则与日志的增删改查 + UserDefaults 持久化
└── Network
    ├── FilterEngine.swift         # 协议注册/注销 + 规则决策
    └── URLFilterProtocol.swift    # NSURLProtocol 拦截核心（block / log 转发）

VPNTunnel (可选，未加入工程默认编译)
└── PacketTunnelProvider.swift     # NEPacketTunnelProvider 透传骨架
```

## 核心实现说明

拦截基于 `URLProtocol`（对应原版 123.dylib 的 `SSURLProtocol` 思路）：

1. App 启动时 `FilterEngine.register()` 注册 `URLFilterProtocol`
2. 每次网络请求进入时，`canInit` 按 host 查 `DomainRuleStore` 规则
3. 命中 `block` → 返回 HTTP 403 空响应；命中 `log` → 记录日志并用独立 URLSession 转发（避免递归）；命中 `allow` → 不拦截直接放行

与原版关键差异：

| 项 | 原版卡皮巴拉 | 本自研版 |
|----|--------------|----------|
| 设备授权 | Keychain 存 UUID + 登录接口 + RSA 验签 | 已全部移除 |
| 拦截规则 | 硬编码请求重定向到第三方 IP | App 内手动添加，本地存储 |
| 服务器依赖 | 依赖原开发者服务器 | 无 |
| URL swizzle hook | 全局 swizzle NSURL 换 IP | swizzle NSURL URLWithString: 命中域名改写为 0.0.0.0（无效地址拦截，目标不依赖原版服务器） |

## 编译（需要一台 Mac）

1. 用 Xcode 打开 `CapybaraVPN.xcodeproj`
2. 在 Signing & Capabilities 中选择你自己的 Team（首次真机运行需免费 Apple ID 签名）
3. 修改 `AppConfig.swift` 中的 `tunnelBundleID`（若启用隧道）与签名后 Bundle ID 保持一致
4. 真机或模拟器运行均可（域名过滤不依赖 VPN 扩展）

## 已知边界

- `NSURLProtocol` 对 App 内通过 `URLSession`/`URLSessionConfiguration` 发起的请求生效；部分系统组件（如 WKWebView 默认配置）不走该协议，如需全量过滤请启用 VPNTunnel 扩展并按注释实现 DNS 分流
- HTTPS 拦截受系统限制（`AppConfig.interceptHTTPS` 默认开启，但效果取决于请求发起方式），完整 HTTPS 域名管控建议走 VPN 隧道
- 仅作用于本 App 进程内的请求，不拦截其他 App 流量

## 合规提醒

仅限自有设备、学习研究使用。不要接入原开发者的任何 API、服务器与第三方 IP。
*（内容由AI生成，仅供参考）*
