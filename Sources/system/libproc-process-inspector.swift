import Darwin
import Foundation
import NookCore

let microsecondsPerSecond = 1_000_000.0

public struct LibprocProcessInspector: ProcessInspector {
    public init() {}

    public func metrics(pid: Int32) throws -> ProcessMetrics? {
        guard let memoryBytes = try readMemoryFootprint(pid: pid), let startDate = try readStartDate(pid: pid) else {
            return nil
        }
        return ProcessMetrics(memoryBytes: memoryBytes, startDate: startDate)
    }

    private func readMemoryFootprint(pid: Int32) throws -> UInt64? {
        var usage = rusage_info_v2()
        let result = withUnsafeMutablePointer(to: &usage) { pointer in
            pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_V2, $0) }
        }
        guard result == 0 else {
            return try missingProcessOrThrow(pid: pid, call: "proc_pid_rusage")
        }
        return usage.ri_phys_footprint
    }

    private func readStartDate(pid: Int32) throws -> Date? {
        var info = proc_bsdinfo()
        let expectedSize = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, expectedSize) == expectedSize else {
            return try missingProcessOrThrow(pid: pid, call: "proc_pidinfo")
        }
        let seconds = TimeInterval(info.pbi_start_tvsec) + TimeInterval(info.pbi_start_tvusec) / microsecondsPerSecond
        return Date(timeIntervalSince1970: seconds)
    }

    private func missingProcessOrThrow<Value>(pid: Int32, call: String) throws -> Value? {
        let code = errno
        guard code == ESRCH else {
            throw ProcessInspectorError.unreadable(pid: pid, call: call, code: code)
        }
        return nil
    }
}

public enum ProcessInspectorError: Error, LocalizedError {
    case unreadable(pid: Int32, call: String, code: Int32)

    public var errorDescription: String? {
        switch self {
        case .unreadable(let pid, let call, let code):
            "\(call) failed for process \(pid): \(String(cString: strerror(code)))"
        }
    }
}
