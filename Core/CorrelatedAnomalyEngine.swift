CorrelatedAnomalyEngine.swift
import Foundation

/// Describes a single anomaly event with source type and timestamp
struct AnomalyEvent: Codable {
    let timestamp: Date
    let source: String
}

/// Delegate for receiving correlation alerts
protocol CorrelatedAnomalyDelegate: AnyObject {
    func didDetectCorrelatedAnomaly(sources: Set<String>, events: [AnomalyEvent])
}

/// Singleton engine that tracks short-term anomaly bursts and correlates cross-sensor activity
final class CorrelatedAnomalyEngine {
    
    static let shared = CorrelatedAnomalyEngine()

    /// Anomalies recorded in the rolling window
    private var anomalyEvents: [AnomalyEvent] = []
    
    /// Time window for correlation analysis (in seconds)
    private let correlationWindow: TimeInterval = 10.0
    
    /// Optional delegate to notify when correlation occurs
    weak var delegate: CorrelatedAnomalyDelegate?
    
    /// Serial queue for thread-safe mutation
    private let queue = DispatchQueue(label: "com.bugdetector.CorrelatedAnomalyEngine")

    private init() {}

    /// Registers a new anomaly event from a named source
    func registerEvent(source: String, timestamp: Date = Date()) {
        queue.async {
            self.anomalyEvents.append(AnomalyEvent(timestamp: timestamp, source: source))
            self.pruneOldEvents()
            self.checkCorrelation()
        }
    }

    /// Returns a snapshot of current anomalies (for debugging or export)
    func currentEvents() -> [AnomalyEvent] {
        queue.sync {
            return anomalyEvents
        }
    }

    /// Clears all stored events
    func reset() {
        queue.async {
            self.anomalyEvents.removeAll()
        }
    }

    /// Removes events outside the correlation time window
    private func pruneOldEvents() {
        let cutoff = Date().addingTimeInterval(-correlationWindow)
        anomalyEvents.removeAll { $0.timestamp < cutoff }
    }

    /// Checks if multiple distinct sources are active within the window
    private func checkCorrelation() {
        let recentSources = Set(anomalyEvents.map { $0.source })
        guard recentSources.count > 1 else { return }

        // Emit correlation event
        print("⚠️ Correlated anomaly detected from: \(recentSources)")
        delegate?.didDetectCorrelatedAnomaly(sources: recentSources, events: anomalyEvents)
    }
}


