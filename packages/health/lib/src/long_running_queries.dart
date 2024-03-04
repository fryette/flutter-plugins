part of health;

late EventChannel channel;

typedef HealthKitHandler = FutureOr<bool> Function(HealthDataType type);

class LongRunningQueries {
  static const MethodChannel _channel = const MethodChannel(
    'health_kit_background_service',
    JSONMethodCodec(),
  );

  Future<bool> configure(
      HealthKitHandler onBackground, List<HealthDataType> types) async {
    final backgroundHandle = PluginUtilities.getCallbackHandle(onBackground);

    final result = await _channel.invokeMethod(
      "configure",
      {
        "handle": backgroundHandle?.toRawHandle(),
        "types": types.map((type) => type.name).toList(),
      },
    );

    return result ?? false;
  }

  Future<void> stopService() async {
    final result = await _channel.invokeMethod("stop_service", {});

    return result ?? false;
  }
}

@pragma('vm:entry-point')
void healthKitEntryPoint(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  print('BEFORE DART CODE EXECUTION');

  final handle = int.parse(args.first);
  final callbackHandle = CallbackHandle.fromRawHandle(handle);
  final onStart = PluginUtilities.getCallbackFromHandle(callbackHandle)
      as HealthKitHandler?;

  channel = EventChannel('health_kit_background_service_channel');
  channel.receiveBroadcastStream().listen((event) {
    onStart?.call(HealthDataType.values.firstWhere((e) => e.name == event));
  });

  print('AFTER DART CODE EXECUTION');
}
