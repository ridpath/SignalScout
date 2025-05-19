import Foundation
import AVFoundation
import UIKit
import CoreImage
import CoreLocation
import SystemConfiguration.CaptiveNetwork

class IRReflectionScanner: NSObject, ObservableObject {
    @Published var devices: [DeviceModel] = []
    @Published var isScanning: Bool = false
    @Published var permissionDenied: Bool = false

    private var captureSession: AVCaptureSession?
    private var output: AVCaptureVideoDataOutput?
    private var frameCounter = 0
    private var torchOn = false
    private var lastTorchToggle = Date.distantPast

    private var reflectionMap: [String: (count: Int, avgBrightness: CGFloat)] = [:]
    private let gridSize = 16
    private let brightnessThreshold: CGFloat = 0.7

    private var ouiDB: [String: String] = [:]
    private let locationManager = CLLocationManager()
    private var currentLocation: CLLocation?

    override init() {
        super.init()
        loadOUIFromJSON()
        locationManager.delegate = self
        locationManager.requestWhenInUseAuthorization()
        locationManager.startUpdatingLocation()
    }

    func startScan() async {
        let granted = await AVCaptureDevice.requestAccess(for: .video)
        guard granted else {
            DispatchQueue.main.async {
                self.permissionDenied = true
                self.isScanning = false
            }
            print("🚫 Camera access not granted.")
            return
        }

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device) else {
            print("❌ Failed to get rear camera.")
            return
        }

        let session = AVCaptureSession()
        session.sessionPreset = .high

        if session.canAddInput(input) { session.addInput(input) }

        let output = AVCaptureVideoDataOutput()
        output.videoSettings = [
            (kCVPixelBufferPixelFormatTypeKey as String): kCVPixelFormatType_32BGRA
        ]
        output.setSampleBufferDelegate(self, queue: DispatchQueue(label: "IRScanQueue"))
        if session.canAddOutput(output) { session.addOutput(output) }

        self.captureSession = session
        self.output = output
        session.startRunning()

        if device.hasTorch {
            try? device.lockForConfiguration()
            device.torchMode = .on
            torchOn = true
            device.unlockForConfiguration()
        }

        DispatchQueue.main.async {
            self.isScanning = true
        }

        print("📸 IR scan started.")
    }

    func stopScan() {
        captureSession?.stopRunning()
        captureSession = nil
        reflectionMap.removeAll()
        locationManager.stopUpdatingLocation()
        DispatchQueue.main.async {
            self.isScanning = false
        }
        print("🛑 IR scan stopped.")
    }

    private func toggleTorch(device: AVCaptureDevice) {
        let now = Date()
        guard now.timeIntervalSince(lastTorchToggle) >= 1.0 else { return }

        try? device.lockForConfiguration()
        torchOn.toggle()
        device.torchMode = torchOn ? .on : .off
        device.unlockForConfiguration()
        lastTorchToggle = now
    }

    private func loadOUIFromJSON() {
        guard let path = Bundle.main.path(forResource: "oui", ofType: "json") else { return }
        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: path))
            let parsed = try JSONDecoder().decode([String: String].self, from: data)
            self.ouiDB = parsed
        } catch {
            print("❌ Failed to load OUI JSON: \(error)")
        }
    }

    private func currentWiFiBSSID() -> String? {
        guard let interfaces = CNCopySupportedInterfaces() as? [String] else { return nil }
        for iface in interfaces {
            if let info = CNCopyCurrentNetworkInfo(iface as CFString) as? [String: AnyObject],
               let bssid = info[kCNNetworkInfoKeyBSSID as String] as? String {
                return bssid.uppercased()
            }
        }
        return nil
    }

    private func manufacturerFromBSSID(_ bssid: String?) -> String? {
        guard let bssid = bssid else { return nil }
        let prefix = bssid.split(separator: ":").prefix(3).joined(separator: ":")
        return ouiDB[prefix]
    }

    private func reverseGeocodeLocation(for device: DeviceModel) {
        guard let lat = device.latitude, let lon = device.longitude else { return }
        let location = CLLocation(latitude: lat, longitude: lon)
        CLGeocoder().reverseGeocodeLocation(location) { placemarks, error in
            if let placemark = placemarks?.first, error == nil {
                DispatchQueue.main.async {
                    device.deviceNotes = placemark.compactAddress
                }
            }
        }
    }

    private func addDevice(at key: String, brightness: CGFloat) {
        let bssid = currentWiFiBSSID()
        let manufacturer = manufacturerFromBSSID(bssid)

        DispatchQueue.main.async {
            let score = Int(brightness * 100)
            let id = key + (bssid ?? "")

            guard !self.devices.contains(where: { $0.identifier == id }) else { return }

            let device = DeviceModel(
                name: "Reflective Surface",
                type: .ir,
                identifier: id,
                manufacturer: manufacturer
            )
            device.latitude = self.currentLocation?.coordinate.latitude
            device.longitude = self.currentLocation?.coordinate.longitude
            device.timestamp = Date()
            device.addRSSISample(score)
            device.severityScore = Double(score)
            device.threatLevel = score > 85 ? .critical : score > 70 ? .high : .moderate
            device.deviceNotes = "Detected via reflection grid | Brightness: \(score)"
            self.reverseGeocodeLocation(for: device)

            self.devices.append(device)
            print("📸 IR Anomaly: \(device.name) [\(manufacturer ?? "Unknown")] Brightness: \(score)")
        }
    }
}

// MARK: - AVCapture Delegate

extension IRReflectionScanner: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        frameCounter += 1
        if frameCounter % 15 == 0 {
            if let device = (captureSession?.inputs.first as? AVCaptureDeviceInput)?.device {
                toggleTorch(device: device)
            }
        }

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        processFrame(ciImage)
    }

    private func processFrame(_ image: CIImage) {
        let width = Int(image.extent.width)
        let height = Int(image.extent.height)

        for y in 0..<gridSize {
            for x in 0..<gridSize {
                let region = CGRect(
                    x: (width / gridSize) * x,
                    y: (height / gridSize) * y,
                    width: width / gridSize,
                    height: height / gridSize
                )
                let regionImage = image.cropped(to: region)
                let brightness = regionImage.averageBrightness()

                if brightness > brightnessThreshold {
                    let key = "\(x),\(y)"
                    let current = reflectionMap[key] ?? (count: 0, avgBrightness: 0)
                    let newAvg = (current.avgBrightness * CGFloat(current.count) + brightness) / CGFloat(current.count + 1)
                    reflectionMap[key] = (count: current.count + 1, avgBrightness: newAvg)

                    if current.count > 5 && torchOn {
                        addDevice(at: key, brightness: newAvg)
                    }
                }
            }
        }
    }
}

// MARK: - CLLocationManagerDelegate

extension IRReflectionScanner: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        currentLocation = locations.last
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if manager.authorizationStatus == .authorizedWhenInUse {
            manager.startUpdatingLocation()
        }
    }
}

// MARK: - CIImage Brightness Helper

extension CIImage {
    func averageBrightness() -> CGFloat {
        let extentVector = CIVector(x: extent.origin.x, y: extent.origin.y, z: extent.size.width, w: extent.size.height)
        guard let filter = CIFilter(name: "CIAreaAverage", parameters: [
            kCIInputImageKey: self,
            kCIInputExtentKey: extentVector
        ]),
        let outputImage = filter.outputImage else { return 0 }

        var bitmap = [UInt8](repeating: 0, count: 4)
        let context = CIContext()
        context.render(outputImage,
                       toBitmap: &bitmap,
                       rowBytes: 4,
                       bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                       format: .RGBA8,
                       colorSpace: CGColorSpaceCreateDeviceRGB())

        let r = CGFloat(bitmap[0]) / 255.0
        let g = CGFloat(bitmap[1]) / 255.0
        let b = CGFloat(bitmap[2]) / 255.0
        return (r + g + b) / 3
    }
}

// MARK: - CLPlacemark Helper

extension CLPlacemark {
    var compactAddress: String {
        [subThoroughfare, thoroughfare, locality, administrativeArea, postalCode, country]
            .compactMap { $0 }
            .joined(separator: ", ")
    }
}
