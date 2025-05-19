import Foundation
import Combine

final class ScanCoordinator: ObservableObject {

    // MARK: - Published Scan Results
    @Published var scanResults: [ScanResult] = []

    // MARK: - Scanners
    let bluetoothScanner = BluetoothScanner()
    let networkScanner = NetworkScanner()
    let magnetometerScanner = MagnetometerScanner()
    let cameraScanner = IRReflectionScanner()
    let airtagScanner = AirTagScanner()
    let wifiSpoofScanner = WiFiHoneypotScanner()
    let motionEMFScanner = MotionEMFScanner()
    let audioAnalyzer = AudioAnalyzer()

    private var cancellables = Set<AnyCancellable>()
    private let minSeverityScore: Double = 50.0
    private let permissions = PermissionManager.shared

    // MARK: - Start All Scans
    func startAllScans() {
        // 🛑 Prevent scanning if critical permissions are missing
        guard permissions.allCriticalPermissionsGranted else {
            print("🚫 Cannot start scan: Missing one or more permissions.")
            logPermissionFailures()
            return
        }

        print("🟢 Starting all scans...")
        Task {
            await withTaskGroup(of: Void.self) { group in
                group.addTask { await self.safeStartScan { await self.bluetoothScanner.startScan() } }
                group.addTask { await self.safeStartScan { await self.networkScanner.startScan() } }
                group.addTask { await self.safeStartScan { await self.magnetometerScanner.startScan() } }
                group.addTask { await self.safeStartScan { await self.cameraScanner.startScan() } }
                group.addTask { self.safeStartScan { self.airtagScanner.startScan() } }
                group.addTask { self.safeStartScan { self.audioAnalyzer.startDetection() } }
                // wifiSpoofScanner and motionEMFScanner start passively via init
            }
        }

        bindScanPipelines()
    }

    // MARK: - Stop All Scans
    func stopAllScans() {
        bluetoothScanner.stopScan()
        networkScanner.stopScan()
        magnetometerScanner.stopScan()
        cameraScanner.stopScan()
        airtagScanner.stopScan()
        audioAnalyzer.stopDetection()
        // wifiSpoofScanner and motionEMFScanner stop passively
        print("🔴 All scans stopped.")
    }

    // MARK: - Combine Data Binding
    private func bindScanPipelines() {
        Publishers.MergeMany([
            bluetoothScanner.$devices.map { $0.map { ScanResult(device: $0, type: .bluetooth) } },
            networkScanner.$devices.map { $0.map { ScanResult(device: $0, type: .wifi) } },
            magnetometerScanner.$devices.map { $0.map { ScanResult(device: $0, type: .emf) } },
            cameraScanner.$devices.map { $0.map { ScanResult(device: $0, type: .ir) } },
            audioAnalyzer.$isDetectingUltrasonic.map { isActive in
                if isActive {
                    let device = DeviceModel(
                        name: "Ultrasonic Source",
                        type: .emf,
                        identifier: UUID().uuidString
                    )
                    device.threatLevel = .high
                    device.severityScore = 95.0
                    return [ScanResult(device: device, type: .emf)]
                }
                return []
            }
        ])
        .receive(on: DispatchQueue.main)
        .sink { [weak self] results in
            guard let self = self else { return }
            let filtered = results.filter { $0.severityScore >= self.minSeverityScore }
            self.scanResults = filtered
            ScanHistoryManager.saveResults(filtered)
        }
        .store(in: &cancellables)
    }

    // MARK: - Helper to Catch Faults in Scanner Tasks
    private func safeStartScan(_ block: @escaping () async throws -> Void) async {
        do {
            try await block()
        } catch {
            print("❌ Scan start failed: \(error)")
        }
    }

    // MARK: - Permission Debugging
    private func logPermissionFailures() {
        if permissions.bluetoothStatus != .granted {
            print("❌ Missing Bluetooth permission")
        }
        if permissions.locationStatus != .granted {
            print("❌ Missing Location permission")
        }
        if permissions.cameraStatus != .granted {
            print("❌ Missing Camera permission")
        }
        if permissions.microphoneStatus != .granted {
            print("❌ Missing Microphone permission")
        }
    }
}
