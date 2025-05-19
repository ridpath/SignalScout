import Foundation

struct ScanResult: Identifiable, Codable {
    let id: UUID
    let device: DeviceModel
    let type: DeviceType

    // MARK: - Derived Properties (not serialized)
    
    /// Threat score 0–100 derived from RSSI patterns, duration, etc.
    var severityScore: Double {
        device.severityScore
    }

    /// Enum: `.low`, `.moderate`, `.high`, `.critical`
    var threatLevel: ThreatLevel {
        device.threatLevel
    }

    /// Time since first signal recorded
    var duration: TimeInterval {
        guard let first = device.signalHistory.first?.timestamp,
              let last = device.signalHistory.last?.timestamp else { return 0 }
        return last.timeIntervalSince(first)
    }

    /// Sortable timestamp of most recent activity
    var lastSeen: Date {
        device.timestamp ?? Date.distantPast
    }

    /// UI grouping key (e.g., for Section headers)
    var sectionKey: String {
        "\(type.rawValue.capitalized) - \(threatLevel.rawValue.capitalized)"
    }

    // MARK: - Initializer
    init(device: DeviceModel, type: DeviceType) {
        self.id = UUID()
        self.device = device
        self.type = type
    }

    // MARK: - Codable
    enum CodingKeys: String, CodingKey {
        case id, device, type
    }
}
