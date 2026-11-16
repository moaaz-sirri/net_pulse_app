import 'package:flutter_test/flutter_test.dart';
import 'package:net_pulse_app/data/network_repository.dart';
import 'package:net_pulse_app/ui/dashboard_view_model.dart';

const SpeedResult result = (download: 40, upload: 8, latencyMs: 32);

class _Network implements NetworkRepository {
  bool failSpeed = true;

  @override
  Future<ConnectionStatus> checkConnection() async =>
      (transport: NetworkTransport.wifi, online: true);

  @override
  Future<SpeedResult> measureSpeed() async {
    if (failSpeed) throw Exception('Speed test failed');
    return result;
  }

  @override
  Future<SpeedResult?> measureOn(NetworkTransport transport) async {
    if (transport == NetworkTransport.wifi) {
      throw Exception('Wi-Fi measurement failed');
    }
    return result;
  }
}

void main() {
  late _Network repository;
  late DashboardViewModel model;

  setUp(() {
    repository = _Network();
    model = DashboardViewModel(repository);
  });

  tearDown(() => model.dispose());

  test('speed test clears its failure when retried successfully', () async {
    await model.run(Diagnostic.speed);

    expect(model.failed, Diagnostic.speed);
    expect(model.speed, isNull);
    expect(model.running, isNull);

    repository.failSpeed = false;
    await model.run(Diagnostic.speed);

    expect(model.failed, isNull);
    expect(model.speed, result);
    expect(model.running, isNull);
  });

  test(
    'report continues after Wi-Fi fails and resets on the next run',
    () async {
      await model.startReport(DashboardViewModel.reportNetworks);

      expect(model.attempted(NetworkTransport.wifi), isTrue);
      expect(model.failedFor(NetworkTransport.wifi), isTrue);
      expect(model.resultFor(NetworkTransport.wifi), isNull);
      expect(model.failedFor(NetworkTransport.mobile), isFalse);
      expect(model.resultFor(NetworkTransport.mobile), result);
      expect(model.running, isNull);

      await model.startReport([NetworkTransport.mobile]);

      expect(model.attempted(NetworkTransport.wifi), isFalse);
      expect(model.failedFor(NetworkTransport.wifi), isFalse);
      expect(model.resultFor(NetworkTransport.mobile), result);
    },
  );
}
