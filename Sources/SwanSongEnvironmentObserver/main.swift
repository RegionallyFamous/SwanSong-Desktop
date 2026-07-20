import Darwin
import Foundation

private typealias EnvironmentEntryPointer = UnsafeMutablePointer<CChar>
private typealias EnvironmentPointer = UnsafeMutablePointer<EnvironmentEntryPointer?>

@_silgen_name("_NSGetEnviron")
private func systemEnvironmentPointer() -> UnsafeMutablePointer<EnvironmentPointer?>

func rawCEnvironment() throws -> [String: String] {
    guard var cursor = systemEnvironmentPointer().pointee else {
        throw CocoaError(.fileReadUnknown)
    }
    var result: [String: String] = [:]
    while let entryPointer = cursor.pointee {
        let entry = String(cString: entryPointer)
        guard let separator = entry.firstIndex(of: "=") else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let key = String(entry[..<separator])
        let value = String(entry[entry.index(after: separator)...])
        guard !key.isEmpty, result.updateValue(value, forKey: key) == nil else {
            throw CocoaError(.fileReadCorruptFile)
        }
        cursor = cursor.advanced(by: 1)
    }
    return result
}

do {
    let raw = try rawCEnvironment()
    let foundation = ProcessInfo.processInfo.environment
    var output = try JSONSerialization.data(
        withJSONObject: [
            "rawCEnvironment": raw,
            "foundationEnvironment": foundation,
        ],
        options: [.sortedKeys, .withoutEscapingSlashes]
    )
    output.append(0x0A)
    FileHandle.standardOutput.write(output)
} catch {
    FileHandle.standardError.write(Data("environment observation failed\n".utf8))
    exit(1)
}
