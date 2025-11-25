import 'package:flutter/material.dart';
import 'settings_page.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/services.dart';

class SettingsMenuPage extends StatelessWidget {
  const SettingsMenuPage({super.key});

  static const String _privacyUrl =
      'https://doc-hosting.flycricket.io/work-reminder-privacy-policy/9e71390e-a8a6-4dd4-a8f8-d7b873487e9f/privacy';
  static const String _termsUrl =
      'https://doc-hosting.flycricket.io/work-reminder-terms-of-use/1eff1294-bfa4-4836-a8c6-85f83985dc81/terms';
  static const String _supportUrl =
      'https://www.instagram.com/work_reminder/'; // أبسّطنا الرابط عشان نتأكد

  /// Helper to build and validate Uri, with debug prints at each check.
  Uri? _makeUri(String url) {
    debugPrint('[_makeUri] raw input: "$url"');
    final cleaned = url.trim();
    debugPrint('[_makeUri] cleaned: "$cleaned"');

    // tryParse is safer and doesn't throw
    final raw = Uri.tryParse(cleaned);
    debugPrint('[_makeUri] Uri.tryParse result: $raw');

    if (raw == null) {
      debugPrint('[_makeUri] parse failed -> returning null');
      return null;
    }

    // if no scheme, try https
    if (!raw.hasScheme) {
      debugPrint('[_makeUri] no scheme found, trying https:// prefix');
      final t = Uri.tryParse('https://$cleaned');
      debugPrint('[_makeUri] after adding https -> $t');
      if (t == null) {
        debugPrint('[_makeUri] https parse failed -> returning null');
        return null;
      }
      return t;
    }

    // allow only http/https
    if (raw.scheme != 'http' && raw.scheme != 'https') {
      debugPrint('[_makeUri] unsupported scheme: ${raw.scheme} -> returning null');
      return null;
    }

    // ensure absolute
    if (!raw.isAbsolute) {
      debugPrint('[_makeUri] uri not absolute -> returning null');
      return null;
    }

    debugPrint('[_makeUri] final uri: $raw');
    return raw;
  }

  /// Open URL with step-by-step debug prints and fallback behaviour.
  Future<void> _openUrl(BuildContext context, String url) async {
    debugPrint('[_openUrl] START for: $url');

    final uri = _makeUri(url);
    debugPrint('[_openUrl] parsed uri: $uri');

    if (uri == null) {
      debugPrint('[_openUrl] uri == null -> showing SnackBar "الرابط غير صالح."');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('الرابط غير صالح.')),
      );
      return;
    }

    try {
      // Check canLaunchUrl first
      debugPrint('[_openUrl] calling canLaunchUrl...');
      final can = await canLaunchUrl(uri);
      debugPrint('[_openUrl] canLaunchUrl returned: $can for $uri');

      if (!can) {
        debugPrint('[_openUrl] canLaunchUrl == false -> trying fallback attempts');
        // Try direct launch without canLaunch as a last resort
        bool fallbackLaunched = false;
        try {
          debugPrint('[_openUrl] Fallback: try launchUrl with platformDefault');
          fallbackLaunched = await launchUrl(uri, mode: LaunchMode.platformDefault);
          debugPrint('[_openUrl] Fallback platformDefault launched: $fallbackLaunched');
        } catch (e) {
          debugPrint('[_openUrl] Fallback platformDefault threw: $e');
        }

        if (!fallbackLaunched) {
          debugPrint('[_openUrl] all attempts failed -> copying URL to clipboard and notifying user');
          await Clipboard.setData(ClipboardData(text: uri.toString()));
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'تعذّر فتح الرابط تلقائيًا. تم نسخ الرابط للحافظة، الصقه في المتصفح لفتحه.',
              ),
              duration: Duration(seconds: 4),
            ),
          );
        }
        return;
      }

      // If canLaunchUrl is true, try to open with preferred modes and log each step
      bool launched = false;

      debugPrint('[_openUrl] Attempt 1: launchUrl externalApplication');
      try {
        launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
        debugPrint('[_openUrl] Attempt 1 result: $launched');
      } catch (e) {
        debugPrint('[_openUrl] Attempt 1 threw: $e');
      }

      if (!launched) {
        debugPrint('[_openUrl] Attempt 2: launchUrl platformDefault');
        try {
          launched = await launchUrl(uri, mode: LaunchMode.platformDefault);
          debugPrint('[_openUrl] Attempt 2 result: $launched');
        } catch (e) {
          debugPrint('[_openUrl] Attempt 2 threw: $e');
        }
      }

      if (!launched) {
        debugPrint('[_openUrl] Attempt 3 (fallback): copying to clipboard and notifying user');
        await Clipboard.setData(ClipboardData(text: uri.toString()));
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'تعذّر فتح الرابط تلقائيًا. تم نسخ الرابط للحافظة، الصقه في المتصفح لفتحه.',
            ),
            duration: Duration(seconds: 4),
          ),
        );
      } else {
        debugPrint('[_openUrl] SUCCESS: launched $uri');
      }
    } on PlatformException catch (e) {
      debugPrint('[_openUrl] PlatformException: ${e.message}');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('حدث خطأ في النظام: ${e.message}')),
      );
    } catch (e, st) {
      debugPrint('[_openUrl] General exception: $e\nStack: $st');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('حدث خطأ أثناء فتح الرابط: $e')),
      );
    } finally {
      debugPrint('[_openUrl] FINISHED for: $url');
    }
  }

  Widget _buildItem(
      BuildContext context, {
        required IconData icon,
        required String title,
        String? subtitle,
        required VoidCallback onTap,
      }) {
    return Material(
      elevation: 2,
      borderRadius: BorderRadius.circular(12),
      color: Theme.of(context).cardColor,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          debugPrint('[UI] tapped: $title');
          onTap();
        },
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              CircleAvatar(
                radius: 22,
                child: Icon(icon, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    if (subtitle != null) const SizedBox(height: 6),
                    if (subtitle != null) Text(subtitle, style: const TextStyle(fontSize: 13)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_left, size: 24),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    debugPrint('[build] SettingsMenuPage building...');
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('الإعدادات العامة'),
        ),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: ListView(
              children: [
                _buildItem(
                  context,
                  icon: Icons.schedule,
                  title: 'إعدادات الدوام',
                  subtitle: 'ضبط نظام العمل، أوقات البداية والإثبات، والتذكير',
                  onTap: () {
                    debugPrint('[action] navigate to SettingsPage');
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const SettingsPage()),
                    );
                  },
                ),
                const SizedBox(height: 12),
                _buildItem(
                  context,
                  icon: Icons.privacy_tip,
                  title: 'سياسة الخصوصية',
                  subtitle: 'عرض سياسة الخصوصية للتطبيق',
                  onTap: () {
                    debugPrint('[action] open privacy URL');
                    _openUrl(context, _privacyUrl);
                  },
                ),
                const SizedBox(height: 12),
                _buildItem(
                  context,
                  icon: Icons.description,
                  title: 'شروط الاستخدام',
                  subtitle: 'عرض الشروط والأحكام الخاصة بالتطبيق',
                  onTap: () {
                    debugPrint('[action] open terms URL');
                    _openUrl(context, _termsUrl);
                  },
                ),
                const SizedBox(height: 12),
                _buildItem(
                  context,
                  icon: Icons.support_agent,
                  title: 'الدعم والتواصل',
                  subtitle: 'تواصل معنا لأي استفسار أو دعم',
                  onTap: () {
                    debugPrint('[action] open support URL');
                    _openUrl(context, _supportUrl);
                  },
                ),
                const SizedBox(height: 18),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.06),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('لأي ملاحظات أو بلاغات عن أخطاء، راسلنا عبر صفحة الدعم.',
                          style: TextStyle(fontSize: 13, color: Theme.of(context).hintColor)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
