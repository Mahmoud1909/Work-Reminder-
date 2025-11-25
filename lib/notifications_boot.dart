// lib/notifications_boot.dart

import 'package:flutter/widgets.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/foundation.dart' as foundation show debugPrint; // optional alias if you prefer

import 'service/notifications_service.dart';

@pragma('vm:entry-point')
Future<void> notificationsBootEntrypoint() async {
  try {
    // تأكد تهيئة الـ bindings (مهم عند تشغيل كـ background isolate)
    WidgetsFlutterBinding.ensureInitialized();
    debugPrint('notificationsBootEntrypoint: started - initializing background environment.');

    // صغير تأخير للتأكد من استقرار الـ isolate قبل تشغيل التهيئات
    await Future.delayed(const Duration(milliseconds: 300));

    try {
      debugPrint('notificationsBootEntrypoint: calling NotificationsService.instance.init()');
      await NotificationsService.instance.init();
      debugPrint('notificationsBootEntrypoint: NotificationsService.init() completed.');
    } catch (e, st) {
      debugPrint('notificationsBootEntrypoint: init failed -> $e\n$st');
    }

    try {
      debugPrint('notificationsBootEntrypoint: calling NotificationsService.instance.rescheduleFromBoot()');
      await NotificationsService.instance.rescheduleFromBoot();
      debugPrint('notificationsBootEntrypoint: rescheduleFromBoot completed.');
    } catch (e, st) {
      debugPrint('notificationsBootEntrypoint: rescheduleFromBoot failed -> $e\n$st');
    }

    debugPrint('notificationsBootEntrypoint: finished.');
  } catch (e, st) {
    debugPrint('notificationsBootEntrypoint: unexpected error -> $e\n$st');
  } finally {
    await Future.delayed(const Duration(milliseconds: 200));
  }
}
