import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'calendar_page.dart';
import '../screens/settings_page.dart';

class DashboardPage extends StatefulWidget {
  final Map<DateTime, String> schedule;
  final Color morningColor;
  final Color afternoonColor;
  final Color nightColor;
  final Color restColor;
  final Color maintenanceColor; // إضافة لون الصيانة

  const DashboardPage({
    super.key,
    required this.schedule,
    required this.morningColor,
    required this.afternoonColor,
    required this.nightColor,
    required this.restColor,
    required this.maintenanceColor,
  });

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  late DateTime today;
  String? todayShift;
  String? nextShift;
  Duration? countdown;

  @override
  void initState() {
    super.initState();
    today = DateTime.now();
    _loadShifts();
  }

  void _loadShifts() {
    final key = DateTime.utc(today.year, today.month, today.day);
    todayShift = widget.schedule[key];

    // ابحث عن النوبة القادمة
    for (int i = 1; i < 30; i++) {
      final nextDay = today.add(Duration(days: i));
      final shift = widget
          .schedule[DateTime.utc(nextDay.year, nextDay.month, nextDay.day)];
      if (shift != null && shift != "راحة") {
        String shiftText = shift;
        if (shift == 'صيانة') shiftText = 'عمل صيانة';

        nextShift =
            "$shiftText (${nextDay.toLocal().toString().split(" ")[0]})";
        countdown = nextDay.difference(today);
        break;
      }
    }
    setState(() {});
  }

  Future<void> _resetSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear(); // مسح الإعدادات
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const SettingsPage()),
    );
  }

  // دالة لعرض إحصائيات سريعة
  Widget _buildQuickStats() {
    final now = DateTime.now();
    final startOfWeek = now.subtract(Duration(days: now.weekday % 7));
    final endOfWeek = startOfWeek.add(const Duration(days: 6));

    int workDays = 0;
    int restDays = 0;
    int maintenanceDays = 0;

    for (int i = 0; i < 7; i++) {
      final day = startOfWeek.add(Duration(days: i));
      final key = DateTime.utc(day.year, day.month, day.day);
      final shift = widget.schedule[key];

      if (shift == 'راحة') {
        restDays++;
      } else if (shift == 'صيانة') {
        maintenanceDays++;
      } else if (shift != null) {
        workDays++;
      }
    }

    return Card(
      margin: const EdgeInsets.all(16.0),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "إحصائيات هذا الأسبوع",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildStatCard("أيام العمل", workDays, Icons.work, Colors.blue),
                _buildStatCard(
                  "أيام الصيانة",
                  maintenanceDays,
                  Icons.build,
                  widget.maintenanceColor,
                ),
                _buildStatCard(
                  "أيام الراحة",
                  restDays,
                  Icons.home,
                  widget.restColor,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatCard(String title, int count, IconData icon, Color color) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: color, size: 30),
        ),
        const SizedBox(height: 8),
        Text(
          '$count',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(
          title,
          style: const TextStyle(fontSize: 12, color: Colors.grey),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  // دالة لعرض معلومات النوبة الحالية
  Widget _buildCurrentShiftCard() {
    String emoji = '';
    String shiftText = todayShift ?? 'راحة';
    Color shiftColor = widget.restColor;

    switch (todayShift) {
      case 'صبح':
        emoji = '🌅';
        shiftColor = widget.morningColor;
        break;
      case 'عصر':
        emoji = '🌇';
        shiftColor = widget.afternoonColor;
        break;
      case 'ليل':
        emoji = '🌙';
        shiftColor = widget.nightColor;
        break;
      case 'صيانة':
        emoji = '🔧';
        shiftText = 'عمل صيانة';
        shiftColor = widget.maintenanceColor;
        break;
      case 'راحة':
      default:
        emoji = '🏡';
        shiftColor = widget.restColor;
        break;
    }

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16.0),
      color: shiftColor.withOpacity(0.1),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            Text(emoji, style: const TextStyle(fontSize: 48)),
            const SizedBox(height: 8),
            Text(
              "اليوم: $shiftText",
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: shiftColor,
              ),
            ),
            Text(
              "${today.toLocal().toString().split(' ')[0]}",
              style: const TextStyle(fontSize: 16, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("لوحة التحكم"),
        backgroundColor: Colors.blue[50],
        elevation: 0,
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            const SizedBox(height: 20),

            // معلومات النوبة الحالية
            _buildCurrentShiftCard(),

            const SizedBox(height: 20),

            // معلومات النوبة القادمة
            if (nextShift != null)
              Card(
                margin: const EdgeInsets.symmetric(horizontal: 16.0),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    children: [
                      const Icon(
                        Icons.schedule,
                        size: 40,
                        color: Colors.orange,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        "النوبة القادمة",
                        style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        nextShift!,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      if (countdown != null)
                        Text(
                          "خلال ${countdown!.inHours} ساعة",
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey[600],
                          ),
                        ),
                    ],
                  ),
                ),
              ),

            const SizedBox(height: 20),

            // إحصائيات الأسبوع
            _buildQuickStats(),

            const SizedBox(height: 20),

            // أزرار الإجراءات
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => CalendarPage(
                              schedule: widget.schedule,
                              morningColor: widget.morningColor,
                              afternoonColor: widget.afternoonColor,
                              nightColor: widget.nightColor,
                              restColor: widget.restColor,
                              maintenanceColor: widget.maintenanceColor,
                            ),
                          ),
                        );
                      },
                      icon: const Icon(Icons.calendar_month),
                      label: const Text("عرض التقويم"),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.all(16),
                        textStyle: const TextStyle(fontSize: 16),
                      ),
                    ),
                  ),

                  const SizedBox(height: 12),

                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const SettingsPage(),
                          ),
                        );
                      },
                      icon: const Icon(Icons.settings),
                      label: const Text("تعديل الإعدادات"),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.grey[600],
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.all(16),
                        textStyle: const TextStyle(fontSize: 16),
                      ),
                    ),
                  ),

                  const SizedBox(height: 12),

                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        final confirm = await showDialog<bool>(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: const Text("تأكيد إعادة الضبط"),
                            content: const Text(
                              "هل أنت متأكد من إعادة ضبط جميع الإعدادات؟ سيتم فقدان جميع البيانات المحفوظة.",
                            ),
                            actions: [
                              TextButton(
                                onPressed: () =>
                                    Navigator.of(context).pop(false),
                                child: const Text("إلغاء"),
                              ),
                              TextButton(
                                onPressed: () =>
                                    Navigator.of(context).pop(true),
                                child: const Text("تأكيد"),
                              ),
                            ],
                          ),
                        );

                        if (confirm == true) {
                          _resetSettings();
                        }
                      },
                      icon: const Icon(Icons.restart_alt),
                      label: const Text("إعادة ضبط الإعدادات"),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.all(16),
                        textStyle: const TextStyle(fontSize: 16),
                        foregroundColor: Colors.red,
                        side: const BorderSide(color: Colors.red),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}
