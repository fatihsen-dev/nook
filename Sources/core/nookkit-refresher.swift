import Foundation

public struct NookKitRefreshFailure: Equatable, Sendable {
    public let nookletID: String
    public let reason: String
}

public struct NookKitRefresher: Sendable {
    let manager: NookletManager
    let builder: NookletBuilder
    let versionStore: NookKitVersionStore

    public init(manager: NookletManager, builder: NookletBuilder, versionStore: NookKitVersionStore) {
        self.manager = manager
        self.builder = builder
        self.versionStore = versionStore
    }

    public func refreshIfNeeded(appVersion: String) async throws -> [NookKitRefreshFailure] {
        guard try versionStore.load() != appVersion else { return [] }
        var failures: [NookKitRefreshFailure] = []
        var isRetryNeeded = false
        for case .ready(let nooklet) in try manager.libraryEntries() {
            let id = nooklet.manifest.id
            do {
                try await builder.updateDependency(nookKitPackageIdentity, packageDirectory: nooklet.directory)
            } catch {
                failures.append(NookKitRefreshFailure(nookletID: id, reason: error.localizedDescription))
                isRetryNeeded = true
                continue
            }
            guard case .running = try await manager.runtime(of: nooklet) else { continue }
            let report = try await manager.run(nooklet)
            if !report.isSuccess {
                failures.append(NookKitRefreshFailure(nookletID: id, reason: "It does not build with the new NookKit; the previous build keeps running. Open it in Nook to see the errors."))
            }
        }
        if !isRetryNeeded {
            try versionStore.save(appVersion)
        }
        return failures
    }
}
