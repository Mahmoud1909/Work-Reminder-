// lib/screens/add_vacation_page.dart
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'vacation_manager.dart';
import '../service/notifications_service.dart';

class AddVacationPage extends StatefulWidget {
  final Vacation? existingVacation;

  const AddVacationPage({super.key, this.existingVacation});

  @override
  State<AddVacationPage> createState() => _AddVacationPageState();
}

class _AddVacationPageState extends State<AddVacationPage> {
  String selectedType = 'emergency';
  DateTime? startDate;
  DateTime? endDate;
  final TextEditingController notesController = TextEditingController();
  bool isLoading = false;
  List<Vacation> existingVacations = [];
  List<Vacation> conflictingVacations = [];

  final Map<String, String> vacationTypes = {
    'emergency': 'إجازة طارئة',
    'sick': 'إجازة مرضية',
    'annual': 'إجازة دورية',
  };

  bool get isEditing => widget.existingVacation != null;

  @override
  void initState() {
    super.initState();
    _loadExistingVacations();

    if (isEditing) {
      final vacation = widget.existingVacation!;
      selectedType = vacation.type;
      startDate = vacation.startDate;
      endDate = vacation.endDate;
      notesController.text = vacation.notes ?? '';
    }
  }

  @override
  void dispose() {
    notesController.dispose();
    super.dispose();
  }

  Future<void> _loadExistingVacations() async {
    debugPrint('AddVacationPage: loading existing vacations...');
    existingVacations = await VacationManager.getAllVacationsSorted();
    debugPrint('AddVacationPage: loaded ${existingVacations.length} vacations.');
    setState(() {});
  }

  void _checkForConflicts() {
    if (startDate == null || endDate == null) {
      setState(() {
        conflictingVacations = [];
      });
      return;
    }

    final tempVacation = Vacation(
      id: isEditing ? widget.existingVacation!.id : '',
      type: selectedType,
      startDate: startDate!,
      endDate: endDate!,
    );

    conflictingVacations = existingVacations.where((vacation) {
      // ignore current when editing
      if (isEditing && vacation.id == widget.existingVacation!.id) {
        return false;
      }
      return tempVacation.overlaps(vacation);
    }).toList();

    debugPrint('AddVacationPage: conflict check -> ${conflictingVacations.length} conflicts found.');
    setState(() {});
  }

  Future<void> _selectStartDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: startDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      helpText: 'اختر تاريخ البداية',
      confirmText: 'موافق',
      cancelText: 'إلغاء',
    );

    if (picked != null) {
      setState(() {
        startDate = picked;
        if (endDate == null || endDate!.isBefore(picked)) {
          endDate = picked;
        }
      });
      _checkForConflicts();
    }
  }

  Future<void> _selectEndDate() async {
    if (startDate == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('اختر تاريخ البداية أولاً')));
      return;
    }

    final picked = await showDatePicker(
      context: context,
      initialDate: endDate ?? startDate!,
      firstDate: startDate!,
      lastDate: DateTime(2030),
      helpText: 'اختر تاريخ النهاية',
      confirmText: 'موافق',
      cancelText: 'إلغاء',
    );

    if (picked != null) {
      setState(() {
        endDate = picked;
      });
      _checkForConflicts();
    }
  }

  Future<void> _saveVacation() async {
    if (startDate == null || endDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('يجب تحديد تاريخ البداية والنهاية')),
      );
      return;
    }

    if (conflictingVacations.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('لا يمكن حفظ الإجازة بسبب وجود تداخل مع إجازات أخرى'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() {
      isLoading = true;
    });

    Vacation? oldVacation;
    if (isEditing) oldVacation = widget.existingVacation;

    try {
      final currentYear = DateTime.now().year;

      if (selectedType == 'emergency' && startDate!.year == currentYear) {
        final canTake = await VacationManager.canTakeEmergencyLeave(currentYear);
        if (!canTake && !isEditing) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'لقد استنفدت الحد الأقصى للإجازات الطارئة هذا العام (4 أيام)',
              ),
              backgroundColor: Colors.red,
            ),
          );
          setState(() {
            isLoading = false;
          });
          return;
        }

        final stats = await VacationManager.getYearlyStats(currentYear);
        final requestedDays = endDate!.difference(startDate!).inDays + 1;
        final usedDays = stats['emergencyDays'] as int? ?? 0;

        int adjustedUsedDays = usedDays;
        if (isEditing &&
            widget.existingVacation!.type == 'emergency' &&
            widget.existingVacation!.startDate.year == currentYear) {
          adjustedUsedDays -= widget.existingVacation!.durationDays;
        }

        if (adjustedUsedDays + requestedDays > 4) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'الإجازة المطلوبة تتجاوز الحد المسموح. متبقي: ${4 - adjustedUsedDays} أيام',
              ),
              backgroundColor: Colors.orange,
            ),
          );
          setState(() {
            isLoading = false;
          });
          return;
        }
      }

      final vacation = Vacation(
        id: isEditing
            ? widget.existingVacation!.id
            : DateTime.now().millisecondsSinceEpoch.toString(),
        type: selectedType,
        startDate: startDate!,
        endDate: endDate!,
        notes: notesController.text.trim().isEmpty
            ? null
            : notesController.text.trim(),
      );

      if (isEditing) {
        await VacationManager.updateVacation(vacation);
        debugPrint('AddVacationPage: updated vacation id=${vacation.id}');
      } else {
        await VacationManager.addVacation(vacation);
        debugPrint('AddVacationPage: added vacation id=${vacation.id}');
      }

      // === Notifications update: request permission (Android 13) then cancel/reschedule ===
      try {
        debugPrint('AddVacationPage: Starting notification permission request (Android 13+).');
        // requestPermissions returns bool (true = granted) or false on error/denied
        bool permissionGranted = false;
        try {
          permissionGranted = await NotificationsService.instance.requestPermissions();
          debugPrint('AddVacationPage: Notification permission result = $permissionGranted');
        } catch (pErr, pSt) {
          debugPrint('AddVacationPage: requestPermissions threw error -> $pErr\n$pSt');
          permissionGranted = false;
        }

        if (!permissionGranted) {
          debugPrint('AddVacationPage: WARNING - notification permission NOT granted. Notifications may not show.');
        } else {
          debugPrint('AddVacationPage: Notification permission GRANTED.');
        }

        // If editing: cancel notifications for the old vacation range (so days freed become schedulable)
        if (oldVacation != null) {
          debugPrint(
              'AddVacationPage: Cancelling notifications for OLD vacation range ${oldVacation.startDate} -> ${oldVacation.endDate}');
          await NotificationsService.instance
              .cancelNotificationsForRange(oldVacation.startDate, oldVacation.endDate);
          debugPrint('AddVacationPage: Cancelled notifications for old vacation.');
        }

        // Always cancel notifications for new vacation range (prevent reminders during vacation)
        debugPrint(
            'AddVacationPage: Cancelling notifications for NEW vacation range ${vacation.startDate} -> ${vacation.endDate}');
        await NotificationsService.instance
            .cancelNotificationsForRange(vacation.startDate, vacation.endDate);
        debugPrint('AddVacationPage: Cancelled notifications for new vacation range.');

        // Re-schedule a short-range window (60 days) after the vacation change.
        // This is idempotent and will skip vacation days automatically.
        debugPrint('AddVacationPage: Rescheduling next 60 days (vacation-aware).');
        await NotificationsService.instance.scheduleNextNDays(60);
        debugPrint('AddVacationPage: Rescheduling completed.');
      } catch (nErr, nSt) {
        debugPrint('AddVacationPage: Notifications update error -> $nErr\n$nSt');
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isEditing
                  ? 'تم تعديل ${vacation.typeNameArabic} بنجاح'
                  : 'تم إضافة ${vacation.typeNameArabic} بنجاح',
            ),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (e, st) {
      debugPrint('AddVacationPage: save error -> $e\n$st');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ في ${isEditing ? "تعديل" : "حفظ"} الإجازة: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }

    setState(() {
      isLoading = false;
    });
  }

  Widget _buildTypeSelector() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'نوع الإجازة',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            ...vacationTypes.entries.map((entry) {
              return RadioListTile<String>(
                title: Text(entry.value),
                value: entry.key,
                groupValue: selectedType,
                onChanged: (value) {
                  setState(() {
                    selectedType = value!;
                  });
                  _checkForConflicts();
                },
              );
            }).toList(),
          ],
        ),
      ),
    );
  }

  Widget _buildDateSelector() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'التواريخ',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _selectStartDate,
                    icon: const Icon(Icons.calendar_today),
                    label: Text(
                      startDate == null
                          ? 'تاريخ البداية'
                          : '${startDate!.day}/${startDate!.month}/${startDate!.year}',
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _selectEndDate,
                    icon: const Icon(Icons.calendar_today),
                    label: Text(
                      endDate == null
                          ? 'تاريخ النهاية'
                          : '${endDate!.day}/${endDate!.month}/${endDate!.year}',
                    ),
                  ),
                ),
              ],
            ),
            if (startDate != null && endDate != null) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'عدد الأيام: ${endDate!.difference(startDate!).inDays + 1}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildConflictWarning() {
    if (conflictingVacations.isEmpty) return const SizedBox();

    return Card(
      color: Colors.red[50],
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: const [
                Icon(Icons.warning, color: Colors.red),
                SizedBox(width: 8),
                Text(
                  'تحذير: يوجد تداخل مع إجازات أخرى',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.red,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ...conflictingVacations
                .map(
                  (vacation) => Padding(
                padding: const EdgeInsets.only(bottom: 8.0),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red.withOpacity(0.3)),
                  ),
                  child: Text(
                    '${vacation.typeNameArabic}: من ${vacation.startDate.day}/${vacation.startDate.month}/${vacation.startDate.year} إلى ${vacation.endDate.day}/${vacation.endDate.month}/${vacation.endDate.year}',
                    style: const TextStyle(color: Colors.red),
                  ),
                ),
              ),
            )
                .toList(),
          ],
        ),
      ),
    );
  }

  Widget _buildNotesField() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'ملاحظة (اختيارية)',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: notesController,
              maxLines: 3,
              decoration: const InputDecoration(
                hintText: 'اكتب ملاحظة حول الإجازة...',
                border: OutlineInputBorder(),
              ),
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
        title: Text(isEditing ? 'تعديل الإجازة' : 'إضافة إجازة'),
        backgroundColor: Colors.blue[50],
        actions: [
          if (isEditing)
            IconButton(
              icon: const Icon(Icons.delete, color: Colors.red),
              onPressed: () async {
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('حذف الإجازة'),
                    content: const Text('هل أنت متأكد من حذف هذه الإجازة؟'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('إلغاء'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('حذف'),
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.red,
                        ),
                      ),
                    ],
                  ),
                );

                if (confirm == true) {
                  try {
                    final vacToDelete = widget.existingVacation!;
                    await VacationManager.removeVacation(vacToDelete.id);
                    debugPrint('AddVacationPage: deleted vacation id=${vacToDelete.id}');

                    try {
                      debugPrint('AddVacationPage: cancelling notifications for deleted vacation range ${vacToDelete.startDate} -> ${vacToDelete.endDate}');
                      await NotificationsService.instance
                          .cancelNotificationsForRange(vacToDelete.startDate, vacToDelete.endDate);
                      debugPrint('AddVacationPage: scheduling next 60 days after deletion.');
                      await NotificationsService.instance.scheduleNextNDays(60);
                      debugPrint('AddVacationPage: notifications updated after deletion.');
                    } catch (e, st) {
                      debugPrint('AddVacationPage: notification update error after deletion: $e\n$st');
                    }

                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('تم حذف الإجازة بنجاح'),
                          backgroundColor: Colors.green,
                        ),
                      );
                      Navigator.pop(context, true);
                    }
                  } catch (e, st) {
                    debugPrint('AddVacationPage: deletion error -> $e\n$st');
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('خطأ في حذف الإجازة: $e'),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                  }
                }
              },
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            _buildTypeSelector(),
            const SizedBox(height: 16),
            _buildDateSelector(),
            const SizedBox(height: 16),
            _buildConflictWarning(),
            const SizedBox(height: 16),
            _buildNotesField(),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: isLoading || conflictingVacations.isNotEmpty
                    ? null
                    : _saveVacation,
                icon: isLoading
                    ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
                    : Icon(isEditing ? Icons.edit : Icons.save),
                label: Text(
                  isLoading
                      ? (isEditing ? 'جاري التعديل...' : 'جاري الحفظ...')
                      : (isEditing ? 'تعديل الإجازة' : 'حفظ الإجازة'),
                ),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.all(16),
                  textStyle: const TextStyle(fontSize: 16),
                  backgroundColor: conflictingVacations.isNotEmpty
                      ? Colors.grey
                      : null,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
