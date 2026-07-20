import Darwin
import Foundation

/// POSIX path policy used by pre-execution authorization receipts.
///
/// Foundation resolves `/private/tmp` through the `/tmp` alias on macOS. That
/// spelling change is unacceptable for a byte-bound authorization path, so
/// existing paths must already equal POSIX `realpath(3)` and future paths must
/// preserve a canonical existing parent's spelling exactly.
public enum SwanSongAuthorizedPathPolicy {
    public static func canonicalExistingPath(_ rawPath: String) throws -> String {
        guard rawPath.hasPrefix("/"), !rawPath.utf8.contains(0) else {
            throw TranslationLabError.unsafePath(rawPath)
        }
        guard let pointer = Darwin.realpath(rawPath, nil) else {
            throw TranslationLabError.unsafePath(rawPath)
        }
        defer { free(pointer) }
        let resolved = String(cString: pointer)
        guard rawPath == resolved else {
            throw TranslationLabError.unsafePath(rawPath)
        }
        return resolved
    }

    public static func canonicalFuturePath(_ rawPath: String) throws -> String {
        guard rawPath.hasPrefix("/"), !rawPath.utf8.contains(0) else {
            throw TranslationLabError.unsafePath(rawPath)
        }
        let components = rawPath.split(
            separator: "/",
            omittingEmptySubsequences: false
        )
        guard components.count >= 2,
              components.first?.isEmpty == true,
              components.dropFirst().allSatisfy({
                  !$0.isEmpty && $0 != "." && $0 != ".."
              }),
              let basename = components.last,
              !basename.isEmpty else {
            throw TranslationLabError.unsafePath(rawPath)
        }
        let parentComponents = components.dropFirst().dropLast()
        let parentPath = parentComponents.isEmpty
            ? "/"
            : "/" + parentComponents.joined(separator: "/")
        let canonicalParent = try canonicalExistingPath(parentPath)
        let expected = canonicalParent == "/"
            ? "/\(basename)"
            : "\(canonicalParent)/\(basename)"
        guard rawPath == expected else {
            throw TranslationLabError.unsafePath(rawPath)
        }
        return expected
    }
}
