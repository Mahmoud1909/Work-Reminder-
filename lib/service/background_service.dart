// lib/service/background_service.dart
import 'package:flutter/widgets.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import '../service/purchase_Manager.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'notifications_service.dart';

// استورد PurchaseManager للنداء من الخلفية

const String WM_TASK_RESCHEDULE = 'khamsat_reschedule_task';
const String WM_TASK_SHOW_TEST = 'khamsat_show_test_notification';

@pragma('vm:entry-point')
Future<bool> workManagerBackgroundHandler(String taskName, Map<String, dynamic>? inputData) async {
  try {
    WidgetsFlutterBinding.ensureInitialized();

    // ensure timezone data in background isolate
    try {
      tz.initializeTimeZones();
      debugPrint('[BG] tz DB initialized');
    } catch (e, st) {
      debugPrint('[BG] tz init error -> $e\n$st');
    }

    // init notifications service in isolate
    try {
      debugPrint('[BG] NotificationsService.initialize() start');
      await NotificationsService.initialize();
      debugPrint('[BG] NotificationsService.initialize() done');
    } catch (e, st) {
      debugPrint('[BG] NotificationsService.initialize() error -> $e\n$st');
    }

    debugPrint('[BG] taskName=$taskName inputData=$inputData');

    // Always attempt to check trial expiry in background (best-effort).
    // This will set the "show upgrade on launch" flag and send a local notification when needed.
    try {
      await PurchaseManager.instance.checkTrialAndNotifyIfExpired();
      debugPrint('[BG] PurchaseManager.checkTrialAndNotifyIfExpired done');
    } catch (e, st) {
      debugPrint('[BG] PurchaseManager.checkTrialAndNotifyIfExpired error -> $e\n$st');
    }

    if (taskName == WM_TASK_RESCHEDULE) {
      try {
        await NotificationsService.instance.rescheduleIfNeeded(force: false);
        debugPrint('[BG] rescheduleIfNeeded done');
      } catch (e, st) {
        debugPrint('[BG] rescheduleIfNeeded error -> $e\n$st');
      }
    } else if (taskName == WM_TASK_SHOW_TEST) {
      try {
        await NotificationsService.instance.showImmediateNotification(
          id: DateTime.now().millisecondsSinceEpoch.remainder(100000),
          title: 'اختبار إشعار (خلفية)',
          body: 'رسالة اختبار من الخلفية.',
          payload: 'workmanager_test',
        );
        debugPrint('[BG] showImmediateNotification done');
      } catch (e, st) {
        debugPrint('[BG] showImmediateNotification error -> $e\n$st');
      }
    } else {
      try {
        await NotificationsService.instance.rescheduleIfNeeded(force: false);
        debugPrint('[BG] default reschedule done');
      } catch (e, st) {
        debugPrint('[BG] default reschedule error -> $e\n$st');
      }
    }

    return Future.value(true);
  } catch (e, st) {
    debugPrint('[BG] uncaught error -> $e\n$st');
    return Future.value(false);
  }
}

/// a wrapper to call from callbackDispatcher
@pragma('vm:entry-point')
Future<bool> backgroundTaskWrapper(String taskName, Map<String, dynamic>? inputData) {
  return workManagerBackgroundHandler(taskName, inputData);
}
