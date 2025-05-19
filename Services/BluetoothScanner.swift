BluetoothScanner.swift
import CoreBluetooth
import CoreLocation
import Foundation

class BluetoothScanner: NSObject, ObservableObject {
    private var centralManager: CBCentralManager!
    @Published var devices: [DeviceModel] = []

    private let locationManager = CLLocationManager()
    private var currentLocation: CLLocation?
    private var rssiHistory: [String: [Int]] = [:]
    private let geocoder = CLGeocoder()
    private var geocodeQueue: [String: Bool] = [:]

    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: DispatchQueue.global(qos: .userInitiated))
        locationManager.delegate = self
        locationManager.requestWhenInUseAuthorization()
        locationManager.startUpdatingLocation()
    }

    func startScan() async {
        guard centralManager.state == .poweredOn else { return }
        centralManager.scanForPeripherals(withServices: nil, options: [
            CBCentralManagerScanOptionAllowDuplicatesKey: true
        ])
        print("🟢 BLE scanning started.")
    }

    func stopScan() {
        centralManager.stopScan()
        locationManager.stopUpdatingLocation()
        print("🔴 BLE scanning stopped.")
    }

    private func processPeripheral(_ peripheral: CBPeripheral, advertisementData: [String: Any], rssi: NSNumber) {
        let identifier = peripheral.identifier.uuidString
        let name = peripheral.name ?? "Unknown BLE Device"
        let manufacturer = ManufacturerLookup.shared.lookup(macOrBSSID: identifier)
            ?? guessManufacturer(from: advertisementData)
        let rssiValue = rssi.intValue

        // Track RSSI history for static detection
        rssiHistory[identifier, default: []].append(rssiValue)
        if rssiHistory[identifier]!.count > 50 {
            rssiHistory[identifier]!.removeFirst()
        }

        DispatchQueue.main.async {
            if let index = self.devices.firstIndex(where: { $0.identifier == identifier }) {
                let device = self.devices[index]
                device.addRSSISample(rssiValue)
                device.latitude = self.currentLocation?.coordinate.latitude
                device.longitude = self.currentLocation?.coordinate.longitude
                device.isStatic = self.isDeviceStatic(identifier: identifier)
                self.reverseGeocodeLocation(for: device)
            } else {
                let device = DeviceModel(
                    name: name,
                    type: .bluetooth,
                    identifier: identifier,
                    manufacturer: manufacturer
                )
                device.addRSSISample(rssiValue)
                device.latitude = self.currentLocation?.coordinate.latitude
                device.longitude = self.currentLocation?.coordinate.longitude
                device.isStatic = self.isDeviceStatic(identifier: identifier)
                self.reverseGeocodeLocation(for: device)
                self.devices.append(device)
            }
        }
    }

    private func guessManufacturer(from advertisementData: [String: Any]) -> String? {
        guard let data = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data,
              data.count >= 2 else { return nil }
        let prefix = data.prefix(2).map { String(format: "%02X", $0) }.joined(separator: ":")
        return ManufacturerLookup.shared.lookup(macOrBSSID: prefix)
    }

    private func isDeviceStatic(identifier: String) -> Bool {
        guard let history = rssiHistory[identifier], history.count >= 10 else { return false }
        let values = history.map(Double.init)
        let variance = values.variance()
        return variance < 5.0
    }

    private func reverseGeocodeLocation(for device: DeviceModel) {
        guard let lat = device.latitude, let lon = device.longitude else { return }
        guard geocodeQueue[device.identifier] != true else { return } // prevent flood
        geocodeQueue[device.identifier] = true

        let location = CLLocation(latitude: lat, longitude: lon)
        geocoder.reverseGeocodeLocation(location) { placemarks, error in
            DispatchQueue.main.async {
                defer { self.geocodeQueue[device.identifier] = false }

                if let placemark = placemarks?.first, error == nil {
                    device.deviceNotes = placemark.compactAddress
                }
            }
        }
    }
}

// MARK: - CBCentralManagerDelegate
extension BluetoothScanner: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn {
            Task { await startScan() }
        } else {
            print("⚠️ Bluetooth not powered on: \(central.state.rawValue)")
        }
    }

    func centralManager(_ central: CBCentralManager,
                        didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any],
                        rssi RSSI: NSNumber) {
        processPeripheral(peripheral, advertisementData: advertisementData, rssi: RSSI)
    }
}

// MARK: - CLLocationManagerDelegate
extension BluetoothScanner: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        currentLocation = locations.last
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if manager.authorizationStatus == .authorizedWhenInUse {
            manager.startUpdatingLocation()
        }
    }
}

// MARK: - Double Array Variance Helper
extension Array where Element == Double {
    func variance() -> Double {
        guard count > 1 else { return 0.0 }
        let mean = reduce(0, +) / Double(count)
        return reduce(0) { $0 + pow($1 - mean, 2) } / Double(count)
    }
}

// MARK: - Compact Placemark Address
extension CLPlacemark {
    var compactAddress: String {
        [subThoroughfare, thoroughfare, locality, administrativeArea, postalCode, country]
            .compactMap { $0 }
            .joined(separator: ", ")
    }
}
