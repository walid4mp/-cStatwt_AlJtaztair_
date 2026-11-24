import 'dart:async';

import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/config.dart';
import '../core/i18n.dart';
import '../core/models.dart';
import '../core/session.dart';
import '../widgets/common.dart';
import '../widgets/header.dart';
import '../widgets/media_picker.dart';
import 'profile.dart';

// ======================================================================== inbox
class MessagesPage extends StatefulWidget {
  const MessagesPage({super.key});
  @override
  State<MessagesPage> createState() => _MessagesPageState();
}

class _MessagesPageState extends State<MessagesPage> {
  List<Conversation> _rows = [];
  bool _loading = true;
  Object? _error;
  StreamSubscription<ChatMessage>? _sub;

  @override
  void initState() {
    super.initState();
    _load();
    _sub = Session.I.messages.stream.listen((_) => _load(silent: true));
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) setState(() { _loading = true; _error = null; });
    try {
      final rows = asMapList(await api.get('/conversations')).map(Conversation.fromJson).toList();
      Session.I.mutedConversations
        ..clear()
        ..addAll(rows.where((c) => c.muted).map((c) => c.id));
      Session.I.setUnreadMessages(rows.fold<int>(0, (a, c) => a + c.unread));
      if (mounted) setState(() { _rows = rows; _loading = false; _error = null; });
    } catch (e) {
      if (mounted) setState(() { _error = e; _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(children: [
      TopHeader(title: context.tr('messages'), subtitle: context.tr('messages_sub')),
      Expanded(
        child: _loading
            ? const LoadingView()
            : _error != null && _rows.isEmpty
                ? ErrorState(error: _error!, onRetry: _load)
                : RefreshIndicator(
                    onRefresh: () => _load(silent: true),
                    child: _rows.isEmpty
                        ? ListView(children: [const SizedBox(height: 60), EmptyState(icon: Icons.chat_bubble_outline_rounded, title: context.tr('no_conversations'), subtitle: context.tr('no_conversations_sub'), action: FilledButton.icon(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const UserSearchPage())), icon: const Icon(Icons.search_rounded), label: Text(context.tr('find_people'))))])
                        : ListView.separated(
                            padding: const EdgeInsets.only(bottom: 100),
                            itemCount: _rows.length,
                            separatorBuilder: (_, i) => const Divider(indent: 76),
                            itemBuilder: (_, i) {
                              final c = _rows[i];
                              final last = c.lastMessage;
                              final mine = last?.senderId == Session.I.userId;
                              final preview = last == null ? '' : (last.body.isNotEmpty ? last.body : (last.mediaType == 'VIDEO' ? '🎬 ${context.tr('video')}' : '📷 ${context.tr('photo')}'));
                              return ListTile(
                                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                                leading: AppAvatar(url: c.other?.avatarUrl, name: c.other?.name ?? '?', radius: 26),
                                title: Row(children: [if (c.other != null) Flexible(child: UserNameRow(c.other!)), if (c.muted) const Padding(padding: EdgeInsetsDirectional.only(start: 6), child: Icon(Icons.notifications_off_outlined, size: 15))]),
                                subtitle: Text('${mine ? '${context.tr('you')}: ' : ''}$preview', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: c.unread > 0 ? FontWeight.w800 : FontWeight.w400, color: c.unread > 0 ? cs.onSurface : cs.onSurfaceVariant)),
                                trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                                  Text(timeAgo(context, last?.createdAt), style: TextStyle(fontSize: 11.5, color: cs.onSurfaceVariant)),
                                  const SizedBox(height: 4),
                                  if (c.unread > 0) Badge(label: Text('${c.unread}'), backgroundColor: kGreen) else const SizedBox(height: 16),
                                ]),
                                onTap: () async {
                                  await Navigator.push(context, MaterialPageRoute(builder: (_) => ChatPage(conversationId: c.id, conversation: c)));
                                  _load(silent: true);
                                },
                              );
                            },
                          ),
                  ),
      ),
    ]);
  }
}

// ======================================================================== chat
class ChatPage extends StatefulWidget {
  final String conversationId;
  final Conversation? conversation;
  const ChatPage({super.key, required this.conversationId, this.conversation});
  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  Conversation? _conv;
  final List<ChatMessage> _msgs = [];
  final TextEditingController _input = TextEditingController();
  final ScrollController _sc = ScrollController();
  bool _loading = true;
  bool _sending = false;
  bool _otherTyping = false;
  bool _hasMore = true;
  bool _loadingMore = false;
  Object? _error;
  Timer? _typingTimer;
  Timer? _typingSend;
  final List<StreamSubscription<dynamic>> _subs = [];

  String get _id => widget.conversationId;
  String get _me => Session.I.userId ?? '';

  @override
  void initState() {
    super.initState();
    _conv = widget.conversation;
    Session.I.activeConversationId = _id;
    Session.I.joinConversation(_id);
    _subs.add(Session.I.messages.stream.listen(_onMessage));
    _subs.add(Session.I.typing.stream.listen((e) {
      if (e['conversationId']?.toString() == _id && e['userId']?.toString() != _me) {
        setState(() => _otherTyping = true);
        _typingTimer?.cancel();
        _typingTimer = Timer(const Duration(seconds: 3), () {
          if (mounted) setState(() => _otherTyping = false);
        });
      }
    }));
    _subs.add(Session.I.readEvents.stream.listen((e) {
      if (e['conversationId']?.toString() == _id && e['by']?.toString() != _me) {
        setState(() {
          for (final m in _msgs) {
            if (m.senderId == _me && m.readAt == null) m.readAt = DateTime.now();
          }
        });
      }
    }));
    _subs.add(Session.I.deletedEvents.stream.listen((e) {
      if (e['conversationId']?.toString() == _id) setState(() => _msgs.removeWhere((m) => m.id == e['id']?.toString()));
    }));
    _sc.addListener(() {
      // list is reversed: maxScrollExtent == oldest messages
      if (_sc.hasClients && _sc.position.pixels > _sc.position.maxScrollExtent - 200) _loadOlder();
    });
    _load();
    if (_conv == null) _loadConv();
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _typingTimer?.cancel();
    _typingSend?.cancel();
    if (Session.I.activeConversationId == _id) Session.I.activeConversationId = null;
    Session.I.leaveConversation(_id);
    _input.dispose();
    _sc.dispose();
    super.dispose();
  }

  Future<void> _loadConv() async {
    try {
      final c = Conversation.fromJson(Map<String, dynamic>.from(await api.get('/conversations/$_id') as Map));
      if (mounted) setState(() => _conv = c);
    } catch (_) {}
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final rows = asMapList(await api.get('/conversations/$_id/messages?limit=40')).map(ChatMessage.fromJson).toList();
      if (!mounted) return;
      setState(() {
        _msgs..clear()..addAll(rows);
        _hasMore = rows.length >= 40;
        _loading = false;
      });
      _markRead();
    } catch (e) {
      if (mounted) setState(() { _error = e; _loading = false; });
    }
  }

  Future<void> _loadOlder() async {
    if (_loadingMore || !_hasMore || _msgs.isEmpty || _msgs.first.createdAt == null) return;
    _loadingMore = true;
    try {
      final rows = asMapList(await api.get('/conversations/$_id/messages?limit=40&before=${Uri.encodeComponent(_msgs.first.createdAt!.toUtc().toIso8601String())}')).map(ChatMessage.fromJson).toList();
      if (mounted) setState(() { _msgs.insertAll(0, rows); _hasMore = rows.length >= 40; });
    } catch (_) {
    } finally {
      _loadingMore = false;
    }
  }

  Future<void> _markRead() async {
    try {
      await api.patch('/conversations/$_id/read');
      Session.I.refreshBadges();
    } catch (_) {}
  }

  void _onMessage(ChatMessage m) {
    if (m.conversationId != _id) return;
    if (_msgs.any((x) => x.id == m.id)) return;
    if (!mounted) return;
    setState(() => _msgs.add(m));
    if (m.senderId != _me) _markRead();
  }

  void _onTyping(String _) {
    if (_typingSend?.isActive == true) return;
    Session.I.sendTyping(_id);
    _typingSend = Timer(const Duration(seconds: 2), () {});
  }

  bool get _blocked => (_conv?.blockedByMe ?? false) || (_conv?.blockedMe ?? false);

  Future<void> _sendText() async {
    final t = _input.text.trim();
    if (t.isEmpty || _sending) return;
    _input.clear();
    setState(() => _sending = true);
    try {
      final d = await api.post('/conversations/$_id/messages', {'body': t});
      _onMessage(ChatMessage.fromJson(Map<String, dynamic>.from(d as Map)));
    } catch (e) {
      _input.text = t;
      if (mounted) toast(context, errMsg(e), error: true);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _sendMedia() async {
    final m = await pickMediaSheet(context);
    if (m == null || !mounted) return;
    setState(() => _sending = true);
    try {
      final d = await api.multipart('POST', '/conversations/$_id/messages', fields: {'body': _input.text.trim()}, files: [UploadFile('media', m.path)]);
      _input.clear();
      _onMessage(ChatMessage.fromJson(Map<String, dynamic>.from(d as Map)));
    } catch (e) {
      if (mounted) toast(context, errMsg(e), error: true);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _deleteMessage(ChatMessage m) async {
    final ok = await confirmDialog(context, title: context.tr('delete_message'), confirmLabel: context.tr('delete'), danger: true);
    if (!ok || !mounted) return;
    try {
      await api.delete('/messages/${m.id}');
      if (mounted) setState(() => _msgs.removeWhere((x) => x.id == m.id));
    } catch (e) {
      if (mounted) toast(context, errMsg(e), error: true);
    }
  }

  Future<void> _menu(String v) async {
    final c = _conv;
    if (c == null) return;
    try {
      if (v == 'mute') {
        final muted = !c.muted;
        await api.patch('/conversations/$_id/mute', {'muted': muted});
        setState(() => c.muted = muted);
        if (muted) {
          Session.I.mutedConversations.add(_id);
        } else {
          Session.I.mutedConversations.remove(_id);
        }
        if (mounted) toast(context, context.tr(muted ? 'muted_done' : 'unmuted_done'));
      } else if (v == 'block') {
        final ok = await confirmDialog(context, title: context.tr(c.blockedByMe ? 'unblock' : 'block'), message: context.tr(c.blockedByMe ? 'unblock_msg' : 'block_msg'), danger: !c.blockedByMe);
        if (!ok) return;
        if (c.blockedByMe) {
          await api.delete('/conversations/$_id/block');
        } else {
          await api.post('/conversations/$_id/block');
        }
        setState(() => c.blockedByMe = !c.blockedByMe);
      } else if (v == 'report') {
        final reason = await promptDialog(context, title: context.tr('report_conversation'), hint: context.tr('reason_hint'), allowEmpty: true);
        if (reason == null) return;
        await api.post('/conversations/$_id/report', {'reason': reason});
        if (mounted) toast(context, context.tr('flag_sent'));
      } else if (v == 'profile' && c.other != null) {
        Navigator.push(context, MaterialPageRoute(builder: (_) => UserProfilePage(userId: c.other!.id)));
      }
    } catch (e) {
      if (mounted) toast(context, errMsg(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final other = _conv?.other;
    final reversed = _msgs.reversed.toList();
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: InkWell(
          onTap: other == null ? null : () => _menu('profile'),
          child: Row(children: [
            AppAvatar(url: other?.avatarUrl, name: other?.name ?? '?', radius: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(other?.name ?? context.tr('messages'), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.w800)),
                if (_otherTyping) Text(context.tr('typing'), style: const TextStyle(fontSize: 12, color: kGreen)),
              ]),
            ),
          ]),
        ),
        actions: [
          PopupMenuButton<String>(
            onSelected: _menu,
            itemBuilder: (_) => [
              PopupMenuItem(value: 'profile', child: Text(context.tr('view_profile'))),
              PopupMenuItem(value: 'mute', child: Text(context.tr((_conv?.muted ?? false) ? 'unmute' : 'mute'))),
              PopupMenuItem(value: 'block', child: Text(context.tr((_conv?.blockedByMe ?? false) ? 'unblock' : 'block'))),
              PopupMenuItem(value: 'report', child: Text(context.tr('report_conversation'))),
            ],
          ),
        ],
      ),
      body: Column(children: [
        Expanded(
          child: _loading
              ? const LoadingView()
              : _error != null
                  ? ErrorState(error: _error!, onRetry: _load)
                  : reversed.isEmpty
                      ? EmptyState(icon: Icons.waving_hand_rounded, title: context.tr('say_hello'), subtitle: context.tr('say_hello_sub'))
                      : ListView.builder(
                          controller: _sc,
                          reverse: true,
                          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                          itemCount: reversed.length,
                          itemBuilder: (_, i) {
                            final m = reversed[i];
                            final older = i + 1 < reversed.length ? reversed[i + 1] : null;
                            final showDay = older == null || older.createdAt == null || m.createdAt == null || older.createdAt!.day != m.createdAt!.day || older.createdAt!.month != m.createdAt!.month;
                            return Column(children: [
                              if (showDay && m.createdAt != null)
                                Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 10),
                                  child: Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4), decoration: BoxDecoration(color: cs.surfaceContainerHighest, borderRadius: BorderRadius.circular(12)), child: Text(fmtDateTime(m.createdAt).substring(0, 10), style: const TextStyle(fontSize: 12))),
                                ),
                              _Bubble(message: m, mine: m.senderId == _me, onLongPress: m.senderId == _me ? () => _deleteMessage(m) : null),
                            ]);
                          },
                        ),
        ),
        if (_blocked)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            color: cs.surfaceContainerHighest,
            child: SafeArea(top: false, child: Text(context.tr((_conv?.blockedByMe ?? false) ? 'you_blocked' : 'blocked_you'), textAlign: TextAlign.center)),
          )
        else
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
              child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                IconButton(onPressed: _sending ? null : _sendMedia, icon: const Icon(Icons.add_photo_alternate_rounded, color: kGreen)),
                Expanded(
                  child: TextField(
                    controller: _input,
                    onChanged: _onTyping,
                    minLines: 1,
                    maxLines: 5,
                    textInputAction: TextInputAction.newline,
                    decoration: InputDecoration(hintText: context.tr('write_message'), contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12)),
                  ),
                ),
                const SizedBox(width: 6),
                IconButton.filled(
                  style: IconButton.styleFrom(backgroundColor: kGreen),
                  onPressed: _sending ? null : _sendText,
                  icon: _sending ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.send_rounded, color: Colors.white),
                ),
              ]),
            ),
          ),
      ]),
    );
  }
}

class _Bubble extends StatelessWidget {
  final ChatMessage message;
  final bool mine;
  final VoidCallback? onLongPress;
  const _Bubble({required this.message, required this.mine, this.onLongPress});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final bg = mine ? kGreen : (dark ? const Color(0xFF1E2B24) : Colors.white);
    final fg = mine ? Colors.white : cs.onSurface;
    final hasMedia = message.mediaUrl != null && message.mediaUrl!.isNotEmpty;
    return Align(
      alignment: mine ? AlignmentDirectional.centerEnd : AlignmentDirectional.centerStart,
      child: GestureDetector(
        onLongPress: onLongPress,
        child: Container(
          constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
          margin: const EdgeInsets.symmetric(vertical: 3),
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadiusDirectional.only(
              topStart: const Radius.circular(18),
              topEnd: const Radius.circular(18),
              bottomStart: Radius.circular(mine ? 18 : 4),
              bottomEnd: Radius.circular(mine ? 4 : 18),
            ),
            border: mine ? null : Border.all(color: cs.outlineVariant.withValues(alpha: 0.6)),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            if (hasMedia)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: message.mediaType == 'VIDEO'
                      ? SizedBox(width: 240, child: VideoBox(url: message.mediaUrl!))
                      : GestureDetector(onTap: () => openImage(context, [message.mediaUrl!]), child: NetImage(message.mediaUrl!, width: 240, height: 200)),
                ),
              ),
            if (message.body.isNotEmpty) Text(message.body, style: TextStyle(color: fg, fontSize: 15.5, height: 1.35)),
            const SizedBox(height: 2),
            Row(mainAxisSize: MainAxisSize.min, children: [
              Text(fmtTime(message.createdAt), style: TextStyle(fontSize: 10.5, color: fg.withValues(alpha: 0.7))),
              if (mine) ...[
                const SizedBox(width: 4),
                Icon(message.readAt != null ? Icons.done_all_rounded : Icons.done_rounded, size: 15, color: message.readAt != null ? const Color(0xFF9FE2B8) : Colors.white70),
              ],
            ]),
          ]),
        ),
      ),
    );
  }
}
