import Foundation
import CoreBluetooth
import CoreLocation
import AVFoundation
import UIKit
import Combine

enum PermissionStatus: String {
    case notDetermined
    case granted
    case denied
    case restricted
    case unknown
}

final class PermissionManager: NSObject, ObservableObject {
    static let shared = PermissionManager()

    // MARK: - Published UI Statuses
    @Published var bluetoothStatus: PermissionStatus = .unknown
    @Published var locationStatus: PermissionStatus = .unknown
    @Published var microphoneStatus: PermissionStatus = .unknown
    @Published var cameraStatus: PermissionStatus = .unknown

    private let locationManager = CLLocationManager()
    private var bluetoothManager: CBCentralManager!
    
    private var cancellables = Set<AnyCancellable>()

    private override init() {
        super.init()
        locationManager.delegate = self
        bluetoothManager = CBCentralManager(delegate: self, queue: nil)
        refreshAllStatuses()
    }

    // MARK: - Manual Refresh
    func refreshAllStatuses() {
        updateCameraStatus()
        updateMicrophoneStatus()
        updateLocationStatus()
        updateBluetoothStatus()
    }

    // MARK: - Camera
    func requestCameraPermission() {
        AVCaptureDevice.requestAccess(for: .video) { granted in
            DispatchQueue.main.async {
                self.cameraStatus = granted ? .granted : .denied
            }
        }
    }

    private func updateCameraStatus() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: cameraStatus = .granted
        case .denied: cameraStatus = .denied
        case .restricted: cameraStatus = .restricted
        case .notDetermined: cameraStatus = .notDetermined
        @unknown default: cameraStatus = .unknown
        }
    }

    // MARK: - Microphone
    func requestMicrophonePermission() {
        AVAudioSession.sharedInstance().requestRecordPermission { granted in
            DispatchQueue.main.async {
                self.microphoneStatus = granted ? .granted : .denied
            }
        }
    }

    private func updateMicrophoneStatus() {
        switch AVAudioSession.sharedInstance().recordPermission {
        case .granted: microphoneStatus = .granted
        case .denied: microphoneStatus = .denied
        case .undetermined: microphoneStatus = .notDetermined
        @unknown default: microphoneStatus = .unknown
        }
    }

    // MARK: - Location
    func requestLocationPermission() {
        locationManager.requestWhenInUseAuthorization()
    }

    private func updateLocationStatus() {
        switch CLLocationManager.authorizationStatus() {
        case .authorizedAlways, .authorizedWhenInUse: locationStatus = .granted
        case .denied: locationStatus = .denied
        case .restricted: locationStatus = .restricted
        case .notDetermined: locationStatus = .notDetermined
        @unknown default: locationStatus = .unknown
        }
    }

    // MARK: - Bluetooth
    private func updateBluetoothStatus() {
        // Will be updated via delegate
        // CentralManager is auto-triggered via init
    }

    // MARK: - Global Status for App Gating
    var allCriticalPermissionsGranted: Bool {
        return [
            bluetoothStatus,
            locationStatus,
            microphoneStatus,
            cameraStatus
        ].allSatisfy { $0 == .granted }
    }
}

// MARK: - CLLocationManagerDelegate
extension PermissionManager: CLLocationManagerDelegate {
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        updateLocationStatus()
    }
}

// MARK: - CBCentralManagerDelegate
extension PermissionManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn: bluetoothStatus = .granted
        case .unauthorized, .unsupported, .poweredOff: bluetoothStatus = .denied
        case .resetting, .unknown: bluetoothStatus = .notDetermined
        @unknown default: bluetoothStatus = .unknown
        }
    }
}
