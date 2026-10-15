import Foundation
import NetworkExtension
import Combine

/// VPN 开关管理：创建/复用 NETunnelProviderManager，拉起 Packet Tunnel 扩展
final class VPNManager: ObservableObject {
    /// 当前 VPN 状态（.invalid 表示未配置过）
    @Published private(set) var status: NEVPNStatus = .invalid
    /// 开关绑定值：连接中/已连接为 true
    @Published private(set) var isOn = false
    /// 最近一次操作错误（供 UI 展示）
    @Published private(set) var errorMessage: String?

    private var current: NETunnelProviderManager?
    private var statusObserver: NSObjectProtocol?

    init() {
        statusObserver = NotificationCenter.default.addObserver(
            forName: .NEVPNStatusDidChange,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let self,
                  let connection = note.object as? NEVPNConnection
            else { return }
            self.apply(connection: connection)
        }
    }

    /// 从系统偏好加载已保存的 VPN 配置（App 启动/界面出现时调用）
    func load(completion: (() -> Void)? = nil) {
        NETunnelProviderManager.loadAllFromPreferences { [weak self] managers, _ in
            DispatchQueue.main.async {
                guard let self else {
                    completion?()
                    return
                }
                let target = managers?.first {
                    $0.protocolConfiguration is NETunnelProviderProtocol
                }
                self.current = target
                if let target {
                    self.apply(connection: target.connection)
                } else {
                    self.status = .invalid
                    self.isOn = false
                }
                completion?()
            }
        }
    }

    /// 打开 VPN：复用已存配置或新建并保存，随后拉起隧道
    func start() {
        errorMessage = nil
        isOn = true // 乐观反馈，失败时回滚
        if let current {
            do {
                try current.connection.startVPNTunnel()
                apply(connection: current.connection)
            } catch {
                handleStartError(error)
            }
            return
        }

        let manager = NETunnelProviderManager()
        manager.localizedDescription = "CapybaraVPN"
        manager.protocolConfiguration = makeProtocol()
        manager.isEnabled = true

        manager.saveToPreferences { [weak self] error in
            DispatchQueue.main.async {
                guard let self else { return }
                if let error {
                    self.handleStartError(error)
                    return
                }
                manager.loadFromPreferences { [weak self] loadError in
                    DispatchQueue.main.async {
                        guard let self else { return }
                        if let loadError {
                            self.handleStartError(loadError)
                            return
                        }
                        self.current = manager
                        do {
                            try manager.connection.startVPNTunnel()
                            self.apply(connection: manager.connection)
                        } catch {
                            self.handleStartError(error)
                        }
                    }
                }
            }
        }
    }

    /// 关闭 VPN
    func stop() {
        current?.connection.stopVPNTunnel()
        status = .disconnected
        isOn = false
        errorMessage = nil
    }

    // MARK: - 内部

    private func makeProtocol() -> NETunnelProviderProtocol {
        let proto = NETunnelProviderProtocol()
        proto.providerBundleIdentifier = AppConfig.tunnelBundleID
        proto.serverAddress = "capybara"
        proto.disconnectOnSleep = false
        return proto
    }

    private func apply(connection: NEVPNConnection) {
        status = connection.status
        isOn = (connection.status == .connecting || connection.status == .connected)
    }

    private func handleStartError(_ error: Error) {
        isOn = false
        let ns = error as NSError
        // NEVPNError.configurationDisabled 等 → 常见于 MDM 策略禁止创建 VPN
        if ns.domain == NEVPNErrorDomain {
            errorMessage = "无法建立 VPN：当前设备的 VPN 配置被系统/管理策略禁止（MDM 限制或未授予 Network Extension 权限）。"
        } else {
            errorMessage = "无法建立 VPN：\(ns.localizedDescription)"
        }
    }
}
