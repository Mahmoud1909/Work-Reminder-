
import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../service/notifications_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationsDebugScreen extends StatefulWidget {
  const NotificationsDebugScreen({Key? key}) : super(key: key);

  @override
  State<NotificationsDebugScreen> createState() => _NotificationsDebugScreenState();
}

class _NotificationsDebugScreenState extends State<NotificationsDebugScreen> {
  bool _loading = true;
  List<PendingNotificationRequest> _pending = [];
  DateTime? _scheduledUntil;
  Map<String, dynamic> _prefs = {};
  final DateFormat _dateFmt = DateFormat('yyyy-MM-dd');
  final DateFormat _timeFmt = DateFormat('HH:mm');

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    try {
      await NotificationsService.instance.init();
      final pending = await NotificationsService.instance.flutterLocalNotificationsPlugin.pendingNotificationRequests();
      final scheduledUntil = await NotificationsService.instance.getScheduledUntil();
      final prefs = await SharedPreferences.getInstance();

      setState(() {
        _pending = pending;
        _scheduledUntil = scheduledUntil;
        _prefs = {
          'workSystem': prefs.getString('workSystem') ?? '',
          'startDate': prefs.getString('startDate') ?? '',
          'maintenanceInterval': prefs.getInt('maintenanceInterval') ?? 0,
          'morningStart': prefs.getString('morningStart') ?? '07:00 صباحاً',
          'morningCheckIn': prefs.getString('morningCheckIn') ?? '07:30 صباحاً',
          'afternoonStart': prefs.getString('afternoonStart') ?? '15:00 مساءً',
          'afternoonCheckIn': prefs.getString('afternoonCheckIn') ?? '15:30 مساءً',
          'nightStart': prefs.getString('nightStart') ?? '19:00 مساءً',
          'nightCheckIn': prefs.getString('nightCheckIn') ?? '19:30 مساءً',
          'reminder': prefs.getString('reminder') ?? 'نصف ساعة',
        };
      });
    } catch (e, st) {
      debugPrint('[NotificationsDebug] refresh error -> $e\n$st');
    } finally {
      setState(() => _loading = false);
    }
  }

  // helpers copied / adapted from your service so we can reconstruct times
  DateTime _parseTime(DateTime day, String timeText) {
    final parts = timeText.trim().split(' ');
    final hm = parts[0].split(':');
    int hour = int.tryParse(hm[0]) ?? 0;
    int minute = int.tryParse(hm[1]) ?? 0;
    final period = parts.length > 1 ? parts[1] : '';

    if (hour >= 13) {
      // 24-hour provided
    } else {
      if (period.contains('مساء')) {
        if (hour < 12) hour += 12;
      } else if (period.contains('صباح')) {
        if (hour == 12) hour = 0;
      }
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

  // parse payload format set in NotificationsService: "{dayIso}|{offset}|{shift}"
  _ParsedPayload? _parsePayload(String? payload) {
    if (payload == null) return null;
    try {
      final parts = payload.split('|');
      if (parts.length < 3) return null;
      final dayIso = parts[0];
      final offset = int.tryParse(parts[1]) ?? 0;
      final shift = parts.sublist(2).join('|');
      final day = DateTime.tryParse(dayIso);
      if (day == null) return null;
      return _ParsedPayload(day: day, offset: offset, shift: shift);
    } catch (e) {
      debugPrint('[NotificationsDebug] parsePayload error -> $e');
      return null;
    }
  }

  // reconstruct scheduled local DateTime for a payload
  DateTime? _reconstructScheduledLocal(_ParsedPayload p) {
    final day = DateTime(p.day.year, p.day.month, p.day.day);
    final workSystem = _prefs['workSystem'] as String? ?? 'صباحي';
    final morningStart = _prefs['morningStart'] as String? ?? '07:00 صباحاً';
    final morningCheckIn = _prefs['morningCheckIn'] as String? ?? '07:30 صباحاً';
    final afternoonStart = _prefs['afternoonStart'] as String? ?? '15:00 مساءً';
    final afternoonCheckIn = _prefs['afternoonCheckIn'] as String? ?? '15:30 مساءً';
    final nightStart = _prefs['nightStart'] as String? ?? '19:00 مساءً';
    final nightCheckIn = _prefs['nightCheckIn'] as String? ?? '19:30 مساءً';
    final reminder = _prefs['reminder'] as String? ?? 'نصف ساعة';

    DateTime startDT;
    DateTime checkInDT;
    if (p.shift == 'صبح' || p.shift == 'صيانة') {
      startDT = _parseTime(day, morningStart);
      checkInDT = _parseTime(day, morningCheckIn);
    } else if (p.shift == 'عصر') {
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
      1: startDT.subtract(_getReminderDurationFromString(reminder)),
      2: checkInDT,
      3: endDT,
    };

    return times[p.offset];
  }

  // build grouped view data from pending notifications
  Map<String, List<_NotificationRow>> _buildRows() {
    final Map<String, List<_NotificationRow>> map = {};
    for (final p in _pending) {
      final parsed = _parsePayload(p.payload);
      final scheduled = parsed != null ? _reconstructScheduledLocal(parsed) : null;
      final when = scheduled ?? DateTime.now();
      final key = _dateFmt.format(DateTime(when.year, when.month, when.day));
      final row = _NotificationRow(
        id: p.id,
        title: p.title ?? '',
        body: p.body ?? '',
        payload: p.payload,
        scheduledLocal: scheduled,
        parsedPayload: parsed,
      );
      map.putIfAbsent(key, () => []).add(row);
    }

    // sort each group by scheduledLocal
    for (final k in map.keys) {
      map[k]?.sort((a, b) {
        final aT = a.scheduledLocal ?? DateTime.now();
        final bT = b.scheduledLocal ?? DateTime.now();
        return aT.compareTo(bT);
      });
    }

    return map;
  }

  Future<void> _cancelAll() async {
    await NotificationsService.instance.cancelAll();
    await _refresh();
  }

  Future<void> _rescheduleForce() async {
    await NotificationsService.rescheduleAllNotifications(days: 60, forceClear: true);
    await _refresh();
  }

  Future<void> _showTest() async {
    await NotificationsService.instance.showImmediateNotification(
      id: DateTime.now().millisecondsSinceEpoch.remainder(100000),
      title: 'إختبار إشعار (يدوي)',
      body: 'هذا إشعار تجريبي من شاشة التفاصيل',
      payload: 'debug_test',
    );
  }

  Future<void> _copyCsv() async {
    final rows = _buildRows();
    final sb = StringBuffer();
    sb.writeln('date,id,title,body,payload,scheduled_local');
    final keys = rows.keys.toList()..sort();
    for (final key in keys) {
      for (final r in rows[key]!) {
        final sched = r.scheduledLocal != null ? DateFormat('yyyy-MM-dd HH:mm:ss').format(r.scheduledLocal!) : '';
        final line = '"$key",${r.id},"${r.title}","${r.body}","${r.payload}","$sched"';
        sb.writeln(line);
      }
    }
    await Clipboard.setData(ClipboardData(text: sb.toString()));
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('CSV copied to clipboard')));
  }

  @override
  Widget build(BuildContext context) {
    final grouped = _buildRows();
    final total = _pending.length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('تفاصيل الإشعارات'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _refresh),
          IconButton(icon: const Icon(Icons.copy_all), onPressed: _copyCsv),
          PopupMenuButton<String>(
            onSelected: (v) async {
              if (v == 'cancel_all') await _cancelAll();
              if (v == 'reschedule') await _rescheduleForce();
              if (v == 'show_test') await _showTest();
              await _refresh();
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'show_test', child: Text('عرض إشعار إختباري')),
              const PopupMenuItem(value: 'reschedule', child: Text('إعادة جدولة بالقوة')),
              const PopupMenuItem(value: 'cancel_all', child: Text('إلغاء كل الإشعارات')),
            ],
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Pending count: $total', style: const TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      Text('Scheduled until: ${_scheduledUntil != null ? DateFormat('yyyy-MM-dd').format(_scheduledUntil!) : 'غير معروف'}'),
                    ]),
                    ElevatedButton(onPressed: _refresh, child: const Text('تحديث')),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: grouped.isEmpty
                  ? const Center(child: Text('لا توجد إشعارات مجدولة'))
                  : ListView.builder(
                itemCount: grouped.keys.length,
                itemBuilder: (context, idx) {
                  final keysSorted = grouped.keys.toList()..sort();
                  final dateKey = keysSorted[idx];
                  final rows = grouped[dateKey]!;
                  return Card(
                    margin: const EdgeInsets.symmetric(vertical: 8),
                    child: ExpansionTile(
                      initiallyExpanded: true,
                      title: Row(
                        children: [
                          Text(dateKey, style: const TextStyle(fontWeight: FontWeight.bold)),
                          const SizedBox(width: 8),
                          Text('(${rows.length})'),
                        ],
                      ),
                      children: rows.map((r) {
                        final sched = r.scheduledLocal;
                        final schedTxt = sched != null ? DateFormat('yyyy-MM-dd HH:mm').format(sched) : 'غير متاح';
                        final parsed = r.parsedPayload;
                        return ListTile(
                          title: Text(r.title.isNotEmpty ? r.title : 'بدون عنوان'),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(r.body),
                              const SizedBox(height: 4),
                              Text('تاريخ/وقت: $schedTxt'),
                              if (parsed != null) Text('نوع النوبة: ${parsed.shift}، offset=${parsed.offset}'),
                              Text('id=${r.id} payload=${r.payload ?? ''}'),
                            ],
                          ),
                          isThreeLine: true,
                          trailing: PopupMenuButton<String>(
                            onSelected: (v) async {
                              if (v == 'cancel') {
                                await NotificationsService.instance.flutterLocalNotificationsPlugin.cancel(r.id);
                                await _refresh();
                              }
                            },
                            itemBuilder: (_) => [
                              const PopupMenuItem(value: 'cancel', child: Text('إلغاء هذا الإشعار')),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ParsedPayload {
  final DateTime day;
  final int offset;
  final String shift;
  _ParsedPayload({required this.day, required this.offset, required this.shift});
}

class _NotificationRow {
  final int id;
  final String title;
  final String body;
  final String? payload;
  final DateTime? scheduledLocal;
  final _ParsedPayload? parsedPayload;
  _NotificationRow({
    required this.id,
    required this.title,
    required this.body,
    required this.payload,
    required this.scheduledLocal,
    required this.parsedPayload,
  });
}
