import Foundation
import Network

class UDPBroadcastListener {
    private var listener: NWListener?
    private let port: NWEndpoint.Port
    private let handler: (String, Data) -> Void

    init?(port: UInt16, handler: @escaping (String, Data) -> Void) {
        guard let nwPort = NWEndpoint.Port(rawValue: port) else { return nil }
        self.port = nwPort
        self.handler = handler
    }

    func start() {
        let params = NWParameters.udp
        params.allowLocalEndpointReuse = true
        do {
            listener = try NWListener(using: params, on: port)
            listener?.stateUpdateHandler = { state in
                switch state {
                case .failed(let error): print("UDP listener failed: \(error)")
                case .cancelled: print("UDP listener cancelled")
                default: break
                }
            }
            listener?.newConnectionHandler = { [weak self] conn in
                conn.start(queue: .main)
                self?.receive(on: conn)
            }
            listener?.start(queue: .main)
        } catch {
            print("❌ Failed to start UDP listener on port \(port.rawValue): \(error)")
        }
    }

    func stop() {
        listener?.cancel()
    }

    private func receive(on connection: NWConnection) {
        connection.receiveMessage { data, context, isComplete, error in
            if let data = data, let remote = connection.endpoint.debugDescription.split(separator: ":").first {
                self.handler(String(remote), data)
            }
            if let error = error {
                print("Receive error: \(error)")
            }
            self.receive(on: connection) // Loop
        }
    }
}
