import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/services.dart';

enum NetworkTransport { wifi, mobile, other, none }

typedef ConnectionStatus = ({NetworkTransport transport, bool online});
typedef SpeedResult = ({double download, double upload, double latencyMs});

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
        (client) => _download(client, 0),
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
    final values = await channel.invokeMapMethod<String, double>('measure', {
      'transport': transport.name,
      'pingUrl': provider.downloadUrl(0).toString(),
      'downloadUrl': provider.downloadUrl(provider.downloadBytes).toString(),
      'downloadBytes': provider.downloadBytes,
      'uploadUrl': provider.uploadUrl.toString(),
    });
    if (values == null) return null;
    return (
      download: values['download']!,
      upload: values['upload']!,
      latencyMs: values['latencyMs']!,
    );
  }

  @override
  Future<SpeedResult> measureSpeed() => _withClient((client) async {
    await _download(client, 0);
    final latency = Stopwatch()..start();
    await _download(client, 0);
    latency.stop();
    final download = await _download(client, provider.downloadBytes);
    final payload = Uint8List(3000000);
    final request = await client.postUrl(provider.uploadUrl);
    request.followRedirects = false;
    request.headers.contentType = ContentType.binary;
    request.contentLength = payload.length;
    final timer = Stopwatch()..start();
    request.add(payload);
    final response = await request.close();
    _validate(response);
    await response.drain<void>();
    return (
      download: download,
      upload: _mbps(payload.length, timer),
      latencyMs: latency.elapsedMicroseconds / 1000,
    );
  }, const Duration(seconds: 35));

  Future<T> _withClient<T>(
    Future<T> Function(HttpClient) operation,
    Duration timeout,
  ) async {
    final client = HttpClient()..autoUncompress = false;
    try {
      return await operation(client).timeout(timeout);
    } finally {
      client.close(force: true);
    }
  }

  Future<double> _download(HttpClient client, int bytes) async {
    final request = await client.getUrl(provider.downloadUrl(bytes));
    request.followRedirects = false;
    request.headers.set(HttpHeaders.cacheControlHeader, 'no-cache');
    final timer = Stopwatch()..start();
    final response = await request.close();
    _validate(response);
    final received = await response.fold<int>(
      0,
      (total, chunk) => total + chunk.length,
    );
    if (received != bytes) {
      throw const HttpException('Unexpected response size');
    }
    return _mbps(received, timer);
  }

  void _validate(HttpClientResponse response) {
    if (response.statusCode != HttpStatus.ok) {
      throw HttpException('Measurement server returned ${response.statusCode}');
    }
  }

  double _mbps(int bytes, Stopwatch timer) =>
      bytes * 8 / (timer.elapsedMicroseconds + 1);
}
