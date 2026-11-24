import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

import 'api.dart';
import 'config.dart';
import 'i18n.dart';
import 'models.dart';
import 'notifier.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
final GlobalKey<ScaffoldMessengerState> messengerKey = GlobalKey<ScaffoldMessengerState>();

/// Bump after creating/deleting content so lists on other tabs reload.
final ValueNotifier<int> contentRefresh = ValueNotifier<int>(0);
void bumpContent() => contentRefresh.value++;

class Session extends ChangeNotifier {
  Session._();
  static final Session I = Session._();

  AppUser? user;
  PublicSettings settings = const PublicSettings();
  int unreadNotifications = 0;
  int unreadMessages = 0;
  String lang = 'ar';
  ThemeMode themeMode = ThemeMode.system;
  bool foreground = true;
  String? activeConversationId;
  final Set<String> mutedConversations = <String>{};

  /// Set by main.dart: opens the screen related to a notification payload.
  void Function(String type, Map<String, dynamic> data)? onOpenTarget;
  /// Set by main.dart: called when the session is no longer valid.
  void Function(String reason)? onSessionLost;

  io.Socket? _socket;
  final StreamController<ChatMessage> messages = StreamController<ChatMessage>.broadcast();
  final StreamController<Map<String, dynamic>> typing = StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<Map<String, dynamic>> readEvents = StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<Map<String, dynamic>> deletedEvents = StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<AppNotification> notifications = StreamController<AppNotification>.broadcast();

  bool get loggedIn => api.token != null;
  bool get socketDown => _socket == null || _socket!.disconnected;
  String? get userId => user?.id;

  Future<void> init() async {
    final p = await SharedPreferences.getInstance();
    lang = p.getString('lang') ?? 'ar';
    if (!kLanguages.contains(lang)) lang = 'ar';
    setCurrentLang(lang);
    final t = p.getString('theme') ?? 'system';
    themeMode = t == 'dark' ? ThemeMode.dark : (t == 'light' ? ThemeMode.light : ThemeMode.system);
    await api.loadToken();
    api.onAuthLost = (reason) {
      user = null;
      unreadMessages = 0;
      unreadNotifications = 0;
      disconnectSocket();
      notifyListeners();
      onSessionLost?.call(reason);
    };
    await LocalNotifier.init();
    unawaitedSafe(refreshSettings());
    if (loggedIn) {
      try {
        await refreshMe().timeout(const Duration(seconds: 8));
      } catch (_) {}
      connectSocket();
    }
  }

  Future<void> setLang(String code) async {
    if (!kLanguages.contains(code)) return;
    lang = code;
    setCurrentLang(code);
    final p = await SharedPreferences.getInstance();
    await p.setString('lang', code);
    notifyListeners();
    if (loggedIn) unawaitedSafe(api.put('/me/language', {'language': code}));
  }

  Future<void> setTheme(ThemeMode m) async {
    themeMode = m;
    final p = await SharedPreferences.getInstance();
    await p.setString('theme', m == ThemeMode.dark ? 'dark' : (m == ThemeMode.light ? 'light' : 'system'));
    notifyListeners();
  }

  Future<void> refreshSettings() async {
    try {
      settings = PublicSettings.fromJson(await api.getMap('/settings/public'));
      notifyListeners();
    } catch (_) {}
  }

  Future<void> refreshMe() async {
    final d = await api.getMap('/me');
    final u = AppUser.maybe(d['user']);
    if (u != null) user = u;
    unreadNotifications = (d['unreadNotifications'] as num?)?.toInt() ?? unreadNotifications;
    if (d['settings'] is Map) settings = PublicSettings.fromJson(Map<String, dynamic>.from(d['settings'] as Map));
    notifyListeners();
  }

  void updateUser(AppUser u) {
    user = u;
    notifyListeners();
  }

  Future<void> refreshBadges() async {
    if (!loggedIn) return;
    try {
      final d = await api.getMap('/badges');
      unreadNotifications = (d['notifications'] as num?)?.toInt() ?? 0;
      unreadMessages = (d['messages'] as num?)?.toInt() ?? 0;
      notifyListeners();
    } catch (_) {}
  }

  void setUnreadMessages(int n) {
    unreadMessages = n < 0 ? 0 : n;
    notifyListeners();
  }

  void setUnreadNotifications(int n) {
    unreadNotifications = n < 0 ? 0 : n;
    notifyListeners();
  }

  Future<void> login(String token, AppUser u) async {
    await api.saveToken(token);
    user = u;
    // keep the language the user picked on this device
    unawaitedSafe(api.put('/me/language', {'language': lang}));
    notifyListeners();
    connectSocket();
    unawaitedSafe(refreshBadges());
    unawaitedSafe(LocalNotifier.requestPermission());
  }

  Future<void> logout() async {
    disconnectSocket();
    try {
      await LocalNotifier.cancelAll();
    } catch (_) {}
    await api.clearToken();
    user = null;
    unreadMessages = 0;
    unreadNotifications = 0;
    mutedConversations.clear();
    notifyListeners();
  }

  // ------------------------------------------------------------ realtime
  void connectSocket() {
    disconnectSocket();
    final t = api.token;
    if (t == null) return;
    final s = io.io(
      Api.base,
      io.OptionBuilder().setTransports(['websocket']).setAuth({'token': t}).enableReconnection().build(),
    );
    _socket = s;
    s.on('message:new', (data) {
      if (data is! Map) return;
      final m = ChatMessage.fromJson(Map<String, dynamic>.from(data));
      messages.add(m);
      if (m.senderId == userId) return;
      if (activeConversationId == m.conversationId) return;
      unreadMessages++;
      notifyListeners();
      if (mutedConversations.contains(m.conversationId)) return;
      final title = m.senderName ?? trNow('messages');
      final body = m.body.isNotEmpty ? m.body : (m.mediaType == 'VIDEO' ? '🎬 ${trNow('video')}' : '📷 ${trNow('photo')}');
      _alert(title, body, 'message', {'conversationId': m.conversationId});
    });
    s.on('message:deleted', (data) {
      if (data is Map) deletedEvents.add(Map<String, dynamic>.from(data));
    });
    s.on('messages:read', (data) {
      if (data is Map) readEvents.add(Map<String, dynamic>.from(data));
    });
    s.on('typing', (data) {
      if (data is Map) typing.add(Map<String, dynamic>.from(data));
    });
    s.on('notification:new', (data) {
      if (data is! Map) return;
      final n = AppNotification.fromJson(Map<String, dynamic>.from(data));
      notifications.add(n);
      unreadNotifications++;
      notifyListeners();
      final payloadData = Map<String, dynamic>.from(n.data);
      _alert(n.title, n.body, n.type, payloadData);
    });
    s.onConnect((_) {
      unawaitedSafe(refreshBadges());
    });
  }

  void joinConversation(String id) => _socket?.emit('conversation:join', id);
  void leaveConversation(String id) => _socket?.emit('conversation:leave', id);
  void sendTyping(String id) => _socket?.emit('typing', id);

  void disconnectSocket() {
    try {
      _socket?.dispose();
    } catch (_) {}
    _socket = null;
  }

  void _alert(String title, String body, String type, Map<String, dynamic> data) {
    if (title.isEmpty && body.isEmpty) return;
    final payload = jsonEncode({'type': type, ...data});
    if (foreground) {
      final ctx = navigatorKey.currentContext;
      final cs = ctx != null ? Theme.of(ctx).colorScheme : null;
      messengerKey.currentState
        ?..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          duration: const Duration(seconds: 5),
          backgroundColor: kDeepGreen,
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
              if (body.isNotEmpty) Text(body, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white70)),
            ],
          ),
          action: SnackBarAction(
            label: trNow('open'),
            textColor: cs == null ? Colors.white : const Color(0xFF9FE2B8),
            onPressed: () => onOpenTarget?.call(type, data),
          ),
        ));
    } else {
      LocalNotifier.show(id: payload.hashCode & 0x7fffffff, title: title, body: body, payload: payload);
    }
  }
}

void unawaitedSafe(Future<dynamic> f) {
  f.catchError((_) {});
}
