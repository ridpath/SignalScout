import Foundation
import CoreMotion
import CoreLocation
import AVFoundation
import UIKit
import CoreTelephony
import SystemConfiguration.CaptiveNetwork

class MagnetometerScanner: NSObject, ObservableObject {

    @Published var devices: [DeviceModel] = []
    @Published var isScanning: Bool = false

    private let motionManager = CMMotionManager()
    private let locationManager = CLLocationManager()
    private let telephonyNetworkInfo = CTTelephonyNetworkInfo()
    private let queue = OperationQueue()

    private var sampleBuffer: [(magnitude: Double, timestamp: Date)] = []
    private let maxBufferSize = 1000

    private var baselineMagnitude: Double = 50.0
    private var anomalyThreshold: Double = 20.0

    private var lastAnomalyTimestamp: Date?
    private var lastTriggerTimestamp: Date?
    private var currentLocation: CLLocation?
    private var currentSSID: String?
    private var currentCellTowerID: String?

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.requestWhenInUseAuthorization()
        startMonitoring()
        updateNetworkInfo()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @MainActor
    func startScan() async {
        guard motionManager.isMagnetometerAvailable, motionManager.isDeviceMotionAvailable else {
            logError("🚫 Magnetometer or device motion unavailable.")
            return
        }

        motionManager.magnetometerUpdateInterval = 0.01
        motionManager.deviceMotionUpdateInterval = 0.01

        motionManager.startMagnetometerUpdates(to: queue) { [weak self] data, error in
            guard let self = self, let field = data?.magneticField else {
                if let error = error { self?.logError("❌ Magnetometer error: \(error)") }
                return
            }

            let timestamp = Date()
            let magnitude = sqrt(field.x * field.x + field.y * field.y + field.z * field.z)

            self.sampleBuffer.append((magnitude, timestamp))
            if self.sampleBuffer.count > self.maxBufferSize {
                self.sampleBuffer.removeFirst()
            }

            self.updateBaseline()

            if self.isAnomaly(magnitude: magnitude) {
                self.processAnomaly(magnitude: magnitude, timestamp: timestamp)
            }
        }

        motionManager.startDeviceMotionUpdates(to: queue) { [weak self] data, error in
            guard let self = self, let motion = data else {
                if let error = error { self?.logError("❌ Device motion error: \(error)") }
                return
            }
            self.correlateMotionWithAnomalies(motion: motion)
        }

        isScanning = true
        locationManager.startUpdatingLocation()
    }

    func stopScan() {
        motionManager.stopMagnetometerUpdates()
        motionManager.stopDeviceMotionUpdates()
        sampleBuffer.removeAll()
        locationManager.stopUpdatingLocation()
        isScanning = false
    }

    // MARK: - Anomaly Processing

    private func processAnomaly(magnitude: Double, timestamp: Date) {
        guard let location = currentLocation else {
            logWarning("⚠️ No GPS fix for anomaly.")
            return
        }

        let frequency = estimateFrequency()
        let anomalyScore = computeAnomalyScore(magnitude: magnitude, frequency: frequency)

        let deviceName = frequency > 1.0 ? NSLocalizedString("RF Source", comment: "Device name") : NSLocalizedString("Magnetic Disturbance", comment: "Device name")
        let identifier = String(format: "emf_%.4f_%.4f", location.coordinate.latitude, location.coordinate.longitude)

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            let scoreInt = Int(magnitude)
            let threat: ThreatLevel = anomalyScore > 90 ? .critical : anomalyScore > 75 ? .high : .moderate

            if let index = self.devices.firstIndex(where: { $0.identifier == identifier }) {
                self.devices[index].addRSSISample(scoreInt)
                self.devices[index].timestamp = timestamp
                self.devices[index].threatLevel = threat
                self.devices[index].severityScore = anomalyScore
            } else {
                let device = DeviceModel(
                    name: deviceName,
                    type: .emf,
                    identifier: identifier,
                    manufacturer: nil
                )
                device.latitude = location.coordinate.latitude
                device.longitude = location.coordinate.longitude
                device.timestamp = timestamp
                device.threatLevel = threat
                device.severityScore = anomalyScore
                device.addRSSISample(scoreInt)
                device.deviceNotes = self.correlateNetworkInfo()
                self.reverseGeocodeLocation(for: device)

                self.devices.append(device)
            }

            CorrelatedAnomalyEngine.shared.registerEvent(source: "emf", timestamp: timestamp)

            self.logInfo("🧲 EMF Anomaly @ \(deviceName) | Mag: \(magnitude) µT | Freq: \(frequency) Hz | Score: \(anomalyScore)")

            if anomalyScore > 80, self.shouldTriggerFeedback(since: timestamp) {
                self.triggerFlashPulse()
                self.triggerHapticFeedback()
                self.lastTriggerTimestamp = timestamp
            }

            self.lastAnomalyTimestamp = timestamp
        }
    }

    private func shouldTriggerFeedback(since timestamp: Date) -> Bool {
        guard let last = lastTriggerTimestamp else { return true }
        return timestamp.timeIntervalSince(last) > 1.0
    }

    // MARK: - Baseline/Scoring

    private func updateBaseline() {
        guard sampleBuffer.count > 10 else { return }
        let sorted = sampleBuffer.map { $0.magnitude }.sorted()
        baselineMagnitude = sorted[sorted.count / 2]
        anomalyThreshold = baselineMagnitude * 0.4
    }

    private func isAnomaly(magnitude: Double) -> Bool {
        return magnitude > baselineMagnitude + anomalyThreshold
    }

    private func estimateFrequency() -> Double {
        guard sampleBuffer.count >= 100 else { return 0.0 }
        let mean = sampleBuffer.map(\.magnitude).reduce(0.0, +) / Double(sampleBuffer.count)
        let crossings = zip(sampleBuffer.dropLast(), sampleBuffer.dropFirst())
            .filter { ($0.0.magnitude < mean && $0.1.magnitude >= mean) || ($0.0.magnitude > mean && $0.1.magnitude <= mean) }
            .count

        let duration = sampleBuffer.last!.timestamp.timeIntervalSince(sampleBuffer.first!.timestamp)
        return Double(crossings) / (2.0 * duration)
    }

    private func computeAnomalyScore(magnitude: Double, frequency: Double) -> Double {
        let magScore = min(1.0, (magnitude - baselineMagnitude) / 200.0)
        let freqScore = min(1.0, frequency / 10.0)
        return (magScore + freqScore) / 2.0 * 100.0
    }

    // MARK: - Motion Correlation

    private func correlateMotionWithAnomalies(motion: CMDeviceMotion) {
        let rotation = sqrt(motion.rotationRate.x * motion.rotationRate.x +
                            motion.rotationRate.y * motion.rotationRate.y +
                            motion.rotationRate.z * motion.rotationRate.z)

        let accel = sqrt(motion.userAcceleration.x * motion.userAcceleration.x +
                         motion.userAcceleration.y * motion.userAcceleration.y +
                         motion.userAcceleration.z * motion.userAcceleration.z)

        if (rotation > 0.5 || accel > 0.2),
           let last = lastAnomalyTimestamp,
           abs(last.timeIntervalSinceNow) < 0.5 {
            logWarning("⚠️ Motion-correlated EMF anomaly detected (Rotation: \(rotation), Accel: \(accel))")
        }
    }

    // MARK: - Feedback

    private func triggerFlashPulse() {
        guard let device = AVCaptureDevice.default(for: .video), device.hasTorch else {
            logWarning("⚠️ Torch not available.")
            return
        }

        do {
            try device.lockForConfiguration()
            device.torchMode = .on
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                device.torchMode = .off
                device.unlockForConfiguration()
            }
        } catch {
            logError("❌ Flash error: \(error)")
        }
    }

    private func triggerHapticFeedback() {
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.warning)
    }

    // MARK: - Network Correlation

    private func updateNetworkInfo() {
        if let carrier = telephonyNetworkInfo.serviceSubscriberCellularProviders?.values.first,
           let mnc = carrier.mobileNetworkCode,
           let mcc = carrier.mobileCountryCode {
            currentCellTowerID = "\(mcc)-\(mnc)"
        }

        if let ssid = UIDevice.current.currentSSID, !ssid.isEmpty {
            currentSSID = ssid
        } else {
            currentSSID = "Unknown"
        }
    }

    private func correlateNetworkInfo() -> String? {
        updateNetworkInfo()
        var notes = [String]()
        if let ssid = currentSSID {
            notes.append("SSID: \(ssid)")
        }
        if let cellTower = currentCellTowerID {
            notes.append("Cell Tower: \(cellTower)")
        }
        return notes.isEmpty ? nil : notes.joined(separator: " | ")
    }

    // MARK: - Reverse Geolocation

    private func reverseGeocodeLocation(for device: DeviceModel) {
        guard let lat = device.latitude, let lon = device.longitude else { return }
        let location = CLLocation(latitude: lat, longitude: lon)
        CLGeocoder().reverseGeocodeLocation(location) { [weak self] placemarks, error in
            guard let self = self, let placemark = placemarks?.first, error == nil else { return }
            DispatchQueue.main.async {
                device.deviceNotes = ([device.deviceNotes, placemark.compactAddress].compactMap { $0 }).joined(separator: " | ")
            }
        }
    }

    // MARK: - App State Monitoring

    private func startMonitoring() {
        NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            self?.locationManager.startUpdatingLocation()
            self?.updateNetworkInfo()
        }
    }

    // MARK: - Logging

    private func logInfo(_ message: String) {
        #if DEBUG
        print(message)
        #endif
    }

    private func logWarning(_ message: String) {
        #if DEBUG
        print(message)
        #endif
    }

    private func logError(_ message: String) {
        #if DEBUG
        print(message)
        #endif
    }
}

// MARK: - CLLocationManagerDelegate

extension MagnetometerScanner: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        currentLocation = locations.last
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            manager.startUpdatingLocation()
        case .denied, .restricted:
            logWarning("📍 Location access denied.")
        default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        logError("❌ Location error: \(error)")
    }
}

// MARK: - UIDevice Extension for SSID

extension UIDevice {
    var currentSSID: String? {
        if let interfaces = CNCopySupportedInterfaces() as NSArray? {
            for interface in interfaces {
                if let info = CNCopyCurrentNetworkInfo(interface as! CFString) as NSDictionary? {
                    return info[kCNNetworkInfoKeySSID as String] as? String
                }
            }
        }
        return nil
    }
}

extension CLPlacemark {
    var compactAddress: String? {
        [subThoroughfare, thoroughfare, locality, administrativeArea, postalCode, country]
            .compactMap { $0 }
            .joined(separator: ", ")
    }
}
