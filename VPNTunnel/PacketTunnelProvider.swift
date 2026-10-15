// PacketTunnelProvider.swift
// 说明：可选组件。若不需要 VPN 隧道，可将本文件从编译目标中移除，
// 域名拦截过滤（URLFilterProtocol）已可独立工作。
//
// 若启用：在 Xcode 新建 App Extension Target（类型 Network Extension / Packet Tunnel），
// 将本文件加入该 target，并在主 App 中配置 NETunnelProviderManager 拉起隧道。
// 本实现仅做隧道生命周期管理与流量转发骨架，不含任何设备授权逻辑。

import NetworkExtension
import Network

final class PacketTunnelProvider: NEPacketTunnelProvider {

    override func startTunnel(options: [String: NSObject]?, completionHandler: @escaping (Error?) -> Void) {
        // 隧道配置：使用默认 DNS，仅透传流量
        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: "127.0.0.1")
        settings.ipv4Settings = NEIPv4Settings(addresses: ["192.0.2.1"], subnetMasks: ["255.255.255.255"])
        settings.ipv4Settings?.includedRoutes = [NEIPv4Route.default()]
        settings.ipv4Settings?.excludedRoutes = []
        settings.dnsSettings = NEDNSSettings(servers: ["223.5.5.5", "114.114.114.114"])

        setTunnelNetworkSettings(settings) { [weak self] error in
            if let error {
                completionHandler(error)
                return
            }
            self?.startForwarding()
            completionHandler(nil)
        }
    }

    override func stopTunnel(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        completionHandler()
    }

    private func startForwarding() {
        // 简易透传：将隧道接口收到的包原样发回（等价于透明代理占位）。
        // 如需完整域名拦截，可在此实现 DNS 分流 + 黑名单丢弃（规则由主 App 经
        // App Group 共享 UserDefaults 下发，AppConfig.rulesStorageKey 可复用）。
        packetFlow.readPackets { [weak self] packets, protocols in
            guard let self else { return }
            self.packetFlow.writePackets(packets, withProtocols: protocols)
            self.startForwarding()
        }
    }
}
