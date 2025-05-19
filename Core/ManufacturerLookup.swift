import Foundation

final class ManufacturerLookup {
    static let shared = ManufacturerLookup()

    private var db: [String: String] = [:]
    private let queue = DispatchQueue(label: "com.signalScout.manufacturerLookup", qos: .userInitiated)
    private var loaded = false

    private init() {
        loadDatabaseSync() // <-- 🔐 load immediately and synchronously at init
    }

    /// Whether the OUI database is loaded and ready
    var isLoaded: Bool {
        queue.sync {
            return loaded && !db.isEmpty
        }
    }

    /// Main lookup entry point
    func lookup(macOrBSSID: String) -> String? {
        let prefix = normalizePrefix(macOrBSSID)

        // Block until loaded (at most 2 seconds for safety)
        let deadline = DispatchTime.now() + .seconds(2)
        while !isLoaded && DispatchTime.now() < deadline {
            usleep(10_000) // wait 10ms
        }

        return queue.sync {
            return db[prefix]
        }
    }

    /// Synchronously load the OUI database from JSON (first time only)
    private func loadDatabaseSync() {
        guard let path = Bundle.main.path(forResource: "oui", ofType: "json") else {
            log("❌ OUI database file not found.")
            return
        }

        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: path))
            let parsed = try JSONDecoder().decode([String: String].self, from: data)

            queue.sync {
                self.db = parsed
                self.loaded = true
            }

            log("✅ Loaded \(parsed.count) OUI entries")
        } catch {
            log("❌ Failed to load OUI database: \(error)")
        }
    }

    /// Normalize MAC/BSSID format into XX:XX:XX
    private func normalizePrefix(_ input: String) -> String {
        let cleaned = input
            .uppercased()
            .replacingOccurrences(of: "-", with: ":")
            .replacingOccurrences(of: ".", with: ":")
            .replacingOccurrences(of: " ", with: "")
            .split(separator: ":")
            .prefix(3)
            .map { $0.count == 1 ? "0\($0)" : String($0) } // pad if needed
            .joined(separator: ":")
        return cleaned
    }

    private func log(_ message: String) {
        #if DEBUG
        print(message)
        #endif
    }
}
