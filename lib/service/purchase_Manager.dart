// lib/service/purchase_Manager.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:connectivity_plus/connectivity_plus.dart';

import 'notifications_service.dart';

const String kYearlySku = 'work_reminder_yearly';

const String _kPrefsKeySubscription = 'pm_subscription_state';
const String _kPrefsKeyPendingReceipts = 'pm_pending_receipts';

const String _kPrefsKeyTrialStart = 'pm_trial_start';
const String _kPrefsShowUpgradeOnLaunch = 'pm_show_upgrade_on_launch';
const int _kTrialDays = 7;

class SubscriptionState {
  final bool active;
  final DateTime? expiresAt;
  final bool isInTrial;
  final String? platform;
  final String? rawPayload;

  SubscriptionState({
    required this.active,
    this.expiresAt,
    this.isInTrial = false,
    this.platform,
    this.rawPayload,
  });

  Map<String, dynamic> toJson() => {
    'active': active,
    'expiresAt': expiresAt?.toIso8601String(),
    'isInTrial': isInTrial,
    'platform': platform,
    'rawPayload': rawPayload,
  };

  static SubscriptionState fromJson(Map<String, dynamic> j) => SubscriptionState(
    active: j['active'] == true,
    expiresAt: j['expiresAt'] != null ? DateTime.parse(j['expiresAt']) : null,
    isInTrial: j['isInTrial'] == true,
    platform: j['platform'],
    rawPayload: j['rawPayload'],
  );
}

class PendingReceipt {
  final String platform;
  final String productId;
  final String receipt;

  PendingReceipt({required this.platform, required this.productId, required this.receipt});

  Map<String, dynamic> toJson() => {
    'platform': platform,
    'productId': productId,
    'receipt': receipt,
  };

  static PendingReceipt fromJson(Map<String, dynamic> j) => PendingReceipt(
    platform: j['platform'],
    productId: j['productId'],
    receipt: j['receipt'],
  );
}

class PurchaseManager {
  PurchaseManager._internal();
  static final PurchaseManager instance = PurchaseManager._internal();

  final InAppPurchase _iap = InAppPurchase.instance;
  StreamSubscription<List<PurchaseDetails>>? _sub;
  List<ProductDetails> products = [];
  bool _initialized = false;

  SubscriptionState? _cachedState;
  SharedPreferences? _prefs;

  String backendVerifyEndpoint = '';
  String? deviceIdentifier;

  // broadcast stream to notify UI when access changes (true = has access)
  final StreamController<bool> _accessController = StreamController<bool>.broadcast();

  Stream<bool> get accessStream => _accessController.stream;

  /// Initialize — call early
  Future<void> init({required String deviceId}) async {
    if (_initialized) return;
    _initialized = true;
    deviceIdentifier = deviceId;

    _prefs = await SharedPreferences.getInstance();
    _loadLocalState();

    final available = await _iap.isAvailable();
    if (!available) {
      debugPrint('[PurchaseManager] store not available');
    } else {
      await _queryProducts();

      _sub = _iap.purchaseStream.listen(
        _onPurchaseUpdated,
        onDone: () => _sub?.cancel(),
        onError: (e) {
          debugPrint('[PurchaseManager] purchaseStream error: $e');
        },
      );

      // best-effort: restore existing purchases (purchaseStream will emit restored)
      try {
        await _iap.restorePurchases();
      } catch (e) {
        debugPrint('[PurchaseManager] restorePurchases initial failed -> $e');
      }
    }

    // try to flush pending receipts when connectivity available
    Connectivity().onConnectivityChanged.listen((_) async => await sendPendingReceipts());
    await sendPendingReceipts();

    // trial start: only set if no active subscription
    try {
      await ensureTrialStartIfNeeded();
      await checkTrialAndNotifyIfExpired();
    } catch (e) {
      debugPrint('[PurchaseManager] trial init/check failed -> $e');
    }

    // emit initial access state
    _emitAccessChanged();
  }

  Future<void> _queryProducts() async {
    try {
      final response = await _iap.queryProductDetails({kYearlySku});
      products = response.productDetails;
      debugPrint('[PurchaseManager] found products: ${products.map((p) => p.id).toList()}');
    } catch (e) {
      debugPrint('[PurchaseManager] queryProductDetails failed: $e');
    }
  }

  Future<void> buyYearly() async {
    if (products.isEmpty) {
      await _queryProducts();
    }
    final pd = products.firstWhere((p) => p.id == kYearlySku, orElse: () => throw Exception('Product not found'));
    final purchaseParam = PurchaseParam(productDetails: pd);
    try {
      await _iap.buyNonConsumable(purchaseParam: purchaseParam);
    } catch (e) {
      debugPrint('[PurchaseManager] buy failed: $e');
      rethrow;
    }
  }

  Future<void> restorePurchases() async {
    try {
      await _iap.restorePurchases();
    } catch (e) {
      debugPrint('[PurchaseManager] restorePurchases failed: $e');
    }
  }

  Future<void> _onPurchaseUpdated(List<PurchaseDetails> purchaseDetailsList) async {
    for (final pd in purchaseDetailsList) {
      debugPrint('[PurchaseManager] purchase update: ${pd.productID} status=${pd.status}');

      if (pd.status == PurchaseStatus.pending) {
        debugPrint('[PurchaseManager] purchase pending ${pd.productID}');
      } else if (pd.status == PurchaseStatus.error) {
        debugPrint('[PurchaseManager] purchase error: ${pd.error}');
      } else if (pd.status == PurchaseStatus.purchased || pd.status == PurchaseStatus.restored) {
        await _processSuccessfulPurchase(pd);
      }
    }
  }

  Future<void> _processSuccessfulPurchase(PurchaseDetails pd) async {
    final platform = _detectPlatform(pd);
    final receipt = pd.verificationData.serverVerificationData;

    await _enqueueReceipt(platform: platform, productId: pd.productID, receipt: receipt);

    _cachedState = SubscriptionState(
      active: true,
      expiresAt: null,
      isInTrial: false,
      platform: platform,
      rawPayload: receipt,
    );
    await _saveLocalState();

    try {
      await InAppPurchase.instance.completePurchase(pd);
    } catch (e) {
      debugPrint('[PurchaseManager] completePurchase failed: $e');
    }

    try {
      await NotificationsService.instance.cancelDailySubscriptionReminder(markCancelled: true);
    } catch (e) {
      debugPrint('[PurchaseManager] cancelDailySubscriptionReminder failed -> $e');
    }

    if (backendVerifyEndpoint.isNotEmpty) {
      try {
        final success = await _sendReceiptToBackend(platform, pd.productID, receipt);
        debugPrint('[PurchaseManager] backend verify immediate -> $success');
      } catch (e) {
        debugPrint('[PurchaseManager] backend verify immediate failed -> $e');
      }
    }

    // emit change (now has access)
    _emitAccessChanged();
  }

  String _detectPlatform(PurchaseDetails pd) {
    final src = pd.verificationData.source ?? '';
    if (src.toLowerCase().contains('play')) return 'android';
    if (src.toLowerCase().contains('appstore') || src.toLowerCase().contains('ios')) return 'ios';
    return Platform.isAndroid ? 'android' : 'ios';
  }

  Future<void> _enqueueReceipt({required String platform, required String productId, required String receipt}) async {
    final listJson = _prefs?.getStringList(_kPrefsKeyPendingReceipts) ?? <String>[];

    final already = listJson.any((s) {
      try {
        final m = jsonDecode(s) as Map<String, dynamic>;
        return m['receipt'] == receipt;
      } catch (_) {
        return false;
      }
    });
    if (already) return;

    final pending = PendingReceipt(platform: platform, productId: productId, receipt: receipt);
    listJson.add(jsonEncode(pending.toJson()));
    await _prefs?.setStringList(_kPrefsKeyPendingReceipts, listJson);
    debugPrint('[PurchaseManager] enqueued receipt for $platform/$productId');
  }

  Future<void> sendPendingReceipts() async {
    final listJson = _prefs?.getStringList(_kPrefsKeyPendingReceipts) ?? <String>[];
    if (listJson.isEmpty) return;

    final remaining = <String>[];
    for (final item in listJson) {
      try {
        final decoded = jsonDecode(item) as Map<String, dynamic>;
        final pr = PendingReceipt.fromJson(decoded);
        final ok = await _sendReceiptToBackend(pr.platform, pr.productId, pr.receipt);
        if (!ok) remaining.add(item);
      } catch (e) {
        debugPrint('[PurchaseManager] sendPendingReceipts decode/send error: $e');
        remaining.add(item);
      }
    }

    await _prefs?.setStringList(_kPrefsKeyPendingReceipts, remaining);
    debugPrint('[PurchaseManager] pending receipts flushed, remaining=${remaining.length}');
  }

  Future<bool> _sendReceiptToBackend(String platform, String productId, String receipt) async {
    if (backendVerifyEndpoint.isEmpty) {
      debugPrint('[PurchaseManager] backendVerifyEndpoint not set — skipping verification (debug)');
      return false;
    }

    try {
      final body = {
        'platform': platform,
        'productId': productId,
        'receipt': receipt,
        'deviceId': deviceIdentifier,
      };

      final r = await http
          .post(
        Uri.parse(backendVerifyEndpoint),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      )
          .timeout(const Duration(seconds: 10));

      if (r.statusCode == 200) {
        final j = jsonDecode(r.body) as Map<String, dynamic>;
        if (j['ok'] == true) {
          DateTime? expires;
          if (j['expiresAt'] != null) expires = DateTime.parse(j['expiresAt']);

          _cachedState = SubscriptionState(
            active: true,
            expiresAt: expires,
            isInTrial: j['isInTrial'] == true,
            platform: platform,
            rawPayload: j['rawPayload'] != null ? jsonEncode(j['rawPayload']) : receipt,
          );

          await _saveLocalState();

          try {
            await NotificationsService.instance.cancelDailySubscriptionReminder(markCancelled: true);
          } catch (e) {
            debugPrint('[PurchaseManager] cancelDailySubscriptionReminder failed -> $e');
          }

          try {
            await markShowUpgradeOnLaunch(false);
          } catch (_) {}

          _emitAccessChanged();

          return true;
        }
      }
      return false;
    } catch (e) {
      debugPrint('[PurchaseManager] _sendReceiptToBackend error: $e');
      return false;
    }
  }

  void _loadLocalState() {
    final raw = _prefs?.getString(_kPrefsKeySubscription);
    if (raw != null) {
      try {
        final j = jsonDecode(raw) as Map<String, dynamic>;
        _cachedState = SubscriptionState.fromJson(j);
      } catch (e) {
        debugPrint('[PurchaseManager] loadLocalState decode error -> $e');
        _cachedState = null;
      }
    }
  }

  Future<void> _saveLocalState() async {
    if (_cachedState == null) {
      await _prefs?.remove(_kPrefsKeySubscription);
      return;
    }
    await _prefs?.setString(_kPrefsKeySubscription, jsonEncode(_cachedState!.toJson()));
  }

  bool isActive() {
    if (_cachedState == null) return false;
    if (!_cachedState!.active) return false;
    if (_cachedState!.expiresAt != null) {
      return DateTime.now().isBefore(_cachedState!.expiresAt!);
    }
    return true;
  }

  Duration? remainingDuration() {
    final exp = _cachedState?.expiresAt;
    if (exp == null) return null;
    return exp.difference(DateTime.now());
  }

  DateTime? expiresAt() => _cachedState?.expiresAt;

  Future<void> refreshFromBackend() async {
    await sendPendingReceipts();
    try {
      await _iap.restorePurchases();
    } catch (e) {
      debugPrint('[PurchaseManager] refreshFromBackend -> restorePurchases failed: $e');
    }

    // after restore, re-check trial flag & emit
    await checkTrialAndNotifyIfExpired();
    _emitAccessChanged();
  }

  Future<void> clearLocalState() async {
    _cachedState = null;
    await _prefs?.remove(_kPrefsKeySubscription);
    await _prefs?.remove(_kPrefsKeyPendingReceipts);
    _emitAccessChanged();
  }

  void dispose() {
    _sub?.cancel();
    _accessController.close();
  }

  Future<void> ensureTrialStartIfNeeded() async {
    final prefs = _prefs ?? await SharedPreferences.getInstance();
    _prefs = prefs;

    if (isActive()) {
      debugPrint('[PurchaseManager] subscription already active -> do not set trial start');
      return;
    }

    if (!prefs.containsKey(_kPrefsKeyTrialStart)) {
      await prefs.setString(_kPrefsKeyTrialStart, DateTime.now().toIso8601String());
      debugPrint('[PurchaseManager] trialStart set -> ${DateTime.now()}');
    }
  }

  bool isTrialExpired() {
    final prefs = _prefs;
    if (prefs == null) return false;
    final raw = prefs.getString(_kPrefsKeyTrialStart);
    if (raw == null) return false;
    try {
      final start = DateTime.parse(raw);
      final expire = start.add(Duration(days: _kTrialDays));
      return DateTime.now().isAfter(expire) && !isActive();
    } catch (e) {
      debugPrint('[PurchaseManager] isTrialExpired parse error -> $e');
      return false;
    }
  }

  Future<void> markShowUpgradeOnLaunch(bool show) async {
    final prefs = _prefs ?? await SharedPreferences.getInstance();
    _prefs = prefs;
    await prefs.setBool(_kPrefsShowUpgradeOnLaunch, show);
  }

  bool shouldShowUpgradeOnLaunch() {
    return _prefs?.getBool(_kPrefsShowUpgradeOnLaunch) ?? false;
  }

  Future<void> checkTrialAndNotifyIfExpired() async {
    try {
      final prefs = _prefs ?? await SharedPreferences.getInstance();
      _prefs = prefs;

      final expired = isTrialExpired();

      await prefs.setBool(_kPrefsShowUpgradeOnLaunch, expired);

      if (expired) {
        debugPrint('[PurchaseManager] Trial expired -> flag set to show upgrade on launch');
      } else {
        debugPrint('[PurchaseManager] Trial active -> ensure upgrade flag cleared');
      }
    } catch (e, st) {
      debugPrint('[PurchaseManager] checkTrialAndNotifyIfExpired error -> $e\n$st');
    }
  }

  bool hasAccess() {
    final prefs = _prefs;
    if (prefs == null) return false;
    final raw = prefs.getString(_kPrefsKeyTrialStart);
    final trialActive = raw != null && DateTime.now().difference(DateTime.parse(raw)).inDays < _kTrialDays;
    return trialActive || isActive();
  }

  // internal helper to notify listeners
  void _emitAccessChanged() {
    final v = hasAccess();
    try {
      _accessController.add(v);
    } catch (_) {}
  }
}
