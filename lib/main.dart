// lib/main.dart
import 'dart:async';
import 'dart:io' show Platform;

import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import 'package:android_intent_plus/android_intent.dart';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:workmanager/workmanager.dart';

import 'package:package_info_plus/package_info_plus.dart';

import 'screens/settings_page.dart' show SettingsPage;
import 'screens/calendar_page.dart';
import 'screens/upgrade_prompt_page.dart';
import 'service/notifications_service.dart';
import 'service/background_service.dart' show backgroundTaskWrapper;
import 'service/purchase_Manager.dart';

// NOTE: removed unused global flutterLocalNotificationsPlugin declaration
// because NotificationsService holds its own instance and we don't use it here.

// Platform channel used by the app/native bits for exact alarms & other native helpers.
const MethodChannel _nativeChannel = MethodChannel('khamsat/native_notifications');

const String WM_TASK_RESCHEDULE = 'khamsat_reschedule_task';
const String WM_TASK_SHOW_TEST = 'khamsat_show_test_notification';

const String _kPrefsShowUpgradeOnLaunch = 'pm_show_upgrade_on_launch';

final GlobalKey<NavigatorState> gNavigatorKey = GlobalKey<NavigatorState>();

bool _upgradePromptShownThisSession = false;

@pragma('vm:entry-point')
void callbackDispatcher() {
  // Workmanager callback dispatcher runs in background isolate.
  Workmanager().executeTask((taskName, inputData) async {
    WidgetsFlutterBinding.ensureInitialized();
    debugPrint('[WM][callback] executeTask invoked. Task: $taskName, inputData: $inputData');
    debugPrint('[WM][callback] (EN) Background task started. Initializing wrapper and delegating to backgroundTaskWrapper.');

    try {
      final ok = await backgroundTaskWrapper(taskName ?? '', inputData as Map<String, dynamic>?);
      debugPrint('[WM][callback] (EN) backgroundTaskWrapper returned -> $ok');
      return ok;
    } catch (e, st) {
      debugPrint('[WM][callback] (EN) Error while executing background wrapper -> $e\n$st');
      return Future.value(false);
    }
  });
}

Future<void> main() async {
  // Early diagnostics
  debugPrint('[main] (EN) App starting. Entering main().');
  WidgetsFlutterBinding.ensureInitialized();
  debugPrint('[main] (EN) WidgetsFlutterBinding.ensureInitialized() done.');

  // Timezone initialization
  try {
    debugPrint('[main] (EN) Initializing timezone database (tz).');
    tz.initializeTimeZones();
    debugPrint('[main] (EN) Timezone DB initialized successfully.');
  } catch (e, st) {
    debugPrint('[main] (EN) tz.initializeTimeZones() failed -> $e\n$st');
  }

  // AndroidAlarmManager initialization (needed if we schedule native alarms)
  try {
    debugPrint('[main] (EN) Initializing AndroidAlarmManager (for native alarms).');
    await AndroidAlarmManager.initialize();
    debugPrint('[main] (EN) AndroidAlarmManager.initialize() completed.');
  } catch (e, st) {
    debugPrint('[main] (EN) AndroidAlarmManager.initialize() error -> $e\n$st');
  }

  // NotificationsService initialization (single call, verbose logs)
  try {
    debugPrint('[main] (EN) Initializing NotificationsService (flutter_local_notifications wrapper).');
    await NotificationsService.initialize();
    debugPrint('[main] (EN) NotificationsService.initialize() completed successfully.');
    debugPrint('[main] (EN) NotificationsService ready — plugin & timezone snapshot set.');
  } catch (e, st) {
    debugPrint('[main] (EN) NotificationsService.initialize() threw -> $e\n$st');
  }

  // PurchaseManager init (in-app purchase / trial management)
  try {
    debugPrint('[main] (EN) Initializing PurchaseManager and reading package info.');
    final pkg = await PackageInfo.fromPlatform();
    debugPrint('[main] (EN) PackageInfo obtained: packageName=${pkg.packageName} appName=${pkg.appName} version=${pkg.version}');
    await PurchaseManager.instance.init(deviceId: pkg.packageName);
    debugPrint('[main] (EN) PurchaseManager initialized with deviceId=${pkg.packageName}');
  } catch (e, st) {
    debugPrint('[main] (EN) PurchaseManager.init failed -> $e\n$st');
  }

  // Attach navigator key so NotificationsService can open UI on tap
  try {
    debugPrint('[main] (EN) Attaching navigator key to NotificationsService so notification taps can open screens.');
    NotificationsService.instance.setNavigatorKey(gNavigatorKey);
    debugPrint('[main] (EN) Navigator key set on NotificationsService.');
  } catch (e, st) {
    debugPrint('[main] (EN) setNavigatorKey failed -> $e\n$st');
  }

  // Decide app flow based on subscription/access state
  bool hasAccess = false;
  try {
    hasAccess = PurchaseManager.instance.hasAccess();
    debugPrint('[main] (EN) PurchaseManager.instance.hasAccess() -> $hasAccess');
  } catch (e, st) {
    debugPrint('[main] (EN) hasAccess check failed -> $e\n$st');
    hasAccess = false;
  }

  // If no access: cancel background jobs & notifications, show upgrade screen only
  if (!hasAccess) {
    debugPrint('[main] (EN) No access detected. Cancelling Workmanager tasks and notifications, then showing UpgradePromptPage.');
    try {
      await Workmanager().cancelAll();
      debugPrint('[main] (EN) Workmanager.cancelAll() succeeded.');
    } catch (e) {
      debugPrint('[main] (EN) Workmanager.cancelAll() error -> $e');
    }

    try {
      await NotificationsService.instance.cancelAll();
      debugPrint('[main] (EN) NotificationsService.cancelAll() succeeded.');
    } catch (e) {
      debugPrint('[main] (EN) NotificationsService.cancelAll() error -> $e');
    }

    debugPrint('[main] (EN) Running app with UpgradePromptPage as the only screen.');
    runApp(MaterialApp(
      navigatorKey: gNavigatorKey,
      debugShowCheckedModeBanner: false,
      home: const UpgradePromptPage(),
    ));
    return;
  }

  // If access is available: register periodic rescheduler and run full app
  try {
    debugPrint('[main] (EN) Initializing Workmanager for periodic background reschedule tasks.');
    await Workmanager().initialize(callbackDispatcher, isInDebugMode: false);
    await Workmanager().registerPeriodicTask(
      "khamsat_periodic_rescheduler",
      WM_TASK_RESCHEDULE,
      frequency: const Duration(minutes: 15),
      initialDelay: const Duration(seconds: 15),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
      constraints: Constraints(
        networkType: NetworkType.notRequired,
        requiresBatteryNotLow: false,
        requiresCharging: false,
        requiresDeviceIdle: false,
        requiresStorageNotLow: false,
      ),
    );
    debugPrint('[main] (EN) Workmanager.initialize + registerPeriodicTask succeeded.');
  } catch (e, st) {
    debugPrint('[main] (EN) Workmanager init/register error -> $e\n$st');
  }

  debugPrint('[main] (EN) Starting Flutter app (runApp).');
  runApp(MyApp(navigatorKey: gNavigatorKey));

  // Post-frame actions: ensure permissions & reschedule notifications if settings exist
  WidgetsBinding.instance.addPostFrameCallback((_) async {
    debugPrint('[main.postFrame] (EN) Post-frame callback running: checking permissions and scheduling.');
    try {
      final ok = await _ensureAllRequiredPermissions(gNavigatorKey);
      debugPrint('[main.postFrame] (EN) _ensureAllRequiredPermissions returned -> $ok');

      // show upgrade (if trial/condition triggered)
      await _maybeShowUpgradeIfNeeded();

      try {
        final prefs = await SharedPreferences.getInstance();
        final hasSettings = prefs.containsKey('workSystem') && prefs.containsKey('startDate');
        debugPrint('[main.postFrame] (EN) SharedPreferences check -> hasSettings=$hasSettings');
        if (hasSettings) {
          debugPrint('[main.postFrame] (EN) Scheduling/rescheduling notifications (NotificationsService.rescheduleIfNeeded).');
          await NotificationsService.instance.rescheduleIfNeeded(force: false);
        } else {
          debugPrint('[main.postFrame] (EN) No saved scheduling settings found. User must configure settings first.');
        }
      } catch (e, st) {
        debugPrint('[main.postFrame] (EN) Reschedule on startup error -> $e\n$st');
      }
    } catch (e, st) {
      debugPrint('[main.postFrame] (EN) Top-level post-frame error -> $e\n$st');
    }
  });

  // Listen for access changes (user buys subscription etc.)
  try {
    debugPrint('[main] (EN) Subscribing to PurchaseManager.accessStream to react to changes in subscription state.');
    PurchaseManager.instance.accessStream.listen((access) async {
      debugPrint('[main] (EN) accessStream event -> $access');
      if (access) {
        debugPrint('[main] (EN) Access granted: rescheduling notifications and ensuring Workmanager registration.');
        try {
          await NotificationsService.instance.rescheduleIfNeeded(force: true);
          debugPrint('[main] (EN) rescheduleIfNeeded(force:true) done.');
        } catch (e) {
          debugPrint('[main] (EN) rescheduleIfNeeded error -> $e');
        }
        try {
          // re-register Workmanager periodic task if necessary
          await Workmanager().initialize(callbackDispatcher, isInDebugMode: false);
          await Workmanager().registerPeriodicTask(
            "khamsat_periodic_rescheduler",
            WM_TASK_RESCHEDULE,
            frequency: const Duration(minutes: 15),
            initialDelay: const Duration(seconds: 15),
            existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
            constraints: Constraints(
              networkType: NetworkType.notRequired,
              requiresBatteryNotLow: false,
              requiresCharging: false,
              requiresDeviceIdle: false,
              requiresStorageNotLow: false,
            ),
          );
          debugPrint('[main] (EN) Workmanager re-registered successfully after access granted.');
        } catch (e) {
          debugPrint('[main] (EN) Workmanager register on access error -> $e');
        }
      } else {
        debugPrint('[main] (EN) Access revoked: cancelling work and clearing notifications.');
        try {
          await Workmanager().cancelAll();
          debugPrint('[main] (EN) Workmanager.cancelAll() done after access revoke.');
        } catch (_) {}
        try {
          await NotificationsService.instance.cancelAll();
          debugPrint('[main] (EN) NotificationsService.cancelAll() done after access revoke.');
        } catch (_) {}
      }
    });
  } catch (e, st) {
    debugPrint('[main] (EN) Failed to subscribe to accessStream -> $e\n$st');
  }
}

// --------------------------- Permissions helpers ---------------------------
Future<bool> _ensureAllRequiredPermissions(GlobalKey<NavigatorState> navigatorKey) async {
  debugPrint('[ensurePerms] (EN) Checking all required permissions (notification + exact alarms).');
  if (kIsWeb) {
    debugPrint('[ensurePerms] (EN) Running on Web platform — skipping native permission checks.');
    return true;
  }

  final prefs = await SharedPreferences.getInstance();
  final blockingMode = prefs.getBool('required_perms_blocking') ?? true;
  debugPrint('[ensurePerms] (EN) blockingMode=$blockingMode');

  // iOS flow
  if (Platform.isIOS) {
    try {
      debugPrint('[ensurePerms] (EN) Requesting iOS notification permissions now.');
      final result = await Permission.notification.request();
      final granted = result.isGranted;
      debugPrint('[ensurePerms] (EN) iOS notification permission result -> $result granted=$granted');
      await prefs.setBool('last_required_perms_notifications', granted);
      await prefs.setBool('last_required_perms_exactalarm', true); // exact alarms not relevant on iOS
      if (!granted && blockingMode) {
        final ctx = navigatorKey.currentState?.overlay?.context;
        if (ctx != null) {
          debugPrint('[ensurePerms] (EN) Showing dialog to prompt user to open system settings for notifications.');
          await showDialog(
            context: ctx,
            builder: (c) => AlertDialog(
              title: const Text('السماح بالإشعارات'),
              content: const Text('يحتاج التطبيق إذن الإشعارات ليعمل بشكل صحيح.\nيرجى السماح من إعدادات النظام.'),
              actions: [
                TextButton(
                  onPressed: () async {
                    await openAppSettings();
                    Navigator.pop(c);
                  },
                  child: const Text('فتح الإعدادات'),
                ),
                TextButton(onPressed: () => Navigator.pop(c), child: const Text('حسنًا')),
              ],
            ),
          );
        }
      }
      return granted;
    } catch (e) {
      debugPrint('[ensurePerms] (EN) iOS permission request failed -> $e');
      return true; // be lenient on unexpected errors
    }
  }

  // Android & others path
  bool notificationsOk = false;
  bool exactAlarmOk = false;
  final ctx = navigatorKey.currentState?.overlay?.context;

  // Sub-function: handle notification permission (Android 13+ runtime)
  Future<void> _handleNotificationPermission() async {
    debugPrint('[ensurePerms] (EN) Checking notification permission status.');
    final status = await Permission.notification.status;
    debugPrint('[ensurePerms] (EN) Current Permission.notification.status -> $status');

    if (status.isGranted) {
      debugPrint('[ensurePerms] (EN) Notification permission already granted.');
      notificationsOk = true;
      return;
    }

    bool done = false;
    while (!done) {
      debugPrint('[ensurePerms] (EN) Requesting notification permission from user.');
      final requestResult = await Permission.notification.request();
      debugPrint('[ensurePerms] (EN) permission.request result -> $requestResult');

      if (requestResult.isGranted) {
        notificationsOk = true;
        debugPrint('[ensurePerms] (EN) User granted notification permission.');
        done = true;
        break;
      }

      if (ctx == null) {
        debugPrint('[ensurePerms] (EN) No UI context available to show dialog — cannot prompt user further.');
        notificationsOk = false;
        done = true;
        break;
      }

      debugPrint('[ensurePerms] (EN) Showing explanation dialog to user about notification permission.');
      final choice = await showDialog<String>(
        context: ctx,
        barrierDismissible: !blockingMode,
        builder: (c) {
          return AlertDialog(
            title: const Text('السماح بالإشعارات'),
            content: const Text(
              'يحتاج التطبيق إذن الإشعارات لعرض التنبيهات في مواعيدها. '
                  'يرجى السماح عند المطالبة أو فتح إعدادات التطبيق لتشغيل الإشعارات.',
            ),
            actions: [
              TextButton(onPressed: () => Navigator.of(c).pop('request'), child: const Text('اطلب الآن')),
              TextButton(onPressed: () => Navigator.of(c).pop('settings'), child: const Text('افتح إعدادات التطبيق')),
              if (!blockingMode) TextButton(onPressed: () => Navigator.of(c).pop('skip'), child: const Text('تجاهل مؤقتاً')),
            ],
          );
        },
      );

      debugPrint('[ensurePerms] (EN) Dialog choice -> $choice');

      if (choice == 'request') {
        debugPrint('[ensurePerms] (EN) User chose to request permission again.');
        continue;
      } else if (choice == 'settings') {
        debugPrint('[ensurePerms] (EN) Opening app settings for the user to grant permission manually.');
        await openAppSettings();
        continue;
      } else {
        debugPrint('[ensurePerms] (EN) User skipped or dismissed the dialog; notificationsOk=false for now.');
        notificationsOk = false;
        done = true;
      }
    }
  }

  // Sub-function: handle exact alarm permission (Android 12+)
  Future<void> _handleExactAlarmPermission() async {
    debugPrint('[ensurePerms] (EN) Checking exact alarms capability via native channel.');
    try {
      final canSchedule = await _nativeChannel.invokeMethod<bool>('canScheduleExactAlarms');
      debugPrint('[ensurePerms] (EN) native canScheduleExactAlarms -> $canSchedule');
      if (canSchedule == true) {
        exactAlarmOk = true;
        return;
      }
    } catch (e) {
      debugPrint('[ensurePerms] (EN) native canScheduleExactAlarms not implemented or error -> $e');
    }

    try {
      debugPrint('[ensurePerms] (EN) Invoking native requestScheduleExactAlarm to ask the platform for permission.');
      await _nativeChannel.invokeMethod('requestScheduleExactAlarm');
      exactAlarmOk = true;
      debugPrint('[ensurePerms] (EN) requestScheduleExactAlarm returned successfully (or no error thrown).');
    } catch (e) {
      debugPrint('[ensurePerms] (EN) requestScheduleExactAlarm native failed (silent) -> $e');
      exactAlarmOk = false;
    }
  }

  // Run both handlers
  await _handleNotificationPermission();

  if (!notificationsOk && blockingMode) {
    debugPrint('[ensurePerms] (EN) User did not grant notifications and blockingMode=true; aborting initialization.');
    await prefs.setBool('last_required_perms_notifications', notificationsOk);
    await prefs.setBool('last_required_perms_exactalarm', false);
    return false;
  }

  await _handleExactAlarmPermission();

  await prefs.setBool('last_required_perms_notifications', notificationsOk);
  await prefs.setBool('last_required_perms_exactalarm', exactAlarmOk);

  final allOk = notificationsOk && exactAlarmOk;
  debugPrint('[ensurePerms] (EN) Final permission state -> notifications:$notificationsOk exactAlarm:$exactAlarmOk allOk:$allOk');
  return allOk;
}

// --------------------------- Upgrade prompt helper ---------------------------
Future<void> _maybeShowUpgradeIfNeeded() async {
  debugPrint('[maybeShowUpgrade] (EN) Checking whether to show upgrade prompt (trial expired or flag).');
  try {
    try {
      debugPrint('[maybeShowUpgrade] (EN) Asking PurchaseManager to check trial and notify if expired.');
      await PurchaseManager.instance.checkTrialAndNotifyIfExpired();
      debugPrint('[maybeShowUpgrade] (EN) PurchaseManager.checkTrialAndNotifyIfExpired done.');
    } catch (e) {
      debugPrint('[maybeShowUpgrade] (EN) PurchaseManager.checkTrialAndNotifyIfExpired threw -> $e');
    }

    final prefs = await SharedPreferences.getInstance();
    final shouldShow = prefs.getBool(_kPrefsShowUpgradeOnLaunch) ?? false;
    debugPrint('[maybeShowUpgrade] (EN) shouldShow flag from prefs -> $shouldShow, sessionShown=$_upgradePromptShownThisSession');

    if (!shouldShow) {
      debugPrint('[maybeShowUpgrade] (EN) No need to show upgrade prompt now.');
      return;
    }
    if (_upgradePromptShownThisSession) {
      debugPrint('[maybeShowUpgrade] (EN) Upgrade prompt already shown this session -> skipping.');
      return;
    }

    await prefs.setBool(_kPrefsShowUpgradeOnLaunch, false);

    try {
      debugPrint('[maybeShowUpgrade] (EN) Cancelling daily subscription reminder before showing upgrade UI.');
      await NotificationsService.instance.cancelDailySubscriptionReminder(markCancelled: true);
      debugPrint('[maybeShowUpgrade] (EN) Daily subscription reminder cancelled.');
    } catch (e) {
      debugPrint('[maybeShowUpgrade] (EN) cancelDailySubscriptionReminder failed -> $e');
    }

    final nav = gNavigatorKey;
    final ctx = nav.currentState?.overlay?.context;
    if (ctx == null) {
      debugPrint('[maybeShowUpgrade] (EN) No navigator context available; cannot push UpgradePromptPage now.');
      return;
    }

    _upgradePromptShownThisSession = true;
    nav.currentState?.push(MaterialPageRoute(builder: (_) => const UpgradePromptPage()));
    debugPrint('[maybeShowUpgrade] (EN) UpgradePromptPage pushed to navigation stack.');
  } catch (e, st) {
    debugPrint('[maybeShowUpgrade] (EN) Unexpected error -> $e\n$st');
  }
}

// --------------------------- App UI & Launcher ---------------------------
class MyApp extends StatelessWidget {
  final GlobalKey<NavigatorState> navigatorKey;

  const MyApp({super.key, required this.navigatorKey});

  Future<bool> hasSettings() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.containsKey('workSystem') && prefs.containsKey('startDate');
  }

  @override
  Widget build(BuildContext context) {
    debugPrint('[MyApp] (EN) Building MaterialApp and loading initial screen based on settings.');
    return MaterialApp(
      navigatorKey: navigatorKey,
      debugShowCheckedModeBanner: false,
      title: 'Work Reminder App',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: FutureBuilder<bool>(
        future: hasSettings(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            debugPrint('[MyApp] (EN) Waiting for settings... showing spinner.');
            return const Scaffold(body: Center(child: CircularProgressIndicator()));
          }
          final ok = snapshot.data == true;
          debugPrint('[MyApp] (EN) hasSettings -> $ok. Routing accordingly.');
          return ok ? const CalendarLauncher() : const SettingsPage();
        },
      ),
    );
  }
}

class CalendarLauncher extends StatefulWidget {
  const CalendarLauncher({super.key});

  @override
  State<CalendarLauncher> createState() => _CalendarLauncherState();
}

class _CalendarLauncherState extends State<CalendarLauncher> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    debugPrint('[CalendarLauncher] (EN) Added WidgetsBinding observer in initState.');

    // safety net: try to show upgrade prompt after first frame inside this page
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      debugPrint('[CalendarLauncher] (EN) post-frame callback: maybeShowUpgradeIfNeeded.');
      await _maybeShowUpgradeIfNeeded();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    debugPrint('[CalendarLauncher] (EN) Removed WidgetsBinding observer in dispose.');
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    debugPrint('[CalendarLauncher] (EN) App lifecycle changed -> $state');
    if (state == AppLifecycleState.resumed) {
      debugPrint('[CalendarLauncher] (EN) App resumed -> calling NotificationsService.onAppResumed and PurchaseManager.refreshFromBackend.');
      NotificationsService.instance.onAppResumed();
      PurchaseManager.instance.refreshFromBackend();
      _maybeShowUpgradeIfNeeded();
    }
  }

  // generateWorkSchedule preserved from original logic
  Map<DateTime, String> generateWorkSchedule(String system, DateTime startDate, int maintenanceInterval) {
    final schedule = <DateTime, String>{};
    int shiftCounter = 0;
    String lastShift = "راحة";
    bool isFirstShift = true;
    for (int i = 0; i < 3650; i++) {
      final dayLocal = startDate.add(Duration(days: i));
      String shift = "راحة";

      if (system == 'نظام العمل 12/24-12/48') {
        final cycle = i % 4;
        if (cycle == 0) shift = "صبح";
        if (cycle == 1) shift = "ليل";
      } else if (system == 'نظام العمل يوم عمل - يومين راحة') {
        shift = (i % 3 == 0) ? "صبح" : "راحة";
      } else if (system == 'يومين عمل ٤ أيام راحة') {
        final cycle = i % 6;
        if (cycle == 0 || cycle == 1) shift = "صبح";
      } else if (system == '3 أيام عمل (صبح - عصر - ليل) يليها يومين راحة') {
        final cycle = i % 5;
        if (cycle == 0) shift = "صبح";
        if (cycle == 1) shift = "عصر";
        if (cycle == 2) shift = "ليل";
      } else if (system == '6 أيام عمل 2 يوم راحة') {
        final cycle = i % 8;
        if (cycle == 0 || cycle == 1) shift = "صبح";
        if (cycle == 2 || cycle == 3) shift = "عصر";
        if (cycle == 4 || cycle == 5) shift = "ليل";
      } else if (system == 'صباحي') {
        final weekday = dayLocal.weekday;
        shift = (weekday >= 1 && weekday <= 5) ? "صبح" : "راحة";
      }

      if (shift != "راحة" && lastShift == "راحة") {
        shiftCounter++;
        if (isFirstShift && maintenanceInterval > 0) {
          shift = "صيانة";
          isFirstShift = false;
        } else {
          if (maintenanceInterval > 0 && shiftCounter > 1 && (shiftCounter - 1) % maintenanceInterval == 0) {
            shift = "صيانة";
          }
        }
      } else if (shift != "راحة" && lastShift != "راحة") {
        if (lastShift == "صيانة") shift = "صيانة";
      }

      final keyUtc = DateTime.utc(dayLocal.year, dayLocal.month, dayLocal.day);
      schedule[keyUtc] = shift;
      lastShift = shift;
    }
    return schedule;
  }

  @override
  Widget build(BuildContext context) {
    debugPrint('[CalendarLauncher] (EN) Building calendar launcher page and loading schedule from prefs.');
    return FutureBuilder<SharedPreferences>(
      future: SharedPreferences.getInstance(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          debugPrint('[CalendarLauncher] (EN) Waiting for SharedPreferences...');
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        final prefs = snapshot.data!;
        final startDateStr = prefs.getString('startDate');
        final system = prefs.getString('workSystem') ?? '';
        final maintenanceInterval = prefs.getInt('maintenanceInterval') ?? 0;
        if (startDateStr == null || system.isEmpty) {
          debugPrint('[CalendarLauncher] (EN) Missing startDate or workSystem -> showing SettingsPage.');
          return const SettingsPage();
        }

        final parsed = DateTime.tryParse(startDateStr);
        if (parsed == null) {
          debugPrint('[CalendarLauncher] (EN) Invalid startDate stored -> showing SettingsPage.');
          return const SettingsPage();
        }
        final startDate = DateTime(parsed.year, parsed.month, parsed.day);
        final schedule = generateWorkSchedule(system, startDate, maintenanceInterval);
        debugPrint('[CalendarLauncher] (EN) Schedule generated with ${schedule.length} entries.');

        return CalendarPage(
          schedule: schedule,
          morningColor: Color(prefs.getInt('morningColor') ?? Colors.red.value),
          afternoonColor: Color(prefs.getInt('afternoonColor') ?? Colors.orange.value),
          nightColor: Color(prefs.getInt('nightColor') ?? Colors.blue.value),
          restColor: Color(prefs.getInt('restColor') ?? Colors.green.value),
          maintenanceColor: Color(prefs.getInt('maintenanceColor') ?? Colors.purple.value),
        );
      },
    );
  }
}

// --------------------------- ExactAlarmsWidget ---------------------------
class ExactAlarmsWidget extends StatefulWidget {
  const ExactAlarmsWidget({super.key});

  @override
  State<ExactAlarmsWidget> createState() => _ExactAlarmsWidgetState();
}

class _ExactAlarmsWidgetState extends State<ExactAlarmsWidget> {
  bool _enabled = true;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    debugPrint('[ExactAlarmsWidget] (EN) initState called - loading preferences.');
    _loadPref();
  }

  Future<void> _loadPref() async {
    final prefs = await SharedPreferences.getInstance();
    final disabled = prefs.getBool('disable_exact_alarms') ?? false;
    setState(() {
      _enabled = !disabled;
      _loading = false;
    });
    debugPrint('[ExactAlarmsWidget] (EN) Loaded disable_exact_alarms -> $disabled. _enabled=$_enabled');
  }

  Future<void> _toggle(bool val) async {
    debugPrint('[ExactAlarmsWidget] (EN) User toggled exact alarms -> new value requested: $val');
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('disable_exact_alarms', !val);
    setState(() => _enabled = val);
    if (!val) {
      debugPrint('[ExactAlarmsWidget] (EN) Exact alarms disabled by user: cancelling notifications.');
      try {
        await NotificationsService.instance.cancelAll();
        debugPrint('[ExactAlarmsWidget] (EN) cancelAll succeeded.');
      } catch (e) {
        debugPrint('[ExactAlarmsWidget] (EN) cancelAll failed -> $e');
      }
    } else {
      debugPrint('[ExactAlarmsWidget] (EN) Exact alarms enabled by user: rescheduling notifications.');
      try {
        await NotificationsService.instance.rescheduleIfNeeded(force: false);
        debugPrint('[ExactAlarmsWidget] (EN) rescheduleIfNeeded succeeded.');
      } catch (e) {
        debugPrint('[ExactAlarmsWidget] (EN) rescheduleIfNeeded failed -> $e');
      }
    }
  }

  Future<void> _disableCompletely() async {
    debugPrint('[ExactAlarmsWidget] (EN) User requested to disable exact alarms completely.');
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('disable_exact_alarms', true);
    setState(() => _enabled = false);
    try {
      await NotificationsService.instance.cancelAll();
      debugPrint('[ExactAlarmsWidget] (EN) All notifications cancelled as part of disabling exact alarms.');
    } catch (e) {
      debugPrint('[ExactAlarmsWidget] (EN) cancelAll failed -> $e');
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'تم تعطيل التنبيهات الدقيقة وإلغاء كل الإشعارات المجدولة.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const SizedBox.shrink();
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'تنبيهات دقيقة',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                Switch(value: _enabled, onChanged: (v) => _toggle(v)),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'تتحكم هذه الخاصية في إمكانية الجدولة بدقة (exact alarms). '
                  'تعطيلها يمنع بعض الإشعارات الدقيقة أثناء Doze، وسيتم إلغاء الجداول المجدولة.',
              textAlign: TextAlign.right,
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: _disableCompletely,
              child: const Text('شلها خالص (تعطيل وإلغاء الكل)'),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            ),
          ],
        ),
      ),
    );
  }
}
