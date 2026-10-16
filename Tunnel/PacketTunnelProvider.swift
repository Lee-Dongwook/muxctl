import Foundation
import NetworkExtension
import CmuxCloudTunnelCore
import os

final class PacketTunnelProvider: NEPacketTunnelProvider {
    private var adapter: CloudTunnelWireGuardAdapter?
    private var lifecycle: CloudTunnelProviderStartGate?
    private var lifecycleTask: Task<Void, Never>?
    private let runtimeConfigurationRedactor = CloudTunnelRuntimeConfigurationRedactor()

    override init() {
        super.init()
        let adapter = CloudTunnelWireGuardAdapter(provider: self)
        self.adapter = adapter
        let lifecycle = CloudTunnelProviderStartGate(
            adapter: adapter,
            didStop: {exit(0)}
        )
        self.lifecycle = lifecycle
        lifecycleTask = Task { await lifecycle.run() }
    }

    deinit {
        lifecycle?.stop {}
    }
}
