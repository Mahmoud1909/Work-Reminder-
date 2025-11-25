// lib/service/notifications_service.dart

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';

// Optional app-specific imports (keep stubs or implement in your app)
import '../screens/vacation_manager.dart';
import '../service/purchase_manager.dart'
    if (dart.library.io) '../service/purchase_manager.dart';

// ---------------- Background entrypoints ----------------
@pragma('vm:entry-point')
Future<bool> workManagerBackgroundHandler(
  String taskName,
  Map<String, dynamic>? inputData,
) async {
  try {
    WidgetsFlutterBinding.ensureInitialized();
  } catch (_) {}

  try {
    tzdata.initializeTimeZones();
    debugPrint('[WM][handler] tz DB initialized');
  } catch (e, st) {
    debugPrint('[WM][handler] tz init error -> $e\n$st');
  }

  debugPrint('[WM][handler] invoked task=$taskName inputData=$inputData');

  try {
    await NotificationsService.initialize();
    debugPrint('[WM][handler] NotificationsService initialized');

    if (taskName == 'khamsat_show_test_notification') {
      await NotificationsService.instance.showImmediateNotification(
        id: DateTime.now().millisecondsSinceEpoch.remainder(100000),
        title: 'إشعار تجريبي',
        body: 'هذا إشعار تجريبي من النظام — للتجربة فقط.',
        payload: 'workmanager_test',
      );
    } else {
      await NotificationsService.instance.rescheduleIfNeeded(force: false);
    }
  } catch (e, st) {
    debugPrint('[WM][handler] error while handling task -> $e\n$st');
  }

  return true;
}

@pragma('vm:entry-point')
void _notificationTapBackground(NotificationResponse response) {
  try {
    debugPrint('[BG_NOTIFY_CALLBACK] payload=${response.payload}');
    NotificationsService.instance._handleNotificationResponse(response);
  } catch (e, st) {
    debugPrint('[BG_NOTIFY_CALLBACK] error -> $e\n$st');
  }
}

@pragma('vm:entry-point')
Future<void> _renewalAlarmEntryPoint() async {
  try {
    WidgetsFlutterBinding.ensureInitialized();
  } catch (_) {}

  try {
    tzdata.initializeTimeZones();
  } catch (_) {}

  debugPrint(
    '[renewalAlarmEntryPoint] invoked - initializing NotificationsService',
  );

  try {
    await NotificationsService.initialize();
    await NotificationsService.instance.rescheduleIfNeeded(force: true);
    debugPrint(
      '[renewalAlarmEntryPoint] rescheduleIfNeeded(force: true) completed',
    );
  } catch (e, st) {
    debugPrint('[renewalAlarmEntryPoint] error -> $e\n$st');
  }
}

// ---------------- Main service ----------------
class NotificationsService {
  NotificationsService._privateConstructor();

  static final NotificationsService instance =
      NotificationsService._privateConstructor();

  static Future<void> initialize() async =>
      await NotificationsService.instance.init();

  static const MethodChannel _nativeChannel = MethodChannel(
    'khamsat/native_notifications',
  );

  // prefs keys
  static const String _kWorkSystem = 'workSystem';
  static const String _kStartDate = 'startDate';
  static const String _kMorningStart = 'morningStart';
  static const String _kMorningCheckIn = 'morningCheckIn';
  static const String _kAfternoonStart = 'afternoonStart';
  static const String _kAfternoonCheckIn = 'afternoonCheckIn';
  static const String _kNightStart = 'nightStart';
  static const String _kNightCheckIn = 'nightCheckIn';
  static const String _kReminder = 'reminder';
  static const String _kMaintenanceInterval = 'maintenanceInterval';
  static const String _kScheduledUntilKey = 'notifications_scheduled_until';
  static const String _kWelcomeShownKey = 'welcomeNotificationShown';
  static const String _kConfirmationShownKey =
      'notifications_confirmed_by_notification';
  static const String _kLastKnownTimeZone = 'lastKnownTimeZone';
  static const String _kSubscriptionReminderScheduled =
      'subscription_reminder_scheduled';
  static const String _kSubscriptionReminderCancelled =
      'subscription_reminder_cancelled';
  static const String _kAutoMonthlyRenew = 'auto_monthly_renew_enabled';

  static const int _kSubscriptionReminderId = 450000;
  static const int _kRenewalAlarmId = 987654;

  // default scheduling horizon (monthly auto-renew uses 30 days)
  static const int _kDefaultScheduleDays = 30;
  static const int _kRenewalBeforeDays =
      3; // renew X days before scheduledUntil

  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  GlobalKey<NavigatorState>? _navigatorKey;

  void setNavigatorKey(GlobalKey<NavigatorState> key) {
    _navigatorKey = key;
    debugPrint('[NotificationsService] navigatorKey set');
  }

  bool _initialized = false;
  String? _lastKnownTimeZone;

  // ---------------- init ----------------
  Future<void> init() async {
    if (_initialized) {
      debugPrint(
        '[NotificationsService.init] already initialized -> returning',
      );
      return;
    }
    debugPrint('[NotificationsService.init] start');

    await _initTimezone(); // sets tz.local and _lastKnownTimeZone

    const androidInitSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );
    const iosInitSettings = DarwinInitializationSettings();

    final initSettings = InitializationSettings(
      android: androidInitSettings,
      iOS: iosInitSettings,
    );

    try {
      await flutterLocalNotificationsPlugin.initialize(
        initSettings,
        onDidReceiveNotificationResponse: (NotificationResponse response) {
          debugPrint(
            '[NotificationsService.init] notification response payload=${response.payload}',
          );
          _handleNotificationResponse(response);
        },
        onDidReceiveBackgroundNotificationResponse: _notificationTapBackground,
      );
      debugPrint('[NotificationsService.init] plugin initialized');
    } catch (e, st) {
      debugPrint('[NotificationsService.init] plugin init error -> $e\n$st');
    }

    // Create Android channels
    if (!kIsWeb && Platform.isAndroid) {
      try {
        final androidImpl = flutterLocalNotificationsPlugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >();

        if (androidImpl != null) {
          final purchaseChannel = AndroidNotificationChannel(
            'purchase_channel',
            'تذكيرات الاشتراك',
            description: 'تذكيرات خاصة بالاشتراكات والمشتريات',
            importance: Importance.max,
            playSound: true,
            showBadge: true,
          );
          final workChannel = AndroidNotificationChannel(
            'work_channel',
            'تذكيرات الوردية',
            description: 'تذكيرات الوردية وفحص الحضور',
            importance: Importance.max,
            playSound: true,
            showBadge: true,
          );
          final firstRunChannel = AndroidNotificationChannel(
            'first_run_channel',
            'إشعارات البداية',
            description: 'إشعارات ترحيبية وتأكيدية لمرة واحدة',
            importance: Importance.max,
            playSound: true,
            showBadge: true,
          );

          await androidImpl.createNotificationChannel(purchaseChannel);
          await androidImpl.createNotificationChannel(workChannel);
          await androidImpl.createNotificationChannel(firstRunChannel);

          debugPrint('[NotificationsService.init] Android channels created');
        }
      } catch (e, st) {
        debugPrint(
          '[NotificationsService.init] createNotificationChannel error -> $e\n$st',
        );
      }
    }

    // snapshot timezone name to prefs
    try {
      final tzName = (await FlutterTimezone.getLocalTimezone()).toString();
      _lastKnownTimeZone = tzName;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kLastKnownTimeZone, tzName);
      debugPrint(
        '[NotificationsService.init] timezone snapshot saved -> $tzName',
      );
    } catch (e) {
      debugPrint(
        '[NotificationsService.init] reading tz snapshot failed -> $e',
      );
    }

    _initialized = true;
    debugPrint('[NotificationsService.init] finished. Service is ready.');
  }

  // ---------------- timezone init (ONLY flutter_timezone used) ----------------
  Future<void> _initTimezone() async {
    // comment: here نحضّر قاعدة بيانات الـ tz ونحاول نضبط tz.local بحيث تكون صحيحة على الجهاز
    debugPrint(
      '[NotificationsService._initTimezone] initializing timezone DB and local location',
    );
    tzdata.initializeTimeZones();

    final prefs = await SharedPreferences.getInstance();

    String? pluginTz;
    try {
      final dynamic fwTz = await FlutterTimezone.getLocalTimezone();
      if (fwTz != null && fwTz.toString().isNotEmpty) {
        pluginTz = fwTz.toString();
        debugPrint(
          '[NotificationsService._initTimezone] flutter_timezone reported -> $pluginTz',
        );
      }
    } catch (e) {
      debugPrint(
        '[NotificationsService._initTimezone] flutter_timezone call failed -> $e',
      );
    }

    final persistedTz = prefs.getString(_kLastKnownTimeZone);
    String? offsetMatch;
    try {
      offsetMatch = _findBestMatchingTimeZoneByOffset(
        DateTime.now().timeZoneOffset,
      );
      if (offsetMatch != null) {
        debugPrint(
          '[NotificationsService._initTimezone] matched by offset -> $offsetMatch',
        );
      }
    } catch (e) {
      debugPrint(
        '[NotificationsService._initTimezone] offset match failed -> $e',
      );
    }

    final fallbackCandidates = <String>{
      if (pluginTz != null) pluginTz,
      if (persistedTz != null && persistedTz.isNotEmpty) persistedTz,
      if (offsetMatch != null) offsetMatch,
      'Asia/Riyadh', // common Gulf timezone (UTC+3)
      'Africa/Cairo',
      'Etc/GMT-3',
      'Europe/Athens',
      'UTC',
    }.toList();

    for (final candidate in fallbackCandidates) {
      try {
        tz.setLocalLocation(tz.getLocation(candidate));
        _lastKnownTimeZone = candidate;
        await prefs.setString(_kLastKnownTimeZone, candidate);
        debugPrint(
          '[NotificationsService._initTimezone] set tz.local -> $candidate',
        );
        return;
      } catch (e) {
        debugPrint(
          '[NotificationsService._initTimezone] tz.getLocation failed for $candidate -> $e',
        );
      }
    }

    // final resort
    tz.setLocalLocation(tz.getLocation('UTC'));
    _lastKnownTimeZone = 'UTC';
    try {
      await prefs.setString(_kLastKnownTimeZone, 'UTC');
    } catch (_) {}
    debugPrint('[NotificationsService._initTimezone] used final fallback UTC');
  }

  // helper: tries to find an IANA timezone name by offset (best-effort)
  String? _findBestMatchingTimeZoneByOffset(Duration offset) {
    // Note: this is best-effort and not perfect. We prefer exact IANA from plugin.
    final all = tz.timeZoneDatabase.locations.keys;
    for (final name in all) {
      final loc = tz.getLocation(name);
      try {
        final off = tz.TZDateTime.now(loc).timeZoneOffset;
        if (off == offset) return name;
      } catch (_) {}
    }
    return null;
  }

  // ---------------- Permissions / platform helpers ----------------
  Future<bool> requestPermissions() async {
    try {
      if (!kIsWeb && Platform.isIOS) {
        final iosImpl = flutterLocalNotificationsPlugin
            .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin
            >();
        if (iosImpl != null)
          await iosImpl.requestPermissions(
            alert: true,
            badge: true,
            sound: true,
          );
      }

      if (!kIsWeb && Platform.isAndroid) {
        try {
          final status = await Permission.notification.status;
          if (!status.isGranted) {
            final res = await Permission.notification.request();
            return res.isGranted;
          }
          return true;
        } catch (e) {
          debugPrint(
            '[NotificationsService.requestPermissions] permission_handler error -> $e',
          );
          return false;
        }
      }
      return true;
    } catch (e, st) {
      debugPrint('[NotificationsService.requestPermissions] error -> $e\n$st');
      return false;
    }
  }

  Future<void> requestExactAlarmPermissionIfNeeded() async {
    if (!kIsWeb && Platform.isAndroid) {
      try {
        try {
          await AndroidFlutterLocalNotificationsPlugin()
              .requestExactAlarmsPermission();
          debugPrint(
            '[NotificationsService] requested exact alarms permission via plugin',
          );
        } catch (pluginErr) {
          debugPrint(
            '[NotificationsService] plugin.requestExactAlarmsPermission not available or failed -> $pluginErr',
          );
          try {
            await _nativeChannel.invokeMethod('requestScheduleExactAlarm');
            debugPrint(
              '[NotificationsService] requested exact alarm permission via native channel',
            );
          } catch (nativeErr) {
            debugPrint(
              '[NotificationsService] native requestScheduleExactAlarm not implemented -> $nativeErr',
            );
          }
        }
      } catch (e) {
        debugPrint(
          '[NotificationsService] requestExactAlarmPermissionIfNeeded outer error -> $e',
        );
      }
    }
  }

  Future<void> requestIgnoreBatteryOptimizationsIfNeeded() async {
    if (!kIsWeb && Platform.isAndroid) {
      try {
        await _nativeChannel.invokeMethod('requestIgnoreBatteryOptimizations');
        debugPrint(
          '[NotificationsService] requested ignore battery optimizations via native channel',
        );
      } catch (e) {
        debugPrint(
          '[NotificationsService] native requestIgnoreBatteryOptimizations not implemented -> $e',
        );
      }
    }
  }

  Future<void> openAppNotificationSettings() async {
    if (!kIsWeb && Platform.isAndroid) {
      try {
        await _nativeChannel.invokeMethod('openNotificationSettings');
        return;
      } catch (e) {
        debugPrint(
          '[NotificationsService] openNotificationSettings native not implemented -> $e',
        );
      }
    }
    try {
      await openAppSettings();
      debugPrint('[NotificationsService] opened app settings');
    } catch (e) {
      debugPrint('[NotificationsService] openAppSettings failed -> $e');
    }
  }

  // ---------------- Scheduling helpers (now expect UTC storage, convert to local on schedule) ----------------

  // Note: scheduleNotification now expects `scheduledDateTimeUtc` (UTC DateTime).
  // Inside, we convert UTC -> tz.local and schedule using zonedSchedule.
  Future<void> scheduleNotification({
    required int id,
    required String title,
    required String body,
    required DateTime scheduledDateTimeUtc, // <-- expects UTC
    String? payload,
    AndroidNotificationDetails? androidDetails,
    DarwinNotificationDetails? iosDetails,
    String channelId = 'work_channel',
    DateTimeComponents? matchDateTimeComponents,
  }) async {
    // debug: print the UTC we received and the device tz
    debugPrint(
      '[scheduleNotification] id=$id title="$title" scheduledUtc=$scheduledDateTimeUtc (tz=${_lastKnownTimeZone ?? "unknown"})',
    );
    try {
      await init();

      // convert the incoming UTC DateTime to device-local tz (using timezone package)
      final scheduledTz = tz.TZDateTime.from(
        scheduledDateTimeUtc.toUtc(),
        tz.local,
      );

      final now = tz.TZDateTime.now(tz.local);
      if (!scheduledTz.isAfter(now) && matchDateTimeComponents == null) {
        debugPrint(
          '[scheduleNotification] skipping past notification id=$id scheduled=$scheduledTz now=$now',
        );
        return;
      }

      final channelDisplay = channelId == 'work_channel'
          ? 'تذكيرات الوردية'
          : 'عام';
      final channelDescription = channelId == 'work_channel'
          ? 'تذكيرات الوردية'
          : 'إشعارات عامة';

      final nd = NotificationDetails(
        android:
            androidDetails ??
            AndroidNotificationDetails(
              channelId,
              channelDisplay,
              channelDescription: channelDescription,
              importance: Importance.max,
              priority: Priority.high,
              playSound: true,
            ),
        iOS:
            iosDetails ??
            const DarwinNotificationDetails(
              presentAlert: true,
              presentSound: true,
            ),
      );

      try {
        await flutterLocalNotificationsPlugin.zonedSchedule(
          id,
          title,
          body,
          scheduledTz,
          nd,
          payload: payload,
          androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
          matchDateTimeComponents: matchDateTimeComponents,
        );
        debugPrint('[scheduleNotification] scheduled id=$id at $scheduledTz');
      } on PlatformException catch (pe) {
        debugPrint(
          '[scheduleNotification] PlatformException -> $pe, trying inexact fallback',
        );
        try {
          await flutterLocalNotificationsPlugin.zonedSchedule(
            id,
            title,
            body,
            scheduledTz,
            nd,
            payload: payload,
            androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
            matchDateTimeComponents: matchDateTimeComponents,
          );
          debugPrint(
            '[scheduleNotification] scheduled inexact id=$id at $scheduledTz',
          );
        } catch (e2, st2) {
          debugPrint(
            '[scheduleNotification] inexact retry failed -> $e2\n$st2',
          );
          await _scheduleNativeFallback(
            id,
            title,
            body,
            scheduledDateTimeUtc.toLocal(),
          );
        }
      } catch (e, st) {
        debugPrint('[scheduleNotification] unexpected error -> $e\n$st');
        await _scheduleNativeFallback(
          id,
          title,
          body,
          scheduledDateTimeUtc.toLocal(),
        );
      }
    } catch (e, st) {
      debugPrint('[scheduleNotification] outer error -> $e\n$st');
    }
  }

  Future<void> _scheduleNativeFallback(
    int id,
    String title,
    String body,
    DateTime scheduledLocal,
  ) async {
    try {
      final delaySeconds = scheduledLocal
          .difference(DateTime.now())
          .inSeconds
          .clamp(5, 2147483647);
      if (delaySeconds <= 0) {
        await showImmediateNotification(
          id: id,
          title: title,
          body: body,
          payload: 'fallback_immediate',
        );
        return;
      }

      if (!kIsWeb && Platform.isAndroid) {
        try {
          await _nativeChannel.invokeMethod('scheduleFallbackAlarm', {
            'id': id,
            'title': title,
            'body': body,
            'delaySeconds': delaySeconds,
          });
          debugPrint(
            '[nativeFallback] requested native fallback alarm id=$id delay=$delaySeconds',
          );
          return;
        } catch (e) {
          debugPrint('[nativeFallback] native invoke failed -> $e');
        }
      }

      await showImmediateNotification(
        id: id,
        title: title,
        body: body,
        payload: 'fallback_immediate',
      );
    } catch (e, st) {
      debugPrint('[nativeFallback] error -> $e\n$st');
    }
  }

  Future<void> showImmediateNotification({
    required int id,
    required String title,
    required String body,
    String? payload,
  }) async {
    try {
      final details = NotificationDetails(
        android: AndroidNotificationDetails(
          'work_channel',
          'تذكيرات الوردية',
          channelDescription: 'تذكيرات الوردية',
          importance: Importance.max,
          priority: Priority.high,
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentSound: true,
        ),
      );
      await flutterLocalNotificationsPlugin.show(
        id,
        title,
        body,
        details,
        payload: payload,
      );
      debugPrint('[showImmediateNotification] shown id=$id title="$title"');
    } catch (e, st) {
      debugPrint('[showImmediateNotification] error -> $e\n$st');
    }
  }

  // convenience: schedule one-off seconds from now (we convert to UTC before calling scheduleNotification)
  Future<void> scheduleOneOffSecondsFromNow({
    required int id,
    required String title,
    required String body,
    required int seconds,
  }) async {
    final scheduledLocal = DateTime.now().add(Duration(seconds: seconds));
    final scheduledUtc = scheduledLocal.toUtc();
    await scheduleNotification(
      id: id,
      title: title,
      body: body,
      scheduledDateTimeUtc: scheduledUtc,
      payload: 'oneoff|$id',
    );
  }

  Future<void> scheduleOneOffMinutesFromNow({
    required int id,
    required String title,
    required String body,
    required int minutes,
  }) async {
    final scheduledLocal = DateTime.now().add(Duration(minutes: minutes));
    final scheduledUtc = scheduledLocal.toUtc();
    await scheduleNotification(
      id: id,
      title: title,
      body: body,
      scheduledDateTimeUtc: scheduledUtc,
      payload: 'oneoff|$id',
    );
  }

  // daily at time: create local DateTime at desired hour/minute, then convert to UTC and schedule.
  Future<void> scheduleDailyAtTime({
    required int id,
    required String title,
    required String body,
    required int hour,
    required int minute,
    String channelId = 'work_channel',
  }) async {
    // Build local DateTime for next occurrence
    final nowLocal = DateTime.now();
    var firstLocal = DateTime(
      nowLocal.year,
      nowLocal.month,
      nowLocal.day,
      hour,
      minute,
    );
    if (!firstLocal.isAfter(nowLocal))
      firstLocal = firstLocal.add(const Duration(days: 1));

    // convert the local moment to UTC for storage/scheduling
    final firstUtc = firstLocal.toUtc();

    final channelDisplay = channelId == 'work_channel'
        ? 'تذكيرات الوردية'
        : 'عام';
    final channelDescription = 'تذكيرات يومية';

    final nd = NotificationDetails(
      android: AndroidNotificationDetails(
        channelId,
        channelDisplay,
        channelDescription: channelDescription,
        importance: Importance.max,
        priority: Priority.high,
        playSound: true,
      ),
      iOS: const DarwinNotificationDetails(
        presentAlert: true,
        presentSound: true,
      ),
    );

    // schedule using our unified method (it will convert firstUtc -> tz.local internally)
    await scheduleNotification(
      id: id,
      title: title,
      body: body,
      scheduledDateTimeUtc: firstUtc,
      payload: 'daily|$hour:$minute',
      channelId: channelId,
      matchDateTimeComponents: DateTimeComponents.time,
    );

    debugPrint(
      '[scheduleDailyAtTime] scheduled daily id=$id at ${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')} (storedUtc=${firstUtc.toIso8601String()})',
    );
  }

  // ---------------- ids / content helpers ----------------
  int _notificationIdFor(DateTime dayUtc, int offset, [String? tag]) {
    // dayUtc expected to be UTC midnight (DateTime.utc(...))
    final baseSeconds =
        DateTime.utc(
          dayUtc.year,
          dayUtc.month,
          dayUtc.day,
        ).millisecondsSinceEpoch ~/
        1000;
    int salt = 0;
    if (tag != null && tag.isNotEmpty) {
      final hashBytes = sha1.convert(utf8.encode(tag)).bytes;
      salt =
          (((hashBytes[0] << 16) | (hashBytes[1] << 8) | hashBytes[2]) &
              0x00FFFFFF) %
          100000;
    }
    final idLarge = ((baseSeconds % 1000000) * 10) + offset + salt;
    return idLarge % 0x7FFFFFFF;
  }

  String _shiftLabel(String shift) {
    switch (shift) {
      case 'morning':
        return 'الصباحية';
      case 'afternoon':
        return 'المسائية';
      case 'night':
        return 'الليلية';
      case 'maintenance':
        return 'الصيانة';
      case 'off':
        return 'إجازة';
      default:
        return 'الوردية';
    }
  }

  String _titleForOffset(int offset, String shift) {
    final s = _shiftLabel(shift);
    switch (offset) {
      case 0:
        return 'تذكير: باقي 12 ساعة على الوردية $s';
      case 1:
        return 'تذكير: قرب بداية الوردية ($s)';
      case 2:
        return 'تأكيد الحضور: $s';
      case 3:
        return 'انتهت الوردية: $s';
      default:
        return 'تذكير';
    }
  }

  String _bodyForOffset(int offset, String shift) {
    final s = _shiftLabel(shift);
    switch (offset) {
      case 0:
        return 'الوردية $s راح تبدأ بعد 12 ساعة — تجهّز بدري.';
      case 1:
        return 'الوردية $s بتبدأ بعد شوي، حضّر أمورك وتجهّز.';
      case 2:
        return 'وقت تأكيد الحضور للوردية $s — فضلاً أكد حضورك عشان نسجّل حضورك.';
      case 3:
        return 'الوردية $s خلصت الحين. إن شاء الله كان يومك طيب.';
      default:
        return '';
    }
  }

  // ---------------- schedule for a local day ----------------
  Future<void> scheduleNotificationsForDayLocal({
    required DateTime localDay,
  }) async {
    // comment: localDay is a local DateTime representing the day to schedule for.
    final day = DateTime(localDay.year, localDay.month, localDay.day);
    debugPrint(
      '[scheduleNotificationsForDayLocal] scheduling notifications for day=$day (local)',
    );

    try {
      try {
        final vac = await VacationManager.getVacationForDate(day);
        if (vac != null) {
          debugPrint(
            '[scheduleNotificationsForDayLocal] day is a vacation; skipping notifications',
          );
          return;
        }
      } catch (e) {
        debugPrint(
          '[scheduleNotificationsForDayLocal] VacationManager check failed -> $e',
        );
      }

      final prefs = await SharedPreferences.getInstance();
      final workSystem = prefs.getString(_kWorkSystem) ?? 'صباحي';
      final maintenanceInterval = prefs.getInt(_kMaintenanceInterval) ?? 0;

      final morningStart = prefs.getString(_kMorningStart) ?? '07:00 صباحاً';
      final morningCheckIn =
          prefs.getString(_kMorningCheckIn) ?? '07:30 صباحاً';
      final afternoonStart = prefs.getString(_kAfternoonStart) ?? '15:00 مساءً';
      final afternoonCheckIn =
          prefs.getString(_kAfternoonCheckIn) ?? '15:30 مساءً';
      final nightStart = prefs.getString(_kNightStart) ?? '19:00 مساءً';
      final nightCheckIn = prefs.getString(_kNightCheckIn) ?? '19:30 مساءً';
      final reminderStr = prefs.getString(_kReminder) ?? 'نصف ساعة';
      final reminderDuration = _getReminderDurationFromString(reminderStr);
      debugPrint(
        '[scheduleNotificationsForDayLocal] reminder=$reminderStr -> duration=${reminderDuration.inMinutes}m',
      );

      final startDateStr = prefs.getString(_kStartDate);
      if (startDateStr == null) {
        debugPrint(
          '[scheduleNotificationsForDayLocal] startDate not configured in preferences -> aborting',
        );
        return;
      }
      var startDate = DateTime.tryParse(startDateStr);
      if (startDate == null) {
        debugPrint(
          '[scheduleNotificationsForDayLocal] startDate in prefs is invalid -> aborting',
        );
        return;
      }
      startDate = DateTime(startDate.year, startDate.month, startDate.day);

      // schedule map generated using UTC keys (we store schedule by UTC date to be stable)
      final schedule = _generateWorkScheduleSegment(
        workSystem,
        startDate,
        maintenanceInterval,
        days: 400,
      );
      final keyUtc = DateTime.utc(day.year, day.month, day.day);
      final shift = schedule[keyUtc];
      if (shift == null || shift == 'off') {
        debugPrint(
          '[scheduleNotificationsForDayLocal] no shift scheduled for this day or it is off -> skipping',
        );
        return;
      }

      DateTime startDT;
      DateTime checkInDT;
      if (shift == 'morning' || shift == 'maintenance') {
        startDT = _parseTime(day, morningStart);
        checkInDT = _parseTime(day, morningCheckIn);
      } else if (shift == 'afternoon') {
        startDT = _parseTime(day, afternoonStart);
        checkInDT = _parseTime(day, afternoonCheckIn);
      } else {
        startDT = _parseTime(day, nightStart);
        checkInDT = _parseTime(day, nightCheckIn);
      }

      final shiftDuration = _getShiftDurationFromSystem(workSystem);
      final endDT = startDT.add(shiftDuration);

      // times are local DateTimes; **we convert to UTC** before calling scheduleNotification
      final reminderTime = startDT.subtract(reminderDuration);
      final Map<int, DateTime> times = {
        0: startDT.subtract(const Duration(hours: 12)),
        1: reminderTime,
        2: checkInDT,
        3: endDT,
      };

      debugPrint(
        '[scheduleNotificationsForDayLocal] shift=$shift start=$startDT reminderAt=$reminderTime checkIn=$checkInDT end=$endDT',
      );

      final dayUtc = DateTime.utc(day.year, day.month, day.day);

      for (final entry in times.entries) {
        final offset = entry.key;
        final scheduledLocal = entry.value;
        final id = _notificationIdFor(dayUtc, offset);
        try {
          // convert to tz-aware time and check if it's in the future using tz.local
          final tzDt = tz.TZDateTime.from(scheduledLocal, tz.local);
          if (tzDt.isBefore(tz.TZDateTime.now(tz.local))) {
            debugPrint(
              '[scheduleNotificationsForDayLocal] skipping offset=$offset because scheduled time $tzDt is in the past',
            );
            continue;
          }

          // convert scheduledLocal -> UTC for storage/scheduling call
          final scheduledUtc = scheduledLocal.toUtc();
          final payload = '${dayUtc.toIso8601String()}|$offset|$shift';
          debugPrint(
            '[scheduleNotificationsForDayLocal] scheduling offset=$offset -> utc=${scheduledUtc.toIso8601String()} local=$scheduledLocal',
          );

          await scheduleNotification(
            id: id,
            title: _titleForOffset(offset, shift),
            body: _bodyForOffset(offset, shift),
            scheduledDateTimeUtc:
                scheduledUtc, // pass UTC; scheduleNotification will convert to local tz
            payload: payload,
            channelId: 'work_channel',
          );
        } catch (e, st) {
          debugPrint(
            '[scheduleNotificationsForDayLocal] error scheduling offset=$offset -> $e\n$st',
          );
        }
      }

      debugPrint(
        '[scheduleNotificationsForDayLocal] finished for $day shift=$shift',
      );
    } catch (e, st) {
      debugPrint('[scheduleNotificationsForDayLocal] outer error -> $e\n$st');
    }
  }

  // ---------------- ensureRemainingNotificationsForDay (uses same UTC conversion) ----------------
  Future<void> _ensureRemainingNotificationsForDay(
    DateTime localDay,
    String shift,
  ) async {
    try {
      final day = DateTime(localDay.year, localDay.month, localDay.day);
      debugPrint('[ensureRemaining] start for $day shift=$shift');

      final prefs = await SharedPreferences.getInstance();

      final workSystem = prefs.getString(_kWorkSystem) ?? 'صباحي';
      final maintenanceInterval = prefs.getInt(_kMaintenanceInterval) ?? 0;
      final morningStart = prefs.getString(_kMorningStart) ?? '07:00 صباحاً';
      final morningCheckIn =
          prefs.getString(_kMorningCheckIn) ?? '07:30 صباحاً';
      final afternoonStart = prefs.getString(_kAfternoonStart) ?? '15:00 مساءً';
      final afternoonCheckIn =
          prefs.getString(_kAfternoonCheckIn) ?? '15:30 مساءً';
      final nightStart = prefs.getString(_kNightStart) ?? '19:00 مساءً';
      final nightCheckIn = prefs.getString(_kNightCheckIn) ?? '19:30 مساءً';
      final reminderStr = prefs.getString(_kReminder) ?? 'نصف ساعة';
      final reminderDuration = _getReminderDurationFromString(reminderStr);
      debugPrint(
        '[ensureRemaining] reminder=$reminderStr -> duration=${reminderDuration.inMinutes}m',
      );

      DateTime startDT;
      DateTime checkInDT;
      if (shift == 'morning' || shift == 'maintenance') {
        startDT = _parseTime(day, morningStart);
        checkInDT = _parseTime(day, morningCheckIn);
      } else if (shift == 'afternoon') {
        startDT = _parseTime(day, afternoonStart);
        checkInDT = _parseTime(day, afternoonCheckIn);
      } else {
        startDT = _parseTime(day, nightStart);
        checkInDT = _parseTime(day, nightCheckIn);
      }

      final shiftDuration = _getShiftDurationFromSystem(workSystem);
      final endDT = startDT.add(shiftDuration);

      final reminderTime = startDT.subtract(reminderDuration);
      final Map<int, DateTime> times = {
        0: startDT.subtract(const Duration(hours: 12)),
        1: reminderTime,
        2: checkInDT,
        3: endDT,
      };

      debugPrint(
        '[ensureRemaining] shift=$shift start=$startDT reminderAt=$reminderTime checkIn=$checkInDT end=$endDT',
      );

      final dayUtc = DateTime.utc(day.year, day.month, day.day);
      final now = DateTime.now();

      for (final entry in times.entries) {
        final offset = entry.key;
        final scheduledLocal = entry.value;
        if (!scheduledLocal.isAfter(now)) {
          debugPrint(
            '[ensureRemaining] offset=$offset scheduledLocal=$scheduledLocal <= now -> skipping',
          );
          continue;
        }

        final id = _notificationIdFor(dayUtc, offset);

        try {
          await flutterLocalNotificationsPlugin.cancel(id);
        } catch (e) {
          debugPrint('[ensureRemaining] cancel(id=$id) failed -> $e');
        }

        try {
          // pass UTC to scheduleNotification
          final scheduledUtc = scheduledLocal.toUtc();
          final payload = '${dayUtc.toIso8601String()}|$offset|$shift';
          await scheduleNotification(
            id: id,
            title: _titleForOffset(offset, shift),
            body: _bodyForOffset(offset, shift),
            scheduledDateTimeUtc: scheduledUtc,
            payload: payload,
            channelId: 'work_channel',
          );
          debugPrint(
            '[ensureRemaining] scheduled offset=$offset id=$id at $scheduledLocal (utc=${scheduledUtc.toIso8601String()})',
          );
        } catch (e, st) {
          debugPrint(
            '[ensureRemaining] scheduleNotification offset=$offset failed -> $e\n$st',
          );
        }
      }

      debugPrint('[ensureRemaining] finished for $day shift=$shift');
    } catch (e, st) {
      debugPrint('[ensureRemaining] outer error -> $e\n$st');
    }
  }

  // ---------------- scheduleNextNDays ----------------
  Future<void> scheduleNextNDays([int nDays = _kDefaultScheduleDays]) async {
    const int MAX_DAYS = 60;
    if (nDays <= 0) return;
    int days = nDays > MAX_DAYS ? MAX_DAYS : nDays;

    final prefs = await SharedPreferences.getInstance();
    final startDateStr = prefs.getString(_kStartDate);
    if (startDateStr == null) {
      debugPrint(
        '[scheduleNextNDays] no startDate in prefs -> aborting scheduleNextNDays',
      );
      return;
    }
    var startDate = DateTime.tryParse(startDateStr);
    if (startDate == null) {
      debugPrint('[scheduleNextNDays] invalid startDate in prefs -> aborting');
      return;
    }
    startDate = DateTime(startDate.year, startDate.month, startDate.day);

    final workSystem = prefs.getString(_kWorkSystem) ?? 'صباحي';
    final maintenanceInterval = prefs.getInt(_kMaintenanceInterval) ?? 0;

    final scheduleMap = _generateWorkScheduleSegment(
      workSystem,
      startDate,
      maintenanceInterval,
      days: days + 365,
    );

    List<Vacation> vacations = [];
    try {
      vacations = await VacationManager.getAllVacationsSorted();
    } catch (e) {
      vacations = [];
      debugPrint(
        '[scheduleNextNDays] VacationManager.getAllVacationsSorted failed -> $e',
      );
    }

    try {
      if (!kIsWeb && Platform.isIOS) {
        final pending = await flutterLocalNotificationsPlugin
            .pendingNotificationRequests();
        final pendingCount = pending.length;
        final maxIOS = 60;
        final approxPerDay = 4;
        final allowedNew = (maxIOS - pendingCount) ~/ approxPerDay;
        if (allowedNew <= 0) return;
        if (allowedNew < days) days = allowedNew;
      }
    } catch (e) {
      debugPrint('[scheduleNextNDays] iOS pending check failed -> $e');
    }

    DateTime current = DateTime.now();
    current = DateTime(current.year, current.month, current.day);
    int scheduled = 0;
    int lookAhead = 0;
    final int safetyLimit = days + 365;

    while (scheduled < days && lookAhead < safetyLimit) {
      final day = current.add(Duration(days: lookAhead));
      final keyUtc = DateTime.utc(day.year, day.month, day.day);
      final shift = scheduleMap[keyUtc];

      bool isVacation = false;
      for (final vac in vacations) {
        final s = DateTime(
          vac.startDate.year,
          vac.startDate.month,
          vac.startDate.day,
        );
        final e = DateTime(
          vac.endDate.year,
          vac.endDate.month,
          vac.endDate.day,
        );
        if (!day.isBefore(s) && !day.isAfter(e)) {
          isVacation = true;
          break;
        }
      }
      if (isVacation) {
        lookAhead++;
        continue;
      }

      if (shift != null && shift != 'off') {
        try {
          await cancelNotificationsForDay(day);
          await scheduleNotificationsForDayLocal(localDay: day);
          scheduled++;
        } catch (e, st) {
          debugPrint('[scheduleNextNDays] error scheduling $day -> $e\n$st');
        }
      }
      lookAhead++;
    }

    final scheduledUntil = DateTime.now().add(Duration(days: lookAhead));
    try {
      // store scheduledUntil as UTC string (stable for backups)
      await prefs.setString(
        _kScheduledUntilKey,
        scheduledUntil.toUtc().toIso8601String(),
      );
      debugPrint(
        '[scheduleNextNDays] saved scheduledUntil -> ${scheduledUntil.toUtc().toIso8601String()}',
      );

      // If monthly auto-renew is enabled, schedule renewal alarm (Android) to call renewal entrypoint
      final autoRenew = prefs.getBool(_kAutoMonthlyRenew) ?? true;
      if (autoRenew) {
        await _scheduleRenewalAlarm(scheduledUntil);
      } else {
        debugPrint(
          '[scheduleNextNDays] auto monthly renew disabled -> not scheduling renewal alarm',
        );
      }
    } catch (e) {
      debugPrint('[scheduleNextNDays] saving scheduledUntil failed -> $e');
    }
    debugPrint(
      '[scheduleNextNDays] done scheduled_count=$scheduled scheduled_until=$scheduledUntil lookAhead=$lookAhead',
    );
  }

  Future<DateTime?> getScheduledUntil() async {
    final prefs = await SharedPreferences.getInstance();
    final s = prefs.getString(_kScheduledUntilKey);
    if (s == null) return null;
    final dt = DateTime.tryParse(s);
    if (dt == null) return null;
    // return as UTC DateTime (consistent with storage)
    return dt.toUtc();
  }

  // ---------------- cancellations ----------------
  Future<void> cancelNotificationsForDay(DateTime localDay) async {
    final dayUtc = DateTime.utc(localDay.year, localDay.month, localDay.day);
    for (int offset = 0; offset < 4; offset++) {
      try {
        final id = _notificationIdFor(dayUtc, offset);
        await flutterLocalNotificationsPlugin.cancel(id);
      } catch (e) {
        debugPrint(
          '[cancelNotificationsForDay] cancel offset=$offset failed -> $e',
        );
      }
    }
  }

  Future<void> cancelNotificationsForRange(
    DateTime startLocal,
    DateTime endLocal,
  ) async {
    var cur = DateTime(startLocal.year, startLocal.month, startLocal.day);
    final end = DateTime(endLocal.year, endLocal.month, endLocal.day);
    while (!cur.isAfter(end)) {
      await cancelNotificationsForDay(cur);
      cur = cur.add(const Duration(days: 1));
    }
  }

  Future<void> cancelAll() async {
    try {
      await flutterLocalNotificationsPlugin.cancelAll();
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_kScheduledUntilKey);
      await _cancelRenewalAlarm();
      debugPrint(
        '[cancelAll] all scheduled notifications canceled and scheduledUntil removed',
      );
    } catch (e, st) {
      debugPrint('[cancelAll] error -> $e\n$st');
    }
  }

  // ---------------- Renewal alarm helpers ----------------
  Future<void> _cancelRenewalAlarm() async {
    try {
      await AndroidAlarmManager.cancel(_kRenewalAlarmId);
      debugPrint(
        '[NotificationsService] canceled renewal alarm id=$_kRenewalAlarmId',
      );
    } catch (e, st) {
      debugPrint(
        '[NotificationsService] cancel renewal alarm failed -> $e\n$st',
      );
    }
  }

  Future<void> _scheduleRenewalAlarm(DateTime scheduledUntil) async {
    try {
      if (kIsWeb) {
        debugPrint(
          '[NotificationsService] _scheduleRenewalAlarm: skipping on web',
        );
        return;
      }
      if (!Platform.isAndroid) {
        debugPrint(
          '[NotificationsService] _scheduleRenewalAlarm: not Android -> skipping',
        );
        return;
      }

      final now = DateTime.now();
      final renewAt = scheduledUntil.subtract(
        Duration(days: _kRenewalBeforeDays),
      );
      if (!renewAt.isAfter(now)) {
        debugPrint(
          '[NotificationsService] renewAt <= now -> skipping scheduling renewal alarm (renewAt=$renewAt now=$now)',
        );
        return;
      }

      await _cancelRenewalAlarm();

      await AndroidAlarmManager.oneShotAt(
        renewAt,
        _kRenewalAlarmId,
        _renewalAlarmEntryPoint,
        exact: true,
        wakeup: true,
        rescheduleOnReboot: true,
      );

      debugPrint(
        '[NotificationsService] scheduled renewal alarm at $renewAt id=$_kRenewalAlarmId',
      );
    } catch (e, st) {
      debugPrint(
        '[NotificationsService] scheduleRenewalAlarm error -> $e\n$st',
      );
    }
  }

  // ---------------- small helpers ----------------
  // Parses both English AM/PM and Arabic formats like "07:00 صباحاً" or "15:30"
  DateTime _parseTime(DateTime day, String timeText) {
    final text = timeText.trim();
    // attempt 24-hour hh:mm first
    final hmOnlyMatch = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(text);
    if (hmOnlyMatch != null) {
      int hour = int.parse(hmOnlyMatch.group(1)!);
      int minute = int.parse(hmOnlyMatch.group(2)!);
      return DateTime(day.year, day.month, day.day, hour, minute);
    }

    // common formats: "07:30 AM", "7:00 PM"
    final enMatch = RegExp(
      r'^(\d{1,2}):(\d{2})\s*([AaPp][Mm])$',
    ).firstMatch(text);
    if (enMatch != null) {
      int hour = int.parse(enMatch.group(1)!);
      int minute = int.parse(enMatch.group(2)!);
      final period = enMatch.group(3)!.toUpperCase();
      if (period == 'PM' && hour < 12) hour += 12;
      if (period == 'AM' && hour == 12) hour = 0;
      return DateTime(day.year, day.month, day.day, hour, minute);
    }

    // Arabic formats: "07:00 صباحاً", "15:30 مساءً", "07:30 صباح"
    final parts = text.split(' ');
    if (parts.isNotEmpty) {
      final hm = parts[0].split(':');
      if (hm.length >= 2) {
        int hour = int.tryParse(hm[0]) ?? 0;
        int minute = int.tryParse(hm[1]) ?? 0;
        final period = parts.length > 1 ? parts[1] : '';
        final p = period.replaceAll(
          RegExp(r'[^^\u0621-\u064A\u0600-\u06FF\w]'),
          '',
        ); // crude cleanup
        if (p.contains('مساء') || p.contains('م')) {
          if (hour < 12) hour += 12;
        } else if (p.contains('صباح') || p.contains('ص')) {
          if (hour == 12) hour = 0;
        } else {
          // if part contains AM/PM english words (fallback)
          final up = period.toUpperCase();
          if (up.contains('PM') && hour < 12) hour += 12;
          if (up.contains('AM') && hour == 12) hour = 0;
        }
        return DateTime(day.year, day.month, day.day, hour, minute);
      }
    }

    // fallback: return day at midnight
    return DateTime(day.year, day.month, day.day);
  }

  Duration _getReminderDurationFromString(String reminder) {
    final r = reminder.toLowerCase().trim();
    if (r.contains('نصف') || r.contains('نص'))
      return const Duration(minutes: 30);
    if (r.contains('ساعة ونصف') || r.contains('1.5') || r.contains('90'))
      return const Duration(minutes: 90);
    if (r.contains('ساعة') && r.contains('ين') == false && r.contains('ون'))
      return const Duration(hours: 1);
    if (r.contains('ساعتين') || r.contains('2h') || r.contains('2 hours'))
      return const Duration(hours: 2);
    // english fallbacks
    switch (r) {
      case '1 hour':
      case 'hour':
      case '1h':
        return const Duration(hours: 1);
      case '1.5 hours':
      case '90 minutes':
      case '1h30':
        return const Duration(minutes: 90);
      case '2 hours':
      case '2h':
        return const Duration(hours: 2);
      default:
        return const Duration(minutes: 30);
    }
  }

  Duration _getShiftDurationFromSystem(String system) {
    final s = system.toLowerCase();
    if (s.contains('12/24') || s.contains('12/48') || s.contains('12'))
      return const Duration(hours: 12);
    if ((s.contains('يوم عمل') && s.contains('يومين')) ||
        s.contains('1 day') ||
        s.contains('1 day work'))
      return const Duration(hours: 24);
    if (s.contains('يومين') &&
        (s.contains('٤') ||
            s.contains('4') ||
            s.contains('4 days') ||
            s.contains('٤ أيام')))
      return const Duration(hours: 48);
    // fallback long cycles: treat as 48 if mentions '2 days' explicitly
    if (s.contains('2 days') || s.contains('2 يوم'))
      return const Duration(hours: 48);
    return const Duration(hours: 8);
  }

  Map<DateTime, String> _generateWorkScheduleSegment(
    String system,
    DateTime startDate,
    int maintenanceInterval, {
    int days = 365,
  }) {
    final schedule = <DateTime, String>{};
    int shiftCounter = 0;
    String lastShift = "off";
    bool isFirstShift = true;

    final s = system.toLowerCase();

    for (int i = 0; i < days; i++) {
      final dayLocal = startDate.add(Duration(days: i));
      String shift = "off";

      // Arabic / English detection for patterns
      if (s.contains('12/24') ||
          s.contains('12/48') ||
          s.contains('12/24-12/48')) {
        final cycle = i % 4;
        if (cycle == 0) shift = "morning";
        if (cycle == 1) shift = "night";
      } else if ((s.contains('يوم عمل') && s.contains('يومين')) ||
          s.contains('1 day work') ||
          s.contains('1 day - 2 days off')) {
        shift = (i % 3 == 0) ? "morning" : "off";
      } else if (s.contains('يومين عمل') ||
          s.contains('2 days work') ||
          s.contains('2 days work 4 days off') ||
          s.contains('4 أيام') ||
          s.contains('٤ أيام')) {
        final cycle = i % 6;
        if (cycle == 0 || cycle == 1) shift = "morning";
      } else if (s.contains('3 أيام') ||
          s.contains('3 days') ||
          s.contains('3 أيام عمل') ||
          s.contains('3 day')) {
        final cycle = i % 5;
        if (cycle == 0) shift = "morning";
        if (cycle == 1) shift = "afternoon";
        if (cycle == 2) shift = "night";
      } else if (s.contains('6 أيام') || s.contains('6 days')) {
        final cycle = i % 8;
        if (cycle == 0 || cycle == 1) shift = "morning";
        if (cycle == 2 || cycle == 3) shift = "afternoon";
        if (cycle == 4 || cycle == 5) shift = "night";
      } else if (s.contains('صباح')) {
        final weekday = dayLocal.weekday;
        shift = (weekday >= 1 && weekday <= 5) ? "morning" : "off";
      } else {
        final weekday = dayLocal.weekday;
        shift = (weekday >= 1 && weekday <= 5) ? "morning" : "off";
      }

      if (shift != "off" && lastShift == "off") {
        shiftCounter++;
        if (isFirstShift && maintenanceInterval > 0) {
          shift = "maintenance";
          isFirstShift = false;
        } else {
          if (maintenanceInterval > 0 &&
              shiftCounter > 1 &&
              (shiftCounter - 1) % maintenanceInterval == 0) {
            shift = "maintenance";
          }
        }
      } else if (shift != "off" && lastShift != "off") {
        if (lastShift == "maintenance") shift = "maintenance";
      }

      final keyUtc = DateTime.utc(dayLocal.year, dayLocal.month, dayLocal.day);
      schedule[keyUtc] = shift;
      lastShift = shift;
    }
    return schedule;
  }

  // ---------------- handle notification taps ----------------
  void _handleNotificationResponse(NotificationResponse response) {
    final payload = response.payload;
    debugPrint('[handleNotificationResponse] payload=$payload');
    if (payload == null) return;

    if (payload == 'purchase_reminder') {
      if (!PurchaseManager.instance.isActive()) {
        try {
          PurchaseManager.instance.buyYearly();
          debugPrint('[handleNotificationResponse] purchase flow started');
        } catch (e) {
          debugPrint('[handleNotificationResponse] buyYearly failed -> $e');
        }
      } else {
        final rem = PurchaseManager.instance.remainingDuration();
        final daysLeft = rem == null ? null : (rem.inDays + 1);
        final body = daysLeft != null
            ? 'اشتراكك فعال — باقي $daysLeft يوم.'
            : 'اشتراكك مفعل.';
        showImmediateNotification(
          id: DateTime.now().millisecondsSinceEpoch.remainder(100000),
          title: 'حالة الاشتراك',
          body: body,
        );
      }
      return;
    }

    try {
      final parts = payload.split('|');
      if (parts.length >= 3) {
        final dayIso = parts[0];
        final offset = parts[1];
        final shift = parts.sublist(2).join('|');
        debugPrint(
          '[handleNotificationResponse] parsed -> day=$dayIso offset=$offset shift=$shift',
        );

        if (offset == '2') {
          try {
            final day = DateTime.parse(dayIso);
            debugPrint(
              '[handleNotificationResponse] checkin tap -> ensuring remaining notifications for $day shift=$shift',
            );
            _ensureRemainingNotificationsForDay(day, shift).catchError((e, st) {
              debugPrint(
                '[handleNotificationResponse] _ensureRemainingNotificationsForDay error -> $e\n$st',
              );
            });
          } catch (e, st) {
            debugPrint(
              '[handleNotificationResponse] parse dayIso failed -> $e\n$st',
            );
          }
        }
      }
    } catch (e, st) {
      debugPrint('[handleNotificationResponse] parse error -> $e\n$st');
    }
  }

  // ---------------- first-run helpers ----------------
  Future<void> sendFirstRunConfirmationIfNeeded() async {
    final prefs = await SharedPreferences.getInstance();
    final alreadySent = prefs.getBool(_kConfirmationShownKey) ?? false;
    if (alreadySent) return;
    await showImmediateNotification(
      id: 999999,
      title: 'تم تفعيل الإشعارات ✅',
      body: 'راح توصلك التذكيرات من التطبيق.',
      payload: 'confirmation|notifications_enabled',
    );
    await prefs.setBool(_kConfirmationShownKey, true);
  }

  Future<void> sendWelcomeNotificationOnce() async {
    final prefs = await SharedPreferences.getInstance();
    final alreadyShown = prefs.getBool(_kWelcomeShownKey) ?? false;
    if (alreadyShown) return;
    await Future.delayed(const Duration(seconds: 6));
    await showImmediateNotification(
      id: 1000000,
      title: 'أهلاً وسهلاً في التطبيق!',
      body: 'شكراً لتنصيب التطبيق — بنذكّرك بمواعيد وردياتك.',
      payload: 'welcome|first_run',
    );
    await prefs.setBool(_kWelcomeShownKey, true);
  }

  // ---------------- lifecycle helpers ----------------
  Future<void> onAppResumed() async {
    debugPrint(
      '[onAppResumed] app resumed — verifying timezone and scheduling notifications',
    );
    try {
      final tzName = (await FlutterTimezone.getLocalTimezone()).toString();
      if (_lastKnownTimeZone == null || _lastKnownTimeZone != tzName) {
        debugPrint(
          '[onAppResumed] timezone changed (last=$_lastKnownTimeZone new=$tzName) -> re-init timezone',
        );
        await _initTimezone();
      }
    } catch (_) {
      debugPrint(
        '[onAppResumed] getLocalTimezone failed -> re-init timezone fallback',
      );
      await _initTimezone();
    }
    await scheduleNextNDays(_kDefaultScheduleDays);
  }

  Future<void> rescheduleIfNeeded({bool force = false}) async {
    if (force) {
      await rescheduleAllNotifications(
        days: _kDefaultScheduleDays,
        forceClear: true,
      );
    } else {
      await onAppResumed();
    }
  }

  static Future<void> rescheduleAllNotifications({
    int days = _kDefaultScheduleDays,
    bool forceClear = false,
  }) async {
    debugPrint(
      '[NotificationsService] rescheduleAllNotifications days=$days forceClear=$forceClear',
    );
    try {
      if (forceClear) {
        await NotificationsService.instance.cancelAll();
      }
      await NotificationsService.instance.init();
      await NotificationsService.instance.scheduleNextNDays(days);
      debugPrint('[NotificationsService] scheduleNextNDays returned');
    } catch (e, st) {
      debugPrint('[NotificationsService] reschedule error -> $e\n$st');
    }
  }

  Future<void> rescheduleFromBoot() async {
    debugPrint(
      '[rescheduleFromBoot] called (boot or reboot) -> initializing then scheduling $_kDefaultScheduleDays days ahead',
    );
    await init();
    await scheduleNextNDays(_kDefaultScheduleDays);
  }

  Future<void> debugListPending() async {
    try {
      final pending = await flutterLocalNotificationsPlugin
          .pendingNotificationRequests();
      debugPrint('[debugListPending] pending.count=${pending.length}');
      for (final p in pending)
        debugPrint(
          '[PENDING] -> id=${p.id} title=${p.title} body=${p.body} payload=${p.payload}',
        );
    } catch (e) {
      debugPrint('[debugListPending] error -> $e');
    }
  }

  // ---------------- schedule from settings (manual config) ----------------
  Future<void> scheduleFromSettings({
    required String workSystem,
    required DateTime startDate,
    required int maintenanceInterval,
    required String morningStart,
    required String morningCheckIn,
    required String afternoonStart,
    required String afternoonCheckIn,
    required String nightStart,
    required String nightCheckIn,
    required String reminder,
    int days = _kDefaultScheduleDays,
  }) async {
    debugPrint(
      '[scheduleFromSettings] scheduling notifications using provided settings (days=$days)',
    );
    await init();
    await requestPermissions();
    await requestExactAlarmPermissionIfNeeded();
    await requestIgnoreBatteryOptimizationsIfNeeded();

    // schedule using provided config (does NOT overwrite prefs -- caller should save prefs)
    final scheduleMap = _generateWorkScheduleSegment(
      workSystem,
      startDate,
      maintenanceInterval,
      days: days + 365,
    );

    DateTime current = DateTime.now();
    current = DateTime(current.year, current.month, current.day);
    int scheduled = 0;
    int lookAhead = 0;
    final int safetyLimit = days + 365;

    while (scheduled < days && lookAhead < safetyLimit) {
      final day = current.add(Duration(days: lookAhead));
      final keyUtc = DateTime.utc(day.year, day.month, day.day);
      final shift = scheduleMap[keyUtc];

      if (shift != null && shift != 'off') {
        try {
          await cancelNotificationsForDay(day);
          await _scheduleNotificationsForDayWithConfig(
            localDay: day,
            startDate: startDate,
            workSystem: workSystem,
            morningStart: morningStart,
            morningCheckIn: morningCheckIn,
            afternoonStart: afternoonStart,
            afternoonCheckIn: afternoonCheckIn,
            nightStart: nightStart,
            nightCheckIn: nightCheckIn,
            reminder: reminder,
            maintenanceInterval: maintenanceInterval,
          );
          scheduled++;
        } catch (e, st) {
          debugPrint('[scheduleFromSettings] error scheduling $day -> $e\n$st');
        }
      }

      lookAhead++;
    }
    debugPrint(
      '[scheduleFromSettings] done scheduled=$scheduled lookAhead=$lookAhead',
    );

    // After scheduling, update scheduledUntil in prefs and renewal alarm if auto-renew enabled
    final scheduledUntil = DateTime.now().add(Duration(days: lookAhead));
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _kScheduledUntilKey,
        scheduledUntil.toUtc().toIso8601String(),
      );
      final autoRenew = prefs.getBool(_kAutoMonthlyRenew) ?? true;
      if (autoRenew) await _scheduleRenewalAlarm(scheduledUntil);
    } catch (e) {
      debugPrint('[scheduleFromSettings] failed to save scheduledUntil -> $e');
    }
  }

  Future<void> _scheduleNotificationsForDayWithConfig({
    required DateTime localDay,
    required DateTime startDate,
    required String workSystem,
    required String morningStart,
    required String morningCheckIn,
    required String afternoonStart,
    required String afternoonCheckIn,
    required String nightStart,
    required String nightCheckIn,
    required String reminder,
    required int maintenanceInterval,
  }) async {
    final day = DateTime(localDay.year, localDay.month, localDay.day);
    final reminderDuration = _getReminderDurationFromString(reminder);
    final schedule = _generateWorkScheduleSegment(
      workSystem,
      startDate,
      maintenanceInterval,
      days: 400,
    );

    final keyUtc = DateTime.utc(day.year, day.month, day.day);
    final shift = schedule[keyUtc] ?? 'off';
    if (shift == 'off') return;

    DateTime startDT;
    DateTime checkInDT;
    if (shift == 'morning' || shift == 'maintenance') {
      startDT = _parseTime(day, morningStart);
      checkInDT = _parseTime(day, morningCheckIn);
    } else if (shift == 'afternoon') {
      startDT = _parseTime(day, afternoonStart);
      checkInDT = _parseTime(day, afternoonCheckIn);
    } else {
      startDT = _parseTime(day, nightStart);
      checkInDT = _parseTime(day, nightCheckIn);
    }

    final shiftDuration = _getShiftDurationFromSystem(workSystem);
    final endDT = startDT.add(shiftDuration);

    final Map<int, DateTime> times = {
      0: startDT.subtract(const Duration(hours: 12)),
      1: startDT.subtract(reminderDuration),
      2: checkInDT,
      3: endDT,
    };

    final dayUtc = DateTime.utc(day.year, day.month, day.day);

    for (final entry in times.entries) {
      final offset = entry.key;
      final scheduledLocal = entry.value;
      final id = _notificationIdFor(dayUtc, offset);
      try {
        final tzDt = tz.TZDateTime.from(scheduledLocal, tz.local);
        if (tzDt.isBefore(tz.TZDateTime.now(tz.local))) {
          debugPrint(
            '[scheduleWithConfig] skipping offset=$offset because time is in the past -> $tzDt',
          );
          continue;
        }
        final payload = '${dayUtc.toIso8601String()}|$offset|$shift';
        final scheduledUtc = scheduledLocal.toUtc();
        await scheduleNotification(
          id: id,
          title: _titleForOffset(offset, shift),
          body: _bodyForOffset(offset, shift),
          scheduledDateTimeUtc: scheduledUtc,
          payload: payload,
          channelId: 'work_channel',
        );
      } catch (e, st) {
        debugPrint(
          '[scheduleWithConfig] error scheduling offset=$offset -> $e\n$st',
        );
      }
    }
  }

  Future<void> scheduleConfirmationAfterSeconds(
    int seconds,
    String message,
  ) async {
    final now = DateTime.now();
    final scheduledTime = now.add(Duration(seconds: seconds));
    final id = now.millisecondsSinceEpoch.remainder(100000) + 200000;
    await scheduleNotification(
      id: id,
      title: 'تأكيد الإعدادات',
      body: message,
      scheduledDateTimeUtc: scheduledTime.toUtc(),
      payload: 'confirmation|$id',
      channelId: 'first_run_channel',
    );
  }

  Future<void> scheduleDailySubscriptionReminderAt9() async {
    try {
      await init();
      final prefs = await SharedPreferences.getInstance();
      final cancelled = prefs.getBool(_kSubscriptionReminderCancelled) ?? false;
      if (cancelled) {
        debugPrint(
          '[scheduleDailySubscriptionReminderAt9] user previously cancelled -> skipping',
        );
        return;
      }

      if (PurchaseManager.instance.isActive()) {
        await cancelDailySubscriptionReminder(markCancelled: true);
        debugPrint(
          '[scheduleDailySubscriptionReminderAt9] subscription active -> canceled reminder',
        );
        return;
      }

      final daysLeft = PurchaseManager.instance.remainingDuration()?.inDays;
      String body;
      if (daysLeft != null && daysLeft > 0) {
        body =
            'اشتراك بريميوم — باقي $daysLeft يوم. فعّل الاشتراك عشان تواصل على المزايا.';
      } else {
        body =
            'جرّب 7 أيام مجاناً، بعدين اشترك سنويًا بـ \$19.99 — فعّل المزايا الحين.';
      }

      await scheduleDailyAtTime(
        id: _kSubscriptionReminderId,
        title: 'اشترك بالنسخة المميزة',
        body: body,
        hour: 9,
        minute: 0,
        channelId: 'purchase_channel',
      );
      await prefs.setBool(_kSubscriptionReminderScheduled, true);
      debugPrint('[Notifications] scheduled purchase reminder at local 09:00');
    } catch (e, st) {
      debugPrint(
        '[Notifications] scheduleDailySubscriptionReminderAt9 error -> $e\n$st',
      );
    }
  }

  Future<void> cancelDailySubscriptionReminder({
    bool markCancelled = true,
  }) async {
    try {
      await flutterLocalNotificationsPlugin.cancel(_kSubscriptionReminderId);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kSubscriptionReminderScheduled, false);
      if (markCancelled)
        await prefs.setBool(_kSubscriptionReminderCancelled, true);
      debugPrint(
        '[Notifications] canceled purchase reminder id=$_kSubscriptionReminderId',
      );
    } catch (e, st) {
      debugPrint(
        '[Notifications] cancelDailySubscriptionReminder error -> $e\n$st',
      );
    }
  }

  Future<void> ensureSubscriptionReminderState() async {
    try {
      if (PurchaseManager.instance.isActive()) {
        await cancelDailySubscriptionReminder(markCancelled: true);
      } else {
        await scheduleDailySubscriptionReminderAt9();
      }
    } catch (e, st) {
      debugPrint(
        '[Notifications] ensureSubscriptionReminderState error -> $e\n$st',
      );
    }
  }

  Future<void> scheduleSaveSuccessNotification({int seconds = 60}) async {
    final now = DateTime.now();
    final id = now.millisecondsSinceEpoch.remainder(100000) + 300000;
    if (seconds <= 0) {
      await showImmediateNotification(
        id: id,
        title: 'تم حفظ الإعدادات ✅',
        body: 'تم حفظ الإعدادات بنجاح. التذكيرات بتوصلك بالمواعيد المحددة.',
        payload: 'save_success|$id',
      );
    } else {
      final scheduledTime = now.add(Duration(seconds: seconds));
      await scheduleNotification(
        id: id,
        title: 'تم حفظ الإعدادات ✅',
        body: 'تم حفظ الإعدادات بنجاح. التذكيرات بتوصلك بالمواعيد المحددة.',
        scheduledDateTimeUtc: scheduledTime.toUtc(),
        payload: 'save_success|$id',
        channelId: 'first_run_channel',
      );
    }
  }

  Future<void> showSimpleNotification({
    required int id,
    required String title,
    required String body,
    String? payload,
  }) async {
    try {
      await init();
      final details = NotificationDetails(
        android: AndroidNotificationDetails(
          'purchase_channel',
          'تذكيرات الاشتراك',
          channelDescription: 'تذكيرات خاصة بالاشتراكات والمشتريات',
          importance: Importance.max,
          priority: Priority.high,
          playSound: true,
          showProgress: false,
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentSound: true,
        ),
      );

      await flutterLocalNotificationsPlugin.show(
        id,
        title,
        body,
        details,
        payload: payload,
      );
      debugPrint('[showSimpleNotification] shown id=$id title="$title"');
    } catch (e, st) {
      debugPrint('[showSimpleNotification] error -> $e\n$st');
    }
  }

  // ---------------- public API for monthly auto-renew toggle ----------------
  Future<void> setAutoMonthlyRenewEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kAutoMonthlyRenew, enabled);
    if (enabled) {
      // schedule renewal based on existing scheduledUntil or schedule next window
      final scheduledUntil = await getScheduledUntil();
      if (scheduledUntil != null) {
        await _scheduleRenewalAlarm(scheduledUntil);
      } else {
        await scheduleNextNDays(_kDefaultScheduleDays);
      }
    } else {
      await _cancelRenewalAlarm();
    }
  }

  Future<bool> isAutoMonthlyRenewEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kAutoMonthlyRenew) ?? true;
  }
}
