// lib/screens/upgrade_prompt_page.dart
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:android_intent_plus/android_intent.dart';
import '../service/purchase_Manager.dart';
import '../screens/settings_page.dart'; // fallback if we can't pop to previous screen

class UpgradePromptPage extends StatelessWidget {
  const UpgradePromptPage({super.key});

  Future<void> _openStore(BuildContext context) async {
    try {
      final pkg = await PackageInfo.fromPlatform();
      final packageName = pkg.packageName;

      if (defaultTargetPlatform == TargetPlatform.android) {
        // حاول تفتح Play Store مباشرةً عن طريق Intent (أفضل تجربة)
        final playUrl = 'https://play.google.com/store/apps/details?id=$packageName';

        try {
          final intent = AndroidIntent(
            action: 'action_view',
            data: playUrl,
          );
          await intent.launch();
          return;
        } catch (e) {
          debugPrint('[UpgradePrompt] Android Intent failed -> $e');
        }

        // fallback: افتح الرابط باستخدام url_launcher
        final uri = Uri.parse(playUrl);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
          return;
        }
      } else if (defaultTargetPlatform == TargetPlatform.iOS) {
        // ضع Apple ID هنا إذا عندك
        const appleId = 'YOUR_APPLE_APP_ID';
        final itmsUri = Uri.parse('itms-apps://itunes.apple.com/app/id$appleId');
        final httpsUri = Uri.parse('https://apps.apple.com/app/id$appleId');

        if (await canLaunchUrl(itmsUri)) {
          await launchUrl(itmsUri, mode: LaunchMode.externalApplication);
          return;
        } else if (await canLaunchUrl(httpsUri)) {
          await launchUrl(httpsUri, mode: LaunchMode.externalApplication);
          return;
        }
      } else {
        // fallback عام
        final url = 'https://play.google.com/store/apps/details?id=$packageName';
        final uri = Uri.parse(url);
        if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication);
      }

      // لو وصلنا هنا معناها مفيش طريقة تفتح المتجر
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذّر فتح المتجر. حاول مرة أخرى.'), duration: Duration(seconds: 2)),
      );
    } catch (e, st) {
      debugPrint('[UpgradePrompt] _openStore error -> $e\n$st');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('فشل فتح المتجر. حاول مرة أخرى.'), duration: Duration(seconds: 2)),
      );
    }
  }

  Future<void> _handleLater(BuildContext context) async {
    // لا تُظهر صفحة الترقية على الفتح التالي
    try {
      await PurchaseManager.instance.markShowUpgradeOnLaunch(false);
    } catch (e) {
      debugPrint('[UpgradePrompt] markShowUpgradeOnLaunch failed -> $e');
    }

    // ارجع للمكان اللي قبل كده لو موجود، وإلا خليك على Settings كفallback
    if (Navigator.canPop(context)) {
      Navigator.of(context).pop();
    } else {
      Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const SettingsPage()));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('الترقية للوصول الكامل'),
        automaticallyImplyLeading: false, // منع الرجوع لأننا نريد أن المستخدم يختار قرار
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 28),
          child: Column(
            children: [
              const SizedBox(height: 24),
              const Icon(Icons.lock_open, size: 92),
              const SizedBox(height: 22),
              const Text(
                'انتهت فترة التجربة المجانية',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              const Text(
                'لاستمرار استقبال الإشعارات والوصول الكامل للمميزات، الرجاء الترقية الآن.',
                textAlign: TextAlign.center,
              ),
              const Spacer(),
              ElevatedButton(
                onPressed: () => _openStore(context),
                child: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 14.0, horizontal: 10.0),
                  child: Text('اشترِ الآن', style: TextStyle(fontSize: 16)),
                ),
                style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => _handleLater(context),
                child: const Text('لاحقًا'),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () async {
                  // زر إضافي: تقدر تضيف زر لاستعادة المشتريات
                  try {
                    await PurchaseManager.instance.restorePurchases();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('تم طلب استعادة المشتريات.'), duration: Duration(seconds: 2)),
                    );
                  } catch (e) {
                    debugPrint('[UpgradePrompt] restorePurchases failed -> $e');
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('فشل استعادة المشتريات.'), duration: Duration(seconds: 2)),
                    );
                  }
                },
                child: const Text('استعادة المشتريات'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
