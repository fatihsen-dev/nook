import Foundation

public final class FileChangeMonitor: @unchecked Sendable {
    private let source: DispatchSourceFileSystemObject

    public init(file: URL, queue: DispatchQueue, onChange: @escaping @Sendable () -> Void) throws {
        let descriptor = open(file.path, O_EVTONLY)
        guard descriptor >= 0 else {
            throw FileChangeMonitorError.cannotOpen(file.path)
        }
        source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor, eventMask: [.write, .extend, .delete, .rename], queue: queue)
        source.setEventHandler(handler: onChange)
        source.setCancelHandler { close(descriptor) }
        source.resume()
    }

    public var isFileGone: Bool {
        !source.data.isDisjoint(with: [.delete, .rename])
    }

    deinit {
        source.cancel()
    }
}

public enum FileChangeMonitorError: Error, Equatable, LocalizedError {
    case cannotOpen(String)

    public var errorDescription: String? {
        switch self {
        case .cannotOpen(let path):
            "Could not watch \(path) for changes; the file does not exist or is not readable."
        }
    }
}
