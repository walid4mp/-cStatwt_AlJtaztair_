import 'package:flutter/services.dart';

/// System notifications through a small native channel (see MainActivity.kt).
/// No third-party plugin is needed, so there is nothing to break the Gradle build.
class LocalNotifier {
  static const MethodChannel _ch = MethodChannel('dz.sawtaljazair.app/notifications');
  static void Function(String payload)? onTap;

  static Future<void> init() async {
    _ch.setMethodCallHandler((call) async {
      if (call.method == 'onTap' && call.arguments is String) {
        onTap?.call(call.arguments as String);
      }
      return null;
    });
  }

  static Future<bool> requestPermission() async {
    try {
      final r = await _ch.invokeMethod<bool>('requestPermission');
      return r ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> enabled() async {
    try {
      final r = await _ch.invokeMethod<bool>('enabled');
      return r ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<String?> initialPayload() async {
    try {
      return await _ch.invokeMethod<String>('getInitialPayload');
    } catch (_) {
      return null;
    }
  }

  static Future<void> show({required int id, required String title, required String body, String? payload}) async {
    try {
      await _ch.invokeMethod<bool>('show', {'id': id, 'title': title, 'body': body, 'payload': payload});
    } catch (_) {}
  }

  static Future<void> cancelAll() async {
    try {
      await _ch.invokeMethod<bool>('cancelAll');
    } catch (_) {}
  }
}
