import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import '../screens/calendar_page.dart';
import '../service/notifications_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Rewritten SettingsPage with automatic monthly renewal of scheduled notifications.
///
/// Behaviour summary:
/// - Saves settings to SharedPreferences (same keys as before).
/// - On save it initializes notifications, requests permission and schedules
///   notifications for the next 30 days by calling NotificationsService.scheduleNextNDays(30).
/// - It relies on NotificationsService to persist `scheduledUntil` and to schedule
///   an Android renewal alarm. For non-Android platforms the page will also check
///   `scheduledUntil` at app resume and will re-schedule if needed.
/// - On app resume the page attempts to ensure the scheduled notifications won't
///   expire soon (i.e. if scheduledUntil is less than 5 days away it renews for
///   another 30 days). This makes the renewal robust across app restarts.

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage>
    with WidgetsBindingObserver {
  final List<String> workSystems = [
    'نظام العمل 12/24-12/48',
    'نظام العمل يوم عمل - يومين راحة',
    'يومين عمل ٤ أيام راحة',
    '3 أيام عمل (صبح - عصر - ليل) يليها يومين راحة',
    '6 أيام عمل 2 يوم راحة',
    'صباحي',
  ];
  String selectedWorkSystem = 'نظام العمل 12/24-12/48';

  DateTime? selectedStartDate;

  final List<String> morningTimes = [
    '05:00 صباحاً',
    '06:00 صباحاً',
    '07:00 صباحاً',
    '07:30 صباحاً',
    '08:00 صباحاً',
    '09:00 صباحاً',
    '10:00 صباحاً',
    '11:00 صباحاً',
  ];

  final List<String> eveningTimes = [
    '13:00 مساءً',
    '14:00 مساءً',
    '15:00 مساءً',
    '15:30 مساءً',
    '16:00 مساءً',
    '17:00 مساءً',
    '18:00 مساءً',
    '19:00 مساءً',
    '19:30 مساءً',
    '20:00 مساءً',
    '21:00 مساءً',
    '22:00 مساءً',
    '23:00 مساءً',
  ];

  String morningStart = '07:00 صباحاً';
  String morningCheckIn = '07:30 صباحاً';
  String afternoonStart = '15:00 مساءً';
  String afternoonCheckIn = '15:30 مساءً';
  String nightStart = '19:00 مساءً';
  String nightCheckIn = '19:30 مساءً';

  final List<String> reminderTimes = [
    'نصف ساعة',
    'ساعة',
    'ساعة ونصف',
    'ساعتين',
  ];
  String reminder = 'نصف ساعة';

  final List<int> maintenanceIntervals = [0, 2, 3, 4, 5, 6, 7, 8, 9, 10];
  int selectedMaintenanceInterval = 0;

  Color morningColor = Colors.red;
  Color afternoonColor = Colors.orange;
  Color nightColor = Colors.blue;
  Color restColor = Colors.green;
  Color maintenanceColor = Colors.purple;

  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    loadSettings().then((_) async {
      // Ensure scheduled notifications are renewed if needed when page starts
      await _ensureMonthlyRenewalIfNeeded();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      debugPrint(
        '[SettingsPage] AppLifecycleState.paused -> saving settings automatically',
      );
      saveSettingsWithVerification().catchError((e) {
        debugPrint('[SettingsPage] auto-save on paused failed -> $e');
      });
    }

    if (state == AppLifecycleState.resumed) {
      // When app comes back to foreground verify scheduledUntil and renew if close to expiry
      _ensureMonthlyRenewalIfNeeded().catchError((e) {
        debugPrint('[SettingsPage] ensureMonthlyRenewal failed -> $e');
      });
    }
  }

  Future<void> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      selectedWorkSystem = prefs.getString('workSystem') ?? selectedWorkSystem;

      String savedMorningStart = prefs.getString('morningStart') ?? morningStart;
      String savedMorningCheckIn = prefs.getString('morningCheckIn') ?? morningCheckIn;
      String savedAfternoonStart = prefs.getString('afternoonStart') ?? afternoonStart;
      String savedAfternoonCheckIn = prefs.getString('afternoonCheckIn') ?? afternoonCheckIn;
      String savedNightStart = prefs.getString('nightStart') ?? nightStart;
      String savedNightCheckIn = prefs.getString('nightCheckIn') ?? nightCheckIn;

      morningStart = morningTimes.contains(savedMorningStart) ? savedMorningStart : morningStart;
      morningCheckIn = morningTimes.contains(savedMorningCheckIn) ? savedMorningCheckIn : morningCheckIn;
      afternoonStart = eveningTimes.contains(savedAfternoonStart) ? savedAfternoonStart : afternoonStart;
      afternoonCheckIn = eveningTimes.contains(savedAfternoonCheckIn) ? savedAfternoonCheckIn : afternoonCheckIn;
      nightStart = eveningTimes.contains(savedNightStart) ? savedNightStart : nightStart;
      nightCheckIn = eveningTimes.contains(savedNightCheckIn) ? savedNightCheckIn : nightCheckIn;

      String savedReminder = prefs.getString('reminder') ?? reminder;
      if (savedReminder == 'نص ساعة') savedReminder = 'نصف ساعة';
      reminder = reminderTimes.contains(savedReminder) ? savedReminder : reminder;

      selectedMaintenanceInterval = prefs.getInt('maintenanceInterval') ?? 0;

      morningColor = Color(prefs.getInt('morningColor') ?? morningColor.value);
      afternoonColor = Color(prefs.getInt('afternoonColor') ?? afternoonColor.value);
      nightColor = Color(prefs.getInt('nightColor') ?? nightColor.value);
      restColor = Color(prefs.getInt('restColor') ?? restColor.value);
      maintenanceColor = Color(prefs.getInt('maintenanceColor') ?? maintenanceColor.value);

      final startDateStr = prefs.getString('startDate');
      if (startDateStr != null) {
        final parsed = DateTime.tryParse(startDateStr);
        if (parsed != null) {
          selectedStartDate = DateTime(parsed.year, parsed.month, parsed.day);
        } else {
          selectedStartDate = null;
        }
      } else {
        selectedStartDate = null;
      }
    });
  }

  Future<void> saveSettingsWithVerification() async {
    final prefs = await SharedPreferences.getInstance();
    const int maxRetries = 3;
    int attempt = 0;
    while (true) {
      attempt++;
      try {
        final futures = <Future<bool>>[];

        futures.add(prefs.setString('workSystem', selectedWorkSystem));
        futures.add(prefs.setString('morningStart', morningStart));
        futures.add(prefs.setString('morningCheckIn', morningCheckIn));
        futures.add(prefs.setString('afternoonStart', afternoonStart));
        futures.add(prefs.setString('afternoonCheckIn', afternoonCheckIn));
        futures.add(prefs.setString('nightStart', nightStart));
        futures.add(prefs.setString('nightCheckIn', nightCheckIn));
        futures.add(prefs.setString('reminder', reminder));
        futures.add(prefs.setInt('maintenanceInterval', selectedMaintenanceInterval));
        futures.add(prefs.setInt('morningColor', morningColor.value));
        futures.add(prefs.setInt('afternoonColor', afternoonColor.value));
        futures.add(prefs.setInt('nightColor', nightColor.value));
        futures.add(prefs.setInt('restColor', restColor.value));
        futures.add(prefs.setInt('maintenanceColor', maintenanceColor.value));

        if (selectedStartDate != null) {
          final dateOnly = DateTime(selectedStartDate!.year, selectedStartDate!.month, selectedStartDate!.day);
          futures.add(prefs.setString('startDate', dateOnly.toIso8601String()));
        } else {
          await prefs.remove('startDate');
        }

        final results = await Future.wait(futures);
        final allOk = results.fold<bool>(true, (prev, element) => prev && element);

        if (!allOk) throw Exception('SharedPreferences set returned false on some keys');

        final verifyWorkSystem = prefs.getString('workSystem');
        if (verifyWorkSystem == selectedWorkSystem) {
          debugPrint('[saveSettingsWithVerification] saved successfully on attempt $attempt');
          return;
        } else {
          throw Exception('verification failed (workSystem mismatch)');
        }
      } catch (e) {
        debugPrint('[saveSettingsWithVerification] attempt $attempt failed -> $e');
        if (attempt >= maxRetries) {
          debugPrint('[saveSettingsWithVerification] reached max retries, aborting.');
          rethrow;
        }
        await Future.delayed(const Duration(milliseconds: 200));
      }
    }
  }

  Future<void> saveSettings() async {
    await saveSettingsWithVerification();
  }

  Future<void> pickStartDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: selectedStartDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() => selectedStartDate = DateTime(picked.year, picked.month, picked.day));
    }
  }

  DateTime parseTime(DateTime day, String timeText) {
    final parts = timeText.split(' ');
    final hm = parts[0].split(':');
    int hour = int.parse(hm[0]);
    int minute = int.parse(hm[1]);
    final period = parts.length > 1 ? parts[1] : '';

    if (period.contains('مساءً') || period.contains('مساء')) {
      if (hour < 12) hour += 12;
    } else if (period.contains('صباحاً') || period.contains('صباح')) {
      if (hour == 12) hour = 0;
    }

    return DateTime(day.year, day.month, day.day, hour, minute);
  }

  Duration getReminderDuration() {
    switch (reminder) {
      case 'ساعة':
        return const Duration(hours: 1);
      case 'ساعة ونصف':
        return const Duration(minutes: 90);
      case 'ساعتين':
        return const Duration(hours: 2);
      default:
        return const Duration(minutes: 30);
    }
  }

  Duration getShiftDuration() {
    if (selectedWorkSystem == 'نظام العمل 12/24-12/48') {
      return const Duration(hours: 12);
    } else if (selectedWorkSystem == 'نظام العمل يوم عمل - يومين راحة') {
      return const Duration(hours: 24);
    } else if (selectedWorkSystem == 'يومين عمل ٤ أيام راحة') {
      return const Duration(hours: 48);
    } else {
      return const Duration(hours: 8);
    }
  }

  Map<DateTime, String> generateWorkSchedule(String system, DateTime startDate, int maintenanceInterval) {
    final schedule = <DateTime, String>{};
    int shiftCounter = 0;
    String lastShift = "راحة";
    bool isFirstShift = true;

    for (int i = 0; i < 3650; i++) {
      final day = startDate.add(Duration(days: i));
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
        shift = (day.weekday >= 1 && day.weekday <= 5) ? "صبح" : "راحة";
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
        if (lastShift == "صيانة") {
          shift = "صيانة";
        }
      }

      schedule[DateTime.utc(day.year, day.month, day.day)] = shift;
      lastShift = shift;
    }
    return schedule;
  }

  Widget buildColorPicker(String title, Color selectedColor, Function(Color) onColorSelected) {
    final colors = [
      Colors.red,
      Colors.orange,
      Colors.green,
      const Color.fromARGB(255, 255, 255, 0),
      const Color.fromARGB(255, 0, 0, 0),
      const Color.fromARGB(255, 255, 255, 255),
      Colors.blue,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontSize: 16)),
        Row(
          children: colors.map((color) {
            final selected = selectedColor == color;
            return GestureDetector(
              onTap: () => setState(() => onColorSelected(color)),
              child: Container(
                margin: const EdgeInsets.all(4),
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: selected ? Colors.black : Colors.transparent,
                    width: 2,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 20),
      ],
    );
  }

  String getMaintenanceIntervalText(int interval) {
    if (interval == 0) return 'بدون عمل صيانة';
    switch (interval) {
      case 2:
        return 'زام / زام';
      case 3:
        return 'زام / زامين';
      case 4:
        return 'زام / ٣ زامات';
      case 5:
        return 'زام / ٤ زامات';
      case 6:
        return 'زام / ٥ زامات';
      case 7:
        return 'زام / ٦ زامات';
      case 8:
        return 'زام / ٧ زامات';
      case 9:
        return 'زام / ٨ زامات';
      case 10:
        return 'زام / ٩ زامات';
      default:
        return 'كل $interval نوبات عمل';
    }
  }

  /// Ensure there are at least `renewThresholdDays` left before scheduledUntil.
  /// If scheduledUntil is null or within the threshold we schedule another 30 days.
  Future<void> _ensureMonthlyRenewalIfNeeded({int renewThresholdDays = 5}) async {
    try {
      await NotificationsService.instance.init();

      // try to read scheduledUntil from service prefs
      final scheduledUntil = await NotificationsService.instance.getScheduledUntil();

      final now = DateTime.now();
      if (scheduledUntil == null) {
        debugPrint('[SettingsPage] scheduledUntil is null -> scheduling next 30 days');
        await NotificationsService.instance.scheduleNextNDays(30);
        return;
      }

      final daysLeft = scheduledUntil.difference(now).inDays;
      debugPrint('[SettingsPage] scheduledUntil=$scheduledUntil daysLeft=$daysLeft');

      if (daysLeft <= renewThresholdDays) {
        debugPrint('[SettingsPage] scheduledUntil low -> scheduling next 30 days');
        await NotificationsService.instance.scheduleNextNDays(30);
      }
    } catch (e) {
      debugPrint('[SettingsPage] _ensureMonthlyRenewalIfNeeded error -> $e');
    }
  }

  Future<void> _setupNotificationsInBackgroundFromForm() async {
    if (selectedStartDate == null) return;

    try {
      debugPrint('SettingsPage: background scheduling from form started.');

      await NotificationsService.instance.init();

      bool granted = true;
      try {
        granted = await NotificationsService.instance.requestPermissions();
        debugPrint('SettingsPage: requestPermissions result = $granted');
      } catch (e) {
        debugPrint('SettingsPage: requestPermissions threw -> $e');
        granted = false;
      }

      if (!granted) {
        debugPrint(
          'SettingsPage: notifications permission not granted. Scheduling will still be attempted,'
              ' but OS may block shown notifications on Android 13+ until user enables permission.',
        );
      }

      // Save settings first (prefs are used by scheduleNextNDays)
      await saveSettingsWithVerification();

      // Schedule notifications for next 30 days. NotificationsService.scheduleNextNDays
      // will persist scheduledUntil and (on Android) schedule renewal alarm.
      await NotificationsService.instance.scheduleNextNDays(30);
      debugPrint('SettingsPage: scheduleNextNDays(30) completed.');

      await NotificationsService.instance.sendWelcomeNotificationOnce();
      debugPrint('SettingsPage: background scheduling from form finished.');
    } catch (e, st) {
      debugPrint('SettingsPage: scheduling from form error -> $e\n$st');
    }
  }

  @override
  Widget build(BuildContext context) {
    final showAfternoon = selectedWorkSystem.contains("3 أيام") || selectedWorkSystem.contains("6 أيام");
    final showNight = selectedWorkSystem.contains("12/24") || selectedWorkSystem.contains("3 أيام") || selectedWorkSystem.contains("6 أيام");
    final showMaintenance = selectedMaintenanceInterval > 0;

    String startDateLabel() {
      if (selectedStartDate == null) return "⚠️ يجب اختيار تاريخ البداية";
      final local = selectedStartDate!.toLocal();
      final y = local.year.toString().padLeft(4, '0');
      final m = local.month.toString().padLeft(2, '0');
      final d = local.day.toString().padLeft(2, '0');
      return "تاريخ البداية: $y-$m-$d";
    }

    return Scaffold(
      appBar: AppBar(title: const Text("إعدادات النظام")),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text("تحديد نظام العمل", style: TextStyle(fontSize: 16)),
              const SizedBox(height: 8),
              DropdownButton<String>(
                value: selectedWorkSystem,
                isExpanded: true,
                items: workSystems.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                onChanged: (v) => setState(() => selectedWorkSystem = v!),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: pickStartDate,
                style: ElevatedButton.styleFrom(
                  backgroundColor: selectedStartDate == null ? Colors.red : null,
                  foregroundColor: selectedStartDate == null ? Colors.white : null,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(startDateLabel(), style: const TextStyle(fontSize: 16)),
                ),
              ),
              const SizedBox(height: 20),

              const Text("عمل الصيانة", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              const Text("فترة عمل الصيانة"),
              DropdownButton<int>(
                value: selectedMaintenanceInterval,
                isExpanded: true,
                items: maintenanceIntervals.map((e) => DropdownMenuItem(value: e, child: Text(getMaintenanceIntervalText(e)))).toList(),
                onChanged: (v) => setState(() => selectedMaintenanceInterval = v!),
              ),
              if (showMaintenance) const SizedBox(height: 10),
              const SizedBox(height: 20),
              const Divider(),
              const SizedBox(height: 8),
              const Text("وقت بداية صبح"),
              DropdownButton<String>(
                value: morningStart,
                isExpanded: true,
                items: morningTimes.map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
                onChanged: (v) => setState(() => morningStart = v!),
              ),
              const SizedBox(height: 8),
              const Text("إثبات حضور صبح"),
              DropdownButton<String>(
                value: morningCheckIn,
                isExpanded: true,
                items: morningTimes.map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
                onChanged: (v) => setState(() => morningCheckIn = v!),
              ),
              if (showAfternoon) ...[
                const SizedBox(height: 20),
                const Text("وقت بداية عصر"),
                DropdownButton<String>(
                  value: afternoonStart,
                  isExpanded: true,
                  items: eveningTimes.map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
                  onChanged: (v) => setState(() => afternoonStart = v!),
                ),
                const SizedBox(height: 8),
                const Text("إثبات حضور عصر"),
                DropdownButton<String>(
                  value: afternoonCheckIn,
                  isExpanded: true,
                  items: eveningTimes.map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
                  onChanged: (v) => setState(() => afternoonCheckIn = v!),
                ),
              ],
              if (showNight) ...[
                const SizedBox(height: 20),
                const Text("وقت بداية ليل"),
                DropdownButton<String>(
                  value: nightStart,
                  isExpanded: true,
                  items: eveningTimes.map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
                  onChanged: (v) => setState(() => nightStart = v!),
                ),
                const SizedBox(height: 8),
                const Text("إثبات حضور ليل"),
                DropdownButton<String>(
                  value: nightCheckIn,
                  isExpanded: true,
                  items: eveningTimes.map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
                  onChanged: (v) => setState(() => nightCheckIn = v!),
                ),
              ],
              const SizedBox(height: 20),
              const Text("ذكرني قبل"),
              DropdownButton<String>(
                value: reminder,
                isExpanded: true,
                items: reminderTimes.map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
                onChanged: (v) => setState(() => reminder = v!),
              ),
              const SizedBox(height: 20),
              const Text("الألوان", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              buildColorPicker("لون صبح", morningColor, (c) => setState(() => morningColor = c)),
              if (showAfternoon) buildColorPicker("لون عصر", afternoonColor, (c) => setState(() => afternoonColor = c)),
              if (showNight) buildColorPicker("لون ليل", nightColor, (c) => setState(() => nightColor = c)),
              buildColorPicker("لون الراحة", restColor, (c) => setState(() => restColor = c)),
              if (showMaintenance) buildColorPicker("لون الصيانة", maintenanceColor, (c) => setState(() => maintenanceColor = c)),
              const SizedBox(height: 20),

              Center(
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _isSaving
                        ? null
                        : () async {
                      if (selectedStartDate == null) {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("اختر تاريخ البداية أولاً")));
                        return;
                      }

                      setState(() => _isSaving = true);

                      try {
                        await saveSettingsWithVerification();
                      } catch (e) {
                        debugPrint('[SettingsPage] saveSettingsWithVerification failed -> $e');
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("فشل حفظ الإعدادات — حاول مرة أخرى")));
                        setState(() => _isSaving = false);
                        return;
                      }

                      try {
                        await NotificationsService.instance.init();
                      } catch (e) {
                        debugPrint('SettingsPage: NotificationsService.init() failed -> $e');
                      }

                      // schedule notifications & ensure monthly automatic renewal
                      await _setupNotificationsInBackgroundFromForm();

                      try {
                        await NotificationsService.instance.scheduleOneOffSecondsFromNow(
                          id: DateTime.now().millisecondsSinceEpoch.remainder(100000),
                          title: 'تم حفظ الإعدادات ✅',
                          body: 'الإعدادات تم حفظها وسيتم إرسال التذكيرات في مواعيدها.',
                          seconds: 2,
                        );
                      } catch (e) {
                        debugPrint('SettingsPage: schedule save-notif failed -> $e');
                        try {
                          await NotificationsService.instance.showImmediateNotification(
                            id: DateTime.now().millisecondsSinceEpoch.remainder(100000),
                            title: 'تم حفظ الإعدادات ✅',
                            body: 'الإعدادات تم حفظها وسيتم إرسال التذكيرات في مواعيدها.',
                          );
                        } catch (_) {}
                      }

                      final schedule = generateWorkSchedule(selectedWorkSystem, selectedStartDate!, selectedMaintenanceInterval);

                      if (!mounted) return;

                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("تم الحفظ وإعداد الإشعارات ✅")));

                      setState(() => _isSaving = false);

                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => CalendarPage(
                            schedule: schedule,
                            morningColor: morningColor,
                            afternoonColor: afternoonColor,
                            nightColor: nightColor,
                            restColor: restColor,
                            maintenanceColor: maintenanceColor,
                          ),
                        ),
                      );
                    },
                    style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                    child: _isSaving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Text("حفظ"),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
