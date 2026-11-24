import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/config.dart';
import '../core/i18n.dart';
import '../core/models.dart';
import '../core/session.dart';
import '../core/wilayas.dart';
import '../widgets/common.dart';
import '../widgets/header.dart';
import 'shell.dart';

class WelcomePage extends StatelessWidget {
  const WelcomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(children: [
        Positioned.fill(child: Image.asset('assets/branding/app_poster.png', fit: BoxFit.cover)),
        Positioned.fill(
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.black.withValues(alpha: 0.35), Colors.black.withValues(alpha: 0.82)],
              ),
            ),
          ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: ListenableBuilder(
                  listenable: Session.I,
                  builder: (context, _) => LanguageButton(color: Colors.white, onSelected: (c) => Session.I.setLang(c)),
                ),
              ),
              const Spacer(),
              const Center(child: AppMark(size: 84)),
              const SizedBox(height: 16),
              Text(context.tr('app_name'), textAlign: TextAlign.center, style: const TextStyle(fontSize: 38, fontWeight: FontWeight.w900, color: Colors.white)),
              const SizedBox(height: 4),
              Text(context.tr('tagline'), textAlign: TextAlign.center, style: const TextStyle(fontSize: 17, color: Colors.white70)),
              const SizedBox(height: 32),
              FilledButton(
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AuthPage(register: true))),
                child: Text(context.tr('create_account')),
              ),
              const SizedBox(height: 10),
              OutlinedButton(
                style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: const BorderSide(color: Colors.white70)),
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AuthPage(register: false))),
                child: Text(context.tr('login')),
              ),
              const SizedBox(height: 18),
              Text(context.tr('disclaimer'), textAlign: TextAlign.center, style: const TextStyle(color: Colors.white60, fontSize: 12)),
            ]),
          ),
        ),
      ]),
    );
  }
}

class AuthPage extends StatefulWidget {
  final bool register;
  const AuthPage({super.key, required this.register});
  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _username = TextEditingController();
  final _name = TextEditingController();
  String? _wilaya;
  bool _busy = false;
  bool _hide = true;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _username.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_form.currentState?.validate() ?? false)) return;
    setState(() => _busy = true);
    try {
      final body = <String, dynamic>{'email': _email.text.trim(), 'password': _password.text};
      if (widget.register) {
        body.addAll({
          'username': _username.text.trim(),
          'name': _name.text.trim(),
          'wilaya': _wilaya,
          'language': Session.I.lang,
        });
      }
      final d = await api.post(widget.register ? '/auth/register' : '/auth/login', body);
      final map = Map<String, dynamic>.from(d as Map);
      final user = AppUser.fromJson(Map<String, dynamic>.from(map['user'] as Map));
      await Session.I.login(map['token'].toString(), user);
      if (!mounted) return;
      Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => const Shell()), (r) => false);
    } catch (e) {
      if (mounted) toast(context, errMsg(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final reg = widget.register;
    final closed = reg && !Session.I.settings.registrationOpen;
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr(reg ? 'create_account' : 'login')),
        actions: [LanguageButton(onSelected: (c) => Session.I.setLang(c))],
      ),
      body: SafeArea(
        child: Form(
          key: _form,
          child: ListView(padding: const EdgeInsets.all(20), children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: SizedBox(height: 130, child: Image.asset('assets/branding/app_poster.png', fit: BoxFit.cover)),
            ),
            const SizedBox(height: 20),
            if (closed)
              Container(
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(color: kRed.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(14)),
                child: Text(context.tr('err_REGISTRATION_CLOSED')),
              ),
            if (reg) ...[
              TextFormField(
                controller: _name,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(labelText: context.tr('full_name'), prefixIcon: const Icon(Icons.badge_outlined)),
                validator: (v) => (v == null || v.trim().isEmpty) ? context.tr('required') : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _username,
                textInputAction: TextInputAction.next,
                autocorrect: false,
                keyboardType: TextInputType.visiblePassword,
                decoration: InputDecoration(labelText: context.tr('username'), prefixIcon: const Icon(Icons.alternate_email_rounded), helperText: context.tr('username_hint')),
                validator: (v) {
                  final t = (v ?? '').trim();
                  if (t.length < 3 || t.length > 30) return context.tr('err_INVALID_USERNAME');
                  if (!RegExp(r'^[A-Za-z0-9_.-]+$').hasMatch(t)) return context.tr('err_INVALID_USERNAME_CHARS');
                  return null;
                },
              ),
              const SizedBox(height: 12),
              InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () async {
                  final w = await pickWilaya(context, current: _wilaya);
                  if (w != null && mounted) setState(() => _wilaya = w.isEmpty ? null : w);
                },
                child: InputDecorator(
                  decoration: InputDecoration(labelText: context.tr('wilaya'), prefixIcon: const Icon(Icons.location_city_rounded), suffixIcon: const Icon(Icons.arrow_drop_down_rounded)),
                  child: Text(_wilaya == null ? context.tr('choose') : wilayaDisplay(_wilaya, context.lang)),
                ),
              ),
              const SizedBox(height: 12),
            ],
            TextFormField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              autocorrect: false,
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(labelText: context.tr(reg ? 'email' : 'email_or_username'), prefixIcon: const Icon(Icons.mail_outline_rounded)),
              validator: (v) {
                final t = (v ?? '').trim();
                if (t.isEmpty) return context.tr('required');
                if (reg && !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(t)) return context.tr('err_INVALID_EMAIL');
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _password,
              obscureText: _hide,
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) => _busy || closed ? null : _submit(),
              decoration: InputDecoration(
                labelText: context.tr('password'),
                prefixIcon: const Icon(Icons.lock_outline_rounded),
                suffixIcon: IconButton(icon: Icon(_hide ? Icons.visibility_off_outlined : Icons.visibility_outlined), onPressed: () => setState(() => _hide = !_hide)),
              ),
              validator: (v) => (v == null || v.length < 6) ? context.tr('err_WEAK_PASSWORD') : null,
            ),
            if (!reg)
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: TextButton(
                  onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ForgotPasswordPage())),
                  child: Text(context.tr('forgot_password')),
                ),
              ),
            const SizedBox(height: 18),
            BusyButton(busy: _busy, onPressed: closed ? null : _submit, label: context.tr(reg ? 'create_account' : 'login'), icon: reg ? Icons.person_add_alt_1_rounded : Icons.login_rounded),
            const SizedBox(height: 12),
            Center(
              child: TextButton(
                onPressed: () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => AuthPage(register: !reg))),
                child: Text(context.tr(reg ? 'have_account' : 'no_account')),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

class ForgotPasswordPage extends StatefulWidget {
  const ForgotPasswordPage({super.key});
  @override
  State<ForgotPasswordPage> createState() => _ForgotPasswordPageState();
}

class _ForgotPasswordPageState extends State<ForgotPasswordPage> {
  final _email = TextEditingController();
  final _code = TextEditingController();
  final _password = TextEditingController();
  bool _sent = false;
  bool _busy = false;
  bool _mailReady = true;

  @override
  void dispose() {
    _email.dispose();
    _code.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_email.text.trim().isEmpty) return;
    setState(() => _busy = true);
    try {
      final d = await api.post('/auth/forgot', {'email': _email.text.trim()});
      _mailReady = !(d is Map && d['emailConfigured'] == false);
      if (mounted) setState(() => _sent = true);
    } catch (e) {
      if (mounted) toast(context, errMsg(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reset() async {
    if (_code.text.trim().isEmpty || _password.text.length < 6) {
      toast(context, context.tr('err_WEAK_PASSWORD'), error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      await api.post('/auth/reset', {'email': _email.text.trim(), 'code': _code.text.trim(), 'password': _password.text});
      if (!mounted) return;
      toast(context, context.tr('password_changed'));
      Navigator.pop(context);
    } catch (e) {
      if (mounted) toast(context, errMsg(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('forgot_password'))),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        Text(context.tr(_sent ? 'reset_code_sent' : 'reset_intro')),
        const SizedBox(height: 16),
        TextField(controller: _email, enabled: !_sent, keyboardType: TextInputType.emailAddress, decoration: InputDecoration(labelText: context.tr('email'), prefixIcon: const Icon(Icons.mail_outline_rounded))),
        if (_sent) ...[
          if (!_mailReady)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(context.tr('mail_not_configured'), style: const TextStyle(color: kRed)),
            ),
          const SizedBox(height: 12),
          TextField(controller: _code, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: context.tr('reset_code'), prefixIcon: const Icon(Icons.pin_outlined))),
          const SizedBox(height: 12),
          TextField(controller: _password, obscureText: true, decoration: InputDecoration(labelText: context.tr('new_password'), prefixIcon: const Icon(Icons.lock_outline_rounded))),
        ],
        const SizedBox(height: 20),
        BusyButton(busy: _busy, onPressed: _sent ? _reset : _send, label: context.tr(_sent ? 'change_password' : 'send_code')),
      ]),
    );
  }
}
