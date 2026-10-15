import Foundation
import Network

/// DNS 查询包解析与 NXDOMAIN 响应构造（IPv4 + UDP + DNS 最小实现）
enum DNSPacket {

    /// 解析出的 DNS 查询
    struct Query {
        /// 原始 IP 包（含 IPv4 + UDP + DNS）
        let original: Data
        /// 查询域名（小写）
        let queryName: String
    }

    /// 尝试从 IPv4 UDP 包中解析 DNS 查询；非 DNS 查询返回 nil
    static func parseQuery(from packet: Data, protocolNumber: NSNumber) -> Query? {
        guard protocolNumber.int32Value == AF_INET else { return nil }
        let bytes = [UInt8](packet)
        guard bytes.count >= 28 else { return nil }

        // IPv4 header
        let ihl = Int(bytes[0] & 0x0F) * 4
        guard ihl >= 20, bytes.count >= ihl + 8 else { return nil }
        guard bytes[9] == 17 else { return nil } // UDP protocol

        // UDP header
        let udpOffset = ihl
        let destPort = (UInt16(bytes[udpOffset + 2]) << 8) | UInt16(bytes[udpOffset + 3])
        guard destPort == 53 else { return nil } // DNS 查询目标端口 53

        // DNS header: 12 bytes
        let dnsOffset = udpOffset + 8
        guard bytes.count >= dnsOffset + 12 else { return nil }

        // 解析 QNAME（支持压缩指针）
        var index = dnsOffset + 12
        var labels: [String] = []
        var jumped = false
        var loop = 0
        while loop < 64 {
            loop += 1
            guard index < bytes.count else { return nil }
            let length = Int(bytes[index])
            if length == 0 {
                break
            }
            if (length & 0xC0) == 0xC0 {
                guard index + 1 < bytes.count else { return nil }
                let pointer = ((length & 0x3F) << 8) | Int(bytes[index + 1])
                guard pointer < bytes.count else { return nil }
                if !jumped {
                    jumped = true
                }
                index = pointer
                continue
            }
            guard index + 1 + length <= bytes.count else { return nil }
            let labelBytes = Array(bytes[(index + 1)..<(index + 1 + length)])
            labels.append(String(decoding: labelBytes, as: UTF8.self))
            index += 1 + length
        }
        guard !labels.isEmpty else { return nil }
        return Query(original: packet, queryName: labels.joined(separator: ".").lowercased())
    }

    /// 构造 NXDOMAIN 响应：复用查询包，改 DNS header（QR=1, RCODE=3, 应答计数清零），
    /// 交换 IP/UDP 源目，重算 IPv4 header checksum（UDP checksum 置 0，IPv4 允许）
    static func nxdomainResponse(for query: Query) -> Data {
        var out = Data(query.original)
        var bytes = [UInt8](out)
        let ihl = Int(bytes[0] & 0x0F) * 4
        let dnsOffset = ihl + 8

        // DNS header 修改
        bytes[dnsOffset + 2] = (bytes[dnsOffset + 2] & 0x01) | 0x80 // QR=1，保留 RD
        bytes[dnsOffset + 3] = (bytes[dnsOffset + 3] & 0xF0) | 0x03 // RCODE=3 (NXDOMAIN)
        bytes[dnsOffset + 6] = 0 // ANCOUNT hi
        bytes[dnsOffset + 7] = 0 // ANCOUNT lo
        bytes[dnsOffset + 8] = 0 // NSCOUNT hi
        bytes[dnsOffset + 9] = 0 // NSCOUNT lo
        bytes[dnsOffset + 10] = 0 // ARCOUNT hi
        bytes[dnsOffset + 11] = 0 // ARCOUNT lo

        // 交换 IPv4 源/目的地址
        for i in 0..<4 {
            let src = bytes[12 + i]
            bytes[12 + i] = bytes[16 + i]
            bytes[16 + i] = src
        }

        // 交换 UDP 源/目的端口（源改为 53）
        bytes[ihl + 0] = 0
        bytes[ihl + 1] = 53
        let origSport = (UInt16(bytes[ihl + 2]) << 8) | UInt16(bytes[ihl + 3])
        bytes[ihl + 2] = UInt8((origSport >> 8) & 0xFF)
        bytes[ihl + 3] = UInt8(origSport & 0xFF)
        // UDP checksum 置 0（IPv4 允许未校验）
        bytes[ihl + 6] = 0
        bytes[ihl + 7] = 0

        // 重算 IPv4 header checksum（先清零原字段）
        bytes[10] = 0
        bytes[11] = 0
        let checksum = ipv4Checksum(bytes, count: ihl)
        bytes[10] = UInt8((checksum >> 8) & 0xFF)
        bytes[11] = UInt8(checksum & 0xFF)

        out = Data(bytes)
        return out
    }

    /// IPv4 header checksum（16-bit 补码和）
    private static func ipv4Checksum(_ bytes: [UInt8], count: Int) -> UInt16 {
        var sum: UInt32 = 0
        var i = 0
        while i < count {
            let word = (UInt32(bytes[i]) << 8) | UInt32(bytes[i + 1])
            sum += word
            i += 2
        }
        while sum >> 16 != 0 {
            sum = (sum & 0xFFFF) + (sum >> 16)
        }
        return UInt16(~sum & 0xFFFF)
    }

    /// 提取 IPv4 UDP 包的 UDP payload（DNS 查询字节），用于转发上游 DNS
    static func udpPayload(from packet: Data, protocolNumber: NSNumber) -> Data? {
        guard protocolNumber.int32Value == AF_INET else { return nil }
        let bytes = [UInt8](packet)
        guard bytes.count >= 28 else { return nil }
        let ihl = Int(bytes[0] & 0x0F) * 4
        guard ihl >= 20, bytes.count >= ihl + 8 else { return nil }
        guard bytes[9] == 17 else { return nil } // UDP
        let udpOffset = ihl
        let udpLength = (UInt16(bytes[udpOffset + 4]) << 8) | UInt16(bytes[udpOffset + 5])
        let payloadStart = udpOffset + 8
        guard payloadStart <= bytes.count else { return nil }
        let rawEnd = min(udpLength == 0 ? bytes.count : udpOffset + Int(udpLength), bytes.count)
        let end = UInt16(rawEnd)
        guard end > UInt16(payloadStart) else { return nil }
        return packet.subdata(in: payloadStart..<Int(end))
    }

    /// 将上游 DNS 响应封装为 IPv4+UDP 包写回隧道（复用查询包的 header，交换源/目）
    static func response(for query: Query, withDNS payload: Data) -> Data {
        let bytes = [UInt8](query.original)
        let ihl = Int(bytes[0] & 0x0F) * 4
        let udpOffset = ihl

        var out = Data(capacity: ihl + 8 + payload.count)
        // IPv4 header（前 ihl 字节）
        out.append(query.original.prefix(ihl))
        var hdr = [UInt8](out)
        // total length
        let total = ihl + 8 + payload.count
        hdr[2] = UInt8((total >> 8) & 0xFF)
        hdr[3] = UInt8(total & 0xFF)
        // 交换源/目的 IP
        for i in 0..<4 {
            let src = hdr[12 + i]
            hdr[12 + i] = hdr[16 + i]
            hdr[16 + i] = src
        }
        // IPv4 checksum
        hdr[10] = 0
        hdr[11] = 0
        let checksum = ipv4Checksum(hdr, count: ihl)
        hdr[10] = UInt8((checksum >> 8) & 0xFF)
        hdr[11] = UInt8(checksum & 0xFF)
        out = Data(hdr)

        // UDP header：源端口 53，目的端口 = 原查询源端口
        var udp = [UInt8](repeating: 0, count: 8)
        udp[0] = 0
        udp[1] = 53
        let origSport = (UInt16(bytes[udpOffset + 2]) << 8) | UInt16(bytes[udpOffset + 3])
        udp[2] = UInt8((origSport >> 8) & 0xFF)
        udp[3] = UInt8(origSport & 0xFF)
        let ulen = 8 + payload.count
        udp[4] = UInt8((ulen >> 8) & 0xFF)
        udp[5] = UInt8(ulen & 0xFF)
        // UDP checksum 置 0（IPv4 允许）
        udp[6] = 0
        udp[7] = 0
        out.append(Data(udp))
        out.append(payload)
        return out
    }
}
