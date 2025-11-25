import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

// فئة لتمثيل الإجازة
class Vacation {
  final String id;
  final String type; // 'emergency', 'sick', 'annual'
  final DateTime startDate;
  final DateTime endDate;
  final String? notes;

  Vacation({
    required this.id,
    required this.type,
    required this.startDate,
    required this.endDate,
    this.notes,
  });

  // تحويل لـ JSON للحفظ
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type,
      'startDate': startDate.toIso8601String(),
      'endDate': endDate.toIso8601String(),
      'notes': notes,
    };
  }

  // إنشاء من JSON للقراءة
  factory Vacation.fromJson(Map<String, dynamic> json) {
    return Vacation(
      id: json['id'],
      type: json['type'],
      startDate: DateTime.parse(json['startDate']),
      endDate: DateTime.parse(json['endDate']),
      notes: json['notes'],
    );
  }

  // حساب عدد الأيام
  int get durationDays {
    return endDate.difference(startDate).inDays + 1;
  }

  // النص باللغة العربية
  String get typeNameArabic {
    switch (type) {
      case 'emergency':
        return 'طارئة';
      case 'sick':
        return 'مرضية';
      case 'annual':
        return 'دورية';
      default:
        return type;
    }
  }

  // التحقق من وجود تداخل مع إجازة أخرى
  bool overlaps(Vacation other) {
    final thisStart = DateTime(startDate.year, startDate.month, startDate.day);
    final thisEnd = DateTime(endDate.year, endDate.month, endDate.day);
    final otherStart = DateTime(
      other.startDate.year,
      other.startDate.month,
      other.startDate.day,
    );
    final otherEnd = DateTime(
      other.endDate.year,
      other.endDate.month,
      other.endDate.day,
    );

    return !(thisEnd.isBefore(otherStart) || thisStart.isAfter(otherEnd));
  }

  // التحقق من وجود تاريخ محدد ضمن فترة الإجازة
  bool containsDate(DateTime date) {
    final targetDate = DateTime(date.year, date.month, date.day);
    final startNormalized = DateTime(
      startDate.year,
      startDate.month,
      startDate.day,
    );
    final endNormalized = DateTime(endDate.year, endDate.month, endDate.day);

    return !targetDate.isBefore(startNormalized) &&
        !targetDate.isAfter(endNormalized);
  }
}

// مدير الإجازات
class VacationManager {
  static const String _keyVacations = 'vacations';

  // حفظ الإجازات
  static Future<void> saveVacations(List<Vacation> vacations) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonList = vacations.map((v) => v.toJson()).toList();
    await prefs.setString(_keyVacations, jsonEncode(jsonList));
  }

  // تحميل الإجازات
  static Future<List<Vacation>> loadVacations() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString(_keyVacations);

    if (jsonString == null) return [];

    final jsonList = jsonDecode(jsonString) as List;
    return jsonList.map((json) => Vacation.fromJson(json)).toList();
  }

  // التحقق من وجود تداخل في الإجازات
  static Future<Vacation?> checkForOverlap(
    Vacation newVacation, {
    String? excludeId,
  }) async {
    final existingVacations = await loadVacations();

    for (final vacation in existingVacations) {
      // تجاهل الإجازة المحددة للاستثناء (عند التعديل)
      if (excludeId != null && vacation.id == excludeId) continue;

      if (newVacation.overlaps(vacation)) {
        return vacation;
      }
    }
    return null;
  }

  // إضافة إجازة جديدة مع التحقق من التداخل
  static Future<bool> addVacation(Vacation vacation) async {
    // التحقق من وجود تداخل
    final overlappingVacation = await checkForOverlap(vacation);
    if (overlappingVacation != null) {
      throw Exception(
        'يوجد تداخل مع إجازة ${overlappingVacation.typeNameArabic} من ${_formatDate(overlappingVacation.startDate)} إلى ${_formatDate(overlappingVacation.endDate)}',
      );
    }

    final vacations = await loadVacations();
    vacations.add(vacation);
    await saveVacations(vacations);
    return true;
  }

  // تعديل إجازة موجودة
  static Future<bool> updateVacation(Vacation updatedVacation) async {
    // التحقق من وجود تداخل (مع استثناء الإجازة الحالية)
    final overlappingVacation = await checkForOverlap(
      updatedVacation,
      excludeId: updatedVacation.id,
    );
    if (overlappingVacation != null) {
      throw Exception(
        'يوجد تداخل مع إجازة ${overlappingVacation.typeNameArabic} من ${_formatDate(overlappingVacation.startDate)} إلى ${_formatDate(overlappingVacation.endDate)}',
      );
    }

    final vacations = await loadVacations();
    final index = vacations.indexWhere((v) => v.id == updatedVacation.id);

    if (index == -1) {
      throw Exception('الإجازة غير موجودة');
    }

    vacations[index] = updatedVacation;
    await saveVacations(vacations);
    return true;
  }

  // حذف إجازة
  static Future<void> removeVacation(String id) async {
    final vacations = await loadVacations();
    vacations.removeWhere((v) => v.id == id);
    await saveVacations(vacations);
  }

  // الحصول على جميع الإجازات مرتبة بالتاريخ
  static Future<List<Vacation>> getAllVacationsSorted() async {
    final vacations = await loadVacations();
    vacations.sort(
      (a, b) => b.startDate.compareTo(a.startDate),
    ); // ترتيب تنازلي حسب التاريخ
    return vacations;
  }

  // فحص إذا كان التاريخ إجازة
  static Future<Vacation?> getVacationForDate(DateTime date) async {
    final vacations = await loadVacations();

    for (final vacation in vacations) {
      if (vacation.containsDate(date)) {
        return vacation;
      }
    }
    return null;
  }

  // الحصول على جميع الإجازات في فترة محددة
  static Future<List<Vacation>> getVacationsInRange(
    DateTime startDate,
    DateTime endDate,
  ) async {
    final vacations = await loadVacations();
    final rangeVacations = <Vacation>[];

    for (final vacation in vacations) {
      // التحقق من وجود أي تداخل مع الفترة المحددة
      if (!(vacation.endDate.isBefore(startDate) ||
          vacation.startDate.isAfter(endDate))) {
        rangeVacations.add(vacation);
      }
    }

    return rangeVacations;
  }

  // إحصائيات الإجازات لسنة محددة
  static Future<Map<String, dynamic>> getYearlyStats(int year) async {
    final vacations = await loadVacations();
    final yearVacations = vacations
        .where((v) => v.startDate.year == year)
        .toList();

    int emergencyDays = 0;
    int sickDays = 0;
    int annualDays = 0;

    List<DateTime> emergencyDates = [];
    List<DateTime> sickDates = [];
    List<DateTime> annualDates = [];

    for (final vacation in yearVacations) {
      final dates = _getDateRange(vacation.startDate, vacation.endDate);

      switch (vacation.type) {
        case 'emergency':
          emergencyDays += vacation.durationDays;
          emergencyDates.addAll(dates);
          break;
        case 'sick':
          sickDays += vacation.durationDays;
          sickDates.addAll(dates);
          break;
        case 'annual':
          annualDays += vacation.durationDays;
          annualDates.addAll(dates);
          break;
      }
    }

    return {
      'emergencyDays': emergencyDays,
      'sickDays': sickDays,
      'annualDays': annualDays,
      'emergencyDates': emergencyDates,
      'sickDates': sickDates,
      'annualDates': annualDates,
      'sickDaysWithSalary': sickDays > 15 ? 15 : sickDays,
      'sickDaysWithoutSalary': sickDays > 15 ? sickDays - 15 : 0,
    };
  }

  // إنشاء قائمة بالتواريخ بين تاريخين
  static List<DateTime> _getDateRange(DateTime startDate, DateTime endDate) {
    final dates = <DateTime>[];
    var currentDate = startDate;

    while (!currentDate.isAfter(endDate)) {
      dates.add(DateTime(currentDate.year, currentDate.month, currentDate.day));
      currentDate = currentDate.add(const Duration(days: 1));
    }

    return dates;
  }

  // التحقق من إمكانية أخذ إجازة طارئة
  static Future<bool> canTakeEmergencyLeave(int year) async {
    final stats = await getYearlyStats(year);
    return stats['emergencyDays'] < 4;
  }

  // التحقق من الإجازات المرضية المتبقية براتب كامل
  static Future<int> getRemainingPaidSickLeave(int year) async {
    final stats = await getYearlyStats(year);
    final usedDays = stats['sickDays'] as int;
    return usedDays >= 15 ? 0 : 15 - usedDays;
  }

  // دالة مساعدة لتنسيق التاريخ
  static String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }

  // البحث عن الإجازات حسب النوع
  static Future<List<Vacation>> getVacationsByType(
    String type, {
    int? year,
  }) async {
    final vacations = await loadVacations();
    return vacations.where((v) {
      if (v.type != type) return false;
      if (year != null && v.startDate.year != year) return false;
      return true;
    }).toList();
  }

  // حساب عدد أيام الإجازة المستخدمة في شهر محدد
  static Future<Map<String, int>> getMonthlyStats(int year, int month) async {
    final vacations = await loadVacations();
    final stats = <String, int>{'emergency': 0, 'sick': 0, 'annual': 0};

    for (final vacation in vacations) {
      // التحقق من وجود تداخل مع الشهر المحدد
      final monthStart = DateTime(year, month, 1);
      final monthEnd = DateTime(year, month + 1, 0);

      if (!(vacation.endDate.isBefore(monthStart) ||
          vacation.startDate.isAfter(monthEnd))) {
        // حساب عدد الأيام التي تقع في هذا الشهر
        final overlapStart = vacation.startDate.isAfter(monthStart)
            ? vacation.startDate
            : monthStart;
        final overlapEnd = vacation.endDate.isBefore(monthEnd)
            ? vacation.endDate
            : monthEnd;

        final daysInMonth = overlapEnd.difference(overlapStart).inDays + 1;
        stats[vacation.type] = (stats[vacation.type] ?? 0) + daysInMonth;
      }
    }

    return stats;
  }
}
