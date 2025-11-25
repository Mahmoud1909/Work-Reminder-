import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../screens/vacation_manager.dart';

class VacationStatsPage extends StatefulWidget {
  const VacationStatsPage({super.key});

  @override
  State<VacationStatsPage> createState() => _VacationStatsPageState();
}

class _VacationStatsPageState extends State<VacationStatsPage> {
  int selectedYear = DateTime.now().year;
  Map<String, dynamic>? stats;
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    setState(() {
      isLoading = true;
    });

    try {
      final yearlyStats = await VacationManager.getYearlyStats(selectedYear);
      setState(() {
        stats = yearlyStats;
        isLoading = false;
      });
    } catch (e) {
      setState(() {
        isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('خطأ في تحميل الإحصائيات: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Widget _buildYearSelector() {
    final currentYear = DateTime.now().year;
    final years = List.generate(10, (index) => currentYear - index);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'السنة:',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            DropdownButton<int>(
              value: selectedYear,
              items: years.map((year) {
                return DropdownMenuItem(value: year, child: Text('$year'));
              }).toList(),
              onChanged: (value) {
                if (value != null) {
                  setState(() {
                    selectedYear = value;
                  });
                  _loadStats();
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatCard({
    required String title,
    required String count,
    required Color color,
    required List<DateTime> dates,
    String? warning,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  count,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
              ],
            ),
            if (warning != null) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange.withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.warning, color: Colors.orange, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        warning,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.orange,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (dates.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border(left: BorderSide(color: color, width: 3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'التواريخ المستخدمة:',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: dates.map((date) {
                        final formattedDate = DateFormat(
                          'd/M/yyyy',
                        ).format(date);
                        return Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: color.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            formattedDate,
                            style: TextStyle(
                              fontSize: 12,
                              color: color.withOpacity(0.8),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('إحصائيات الإجازات'),
        backgroundColor: Colors.blue[50],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : stats == null
          ? const Center(child: Text('لا توجد بيانات'))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  _buildYearSelector(),
                  const SizedBox(height: 16),

                  // إحصائيات الإجازات الطارئة
                  _buildStatCard(
                    title: 'الإجازات الطارئة:',
                    count: '${stats!['emergencyDays']} من 4 أيام',
                    color: Colors.red,
                    dates: List<DateTime>.from(stats!['emergencyDates']),
                    warning: stats!['emergencyDays'] >= 3
                        ? 'تبقى لك ${4 - stats!['emergencyDays']} أيام طوارئ فقط هذا العام'
                        : null,
                  ),

                  const SizedBox(height: 16),

                  // إحصائيات الإجازات المرضية
                  _buildStatCard(
                    title: 'الإجازات المرضية (براتب كامل):',
                    count: '${stats!['sickDaysWithSalary']} من 15 يوم',
                    color: Colors.orange,
                    dates: List<DateTime>.from(stats!['sickDates']),
                    warning: stats!['sickDaysWithSalary'] >= 12
                        ? 'تبقى لك ${15 - stats!['sickDaysWithSalary']} أيام مرضية براتب كامل'
                        : null,
                  ),

                  // إحصائيات الإجازات المرضية الإضافية
                  if (stats!['sickDaysWithoutSalary'] > 0) ...[
                    const SizedBox(height: 16),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'الإجازات المرضية الإضافية:',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              '${stats!['sickDaysWithoutSalary']} أيام',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.red,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],

                  const SizedBox(height: 16),

                  // إحصائيات الإجازات الدورية
                  _buildStatCard(
                    title: 'الإجازات الدورية:',
                    count: '${stats!['annualDays']} أيام',
                    color: Colors.purple,
                    dates: List<DateTime>.from(stats!['annualDates']),
                  ),

                  const SizedBox(height: 20),

                  // معلومات إضافية
                  Card(
                    color: Colors.blue[50],
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'معلومات مهمة:',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            '• الإجازات الطارئة: 4 أيام سنوياً كحد أقصى',
                          ),
                          const Text(
                            '• الإجازات المرضية: 15 يوم براتب كامل، ثم بدون راتب',
                          ),
                          const Text('• الإجازات الدورية: بدون حد أقصى'),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
