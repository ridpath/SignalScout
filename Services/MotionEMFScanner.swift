import Foundation
import CoreMotion

class MotionEMFScanner: ObservableObject {
    private let motionManager = CMMotionManager()
    private let queue = OperationQueue()
    
    @Published var emfSpikes: [Date] = []
    @Published var motionSpikes: [Date] = []
    @Published var correlationDetected: Bool = false

    private let motionThreshold = 0.3 // radians
    private let emfThreshold = 80.0 // µT

    init() {
        startMonitoring()
    }

    func startMonitoring() {
        motionManager.magnetometerUpdateInterval = 0.5
        motionManager.deviceMotionUpdateInterval = 0.5

        motionManager.startMagnetometerUpdates(to: queue) { data, _ in
            guard let m = data?.magneticField else { return }
            let magnitude = sqrt(m.x * m.x + m.y * m.y + m.z * m.z)
            if magnitude > self.emfThreshold {
                DispatchQueue.main.async {
                    self.emfSpikes.append(Date())
                    self.checkForCorrelation()
                }
            }
        }

        motionManager.startDeviceMotionUpdates(to: queue) { data, _ in
            guard let d = data else { return }
            let rotation = abs(d.rotationRate.x) + abs(d.rotationRate.y) + abs(d.rotationRate.z)
            if rotation > self.motionThreshold {
                DispatchQueue.main.async {
                    self.motionSpikes.append(Date())
                    self.checkForCorrelation()
                }
            }
        }
    }

    func checkForCorrelation() {
        guard let lastEMF = emfSpikes.last,
              let lastMotion = motionSpikes.last else { return }

        if abs(lastEMF.timeIntervalSince(lastMotion)) < 1.5 {
            correlationDetected = true
        }
    }
}

