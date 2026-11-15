import Flutter
import Network
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    let channel = FlutterMethodChannel(
      name: "netpulse/network",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    channel.setMethodCallHandler { call, reply in
      guard call.method == "measure", let transport = call.arguments as? String,
            transport == "wifi" || transport == "mobile" else {
        reply(FlutterMethodNotImplemented)
        return
      }
      InterfaceSpeedTest(interface: transport == "wifi" ? .wifi : .cellular, reply: reply)
        .start()
    }
  }
}

private final class InterfaceSpeedTest {
  private struct Transfer {
    let bytes: Int
    let upload: Bool
  }

  private let host = "speed.cloudflare.com"
  private let interface: NWInterface.InterfaceType
  private let reply: FlutterResult
  private let queue = DispatchQueue(label: "netpulse.network")
  private let phases = [
    Transfer(bytes: 0, upload: false),
    Transfer(bytes: 8_000_000, upload: false),
    Transfer(bytes: 3_000_000, upload: true)
  ]
  private var times: [Double] = []
  private var connection: NWConnection?
  private var timeout: DispatchWorkItem?
  private var header = Data()
  private var received = 0
  private var parsedHeader = false
  private var startTime: UInt64 = 0

  init(interface: NWInterface.InterfaceType, reply: @escaping FlutterResult) {
    self.interface = interface
    self.reply = reply
  }

  func start() {
    queue.async { self.connect() }
  }

  private func connect() {
    let parameters = NWParameters(tls: NWProtocolTLS.Options(), tcp: NWProtocolTCP.Options())
    parameters.requiredInterfaceType = interface
    let connection = NWConnection(host: NWEndpoint.Host(host), port: .https, using: parameters)
    self.connection = connection
    header = Data()
    received = 0
    parsedHeader = false
    startTime = 0
    let availabilityTimeout = DispatchWorkItem { [weak self] in
      guard let self else { return }
      self.finish(self.times.isEmpty ? nil : self.failure())
    }
    timeout = availabilityTimeout
    queue.asyncAfter(deadline: .now() + 8, execute: availabilityTimeout)
    connection.stateUpdateHandler = { [self, weak connection] state in
      guard let connection, connection === self.connection else { return }
      switch state {
      case .ready where startTime == 0:
        send(on: connection)
      case .failed:
        finish(failure())
      default:
        break
      }
    }
    connection.start(queue: queue)
  }

  private func send(on connection: NWConnection) {
    timeout?.cancel()
    let transferTimeout = DispatchWorkItem { [weak self] in
      guard let self else { return }
      self.finish(self.failure())
    }
    timeout = transferTimeout
    queue.asyncAfter(deadline: .now() + 20, execute: transferTimeout)

    let transfer = phases[times.count]
    let nonce = DispatchTime.now().uptimeNanoseconds
    let path = transfer.upload ? "/__up?nonce=\(nonce)" : "/__down?bytes=\(transfer.bytes)&nonce=\(nonce)"
    let method = transfer.upload ? "POST" : "GET"
    var request = "\(method) \(path) HTTP/1.0\r\nHost: \(host)\r\nConnection: close\r\nAccept-Encoding: identity\r\nCache-Control: no-cache\r\n"
    if transfer.upload {
      request += "Content-Type: application/octet-stream\r\nContent-Length: \(transfer.bytes)\r\n"
    }
    var data = Data((request + "\r\n").utf8)
    if transfer.upload { data.append(Data(count: transfer.bytes)) }
    startTime = DispatchTime.now().uptimeNanoseconds
    connection.send(content: data, completion: .contentProcessed { [weak self, weak connection] error in
      guard let self, let connection, connection === self.connection else { return }
      if error != nil { self.finish(self.failure()) }
      else { self.receive(on: connection) }
    })
  }

  private func receive(on connection: NWConnection) {
    connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) {
      [weak self, weak connection] data, _, complete, error in
      guard let self, let connection, connection === self.connection else { return }
      let transfer = self.phases[self.times.count]
      if let data {
        if self.parsedHeader {
          self.received += data.count
        } else {
          self.header.append(data)
          let separator = Data([13, 10, 13, 10])
          if let end = self.header.range(of: separator) {
            let lines = String(decoding: self.header[..<end.lowerBound], as: UTF8.self)
              .components(separatedBy: "\r\n")
            guard lines.first?.split(separator: " ").dropFirst().first == "200",
                  !lines.dropFirst().contains(where: {
                    $0.lowercased().hasPrefix("transfer-encoding:")
                  }) else {
              self.finish(self.failure())
              return
            }
            self.parsedHeader = true
            self.received = self.header.count - end.upperBound
            self.header = Data()
          } else if self.header.count > 16 * 1024 {
            self.finish(self.failure())
            return
          }
        }
      }
      if self.parsedHeader && (transfer.upload || self.received == transfer.bytes) {
        self.completeTransfer()
      } else if error != nil || complete || self.received > transfer.bytes {
        self.finish(self.failure())
      } else {
        self.receive(on: connection)
      }
    }
  }

  private func completeTransfer() {
    let elapsed = DispatchTime.now().uptimeNanoseconds - startTime
    times.append(max(Double(elapsed) / 1000, 1))
    closeConnection()
    if times.count < phases.count {
      connect()
    } else {
      finish([
        "download": Double(phases[1].bytes) * 8 / times[1],
        "upload": Double(phases[2].bytes) * 8 / times[2],
        "latencyMs": times[0] / 1000
      ])
    }
  }

  private func failure() -> FlutterError {
    FlutterError(code: "measurement_failed", message: nil, details: nil)
  }

  private func closeConnection() {
    timeout?.cancel()
    connection?.stateUpdateHandler = nil
    connection?.cancel()
    connection = nil
  }

  private func finish(_ value: Any?) {
    closeConnection()
    DispatchQueue.main.async { self.reply(value) }
  }
}
