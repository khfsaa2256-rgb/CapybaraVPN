// PacketTunnelProvider.swift
// VPN 隧道：系统级接管流量，在 DNS 层按 App Group 共享规则拦截域名。
// - 命中 block：丢弃 DNS 查询，回 NXDOMAIN（域名解析失败 → 连接失败，实现拦截）
// - 命中 log  ：记录隧道日志后放行
// - 未命中    ：正常放行
// 不含任何设备授权/UUID 上报逻辑。

import NetworkExtension
import Network

final class PacketTunnelProvider: NEPacketTunnelProvider {

    override func startTunnel(options: [String: NSObject]?, completionHandler: @escaping (Error?) -> Void) {
        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: "10.0.0.1")
        settings.ipv4Settings = NEIPv4Settings(addresses: ["10.0.0.2"], subnetMasks: ["255.255.255.255"])
        settings.ipv4Settings?.includedRoutes = [NEIPv4Route.default()]
        settings.ipv4Settings?.excludedRoutes = []
        settings.dnsSettings = NEDNSSettings(servers: ["223.5.5.5", "114.114.114.114"])
        // 空 matchDomains = 所有域名走隧道 DNS，使 DNS 查询经过本进程可拦截
        settings.dnsSettings?.matchDomains = []
        // includeAllNetworks 仅 macOS 可用；iOS 默认全流量接管（includedRoutes=default 已覆盖）

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

    override func handleAppMessage(_ messageData: Data, completionHandler: ((Data?) -> Void)?) {
        completionHandler?(nil)
    }

    /// 流量转发主循环：拦截 IPv4 UDP:53 查询，按规则阻断或放行
    private func startForwarding() {
        packetFlow.readPackets { [weak self] packets, protocols in
            guard let self else { return }
            let rules = TunnelRuleLoader.load()

            var toWrite: [Data] = []
            var protocolsToWrite: [NSNumber] = []
            toWrite.reserveCapacity(packets.count)
            protocolsToWrite.reserveCapacity(packets.count)

            for (index, packet) in packets.enumerated() {
                let proto = protocols[index]
                if let query = DNSPacket.parseQuery(from: packet, protocolNumber: proto) {
                    if let rule = rules.first(where: { $0.isEnabled && $0.matches(host: query.queryName) }) {
                        if rule.action == .block {
                            TunnelRuleLoader.recordTunnelLog(host: query.queryName, action: .block, rule: rule.domain)
                            // 丢弃原查询，回 NXDOMAIN 使应用快速失败
                            toWrite.append(DNSPacket.nxdomainResponse(for: query))
                            protocolsToWrite.append(proto)
                            continue
                        } else if rule.action == .log {
                            TunnelRuleLoader.recordTunnelLog(host: query.queryName, action: .log, rule: rule.domain)
                            // 记录后放行（落入下方透传）
                        }
                    }
                }
                toWrite.append(packet)
                protocolsToWrite.append(proto)
            }

            self.packetFlow.writePackets(toWrite, withProtocols: protocolsToWrite)
            self.startForwarding()
        }
    }
}
