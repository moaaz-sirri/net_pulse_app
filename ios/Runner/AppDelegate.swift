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
      guard call.method == "transfer", let args = call.arguments as? [String: Any],
            let transport = args["transport"] as? String,
            transport == "wifi" || transport == "mobile" else {
        reply(FlutterMethodNotImplemented)
        return
      }
      guard let endpoint = args["url"] as? String, let url = URL(string: endpoint),
            let bytes = args["bytes"] as? Int, (0...10_000_000).contains(bytes),
            let upload = args["upload"] as? Bool,
            url.scheme == "https", url.host != nil, url.port == nil else {
        reply(FlutterError(code: "invalid_measurement", message: "Invalid HTTPS transfer", details: nil))
        return
      }
      InterfaceTransfer(
        interface: transport == "wifi" ? .wifi : .cellular,
        url: url,
        bytes: bytes,
        upload: upload,
        reply: reply
      ).start()
    }
  }
}

private final class InterfaceTransfer {
  private let interface: NWInterface.InterfaceType
  private let reply: FlutterResult
  private let queue = DispatchQueue(label: "netpulse.network")
  private let url: URL
  private let bytes: Int
  private let upload: Bool
  private var connection: NWConnection?
  private var timeout: DispatchWorkItem?
  private var header = Data()
  private var received = 0
  private var parsedHeader = false
  private var startTime: UInt64 = 0

  init(interface: NWInterface.InterfaceType, url: URL, bytes: Int, upload: Bool,
       reply: @escaping FlutterResult) {
    self.url = url
    self.bytes = bytes
    self.upload = upload
    self.interface = interface
    self.reply = reply
  }

  func start() {
    queue.async { self.connect() }
  }

  private func connect() {
    let parameters = NWParameters(tls: NWProtocolTLS.Options(), tcp: NWProtocolTCP.Options())
    parameters.requiredInterfaceType = interface
    guard let host = url.host else {
      finish(failure())
      return
    }
    let connection = NWConnection(host: NWEndpoint.Host(host), port: .https, using: parameters)
    self.connection = connection
    header = Data()
    received = 0
    parsedHeader = false
    startTime = 0
    let availabilityTimeout = DispatchWorkItem { [weak self] in
      guard let self else { return }
      self.finish(nil)
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

    guard let url = URLComponents(url: self.url, resolvingAgainstBaseURL: false),
          let host = url.host else {
      finish(failure())
      return
    }
    let path = url.percentEncodedPath + (url.percentEncodedQuery.map { "?" + $0 } ?? "")
    let method = upload ? "POST" : "GET"
    var request = "\(method) \(path) HTTP/1.0\r\nHost: \(host)\r\nConnection: close\r\nAccept-Encoding: identity\r\nCache-Control: no-cache\r\n"
    if upload {
      request += "Content-Type: application/octet-stream\r\nContent-Length: \(bytes)\r\n"
    }
    var data = Data((request + "\r\n").utf8)
    if upload { data.append(Data(count: bytes)) }
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
      if let data {
        if self.parsedHeader {
          self.received += data.count
        } else {
          self.header.append(data)
          let separator = Data([13, 10, 13, 10])
          if let end = self.header.range(of: separator) {
            let lines = String(decoding: self.header[..<end.lowerBound], as: UTF8.self)
              .components(separatedBy: "\r\n")
            guard let statusField = lines.first?.split(separator: " ").dropFirst().first,
                  let status = Int(statusField), (200...299).contains(status),
                  (self.upload || self.bytes == 0 || !lines.dropFirst().contains(where: {
                    $0.lowercased().hasPrefix("transfer-encoding:")
                  })) else {
              self.finish(self.failure())
              return
            }
            if !self.upload && self.bytes > 0 {
              self.startTime = DispatchTime.now().uptimeNanoseconds
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
      if self.parsedHeader && (self.upload || self.bytes == 0 || self.received == self.bytes) {
        self.completeTransfer()
      } else if error != nil || complete || self.received > self.bytes {
        self.finish(self.failure())
      } else {
        self.receive(on: connection)
      }
    }
  }

  private func completeTransfer() {
    finish([
      "start": Int64(startTime / 1000),
      "end": Int64(DispatchTime.now().uptimeNanoseconds / 1000)
    ])
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
