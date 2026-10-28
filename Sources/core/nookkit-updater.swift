import Foundation

public struct NookKitUpdater: Sendable {
    let url: URL
    let version: AppVersion
    let builder: NookletBuilder
    let store: NookKitSyncStore

    public init(url: URL, version: AppVersion, builder: NookletBuilder, store: NookKitSyncStore) {
        self.url = url
        self.version = version
        self.builder = builder
        self.store = store
    }

    func isOutdated(_ nooklet: InstalledNooklet) throws -> Bool {
        guard try store.load()[nooklet.manifest.id] != version.description else { return false }
        let packageManifest = try String(contentsOf: packageManifestURL(of: nooklet), encoding: .utf8)
        return packageManifest.contains(remotePackageReference(url: url))
    }

    func update(_ nooklet: InstalledNooklet) async throws {
        let manifestURL = packageManifestURL(of: nooklet)
        let packageManifest = try String(contentsOf: manifestURL, encoding: .utf8)
        if let pinned = pinNookKitDependency(in: packageManifest, url: url, version: version) {
            try Data(pinned.utf8).write(to: manifestURL, options: .atomic)
        }
        try await builder.updateDependency(nookKitPackageIdentity, packageDirectory: nooklet.directory)
        try record(nooklet.manifest.id, as: version.description)
    }

    func markCurrent(_ id: String) throws {
        try record(id, as: version.description)
    }

    func forget(_ id: String) throws {
        var versions = try store.load()
        guard versions.removeValue(forKey: id) != nil else { return }
        try store.save(versions)
    }

    private func record(_ id: String, as version: String) throws {
        var versions = try store.load()
        versions[id] = version
        try store.save(versions)
    }

    private func packageManifestURL(of nooklet: InstalledNooklet) -> URL {
        nooklet.directory.appending(path: packageManifestFileName)
    }
}
