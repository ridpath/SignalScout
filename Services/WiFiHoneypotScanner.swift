import Foundation
import SystemConfiguration.CaptiveNetwork
import Network

class WiFiHoneypotScanner: ObservableObject {
    @Published var isSuspicious = false
    @Published var ssid: String?
    @Published var bssidHistory: [String] = []

    private var monitorTimer: Timer?

    init() {
        monitorTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { _ in
            self.checkCurrentNetwork()
        }
    }

    func checkCurrentNetwork() {
        guard let interfaces = CNCopySupportedInterfaces() as? [String] else { return }

        for iface in interfaces {
            if let info = CNCopyCurrentNetworkInfo(iface as CFString) as? [String: AnyObject],
               let ssid = info[kCNNetworkInfoKeySSID as String] as? String,
               let bssid = info[kCNNetworkInfoKeyBSSID as String] as? String {

                self.ssid = ssid
                if !bssidHistory.contains(bssid) {
                    bssidHistory.append(bssid)
                }

                if bssidHistory.count > 2 {
                    isSuspicious = true // SSID same, BSSID changed = spoof
                }
            }
        }
    }
}
