import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'core/i18n.dart';
import 'core/notifier.dart';
import 'core/session.dart';
import 'core/theme.dart';
import 'pages/auth.dart';
import 'pages/deeplink.dart';
import 'pages/shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting();
  await Session.I.init();
  runApp(const SawtApp());
}

class SawtApp extends StatefulWidget {
  const SawtApp({super.key});
  @override
  State<SawtApp> createState() => _SawtAppState();
}

class _SawtAppState extends State<SawtApp> with WidgetsBindingObserver {
  late final Widget _home = Session.I.loggedIn ? const Shell() : const WelcomePage();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    Session.I.onOpenTarget = openTarget;
    Session.I.onSessionLost = _sessionLost;
    LocalNotifier.onTap = _handlePayload;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final p = await LocalNotifier.initialPayload();
      if (p != null) _handlePayload(p);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    Session.I.foreground = state == AppLifecycleState.resumed;
    if (state == AppLifecycleState.resumed && Session.I.loggedIn) {
      Session.I.refreshBadges();
      if (Session.I.socketDown) Session.I.connectSocket();
    }
  }

  void _handlePayload(String payload) {
    try {
      final m = Map<String, dynamic>.from(jsonDecode(payload) as Map);
      final type = (m.remove('type') ?? '').toString();
      openTarget(type, m);
    } catch (_) {}
  }

  void _sessionLost(String reason) {
    final nav = navigatorKey.currentState;
    nav?.pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const WelcomePage()), (r) => false);
    final msg = reason == 'BANNED' ? trNow('err_BANNED') : trNow('session_expired');
    messengerKey.currentState?.showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Session.I,
      builder: (context, _) => MaterialApp(
        debugShowCheckedModeBanner: false,
        navigatorKey: navigatorKey,
        scaffoldMessengerKey: messengerKey,
        title: 'صوت الجزائر',
        locale: Locale(Session.I.lang),
        supportedLocales: const [Locale('ar'), Locale('fr'), Locale('en')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        theme: buildTheme(Brightness.light),
        darkTheme: buildTheme(Brightness.dark),
        themeMode: Session.I.themeMode,
        home: _home,
      ),
    );
  }
}
