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
        // DNS 分流：不接管任何 IP 路由（避免非 DNS 流量进入隧道后无法上行导致无网络），
        // 只拦截规则域名的 DNS 解析，其余流量全部走物理网络。
        settings.ipv4Settings?.includedRoutes = []
        settings.ipv4Settings?.excludedRoutes = []
        settings.dnsSettings = NEDNSSettings(servers: ["223.5.5.5", "114.114.114.114"])

        // 显式列出需要经过隧道的域名（block/log 规则），allow 规则与其它域名走系统正常解析。
        // 空数组 = 所有域名都走隧道，必须避免；无规则时用占位域名兜底。
        let rules = TunnelRuleLoader.load().filter { $0.isEnabled }
        let tunnelDomains = rules
            .filter { $0.action != .allow }
            .map { $0.normalizedDomain }
            .filter { !$0.isEmpty }
        settings.dnsSettings?.matchDomains = tunnelDomains.isEmpty ? ["localhost"] : tunnelDomains

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

    /// 流量转发主循环：拦截规则域名的 IPv4 UDP:53 查询，按规则阻断或转发上游放行
    private func startForwarding() {
        packetFlow.readPackets { [weak self] packets, protocols in
            guard let self else { return }
            let rules = TunnelRuleLoader.load().filter { $0.isEnabled }

            var toWrite: [Data] = []
            var protocolsToWrite: [NSNumber] = []
            toWrite.reserveCapacity(packets.count)
            protocolsToWrite.reserveCapacity(packets.count)

            for (index, packet) in packets.enumerated() {
                let proto = protocols[index]
                if let query = DNSPacket.parseQuery(from: packet, protocolNumber: proto) {
                    if let rule = rules.first(where: { $0.matches(host: query.queryName) }) {
                        if rule.action == .block {
                            TunnelRuleLoader.recordTunnelLog(host: query.queryName, action: .block, rule: rule.domain)
                            // 丢弃原查询，回 NXDOMAIN 使应用快速失败
                            toWrite.append(DNSPacket.nxdomainResponse(for: query))
                            protocolsToWrite.append(proto)
                            continue
                        } else if rule.action == .log {
                            TunnelRuleLoader.recordTunnelLog(host: query.queryName, action: .log, rule: rule.domain)
                            // log / allow / 未命中：转发上游 DNS，拿到响应再写回隧道
                            forwardDNS(packet, protocolNumber: proto, query: query)
                            continue
                        }
                    }
                    forwardDNS(packet, protocolNumber: proto, query: query)
                    continue
                }
                // 非 DNS 流量：split 模式下不会进入隧道，防御性写回
                toWrite.append(packet)
                protocolsToWrite.append(proto)
            }

            self.packetFlow.writePackets(toWrite, withProtocols: protocolsToWrite)
            self.startForwarding()
        }
    }

    /// 将查询原样转发给上游 DNS（223.5.5.5:53），收到响应后封装回隧道
    private func forwardDNS(_ packet: Data, protocolNumber: NSNumber, query: DNSPacket.Query) {
        guard let payload = DNSPacket.udpPayload(from: packet, protocolNumber: protocolNumber) else { return }
        let connection = NWConnection(host: "223.5.5.5", port: 53, using: .udp)
        connection.stateUpdateHandler = { state in
            guard state == .ready else {
                if state == .failed || state == .cancelled {
                    connection.cancel()
                }
                return
            }
            connection.send(content: payload, completion: .contentProcessed { error in
                guard error == nil else {
                    connection.cancel()
                    return
                }
                connection.receiveMessage { [weak self] data, _, _, _ in
                    defer { connection.cancel() }
                    guard let self, let data, !data.isEmpty else { return }
                    let response = DNSPacket.response(for: query, withDNS: data)
                    self.packetFlow.writePackets([response], withProtocols: [protocolNumber])
                }
            })
        }
        connection.start(queue: .global())
    }
}
