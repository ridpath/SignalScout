# 📡 Signal Scout

> **Real-time Threat Detection for Physical Tracking, EMF Anomalies, and Surveillance Devices**

Signal Scout turns your iPhone into a powerful signal analysis tool, detecting unusual wireless activity, rogue devices, and invisible threats — all powered by onboard sensors and machine learning heuristics.

## ⚙️ Features

- ✅ **Bluetooth & AirTag Detection** – Tracks known and unknown BLE devices
- ✅ **Wi-Fi Honeypot Detection** – Detects SSID spoofing, MAC hopping, and rogue APs
- ✅ **EMF/Magnetometer Anomalies** – Finds signal bursts from suspicious electronics
- ✅ **Ultrasonic Audio Monitoring** – Flags ultrasonic pulses used in tracking systems
- ✅ **IR Reflection Detection** – Uses your camera to spot optical surveillance hardware
- ✅ **Location + RSSI Mapping** – Tracks anomalies with GPS heatmaps and signal graphs
- ✅ **Signal History Graphs** – Shows device RSSI over time to identify persistence
- ✅ **Correlated Event Engine** – Detects cross-sensor threats (e.g. EMF + motion)

All data is stored locally and exportable as JSON logs. No cloud storage, ever.

---

## 🚧 Status

- 🔬 In active development
- 📦 Open for non-commercial use only

---

## 🛠 Tech Stack
-- iOS 15+
- `Swift` / `SwiftUI` / `Combine`
- CoreBluetooth, CoreLocation, AVFoundation
- CoreMotion, CoreImage, Network, Foundation
- Fine-grained modular scanner architecture (each scanner is independently testable)

---

## 🧠 Why This Exists
Many threat vectors operate physically, not digitally. AirTags, rogue hotspots, IR bugs, ultrasonic ads — all leave RF, EMF, or optical traces. Signal Scout empowers users to detect, validate, and investigate physical-layer anomalies using nothing but their iPhone.


## This project is licensed under the Business Source License 1.1.

✅ Permitted: personal use, education, research, transparency, bug reports

❌ Not permitted:

Redistribution on the App Store or third-party stores

Use in commercial products or forks

Selling forks or derived apps
For more details: https://github.com/ridpath/SignalScout/blob/main/LICENSE



## 📢 Attribution
Signal Scout uses:

Apple's Core APIs (CoreMotion, CoreBluetooth, AVFoundation, etc.)

OUI Database for manufacturer lookups

FFT via Accelerate for real-time audio spectrum analysis



