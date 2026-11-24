import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/api.dart';
import '../core/config.dart';
import '../core/i18n.dart';
import '../core/notifier.dart';
import '../core/session.dart';
import '../widgets/common.dart';
import 'auth.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _notifOn = true;

  @override
  void initState() {
    super.initState();
    LocalNotifier.enabled().then((v) { if (mounted) setState(() => _notifOn = v); });
  }

  Future<void> _password() async {
    final cur = TextEditingController();
    final nw = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.tr('change_password')),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: cur, obscureText: true, decoration: InputDecoration(labelText: ctx.tr('current_password'))),
          const SizedBox(height: 10),
          TextField(controller: nw, obscureText: true, decoration: InputDecoration(labelText: ctx.tr('new_password'))),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(ctx.tr('cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(ctx.tr('save'))),
        ],
      ),
    );
    final c = cur.text, n = nw.text;
    cur.dispose();
    nw.dispose();
    if (ok != true || !mounted) return;
    try {
      await api.post('/me/password', {'currentPassword': c, 'newPassword': n});
      if (mounted) toast(context, context.tr('password_changed'));
    } catch (e) {
      if (mounted) toast(context, errMsg(e), error: true);
    }
  }

  Future<void> _deleteAccount() async {
    final ok = await confirmDialog(context, title: context.tr('delete_account'), message: context.tr('delete_account_msg'), confirmLabel: context.tr('delete'), danger: true);
    if (!ok || !mounted) return;
    final pw = await promptDialog(context, title: context.tr('current_password'), maxLines: 1);
    if (pw == null || !mounted) return;
    try {
      await api.delete('/me', {'password': pw});
      await Session.I.logout();
      navigatorKey.currentState?.pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const WelcomePage()), (r) => false);
    } catch (e) {
      if (mounted) toast(context, errMsg(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Session.I,
      builder: (context, _) {
        final s = Session.I;
        return Scaffold(
          appBar: AppBar(title: Text(context.tr('settings'))),
          body: ListView(children: [
            SectionTitle(context.tr('language')),
            for (final code in kLanguages)
              RadioListTile<String>(
                value: code,
                groupValue: s.lang,
                title: Text(kLanguageNames[code] ?? code),
                onChanged: (v) { if (v != null) s.setLang(v); },
              ),
            SectionTitle(context.tr('theme')),
            RadioListTile<ThemeMode>(value: ThemeMode.system, groupValue: s.themeMode, title: Text(context.tr('theme_system')), onChanged: (v) => s.setTheme(v!)),
            RadioListTile<ThemeMode>(value: ThemeMode.light, groupValue: s.themeMode, title: Text(context.tr('theme_light')), onChanged: (v) => s.setTheme(v!)),
            RadioListTile<ThemeMode>(value: ThemeMode.dark, groupValue: s.themeMode, title: Text(context.tr('theme_dark')), onChanged: (v) => s.setTheme(v!)),
            SectionTitle(context.tr('notifications')),
            SwitchListTile(
              value: _notifOn,
              title: Text(context.tr('notifications_enable')),
              subtitle: Text(context.tr('notifications_hint')),
              onChanged: (v) async {
                final ok = await LocalNotifier.requestPermission();
                if (mounted) setState(() => _notifOn = ok);
                if (!ok && mounted) toast(context, context.tr('notifications_denied'), error: true);
              },
            ),
            SectionTitle(context.tr('account')),
            ListTile(leading: const Icon(Icons.lock_reset_rounded), title: Text(context.tr('change_password')), onTap: _password),
            ListTile(leading: const Icon(Icons.delete_forever_rounded, color: kRed), title: Text(context.tr('delete_account'), style: const TextStyle(color: kRed)), onTap: _deleteAccount),
            SectionTitle(context.tr('about')),
            ListTile(leading: const Icon(Icons.info_outline_rounded), title: Text(context.tr('app_name')), subtitle: Text('v${AppConfig.appVersion}')),
            ListTile(
              leading: const Icon(Icons.public_rounded),
              title: Text(context.tr('server')),
              subtitle: Text(AppConfig.apiBase),
              onTap: () => launchUrl(Uri.parse('${AppConfig.apiBase}/health'), mode: LaunchMode.externalApplication),
            ),
            const SizedBox(height: 40),
          ]),
        );
      },
    );
  }
}
