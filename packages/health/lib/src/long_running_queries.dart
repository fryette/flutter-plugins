part of health;

typedef HealthKitHandler = FutureOr<bool> Function(HealthDataType type);

class LongRunningQueries {
  final _eventChannel = EventChannel('health_kit_background_service_channel');
  final _channel = const MethodChannel(
    'health_kit_background_service',
    JSONMethodCodec(),
  );
  StreamSubscription<dynamic>? _subscription;

  Future<bool> configure(List<HealthDataType> types) async {
    final result = await _channel.invokeMethod(
      'configure',
      {
        'types': types.map((type) => type.name).toList(),
      },
    );

    return result ?? false;
  }

  Future<void> stopService() async {
    await _subscription?.cancel();
    final result = await _channel.invokeMethod('stop_service', {});

    return result ?? false;
  }

  Future<void> startService(HealthKitHandler handler) async {
    await _channel.invokeMethod('start_service', {});
    _subscription = _eventChannel.receiveBroadcastStream().listen((event) {
      print('DATA RECEIVED');
      handler?.call(HealthDataType.values.firstWhere((e) => e.name == event));
    });
  }
}
