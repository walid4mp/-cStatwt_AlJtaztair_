import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/config.dart';
import '../core/i18n.dart';
import '../core/models.dart';
import '../core/session.dart';
import '../widgets/common.dart';
import 'deeplink.dart';

IconData notifIcon(String type) {
  switch (type) {
    case 'message':
      return Icons.chat_bubble_rounded;
    case 'like':
      return Icons.favorite_rounded;
    case 'comment':
      return Icons.mode_comment_rounded;
    case 'follow':
      return Icons.person_add_alt_1_rounded;
    case 'report_status':
    case 'new_report':
      return Icons.fact_check_rounded;
    case 'verification':
    case 'new_verification':
      return Icons.verified_rounded;
    case 'lf_match':
      return Icons.manage_search_rounded;
    case 'new_flag':
      return Icons.flag_rounded;
    case 'broadcast':
      return Icons.campaign_rounded;
    default:
      return Icons.notifications_rounded;
  }
}

class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key});
  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  List<AppNotification> _rows = [];
  bool _loading = true;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final rows = asMapList(await api.get('/notifications')).map(AppNotification.fromJson).toList();
      if (mounted) setState(() { _rows = rows; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e; _loading = false; });
    }
  }

  Future<void> _markAll() async {
    try {
      await api.post('/notifications/read', {});
      for (final n in _rows) { n.read = true; }
      if (mounted) setState(() {});
      Session.I.refreshBadges();
    } catch (e) {
      if (mounted) toast(context, errMsg(e), error: true);
    }
  }

  Future<void> _clear() async {
    final ok = await confirmDialog(context, title: context.tr('clear_all'), message: context.tr('delete_confirm'), confirmLabel: context.tr('clear_all'), danger: true);
    if (!ok) return;
    try {
      await api.delete('/notifications');
      if (mounted) setState(() => _rows = []);
      Session.I.refreshBadges();
    } catch (e) {
      if (mounted) toast(context, errMsg(e), error: true);
    }
  }

  Future<void> _open(AppNotification n) async {
    if (!n.read && n.id != null) {
      n.read = true;
      setState(() {});
      api.post('/notifications/read', {'ids': [n.id]}).then((_) => Session.I.refreshBadges()).catchError((_) {});
    }
    openTarget(n.type, n.data);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('notifications')), actions: [
        if (_rows.isNotEmpty) IconButton(tooltip: context.tr('mark_all_read'), onPressed: _markAll, icon: const Icon(Icons.done_all_rounded)),
        if (_rows.isNotEmpty) IconButton(tooltip: context.tr('clear_all'), onPressed: _clear, icon: const Icon(Icons.delete_sweep_rounded)),
      ]),
      body: _loading
          ? const LoadingView()
          : _error != null
              ? ErrorState(error: _error!, onRetry: _load)
              : _rows.isEmpty
                  ? EmptyState(icon: Icons.notifications_none_rounded, title: context.tr('no_notifications'))
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.separated(
                        itemCount: _rows.length,
                        separatorBuilder: (_, i) => const Divider(height: 1, indent: 72),
                        itemBuilder: (_, i) {
                          final n = _rows[i];
                          return Dismissible(
                            key: ValueKey(n.id ?? 'n$i'),
                            background: Container(color: kRed, alignment: AlignmentDirectional.centerStart, padding: const EdgeInsets.symmetric(horizontal: 20), child: const Icon(Icons.delete_rounded, color: Colors.white)),
                            secondaryBackground: Container(color: kRed, alignment: AlignmentDirectional.centerEnd, padding: const EdgeInsets.symmetric(horizontal: 20), child: const Icon(Icons.delete_rounded, color: Colors.white)),
                            onDismissed: (_) {
                              final id = n.id;
                              setState(() => _rows.removeAt(i));
                              if (id != null) api.delete('/notifications/$id').catchError((_) {});
                            },
                            child: ListTile(
                              tileColor: n.read ? null : kGreen.withValues(alpha: 0.07),
                              leading: CircleAvatar(backgroundColor: kGreen.withValues(alpha: 0.12), child: Icon(notifIcon(n.type), color: kGreen)),
                              title: Text(n.title, style: TextStyle(fontWeight: n.read ? FontWeight.w600 : FontWeight.w900)),
                              subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                if (n.body.isNotEmpty) Text(n.body, maxLines: 3, overflow: TextOverflow.ellipsis),
                                Text(timeAgo(context, n.createdAt), style: TextStyle(fontSize: 11.5, color: cs.onSurfaceVariant)),
                              ]),
                              onTap: () => _open(n),
                            ),
                          );
                        },
                      ),
                    ),
    );
  }
}
