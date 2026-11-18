import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/services.dart';

enum NetworkTransport { wifi, mobile, other, none }

typedef ConnectionStatus = ({NetworkTransport transport, bool online});
typedef SpeedResult = ({
  double download,
  double upload,
  double latencyMs,
  double? downloadLatencyMs,
  double? uploadLatencyMs,
});

abstract interface class NetworkRepository {
  Future<ConnectionStatus> checkConnection();
  Future<SpeedResult> measureSpeed();
  Future<SpeedResult?> measureOn(NetworkTransport transport);
}

enum TestProvider {
  cloudflare('Cloudflare', 'speed.cloudflare.com'),
  clouvider('Clouvider', 'ams.speedtest.clouvider.net', prefix: '/backend'),
  cesnet('CESNET', 'speedtest.cesnet.cz', prefix: '/backend');

  const TestProvider(this.label, this.host, {this.prefix = ''});

  final String label;
  final String host;
  final String prefix;

  int get downloadBytes => this == cloudflare ? 8000000 : 8 * 1024 * 1024;

  Uri downloadUrl(int bytes) => this == cloudflare
      ? _url('/__down', {'bytes': '$bytes'})
      : bytes == 0
      ? _url('$prefix/empty.php')
      : _url('$prefix/garbage.php', {'ckSize': '8'});

  Uri get uploadUrl => _url(this == cloudflare ? '/__up' : '$prefix/empty.php');

  Uri _url(String path, [Map<String, String> query = const {}]) => Uri.https(
    host,
    path,
    {...query, 'nonce': '${DateTime.now().microsecondsSinceEpoch}'},
  );
}

class HttpNetworkRepository implements NetworkRepository {
  HttpNetworkRepository(this.provider);

  final TestProvider provider;

  Future<NetworkTransport> _activeTransport() async {
    final interfaces = await Connectivity().checkConnectivity();
    return switch (interfaces) {
      _ when interfaces.contains(ConnectivityResult.vpn) =>
        NetworkTransport.other,
      _ when interfaces.contains(ConnectivityResult.wifi) =>
        NetworkTransport.wifi,
      _ when interfaces.contains(ConnectivityResult.mobile) =>
        NetworkTransport.mobile,
      _ when interfaces.every((type) => type == ConnectivityResult.none) =>
        NetworkTransport.none,
      _ => NetworkTransport.other,
    };
  }

  @override
  Future<ConnectionStatus> checkConnection() async {
    final transport = await _activeTransport();
    if (transport == NetworkTransport.none) {
      return (transport: transport, online: false);
    }
    try {
      await _withClient(
        (client) => _transfer(client, Stopwatch()..start(), 0, false),
        const Duration(seconds: 6),
      );
      return (transport: transport, online: true);
    } on Exception {
      return (transport: transport, online: false);
    }
  }

  @override
  Future<SpeedResult?> measureOn(NetworkTransport transport) async {
    const channel = MethodChannel('netpulse/network');
    try {
      return await _measure((bytes, upload) async {
        final timing = await channel.invokeMapMethod<String, int>('transfer', {
          'transport': transport.name,
          'url': (upload ? provider.uploadUrl : provider.downloadUrl(bytes))
              .toString(),
          'bytes': bytes,
          'upload': upload,
        });
        if (timing == null) throw const _NetworkUnavailable();
        return (start: timing['start']!, end: timing['end']!);
      });
    } on _NetworkUnavailable {
      return null;
    }
  }

  @override
  Future<SpeedResult> measureSpeed() => _withClient((client) async {
    final clock = Stopwatch()..start();
    return _measure((bytes, upload) => _transfer(client, clock, bytes, upload));
  }, const Duration(seconds: 65));

  Future<SpeedResult> _measure(
    Future<_Timing> Function(int bytes, bool upload) transfer,
  ) async {
    await transfer(0, false);
    final latency = <int>[];
    for (var sample = 0; sample < 3; sample++) {
      final timing = await transfer(0, false);
      latency.add(timing.end - timing.start);
    }
    latency.sort();

    Future<({double mbps, double? latencyMs})> bandwidth(
      int bytes,
      bool upload,
    ) async {
      final adaptive = upload || provider == TestProvider.cloudflare;
      final probeBytes = adaptive ? 1000000 : bytes;
      final first = await transfer(probeBytes, upload);
      final elapsed = math.max(1, first.end - first.start);
      if (!adaptive && elapsed >= 4000000) {
        return (mbps: bytes * 8 / elapsed, latencyMs: null);
      }

      final streamBytes = adaptive
          ? (probeBytes * 1000000 ~/ elapsed).clamp(64000, bytes)
          : bytes;
      var finished = false;
      final probes = <_Timing>[];
      final streams = Future.wait([
        for (var stream = 0; stream < 3; stream++)
          transfer(streamBytes, upload),
      ]).whenComplete(() => finished = true);

      Future<void> sampleLatency() async {
        for (var sample = 0; sample < 8 && !finished; sample++) {
          try {
            probes.add(await transfer(0, false));
          } on Exception {
            // A missed probe should not discard a valid bandwidth result.
            break;
          }
          if (!finished) {
            await Future.any<void>([
              streams.then<void>((_) {}),
              Future<void>.delayed(const Duration(milliseconds: 250)),
            ]);
          }
        }
      }

      final (samples, _) = await (streams, sampleLatency()).wait;
      final start = samples.map((sample) => sample.start).reduce(math.min);
      final end = samples.map((sample) => sample.end).reduce(math.max);
      final loaded = [
        for (final probe in probes)
          if (probe.start >= start && probe.end <= end) probe.end - probe.start,
      ]..sort();
      final middle = loaded.length ~/ 2;
      return (
        mbps: streamBytes * samples.length * 8 / math.max(1, end - start),
        latencyMs: loaded.isEmpty
            ? null
            : (loaded[(loaded.length - 1) ~/ 2] + loaded[middle]) / 2000,
      );
    }

    final download = await bandwidth(provider.downloadBytes, false);
    final upload = await bandwidth(3000000, true);
    return (
      download: download.mbps,
      upload: upload.mbps,
      latencyMs: latency[1] / 1000,
      downloadLatencyMs: download.latencyMs,
      uploadLatencyMs: upload.latencyMs,
    );
  }

  Future<T> _withClient<T>(
    Future<T> Function(HttpClient) operation,
    Duration timeout,
  ) async {
    final client = HttpClient()
      ..autoUncompress = false
      ..connectionTimeout = const Duration(seconds: 8);
    try {
      return await operation(client).timeout(timeout);
    } finally {
      client.close(force: true);
    }
  }

  Future<_Timing> _transfer(
    HttpClient client,
    Stopwatch clock,
    int bytes,
    bool upload,
  ) async {
    final url = upload ? provider.uploadUrl : provider.downloadUrl(bytes);
    final request = await client.openUrl(upload ? 'POST' : 'GET', url);
    request.followRedirects = false;
    request.headers.set(HttpHeaders.cacheControlHeader, 'no-cache');
    request.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
    if (upload) {
      request.headers.contentType = ContentType.binary;
      request.contentLength = bytes;
    }
    var start = clock.elapsedMicroseconds;
    if (upload) request.add(Uint8List(bytes));
    final response = await request.close();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException('Measurement server returned ${response.statusCode}');
    }
    if (upload || bytes == 0) {
      final end = clock.elapsedMicroseconds;
      await response.drain<void>();
      return (start: start, end: end);
    }

    start = clock.elapsedMicroseconds;
    final received = await response.fold<int>(
      0,
      (total, chunk) => total + chunk.length,
    );
    if (received != bytes) {
      throw const HttpException('Unexpected response size');
    }
    return (start: start, end: clock.elapsedMicroseconds);
  }
}

typedef _Timing = ({int start, int end});

class _NetworkUnavailable implements Exception {
  const _NetworkUnavailable();
}
