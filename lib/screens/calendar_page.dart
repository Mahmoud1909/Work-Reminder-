// lib/screens/calendar_page.dart
import 'dart:ui' as ui; // لاستخدام ui.TextDirection.rtl
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:khamsat/screens/SettingsMenuPage.dart';
import '../screens/add_vacation_page.dart';
import '../screens/vacation_manager.dart';
import '../screens/vacation_stats_page.dart';
import '../screens/vacations_list_page.dart';
import '../service/purchase_Manager.dart';
import 'package:table_calendar/table_calendar.dart';
import '../screens/settings_page.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';

// تأكد أن المسار صحيح لصفحة الترقية (UpgradePromptPage)
import 'upgrade_prompt_page.dart';

/// ------------------------ CalendarPage ------------------------
class CalendarPage extends StatefulWidget {
  final Map<DateTime, String> schedule;
  final Color morningColor;
  final Color afternoonColor;
  final Color nightColor;
  final Color restColor;
  final Color maintenanceColor;

  const CalendarPage({
    super.key,
    required this.schedule,
    required this.morningColor,
    required this.afternoonColor,
    required this.nightColor,
    required this.restColor,
    required this.maintenanceColor,
  });

  @override
  State<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends State<CalendarPage> {
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  int _refreshKey = 0;

  static const String _kLastBannerDateKey = 'last_subscription_banner_date';
  static const String _kPrefsShowUpgradeOnLaunch = 'pm_show_upgrade_on_launch';

  @override
  void initState() {
    super.initState();

    // بعد أول إطار: نعرض البنر اليومي (إذا يلزم) ونفحص انتهاء فترة التجربة
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _maybeShowSubscriptionBanner();

      // نفحص Trial ونضع العلم إن انتهى (وظيفة PurchaseManager يفترض أنها لا ترسل إشعارات)
      _runTrialCheckAndMaybeShowUpgrade();
    });
  }

  Future<void> _runTrialCheckAndMaybeShowUpgrade() async {
    try {
      // 1) دع PurchaseManager يتحقق ويضع العلامة لو انتهت التجربة (دون إشعارات)
      try {
        await PurchaseManager.instance.checkTrialAndNotifyIfExpired();
      } catch (e) {
        // إن لم تكن الدالة موجودة في PurchaseManager، حاول استخدام بديل (isTrialExpired)
        debugPrint('[CalendarPage] PurchaseManager.checkTrialAndMarkIfExpired not available -> $e');
        try {
          final expired = (PurchaseManager.instance.isTrialExpired != null)
              ? await Future.value(PurchaseManager.instance.isTrialExpired())
              : false;
          if (expired) {
            final prefs = await SharedPreferences.getInstance();
            await prefs.setBool(_kPrefsShowUpgradeOnLaunch, true);
          }
        } catch (_) {}
      }

      // 2) الآن اقرأ العلم من SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      final shouldShow = prefs.getBool(_kPrefsShowUpgradeOnLaunch) ?? false;

      if (!shouldShow) return;

      // مسح العلم فوراً حتى لا يُعرض مرارًا
      await prefs.setBool(_kPrefsShowUpgradeOnLaunch, false);

      // انتظارٍ بسيط للتأكد أن الـ Navigator جاهز
      await Future.delayed(const Duration(milliseconds: 150));
      if (!mounted) return;

      // عرض صفحة الترقية واستبدال الصفحة الحالية (لا نريد رجوع تلقائي)
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const UpgradePromptPage()),
      );
    } catch (e, st) {
      debugPrint('[CalendarPage] _runTrialCheckAndMaybeShowUpgrade error -> $e\n$st');
    }
  }

  void _refreshCalendar() {
    setState(() {
      _refreshKey++;
    });
  }

  Color getTextColor(Color backgroundColor) {
    double luminance = backgroundColor.computeLuminance();
    return luminance > 0.5 ? Colors.black : Colors.white;
  }

  Color _getShiftColor(String shift) {
    switch (shift) {
      case 'صبح':
        return widget.morningColor;
      case 'عصر':
        return widget.afternoonColor;
      case 'ليل':
        return widget.nightColor;
      case 'صيانة':
        return widget.maintenanceColor;
      case 'راحة':
      default:
        return widget.restColor;
    }
  }

  Map<String, int> _getMonthlyStats() {
    final stats = <String, int>{
      'صبح': 0,
      'عصر': 0,
      'ليل': 0,
      'صيانة': 0,
      'راحة': 0,
    };

    final currentMonth = _focusedDay.month;
    final currentYear = _focusedDay.year;

    for (final entry in widget.schedule.entries) {
      if (entry.key.month == currentMonth && entry.key.year == currentYear) {
        final shift = entry.value;
        stats[shift] = (stats[shift] ?? 0) + 1;
      }
    }
    return stats;
  }

  Widget _buildMonthlyStatsCard() {
    final stats = _getMonthlyStats();
    final monthName = [
      'يناير',
      'فبراير',
      'مارس',
      'إبريل',
      'مايو',
      'يونيو',
      'يوليو',
      'أغسطس',
      'سبتمبر',
      'أكتوبر',
      'نوفمبر',
      'ديسمبر',
    ][_focusedDay.month - 1];

    return Card(
      margin: const EdgeInsets.all(8.0),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "إحصائيات شهر $monthName ${_focusedDay.year}",
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildStatItem('صبح', stats['صبح'] ?? 0, widget.morningColor),
                _buildStatItem('عصر', stats['عصر'] ?? 0, widget.afternoonColor),
                _buildStatItem('ليل', stats['ليل'] ?? 0, widget.nightColor),
                _buildStatItem('صيانة', stats['صيانة'] ?? 0, widget.maintenanceColor),
                _buildStatItem('راحة', stats['راحة'] ?? 0, widget.restColor),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatItem(String label, int count, Color color) {
    return Column(
      children: [
        Container(width: 20, height: 20, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(fontSize: 12)),
        Text('$count', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
      ],
    );
  }

  DateTime _parseTime(DateTime day, String timeText) {
    final parts = timeText.split(' ');
    final hm = parts[0].split(':');
    int hour = int.tryParse(hm[0]) ?? 0;
    int minute = int.tryParse(hm[1]) ?? 0;
    final period = parts.length > 1 ? parts[1] : '';
    if (period.contains('مساء')) {
      if (hour < 12) hour += 12;
    } else if (period.contains('صباح')) {
      if (hour == 12) hour = 0;
    }
    return DateTime(day.year, day.month, day.day, hour, minute);
  }

  Duration _getReminderDurationFromString(String reminder) {
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

  Duration _getShiftDurationFromSystem(String system) {
    if (system == 'نظام العمل 12/24-12/48') return const Duration(hours: 12);
    if (system == 'نظام العمل يوم عمل - يومين راحة') return const Duration(hours: 24);
    if (system == 'يومين عمل ٤ أيام راحة') return const Duration(hours: 48);
    return const Duration(hours: 8);
  }

  Future<void> _showAllDataDialog({int nextDays = 14}) async {
    final prefs = await SharedPreferences.getInstance();

    final workSystem = prefs.getString('workSystem') ?? '(غير محدد)';
    final startDateStr = prefs.getString('startDate') ?? '(غير محدد)';
    final maintenanceInterval = prefs.getInt('maintenanceInterval') ?? 0;
    final morningStart = prefs.getString('morningStart') ?? '07:00 صباحاً';
    final morningCheckIn = prefs.getString('morningCheckIn') ?? '07:30 صباحاً';
    final afternoonStart = prefs.getString('afternoonStart') ?? '15:00 مساءً';
    final afternoonCheckIn = prefs.getString('afternoonCheckIn') ?? '15:30 مساءً';
    final nightStart = prefs.getString('nightStart') ?? '19:00 مساءً';
    final nightCheckIn = prefs.getString('nightCheckIn') ?? '19:30 مساءً';
    final reminder = prefs.getString('reminder') ?? 'نصف ساعة';

    final df = DateFormat('yyyy-MM-dd HH:mm');
    final List<String> lines = [];

    lines.add('--- الإعدادات المحفوظة ---');
    lines.add('نظام العمل: $workSystem');
    lines.add('تاريخ البداية: $startDateStr');
    lines.add('فترة الصيانة: ${maintenanceInterval == 0 ? "بدون" : maintenanceInterval.toString()}');
    lines.add('وقت صباحي: بداية=$morningStart إثبات=$morningCheckIn');
    lines.add('وقت عصري: بداية=$afternoonStart إثبات=$afternoonCheckIn');
    lines.add('وقت ليلي: بداية=$nightStart إثبات=$nightCheckIn');
    lines.add('تذكير مسبق: $reminder');
    lines.add('');
    lines.add('--- معاينة مواعيد الإشعارات للأيام القادمة ($nextDays يوم) ---');

    final now = DateTime.now();
    for (int i = 0; i < nextDays; i++) {
      final day = DateTime(now.year, now.month, now.day).add(Duration(days: i));
      final keyUtc = DateTime.utc(day.year, day.month, day.day);
      final shift = widget.schedule[keyUtc];
      if (shift == null || shift == 'راحة') continue;

      bool isVacation = false;
      try {
        final vac = await VacationManager.getVacationForDate(day);
        if (vac != null) isVacation = true;
      } catch (_) {}

      if (isVacation) {
        lines.add('اليوم ${day.toLocal().toIso8601String().split("T")[0]}: (إجازة) — تخطي');
        lines.add('');
        continue;
      }

      DateTime startDT;
      DateTime checkInDT;
      if (shift == 'صبح' || shift == 'صيانة') {
        startDT = _parseTime(day, morningStart);
        checkInDT = _parseTime(day, morningCheckIn);
      } else if (shift == 'عصر') {
        startDT = _parseTime(day, afternoonStart);
        checkInDT = _parseTime(day, afternoonCheckIn);
      } else {
        startDT = _parseTime(day, nightStart);
        checkInDT = _parseTime(day, nightCheckIn);
      }

      final shiftDuration = _getShiftDurationFromSystem(workSystem);
      final endDT = startDT.add(shiftDuration);
      final before12h = startDT.subtract(const Duration(hours: 12));
      final reminderAt = startDT.subtract(_getReminderDurationFromString(reminder));

      lines.add('اليوم ${day.toLocal().toIso8601String().split("T")[0]} -> نوع النوبة: $shift');
      lines.add('  • تذكير قبل 12 ساعة : ${df.format(before12h.toLocal())}');
      lines.add('  • تذكير قبل البداية ($reminder) : ${df.format(reminderAt.toLocal())}');
      lines.add('  • إثبات حضور : ${df.format(checkInDT.toLocal())}');
      lines.add('  • نهاية النوبة : ${df.format(endDT.toLocal())}');
      lines.add('');
    }

    if (lines.length <= 2) {
      lines.add('لا توجد نوبات مجدولة للأيام القادمة حسب الإعدادات.');
    }

    await showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('بيانات الإعدادات ومواعيد الإشعارات'),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: SelectableText(lines.join('\n')),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('إغلاق')),
          ],
        );
      },
    );
  }

  void _onDaySelected(DateTime selectedDay, DateTime focusedDay) async {
    setState(() {
      _selectedDay = selectedDay;
      _focusedDay = focusedDay;
    });

    final vacation = await VacationManager.getVacationForDate(selectedDay);

    if (vacation != null) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(vacation.typeNameArabic),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('من: ${vacation.startDate.day}/${vacation.startDate.month}/${vacation.startDate.year}'),
              Text('إلى: ${vacation.endDate.day}/${vacation.endDate.month}/${vacation.endDate.year}'),
              Text('المدة: ${vacation.durationDays} أيام'),
              if (vacation.notes != null && vacation.notes!.isNotEmpty) Text('ملاحظة: ${vacation.notes}'),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('إغلاق')),
            TextButton(
              onPressed: () async {
                Navigator.pop(context);
                final result = await Navigator.push(context, MaterialPageRoute(builder: (context) => AddVacationPage(existingVacation: vacation)));
                if (result == true) _refreshCalendar();
              },
              child: const Text('تعديل'),
            ),
          ],
        ),
      );
    } else {
      final key = DateTime.utc(selectedDay.year, selectedDay.month, selectedDay.day);
      final shift = widget.schedule[key];
      if (shift != null) {
        String shiftText = shift == 'صيانة' ? 'عمل صيانة' : shift;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("اليوم ${selectedDay.toLocal().toString().split(' ')[0]}: $shiftText"), duration: const Duration(seconds: 2)));
      }
    }
  }

  Widget _buildCalendarCell(DateTime day, { bool isSelected = false, bool isToday = false }) {
    final key = DateTime.utc(day.year, day.month, day.day);
    final shift = widget.schedule[key];

    return FutureBuilder<Vacation?>(key: ValueKey('${day.toIso8601String()}_$_refreshKey'), future: VacationManager.getVacationForDate(day), builder: (context, vacationSnapshot) {
      final vacation = vacationSnapshot.data;
      if (vacation != null) {
        Color bgColor;
        String symbol;
        switch (vacation.type) {
          case 'emergency':
            bgColor = shift != null ? _getShiftColor(shift) : Colors.red;
            symbol = '⚠️';
            break;
          case 'sick':
            bgColor = shift != null ? _getShiftColor(shift) : Colors.orange;
            symbol = '➕';
            break;
          case 'annual':
            bgColor = shift != null ? _getShiftColor(shift) : Colors.purple;
            symbol = '🏖️';
            break;
          default:
            bgColor = shift != null ? _getShiftColor(shift) : Colors.grey;
            symbol = '?';
        }

        return Container(
          margin: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(8),
            border: isSelected ? Border.all(color: Colors.white, width: 2) : isToday ? Border.all(color: Colors.amber, width: 2) : null,
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(isSelected ? 0.3 : 0.1), blurRadius: isSelected ? 4 : 2, offset: Offset(isSelected ? 2 : 1, isSelected ? 2 : 1))],
          ),
          alignment: Alignment.center,
          child: Stack(children: [
            Center(child: Text(symbol, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold))),
            Positioned(top: 2, right: 2, child: Container(width: 16, height: 16, decoration: BoxDecoration(color: Colors.black.withOpacity(0.7), borderRadius: BorderRadius.circular(8)), child: Center(child: Text('${day.day}', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold))))),
          ]),
        );
      }

      if (shift == null) {
        return Center(child: Text('${day.day}', style: const TextStyle(color: Colors.black)));
      }

      Color bgColor;
      String displayText;
      switch (shift) {
        case 'صبح':
          bgColor = widget.morningColor;
          displayText = 'صبح';
          break;
        case 'عصر':
          bgColor = widget.afternoonColor;
          displayText = 'عصر';
          break;
        case 'ليل':
          bgColor = widget.nightColor;
          displayText = 'ليل';
          break;
        case 'صيانة':
          bgColor = widget.maintenanceColor;
          displayText = 'صيانة';
          break;
        case 'راحة':
        default:
          bgColor = widget.restColor;
          displayText = 'راحة';
          break;
      }

      return Container(
        margin: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(8),
          border: isSelected ? Border.all(color: Colors.white, width: 2) : isToday ? Border.all(color: Colors.amber, width: 2) : null,
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(isSelected ? 0.3 : 0.1), blurRadius: isSelected ? 4 : 2, offset: Offset(isSelected ? 2 : 1, isSelected ? 2 : 1))],
        ),
        alignment: Alignment.center,
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Text('${day.day}', style: TextStyle(color: getTextColor(bgColor), fontWeight: FontWeight.bold, fontSize: 14)),
          const SizedBox(height: 2),
          Text(displayText, style: TextStyle(color: getTextColor(bgColor), fontSize: 8, fontWeight: FontWeight.w600), textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis),
        ]),
      );
    });
  }

  Future<void> _maybeShowSubscriptionBanner() async {
    final prefs = await SharedPreferences.getInstance();
    final lastDateStr = prefs.getString(_kLastBannerDateKey);
    final todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());

    // if already shown today -> skip
    if (lastDateStr == todayStr) return;

    // determine subscription state
    final hasActive = PurchaseManager.instance.isActive();
    final expiresAt = PurchaseManager.instance.expiresAt();
    String bannerMessage;
    if (hasActive) {
      final remaining = PurchaseManager.instance.remainingDuration();
      final daysLeft = remaining == null ? null : (remaining.inDays + 1);
      bannerMessage = (daysLeft != null)
          ? 'اشتراكك مفعل — تبقى $daysLeft يومًا. اضغط لعرض خيارات الاشتراك.'
          : 'اشتراكك مفعل. اضغط لعرض خيارات الاشتراك.';
    } else {
      bannerMessage = 'احصل على تجربة مجانية 7 أيام ثم اشتراك سنوي \$19.99 — فعّل الحساب الآن.';
    }

    // build banner
    final materialBanner = MaterialBanner(
      content: Text(bannerMessage, style: const TextStyle(fontWeight: FontWeight.w600)),
      leading: const Icon(Icons.star_border),
      backgroundColor: Colors.blue.shade50,
      actions: [
        TextButton(
          onPressed: () async {
            // اشترِ الآن
            ScaffoldMessenger.of(context).hideCurrentMaterialBanner();
            await prefs.setString(_kLastBannerDateKey, todayStr); // mark as shown today
            try {
              await PurchaseManager.instance.buyYearly();
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم بدء عملية الشراء — تابع المتجر'))); // user feedback
            } catch (e) {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطأ عند بدء الشراء: $e')));
            }
          },
          child: const Text('اشترك الآن'),
        ),
        TextButton(
          onPressed: () async {
            // restore purchases
            ScaffoldMessenger.of(context).hideCurrentMaterialBanner();
            await prefs.setString(_kLastBannerDateKey, todayStr); // mark as shown today
            try {
              await PurchaseManager.instance.restorePurchases();
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('جاري استعادة المشتريات...')));
            } catch (e) {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطأ أثناء الاستعادة: $e')));
            }
          },
          child: const Text('استعادة'),
        ),
        TextButton(
          onPressed: () async {
            // dismiss for today
            ScaffoldMessenger.of(context).hideCurrentMaterialBanner();
            await prefs.setString(_kLastBannerDateKey, todayStr);
          },
          child: const Text('إغلاق'),
        ),
      ],
    );

    ScaffoldMessenger.of(context).showMaterialBanner(materialBanner);
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: ui.TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          title: const Text("التقويم"),
          actions: [
            IconButton(icon: const Icon(Icons.add_circle_outline), tooltip: "إضافة إجازة", onPressed: () async {
              final result = await Navigator.push(context, MaterialPageRoute(builder: (_) => const AddVacationPage()));
              if (result == true) _refreshCalendar();
            }),
            IconButton(icon: const Icon(Icons.event_note), tooltip: "إدارة الإجازات", onPressed: () async {
              final result = await Navigator.push(context, MaterialPageRoute(builder: (_) => const VacationsListPage()));
              if (result == true) _refreshCalendar();
            }),
            IconButton(icon: const Icon(Icons.bar_chart), tooltip: "إحصائيات الإجازات", onPressed: () {
              Navigator.push(context, MaterialPageRoute(builder: (_) => const VacationStatsPage()));
            }),
            IconButton(
              icon: const Icon(Icons.settings_applications), // أيقونة إعدادات عامة
              tooltip: "الإعدادات العامة",
              onPressed: () {
                Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsMenuPage()));
              },
            ),
          ],
        ),
        body: Column(children: [
          _buildMonthlyStatsCard(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              ElevatedButton(onPressed: () {
                setState(() {
                  _focusedDay = DateTime(_focusedDay.year, _focusedDay.month - 1, 1);
                  _refreshKey++;
                });
              }, child: const Text("السابق")),
              Text(
                ['يناير', 'فبراير', 'مارس', 'إبريل', 'مايو', 'يونيو', 'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر'][_focusedDay.month - 1] + ' ${_focusedDay.year}',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              ElevatedButton(onPressed: () {
                setState(() {
                  _focusedDay = DateTime(_focusedDay.year, _focusedDay.month + 1, 1);
                  _refreshKey++;
                });
              }, child: const Text("التالي")),
            ]),
          ),
          Expanded(
            child: TableCalendar(
              firstDay: DateTime.utc(2020, 1, 1),
              lastDay: DateTime.utc(2100, 12, 31),
              focusedDay: _focusedDay,
              selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
              calendarFormat: CalendarFormat.month,
              startingDayOfWeek: StartingDayOfWeek.sunday,
              availableCalendarFormats: const { CalendarFormat.month: 'شهر', CalendarFormat.week: 'أسبوع' },
              daysOfWeekStyle: const DaysOfWeekStyle(weekdayStyle: TextStyle(fontSize: 14, fontWeight: FontWeight.bold), weekendStyle: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.red)),
              headerStyle: const HeaderStyle(formatButtonVisible: false, titleCentered: true, leftChevronVisible: false, rightChevronVisible: false, titleTextStyle: TextStyle(fontSize: 0)),
              calendarBuilders: CalendarBuilders(
                dowBuilder: (context, day) {
                  final dayNames = ['الأحد','الاثنين','الثلاثاء','الأربعاء','الخميس','الجمعة','السبت'];
                  final isWeekend = day.weekday == DateTime.friday || day.weekday == DateTime.saturday;
                  int dayIndex = day.weekday == 7 ? 0 : day.weekday;
                  return Center(child: Text(dayNames[dayIndex], style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: isWeekend ? Colors.red : Colors.black)));
                },
                defaultBuilder: (context, day, focusedDay) => _buildCalendarCell(day),
                selectedBuilder: (context, day, focusedDay) => _buildCalendarCell(day, isSelected: true),
                todayBuilder: (context, day, focusedDay) => _buildCalendarCell(day, isToday: true),
              ),
              onPageChanged: (focusedDay) {
                setState(() {
                  _focusedDay = focusedDay;
                  _refreshKey++;
                });
              },
              onDaySelected: _onDaySelected,
            ),
          ),
        ]),
      ),
    );
  }
}