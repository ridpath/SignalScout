import Foundation
import CoreBluetooth
import CoreLocation

class AirTagScanner: NSObject, ObservableObject {
    private var centralManager: CBCentralManager!
    @Published var suspectedTrackers: [DeviceModel] = []
    private var seenDevices: [UUID: [Date]] = [:]
    private let locationManager = CLLocationManager()
    private var currentLocation: CLLocation?

    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: .global())
        locationManager.delegate = self
        locationManager.requestWhenInUseAuthorization()
        locationManager.startUpdatingLocation()
    }

    func startScan() {
        if centralManager.state == .poweredOn {
            centralManager.scanForPeripherals(
                withServices: nil,
                options: [CBCentralManagerScanOptionAllowDuplicatesKey: true]
            )
        }
    }

    func stopScan() {
        centralManager.stopScan()
        locationManager.stopUpdatingLocation()
    }

    private func evaluatePeripheral(_ peripheral: CBPeripheral, advertisementData: [String: Any], rssi: NSNumber) {
        let now = Date()
        let id = peripheral.identifier
        let rssiValue = rssi.intValue

        seenDevices[id, default: []].append(now)
        seenDevices[id] = seenDevices[id]?.filter { now.timeIntervalSince($0) < 600 } // Keep last 10 min

        guard let timestamps = seenDevices[id], timestamps.count >= 3 else { return }

        let timeBetween = timestamps.last!.timeIntervalSince(timestamps.first!)
        if timeBetween >= 60 && timeBetween <= 600 {
            // Heuristic: device seen multiple times across a time span — likely tracking
            DispatchQueue.main.async {
                if !self.suspectedTrackers.contains(where: { $0.identifier == id.uuidString }) {
                    let model = DeviceModel(
                        name: peripheral.name ?? "Unidentified Tracker",
                        type: .bluetooth,
                        identifier: id.uuidString,
                        manufacturer: ManufacturerLookup.shared.lookup(macOrBSSID: id.uuidString)
                    )
                    model.addRSSISample(rssiValue)
                    model.latitude = self.currentLocation?.coordinate.latitude
                    model.longitude = self.currentLocation?.coordinate.longitude
                    model.timestamp = now
                    model.isStatic = false
                    model.threatLevel = .high
                    model.severityScore = 85.0

                    CorrelatedAnomalyEngine.shared.registerEvent(source: "airtag", timestamp: now)
                    self.suspectedTrackers.append(model)
                }
            }
        }
    }
}

// MARK: - CBCentralManagerDelegate
extension AirTagScanner: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn {
            startScan()
        }
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        evaluatePeripheral(peripheral, advertisementData: advertisementData, rssi: RSSI)
    }
}

// MARK: - CLLocationManagerDelegate
extension AirTagScanner: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        currentLocation = locations.last
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if manager.authorizationStatus == .authorizedWhenInUse {
            manager.startUpdatingLocation()
        }
    }
}
