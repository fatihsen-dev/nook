import Foundation

private let timestampFormat = Date.FormatStyle().hour(.twoDigits(amPM: .omitted)).minute(.twoDigits).second(.twoDigits)

public func writeLog(_ message: String) {
    print("\(Date().formatted(timestampFormat))  \(message)")
}
