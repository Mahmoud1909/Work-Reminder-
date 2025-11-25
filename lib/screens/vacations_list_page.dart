// lib/screens/vacations_list_page.dart
import 'package:flutter/material.dart';
import 'vacation_manager.dart';
import 'add_vacation_page.dart';
import '../service/notifications_service.dart';
import 'package:flutter/foundation.dart' show debugPrint;

class VacationsListPage extends StatefulWidget {
  const VacationsListPage({super.key});

  @override
  State<VacationsListPage> createState() => _VacationsListPageState();
}

class _VacationsListPageState extends State<VacationsListPage> {
  List<Vacation> vacations = [];
  bool isLoading = true;
  String selectedFilter = 'all'; // all, emergency, sick, annual

  final Map<String, String> filterOptions = {
    'all': 'جميع الإجازات',
    'emergency': 'الإجازات الطارئة',
    'sick': 'الإجازات المرضية',
    'annual': 'الإجازات الدورية',
  };

  @override
  void initState() {
    super.initState();
    _loadVacations();
  }

  Future<void> _loadVacations() async {
    setState(() {
      isLoading = true;
    });

    try {
      final allVacations = await VacationManager.getAllVacationsSorted();
      setState(() {
        vacations = allVacations;
        isLoading = false;
      });
      debugPrint('VacationsListPage: loaded ${vacations.length} vacations.');
    } catch (e) {
      setState(() {
        isLoading = false;
      });
      debugPrint('VacationsListPage: error loading vacations: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('خطأ في تحميل الإجازات: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  List<Vacation> get filteredVacations {
    if (selectedFilter == 'all') return vacations;
    return vacations.where((v) => v.type == selectedFilter).toList();
  }

  Color _getVacationColor(String type) {
    switch (type) {
      case 'emergency':
        return Colors.red;
      case 'sick':
        return Colors.orange;
      case 'annual':
        return Colors.purple;
      default:
        return Colors.grey;
    }
  }

  IconData _getVacationIcon(String type) {
    switch (type) {
      case 'emergency':
        return Icons.warning;
      case 'sick':
        return Icons.local_hospital;
      case 'annual':
        return Icons.beach_access;
      default:
        return Icons.event;
    }
  }

  String _formatDateRange(DateTime start, DateTime end) {
    if (start.day == end.day &&
        start.month == end.month &&
        start.year == end.year) {
      return '${start.day}/${start.month}/${start.year}';
    }
    return '${start.day}/${start.month}/${start.year} - ${end.day}/${end.month}/${end.year}';
  }

  Widget _buildFilterChips() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: filterOptions.entries.map((entry) {
          final isSelected = selectedFilter == entry.key;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilterChip(
              label: Text(entry.value),
              selected: isSelected,
              onSelected: (selected) {
                setState(() {
                  selectedFilter = entry.key;
                });
              },
              backgroundColor: Colors.grey[200],
              selectedColor: Colors.blue[100],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildVacationCard(Vacation vacation) {
    final color = _getVacationColor(vacation.type);
    final icon = _getVacationIcon(vacation.type);
    final dateRange = _formatDateRange(vacation.startDate, vacation.endDate);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: InkWell(
        onTap: () => _editVacation(vacation),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(icon, color: color, size: 24),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          vacation.typeNameArabic,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: color,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          dateRange,
                          style: const TextStyle(
                            fontSize: 14,
                            color: Colors.grey,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Column(
                    children: [
                      Text(
                        '${vacation.durationDays}',
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Text(
                        'أيام',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ],
                  ),
                ],
              ),
              if (vacation.notes != null && vacation.notes!.isNotEmpty) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey[50],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey[300]!),
                  ),
                  child: Text(
                    vacation.notes!,
                    style: const TextStyle(fontSize: 14),
                  ),
                ),
              ],
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton.icon(
                    onPressed: () => _editVacation(vacation),
                    icon: const Icon(Icons.edit, size: 16),
                    label: const Text('تعديل'),
                    style: TextButton.styleFrom(foregroundColor: Colors.blue),
                  ),
                  const SizedBox(width: 8),
                  TextButton.icon(
                    onPressed: () => _deleteVacation(vacation),
                    icon: const Icon(Icons.delete, size: 16),
                    label: const Text('حذف'),
                    style: TextButton.styleFrom(foregroundColor: Colors.red),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _editVacation(Vacation vacation) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AddVacationPage(existingVacation: vacation),
      ),
    );

    if (result == true) {
      _loadVacations();
    }
  }

  Future<void> _deleteVacation(Vacation vacation) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('حذف الإجازة'),
        content: Text(
          'هل أنت متأكد من حذف ${vacation.typeNameArabic} من ${_formatDateRange(vacation.startDate, vacation.endDate)}؟',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('حذف'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await VacationManager.removeVacation(vacation.id);
        debugPrint('VacationsListPage: removed vacation id=${vacation.id}');

        // -----------------------
        // New: notification update after deletion (step #2)
        // -----------------------
        try {
          debugPrint('VacationsListPage: starting notification update after vacation deletion.');
          debugPrint('VacationsListPage: requesting notification permissions (best-effort).');

          bool permsGranted = false;
          try {
            permsGranted = await NotificationsService.instance.requestPermissions();
            debugPrint('VacationsListPage: requestPermissions returned $permsGranted');
          } catch (e, st) {
            debugPrint('VacationsListPage: requestPermissions error -> $e\n$st');
          }

          debugPrint('VacationsListPage: cancelling notifications for deleted vacation range ${vacation.startDate} -> ${vacation.endDate} (if any).');
          await NotificationsService.instance.cancelNotificationsForRange(vacation.startDate, vacation.endDate);
          debugPrint('VacationsListPage: cancelNotificationsForRange completed for ${vacation.startDate} -> ${vacation.endDate}.');

          debugPrint('VacationsListPage: scheduling next 60 days (short-range reschedule).');
          await NotificationsService.instance.scheduleNextNDays(60);
          debugPrint('VacationsListPage: scheduleNextNDays(60) completed.');

          debugPrint('VacationsListPage: notification update after deletion finished successfully.');
        } catch (e, st) {
          debugPrint('VacationsListPage: notification update error after deletion: $e\n$st');
        }

        // show success to user and refresh UI
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم حذف الإجازة بنجاح'),
            backgroundColor: Colors.green,
          ),
        );
        _loadVacations();

        // If this page was opened as a modal and caller expects a result, return true.
        // Keep existing behavior: pop and return true to the caller.
        Navigator.pop(context, true);
      } catch (e) {
        debugPrint('VacationsListPage: deletion error: $e');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ في حذف الإجازة: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Widget _buildEmptyState() {
    final filteredCount = filteredVacations.length;

    if (vacations.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.event_busy, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              'لا توجد إجازات مسجلة',
              style: TextStyle(fontSize: 18, color: Colors.grey[600]),
            ),
            const SizedBox(height: 8),
            Text(
              'اضغط على زر + لإضافة إجازة جديدة',
              style: TextStyle(fontSize: 14, color: Colors.grey[500]),
            ),
          ],
        ),
      );
    }

    if (filteredCount == 0) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.filter_list_off, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              'لا توجد إجازات تطابق المرشح المحدد',
              style: TextStyle(fontSize: 18, color: Colors.grey[600]),
            ),
          ],
        ),
      );
    }

    return const SizedBox();
  }

  @override
  Widget build(BuildContext context) {
    final filteredCount = filteredVacations.length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('إدارة الإجازات'),
        backgroundColor: Colors.blue[50],
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () async {
              final result = await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const AddVacationPage(),
                ),
              );
              if (result == true) {
                _loadVacations();
              }
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            color: Colors.blue[50],
            child: Column(
              children: [
                _buildFilterChips(),
                const SizedBox(height: 16),
                if (vacations.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'عدد الإجازات: $filteredCount',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (filteredCount > 0)
                          Text(
                            'إجمالي الأيام: ${filteredVacations.fold(0, (sum, v) => sum + v.durationDays)}',
                            style: const TextStyle(
                              fontSize: 14,
                              color: Colors.grey,
                            ),
                          ),
                      ],
                    ),
                  ),
                const SizedBox(height: 16),
              ],
            ),
          ),
          Expanded(
            child: isLoading
                ? const Center(child: CircularProgressIndicator())
                : filteredCount == 0
                ? _buildEmptyState()
                : RefreshIndicator(
              onRefresh: _loadVacations,
              child: ListView.builder(
                itemCount: filteredCount,
                itemBuilder: (context, index) {
                  return _buildVacationCard(filteredVacations[index]);
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
