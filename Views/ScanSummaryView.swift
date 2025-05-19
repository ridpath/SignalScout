import SwiftUI
import CoreLocation

struct ScanSummaryView: View {
    @ObservedObject var coordinator: ScanCoordinator

    var body: some View {
        List {
            // Bluetooth Devices
            if !coordinator.scanResults.filter({ $0.type == .bluetooth }).isEmpty {
                Section(header: Text("Bluetooth Devices")) {
                    ForEach(coordinator.scanResults.filter { $0.type == .bluetooth }) { result in
                        DeviceRow(result: result)
                    }
                }
            }

            // Wi-Fi Devices
            if !coordinator.scanResults.filter({ $0.type == .wifi }).isEmpty {
                Section(header: Text("Wi-Fi Devices")) {
                    ForEach(coordinator.scanResults.filter { $0.type == .wifi }) { result in
                        DeviceRow(result: result)
                    }
                }
            }

            // EMF Anomalies
            if !coordinator.scanResults.filter({ $0.type == .emf }).isEmpty {
                Section(header: Text("EMF Anomalies")) {
                    ForEach(coordinator.scanResults.filter { $0.type == .emf }) { result in
                        EMFAnomalyRow(result: result)
                    }
                }
            }

            // Advanced Detection
            if !coordinator.airtagScanner.suspectedTrackers.isEmpty ||
                coordinator.wifiSpoofScanner.isSuspicious ||
                coordinator.motionEMFScanner.correlationDetected {
                Section(header: Text("Advanced Detection")) {
                    if !coordinator.airtagScanner.suspectedTrackers.isEmpty {
                        Text("🔍 Possible Trackers: \(coordinator.airtagScanner.suspectedTrackers.count)")
                            .foregroundColor(.orange)
                    }
                    if coordinator.wifiSpoofScanner.isSuspicious {
                        Text("⚠️ Wi-Fi Spoofing Detected")
                            .foregroundColor(.red)
                    }
                    if coordinator.motionEMFScanner.correlationDetected {
                        Text("⚠️ Motion & EMF Anomaly Correlated")
                            .foregroundColor(.red)
                    }
                }
            }
        }
        .navigationTitle("Scan Results")
        .navigationBarTitleDisplayMode(.inline)
        .listStyle(GroupedListStyle())
        .background(Color(.systemGroupedBackground))
        .accessibilityElement(children: .contain)
    }
}

// MARK: - Device Row

struct DeviceRow: View {
    let result: ScanResult

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(result.device.name ?? "Unknown Device")
                    .font(.headline)
                Spacer()
                ThreatBadge(level: result.threatLevel)
            }

            if let manufacturer = result.device.manufacturer {
                Text("Manufacturer: \(manufacturer)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            if let location = result.device.deviceNotes {
                Text("Location: \(location)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Text("Last Seen: \(result.lastSeen, style: .relative)")
                .font(.caption)
                .foregroundColor(.gray)
        }
        .padding(.vertical, 5)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - EMF Anomaly Row

struct EMFAnomalyRow: View {
    let result: ScanResult

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(result.device.name ?? "Magnetic Anomaly")
                    .font(.headline)
                Spacer()
                ThreatBadge(level: result.threatLevel)
            }

            if let last = result.device.signalHistory.last {
                Text("Last Magnitude: \(last.rssi) µT")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            if let notes = result.device.deviceNotes {
                Text("Details: \(notes)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Text("Detected at: \(result.lastSeen, style: .time)")
                .font(.caption)
                .foregroundColor(.gray)
        }
        .padding(.vertical, 5)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Threat Badge

struct ThreatBadge: View {
    let level: ThreatLevel

    var body: some View {
        Text(level.rawValue.capitalized)
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(threatColor(level).opacity(0.15))
            .foregroundColor(threatColor(level))
            .cornerRadius(4)
            .accessibilityLabel("Threat level \(level.rawValue)")
    }

    private func threatColor(_ level: ThreatLevel) -> Color {
        switch level {
        case .low: return .green
        case .moderate: return .yellow
        case .high: return .orange
        case .critical: return .red
        }
    }
}

// MARK: - Utility Extensions

extension ScanResult {
    var lastSeen: Date {
        device.timestamp ?? Date()
    }
}

extension CLPlacemark {
    var compactAddress: String? {
        [subThoroughfare, thoroughfare, locality, administrativeArea, postalCode, country]
            .compactMap { $0 }
            .joined(separator: ", ")
    }
}
