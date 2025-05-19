import Foundation
import CoreLocation
import Combine

// MARK: - SignalSample
struct SignalSample: Identifiable, Codable {
    let id = UUID()
    let timestamp: Date
    let rssi: Int
}

// MARK: - ThreatLevel Enum
enum ThreatLevel: String, Codable, CaseIterable {
    case low, moderate, high, critical
}

// MARK: - DeviceType Enum
enum DeviceType: String, CaseIterable, Codable {
    case bluetooth, wifi, ir, emf
}

// MARK: - DeviceModel
class DeviceModel: Identifiable, ObservableObject, Codable {
    // Static Identifiable ID
    let id: UUID

    // Static properties
    let name: String
    let type: DeviceType
    let identifier: String
    let manufacturer: String?

    // Dynamic properties
    @Published var currentRSSI: Int?
    @Published var signalHistory: [SignalSample] = []
    @Published var latitude: Double?
    @Published var longitude: Double?
    @Published var ssid: String?
    @Published var timestamp: Date?

    @Published var threatLevel: ThreatLevel = .low
    @Published var severityScore: Double = 0.0
    @Published var isStatic: Bool = false
    @Published var deviceNotes: String?

    // MARK: - Init
    init(name: String, type: DeviceType, identifier: String, manufacturer: String? = nil) {
        self.id = UUID()
        self.name = name
        self.type = type
        self.identifier = identifier
        self.manufacturer = manufacturer
    }

    // MARK: - Update Signal & Score
    func addRSSISample(_ rssi: Int) {
        let sample = SignalSample(timestamp: Date(), rssi: rssi)
        signalHistory.append(sample)
        if signalHistory.count > 100 {
            signalHistory.removeFirst()
        }

        currentRSSI = rssi
        timestamp = sample.timestamp
        updateSeverityScore()
    }

    // MARK: - Severity Scoring
    private func updateSeverityScore() {
        let rssiStability = signalHistory.count > 5 ? 30.0 : 10.0
        let duration = signalHistory.last!.timestamp.timeIntervalSince(signalHistory.first!.timestamp)
        let durationScore = min(30.0, duration * 10)
        let rssiScore = Double(max(0, (currentRSSI ?? -100) + 100)) // Normalize -100 → 0

        severityScore = min(100.0, rssiStability + durationScore + rssiScore)

        switch severityScore {
        case 0..<30: threatLevel = .low
        case 30..<60: threatLevel = .moderate
        case 60..<85: threatLevel = .high
        default: threatLevel = .critical
        }
    }

    // MARK: - Codable Support
    enum CodingKeys: String, CodingKey {
        case id, name, type, identifier, manufacturer
        case currentRSSI, signalHistory, latitude, longitude, ssid, timestamp
        case threatLevel, severityScore, isStatic, deviceNotes
    }

    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.name = try container.decode(String.self, forKey: .name)
        self.type = try container.decode(DeviceType.self, forKey: .type)
        self.identifier = try container.decode(String.self, forKey: .identifier)
        self.manufacturer = try container.decodeIfPresent(String.self, forKey: .manufacturer)
        self.currentRSSI = try container.decodeIfPresent(Int.self, forKey: .currentRSSI)
        self.signalHistory = try container.decode([SignalSample].self, forKey: .signalHistory)
        self.latitude = try container.decodeIfPresent(Double.self, forKey: .latitude)
        self.longitude = try container.decodeIfPresent(Double.self, forKey: .longitude)
        self.ssid = try container.decodeIfPresent(String.self, forKey: .ssid)
        self.timestamp = try container.decodeIfPresent(Date.self, forKey: .timestamp)
        self.threatLevel = try container.decode(ThreatLevel.self, forKey: .threatLevel)
        self.severityScore = try container.decode(Double.self, forKey: .severityScore)
        self.isStatic = try container.decodeIfPresent(Bool.self, forKey: .isStatic) ?? false
        self.deviceNotes = try container.decodeIfPresent(String.self, forKey: .deviceNotes)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(type, forKey: .type)
        try container.encode(identifier, forKey: .identifier)
        try container.encodeIfPresent(manufacturer, forKey: .manufacturer)
        try container.encodeIfPresent(currentRSSI, forKey: .currentRSSI)
        try container.encode(signalHistory, forKey: .signalHistory)
        try container.encodeIfPresent(latitude, forKey: .latitude)
        try container.encodeIfPresent(longitude, forKey: .longitude)
        try container.encodeIfPresent(ssid, forKey: .ssid)
        try container.encodeIfPresent(timestamp, forKey: .timestamp)
        try container.encode(threatLevel, forKey: .threatLevel)
        try container.encode(severityScore, forKey: .severityScore)
        try container.encode(isStatic, forKey: .isStatic)
        try container.encodeIfPresent(deviceNotes, forKey: .deviceNotes)
    }
}
