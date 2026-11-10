//
//  ConfigFile.swift
//  BallGesture
//
//  Reads, writes and watches a JSON file that is edited by hand as well as by
//  the app.
//

import Foundation

@MainActor
final class ConfigFile {
    enum ReadResult {
        case missing
        case unparseable
        case parsed([String: Any])
    }

    let url: URL

    /// Modification date of the file last read or written. The file is often
    /// a symlink into a dotfiles folder, and editors save by replacing the
    /// target, so the date is taken from the resolved path rather than the link.
    private var stamp: Date?
    private var watchTimer: Timer?

    init(url: URL) {
        self.url = url
    }

    /// The file the link points at, followed link by link so a link whose
    /// target does not exist yet still resolves to where the target belongs.
    /// Writing there instead of at `url` keeps the link itself in place.
    var resolvedURL: URL {
        var current = url
        for _ in 0..<16 {
            guard let destination = try? FileManager.default.destinationOfSymbolicLink(atPath: current.path) else {
                break
            }
            current = URL(fileURLWithPath: destination, relativeTo: current.deletingLastPathComponent())
                .standardizedFileURL
        }
        return current.resolvingSymlinksInPath()
    }

    private func currentStamp() -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: resolvedURL.path))?[.modificationDate] as? Date
    }

    /// Reads the file and remembers its date, so the watcher only reports
    /// changes made after this read.
    func read() -> ReadResult {
        // Taken before the contents, so an edit landing mid-read is seen again.
        stamp = currentStamp()
        return load()
    }

    private func load() -> ReadResult {
        let target = resolvedURL
        guard FileManager.default.fileExists(atPath: target.path) else { return .missing }
        guard let data = try? Data(contentsOf: target),
              let raw = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return .unparseable
        }
        return .parsed(raw)
    }

    /// Writes `owned` into the file, merged into what is already there so keys
    /// the app does not know about (hand-added, or from a later version) are
    /// kept. Objects merge key by key; any other value replaces the old one,
    /// and `NSNull` removes the key. Returns a problem to show, or nil.
    func write(_ owned: [String: Any]) -> String? {
        let target = resolvedURL
        var raw: [String: Any] = [:]
        switch load() {
        case .missing:
            break
        case .unparseable:
            // Writing over a file that does not parse would replace the
            // user's settings with only what the app knows.
            return "config.json is not valid JSON; changes are not saved until it is fixed."
        case .parsed(let existing):
            raw = existing
        }
        raw = Self.merge(owned, into: raw)

        do {
            var data = try JSONSerialization.data(
                withJSONObject: raw,
                options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            )
            data.append(contentsOf: Array("\n".utf8))
            try FileManager.default.createDirectory(
                at: target.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: target, options: .atomic)
        } catch {
            return "config.json could not be saved: \(error.localizedDescription)"
        }
        // The app already holds what it just wrote; reading it back would
        // only fire change notifications for nothing.
        stamp = currentStamp()
        return nil
    }

    private static func merge(_ owned: [String: Any], into existing: [String: Any]) -> [String: Any] {
        var result = existing
        for (key, value) in owned {
            if value is NSNull {
                result.removeValue(forKey: key)
            } else if let ownedObject = value as? [String: Any],
                      let existingObject = existing[key] as? [String: Any] {
                result[key] = merge(ownedObject, into: existingObject)
            } else {
                result[key] = value
            }
        }
        return result
    }

    /// Calls `onChange` whenever the file's date moves on from the last read
    /// or write, so a hand edit takes effect while the app runs.
    func startWatching(onChange: @escaping @MainActor () -> Void) {
        watchTimer?.invalidate()
        watchTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                let now = self.currentStamp()
                guard now != self.stamp else { return }
                self.stamp = now
                onChange()
            }
        }
    }
}
