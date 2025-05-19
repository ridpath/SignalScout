import Foundation
import Network
import SystemConfiguration.CaptiveNetwork
import Combine
import CoreLocation
import UIKit

class NetworkScanner: NSObject, ObservableObject {
    @Published var devices: [DeviceModel] = []
    @Published var currentSSID: String?
    @Published var currentBSSID: String?
    @Published var isSuspicious: Bool = false

    private var bssidHistory: [String] = []
    private var lastScanTime: Date?
    private var mdnsBrowser: NWBrowser?
    private var timer: Timer?
    private var udpListeners: [UDPBroadcastListener] = []
    private var cancellables = Set<AnyCancellable>()
    private let locationManager = CLLocationManager()
    private var currentLocation: CLLocation?
    private var ouiDB: [String: String] = [:]
    private var geocodeQueue: [String: Bool] = [:]

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.requestWhenInUseAuthorization()
        locationManager.startUpdatingLocation()
        loadOUIFromJSON()
        startMonitoring()
    }

    func startScan() async {
        mdnsBrowser = NWBrowser(for: .bonjour(type: "_services._dns-sd._udp", domain: nil), using: .tcp)
        mdnsBrowser?.browseResultsChangedHandler = { results, _ in
            self.processMDNSResults(results)
        }
        mdnsBrowser?.stateUpdateHandler = { state in
            if case .failed(let err) = state {
                print("❌ Browser error: \(err)")
            }
        }
        mdnsBrowser?.start(queue: .main)

        listenForUDPBroadcasts()

        timer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { _ in
            self.checkWiFiInfo()
            self.analyzeNetworkHealth()
            self.removeStaleDevices()
        }

        lastScanTime = Date()
    }

    func stopScan() {
        mdnsBrowser?.cancel()
        timer?.invalidate()
        udpListeners.forEach { $0.stop() }
        udpListeners.removeAll()
        locationManager.stopUpdatingLocation()
    }

    private func checkWiFiInfo() {
        guard CLLocationManager.authorizationStatus() == .authorizedWhenInUse,
              let interfaces = CNCopySupportedInterfaces() as? [String] else {
            print("⚠️ No Wi-Fi info available.")
            return
        }

        for iface in interfaces {
            if let info = CNCopyCurrentNetworkInfo(iface as CFString) as? [String: AnyObject],
               let ssid = info[kCNNetworkInfoKeySSID as String] as? String,
               let bssid = info[kCNNetworkInfoKeyBSSID as String] as? String {

                if currentSSID != ssid || currentBSSID != bssid {
                    currentSSID = ssid
                    currentBSSID = bssid
                    bssidHistory.append(bssid)
                    if bssidHistory.count > 10 {
                        bssidHistory.removeFirst()
                    }
                    CorrelatedAnomalyEngine.shared.registerEvent(source: "wifi-\(ssid)", timestamp: Date())
                    print("📶 SSID/BSSID change: \(ssid) / \(bssid)")
                }

                updateOrAddAccessPoint(ssid: ssid, bssid: bssid)
            }
        }
    }

    private func updateOrAddAccessPoint(ssid: String, bssid: String) {
        let identifier = bssid
        let manufacturer = ManufacturerLookup.shared.lookup(macOrBSSID: bssid) ?? lookupManufacturer(from: bssid)
        let rssi = Int.random(in: -80 ... -30) // Simulated RSSI

        DispatchQueue.main.async {
            if let device = self.devices.first(where: { $0.identifier == identifier }) {
                device.addRSSISample(rssi)
                device.latitude = self.currentLocation?.coordinate.latitude
                device.longitude = self.currentLocation?.coordinate.longitude
                device.ssid = ssid
            } else {
                let device = DeviceModel(
                    name: ssid,
                    type: .wifi,
                    identifier: identifier,
                    manufacturer: manufacturer
                )
                device.addRSSISample(rssi)
                device.latitude = self.currentLocation?.coordinate.latitude
                device.longitude = self.currentLocation?.coordinate.longitude
                device.ssid = ssid
                device.isStatic = true
                self.reverseGeocodeLocation(for: device)
                self.devices.append(device)
            }
        }
    }

    private func processMDNSResults(_ results: Set<NWBrowser.Result>) {
        for result in results {
            guard case let .service(name, type, domain, _) = result.endpoint else { continue }
            let identifier = "\(name).\(type).\(domain ?? "local")"

            DispatchQueue.main.async {
                if let device = self.devices.first(where: { $0.identifier == identifier }) {
                    device.timestamp = Date()
                    device.latitude = self.currentLocation?.coordinate.latitude
                    device.longitude = self.currentLocation?.coordinate.longitude
                } else {
                    let device = DeviceModel(
                        name: name,
                        type: .wifi,
                        identifier: identifier,
                        manufacturer: self.lookupManufacturer(from: identifier)
                    )
                    device.latitude = self.currentLocation?.coordinate.latitude
                    device.longitude = self.currentLocation?.coordinate.longitude
                    device.ssid = self.currentSSID
                    device.timestamp = Date()
                    device.isStatic = false
                    self.reverseGeocodeLocation(for: device)
                    self.devices.append(device)
                }
            }
        }
    }

    private func listenForUDPBroadcasts() {
        let ports: [UInt16] = [1900, 5353]

        for port in ports {
            if let listener = UDPBroadcastListener(port: port) { address, data in
                let identifier = "\(address)-\(port)"
                let rssi = Int.random(in: -80 ... -30) // Simulated RSSI

                DispatchQueue.main.async {
                    if let device = self.devices.first(where: { $0.identifier == identifier }) {
                        device.addRSSISample(rssi)
                        device.timestamp = Date()
                    } else {
                        let device = DeviceModel(
                            name: "UDP Device",
                            type: .wifi,
                            identifier: identifier,
                            manufacturer: nil
                        )
                        device.addRSSISample(rssi)
                        device.latitude = self.currentLocation?.coordinate.latitude
                        device.longitude = self.currentLocation?.coordinate.longitude
                        device.ssid = self.currentSSID
                        device.timestamp = Date()
                        device.isStatic = false
                        self.reverseGeocodeLocation(for: device)
                        self.devices.append(device)
                    }
                }
            } {
                listener.start()
                udpListeners.append(listener)
            } else {
                print("❌ Failed to start UDP listener on port \(port)")
            }
        }
    }

    private func analyzeNetworkHealth() {
        guard let last = lastScanTime else { return }
        let timeElapsed = Date().timeIntervalSince(last)

        if Set(bssidHistory.suffix(5)).count > 3 && timeElapsed < 60 {
            isSuspicious = true
            print("⚠️ Rapid BSSID switching detected")
        }

        if Double(devices.count) / timeElapsed > 0.5 {
            isSuspicious = true
            print("⚠️ High device discovery rate")
        }

        lastScanTime = Date()
    }

    private func removeStaleDevices() {
        let threshold = Date().addingTimeInterval(-300)
        devices.removeAll { ($0.timestamp ?? .distantPast) < threshold }
    }

    private func startMonitoring() {
        NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in self?.checkWiFiInfo() }
            .store(in: &cancellables)
    }

    private func reverseGeocodeLocation(for device: DeviceModel) {
        guard let lat = device.latitude, let lon = device.longitude else { return }
        guard geocodeQueue[device.identifier] != true else { return }
        geocodeQueue[device.identifier] = true

        let location = CLLocation(latitude: lat, longitude: lon)
        CLGeocoder().reverseGeocodeLocation(location) { placemarks, error in
            defer { self.geocodeQueue[device.identifier] = false }

            if let placemark = placemarks?.first, error == nil {
                device.deviceNotes = placemark.compactAddress
            }
        }
    }

    private func loadOUIFromJSON() {
        guard let path = Bundle.main.path(forResource: "oui", ofType: "json") else {
            print("❌ OUI file not found.")
            return
        }

        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: path))
            self.ouiDB = try JSONDecoder().decode([String: String].self, from: data)
            print("✅ Loaded \(ouiDB.count) OUI entries")
        } catch {
            print("❌ Failed to load OUI JSON: \(error)")
        }
    }

    private func lookupManufacturer(from identifier: String) -> String? {
        let macRegex = #"([0-9A-Fa-f]{2}[:-]){5}([0-9A-Fa-f]{2})"#
        guard let match = identifier.range(of: macRegex, options: .regularExpression) else { return nil }

        let mac = identifier[match]
            .uppercased()
            .replacingOccurrences(of: "-", with: ":")
            .split(separator: ":")
            .prefix(3)
            .joined(separator: ":")

        return ouiDB[mac]
    }
}

extension NetworkScanner: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        currentLocation = locations.last
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if manager.authorizationStatus == .authorizedWhenInUse {
            manager.startUpdatingLocation()
        }
    }
}

extension CLPlacemark {
    var compactAddress: String {
        [subThoroughfare, thoroughfare, locality, administrativeArea, postalCode, country]
            .compactMap { $0 }
            .joined(separator: ", ")
    }
}
