import 'package:flutter/foundation.dart';

import '../data/network_repository.dart';

enum Diagnostic { connection, speed, full }

class DashboardViewModel extends ChangeNotifier {
  DashboardViewModel(this._repository);

  final NetworkRepository _repository;

  Diagnostic? _running;
  Diagnostic? get running => _running;

  Diagnostic? _failed;
  Diagnostic? get failed => _failed;

  ConnectionStatus? _connection;
  ConnectionStatus? get connection => _connection;

  SpeedResult? _speed;
  SpeedResult? get speed => _speed;

  static const reportNetworks = [
    NetworkTransport.wifi,
    NetworkTransport.mobile,
  ];
  final _report = <NetworkTransport, SpeedResult?>{};
  final _reportFailures = <NetworkTransport>{};
  List<NetworkTransport> _selectedNetworks = const [];
  int _step = 0;
  NetworkTransport? get reportTarget =>
      _step < _selectedNetworks.length ? _selectedNetworks[_step] : null;

  SpeedResult? resultFor(NetworkTransport network) => _report[network];
  bool attempted(NetworkTransport network) => _report.containsKey(network);
  bool failedFor(NetworkTransport network) => _reportFailures.contains(network);

  Future<void> startReport(List<NetworkTransport> networks) async {
    if (_running != null || _disposed) return;
    _report.clear();
    _reportFailures.clear();
    _selectedNetworks = List.of(networks);
    _step = 0;
    _running = Diagnostic.full;
    while (_step < _selectedNetworks.length && !_disposed) {
      final target = _selectedNetworks[_step];
      notifyListeners();
      try {
        _report[target] = await _repository.measureOn(target);
      } on Exception {
        _reportFailures.add(target);
        _report[target] = null;
      }
      _step++;
    }
    _running = null;
    if (!_disposed) notifyListeners();
  }

  bool _disposed = false;

  Future<void> run(Diagnostic diagnostic) async {
    if (_running != null || _disposed) return;
    if (diagnostic == Diagnostic.full) return startReport(reportNetworks);
    _running = diagnostic;
    _failed = null;
    switch (diagnostic) {
      case Diagnostic.connection:
        _connection = null;
      case Diagnostic.speed:
        _speed = null;
      case Diagnostic.full:
        break;
    }
    notifyListeners();
    try {
      switch (diagnostic) {
        case Diagnostic.connection:
          _connection = await _repository.checkConnection();
        case Diagnostic.speed:
          _speed = await _repository.measureSpeed();
        case Diagnostic.full:
          break;
      }
    } on Exception {
      _failed = diagnostic;
    } finally {
      _running = null;
      if (!_disposed) notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
