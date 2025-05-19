import Foundation

final class ScanHistoryManager {
    static let shared = ScanHistoryManager()

    private let fileURL: URL
    private let queue = DispatchQueue(label: "com.signalScout.scanHistory", qos: .utility)

    private init() {
        fileURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("scan_history.json")
    }

    // MARK: - Save Results
    static func saveResults(_ results: [ScanResult]) {
        shared.queue.async {
            do {
                var history = shared.loadHistorySync()
                history.append(contentsOf: results)

                if history.count > 1000 {
                    history = Array(history.suffix(1000))
                }

                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .iso8601
                let data = try encoder.encode(history)
                try data.write(to: shared.fileURL, options: [.atomic])
                shared.log("✅ Saved \(results.count) scan results")
            } catch {
                shared.log("❌ Error saving scan history: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Load History (Sync)
    func loadHistorySync() -> [ScanResult] {
        do {
            guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode([ScanResult].self, from: data)
        } catch {
            log("❌ Error loading scan history: \(error.localizedDescription)")
            return []
        }
    }

    // MARK: - Load History (Async)
    func loadHistory(completion: @escaping ([ScanResult]) -> Void) {
        queue.async {
            let history = self.loadHistorySync()
            DispatchQueue.main.async {
                completion(history)
            }
        }
    }

    // MARK: - Clear History
    func clearHistory(completion: (() -> Void)? = nil) {
        queue.async {
            do {
                if FileManager.default.fileExists(atPath: self.fileURL.path) {
                    try FileManager.default.removeItem(at: self.fileURL)
                    self.log("🗑️ Cleared scan history")
                }
            } catch {
                self.log("❌ Error clearing scan history: \(error.localizedDescription)")
            }

            if let completion = completion {
                DispatchQueue.main.async {
                    completion()
                }
            }
        }
    }

    // MARK: - Logging
    private func log(_ message: String) {
#if DEBUG
        print(message)
#endif
    }
}
