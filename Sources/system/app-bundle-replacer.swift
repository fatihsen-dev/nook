import Foundation
import NookCore
import Security

let appTranslocationPathComponent = "AppTranslocation"
let appBundleExtension = "app"
let developerIDApplicationExtension = "1.2.840.113635.100.6.1.13"

struct InPlaceAppBundleReplacer: AppBundleReplacer {
    let appBundle: URL
    let bundleIdentifier: String
    let ditto: URL

    var canReplaceInPlace: Bool {
        guard appBundle.pathExtension == appBundleExtension,
              !appBundle.pathComponents.contains(appTranslocationPathComponent),
              (try? appBundle.resourceValues(forKeys: [.volumeIsReadOnlyKey]).volumeIsReadOnly) != true
        else { return false }
        return FileManager.default.isWritableFile(atPath: appBundle.deletingLastPathComponent().path)
    }

    func replace(withArchive archive: URL) async throws {
        guard let team = currentSigningTeam() else { throw AppUpdateError.unsignedCurrentCopy }
        let staging = try FileManager.default.url(for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: appBundle, create: true)
        let unpacked = try await unpack(archive, into: staging)
        try verifySignature(of: unpacked, bundleIdentifier: bundleIdentifier, team: team)
        _ = try FileManager.default.replaceItemAt(appBundle, withItemAt: unpacked, backupItemName: nil, options: .usingNewMetadataOnly)
        try FileManager.default.removeItem(at: staging)
        try FileManager.default.removeItem(at: archive)
    }

    private func unpack(_ archive: URL, into directory: URL) async throws -> URL {
        let output = try await runProcess(ditto, arguments: ["-x", "-k", archive.path, directory.path])
        guard output.isSuccess else { throw AppUpdateError.unpackFailed(output.text) }
        let app = directory.appending(path: appBundle.lastPathComponent)
        guard FileManager.default.fileExists(atPath: app.path) else {
            throw AppUpdateError.missingAppInArchive(appBundle.lastPathComponent)
        }
        return app
    }
}

func currentSigningTeam() -> String? {
    var code: SecCode?
    var staticCode: SecStaticCode?
    var information: CFDictionary?
    guard SecCodeCopySelf([], &code) == errSecSuccess, let code,
          SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode,
          SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &information) == errSecSuccess
    else { return nil }
    return (information as? [String: Any])?[kSecCodeInfoTeamIdentifier as String] as? String
}

func verifySignature(of app: URL, bundleIdentifier: String, team: String) throws {
    var staticCode: SecStaticCode?
    guard SecStaticCodeCreateWithPath(app as CFURL, [], &staticCode) == errSecSuccess, let staticCode else {
        throw AppUpdateError.untrustedSignature("\(app.path) has no code signature")
    }
    let requirementText = "anchor apple generic and identifier \"\(bundleIdentifier)\" and certificate leaf[field.\(developerIDApplicationExtension)] exists and certificate leaf[subject.OU] = \"\(team)\""
    var requirement: SecRequirement?
    guard SecRequirementCreateWithString(requirementText as CFString, [], &requirement) == errSecSuccess, let requirement else {
        throw AppUpdateError.untrustedSignature("invalid code requirement \(requirementText)")
    }
    let flags = SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSStrictValidate | kSecCSCheckNestedCode)
    let status = SecStaticCodeCheckValidity(staticCode, flags, requirement)
    guard status == errSecSuccess else {
        let reason = SecCopyErrorMessageString(status, nil) as String? ?? "code signature check failed with status \(status)"
        throw AppUpdateError.untrustedSignature("\(reason) (expected Developer ID \(team)).")
    }
}
