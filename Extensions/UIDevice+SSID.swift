import UIKit
import SystemConfiguration.CaptiveNetwork

extension UIDevice {
    /// Attempts to fetch the current Wi-Fi SSID
    var currentSSID: String? {
        guard let interfaces = CNCopySupportedInterfaces() as? [String] else { return nil }

        for interface in interfaces {
            if let info = CNCopyCurrentNetworkInfo(interface as CFString) as? [String: AnyObject],
               let ssid = info[kCNNetworkInfoKeySSID as String] as? String {
                return ssid
            }
        }
        return nil
    }
}
