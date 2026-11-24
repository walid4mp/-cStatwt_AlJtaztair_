import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/config.dart';
import '../../core/i18n.dart';
import '../../core/models.dart';
import '../../core/session.dart';
import '../../core/wilayas.dart';
import '../../widgets/common.dart';
import '../chat.dart';
import '../profile.dart';

class AdminUsersTab extends StatefulWidget {
  const AdminUsersTab({super.key});
  @override
  State<AdminUsersTab> createState() => _AdminUsersTabState();
}

class _AdminUsersTabState extends State<AdminUsersTab> {
  final TextEditingController _q = TextEditingController();
  final Debouncer _deb = Debouncer();
  String _filter = 'all';
  List<AppUser> _rows = [];
  bool _loading = true;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _deb.dispose();
    _q.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final qs = <String>[
        if (_q.text.trim().isNotEmpty) 'q=${Uri.encodeComponent(_q.text.trim())}',
        if (_filter == 'banned') 'banned=1',
        if (_filter == 'verified') 'verified=1',
        if (_filter == 'staff') 'role=MODERATOR',
        if (_filter == 'admin') 'role=ADMIN',
      ];
      final rows = asMapList(await api.get('/admin/users${qs.isEmpty ? '' : '?${qs.join('&')}'}')).map(AppUser.fromJson).toList();
      if (mounted) setState(() { _rows = rows; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e; _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
        child: TextField(controller: _q, onChanged: (_) => _deb.run(_load), decoration: InputDecoration(hintText: context.tr('search_users_admin'), prefixIcon: const Icon(Icons.search_rounded), isDense: true)),
      ),
      SizedBox(
        height: 52,
        child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 10), children: [
          for (final f in const ['all', 'banned', 'verified', 'staff', 'admin'])
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 8),
              child: Center(child: ChoiceChip(label: Text(context.tr('uf_$f')), selected: _filter == f, onSelected: (_) { setState(() => _filter = f); _load(); })),
            ),
        ]),
      ),
      Expanded(
        child: _loading
            ? const LoadingView()
            : _error != null
                ? ErrorState(error: _error!, onRetry: _load)
                : _rows.isEmpty
                    ? EmptyState(icon: Icons.people_outline_rounded, title: context.tr('no_results'))
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: ListView.separated(
                          itemCount: _rows.length,
                          separatorBuilder: (_, i) => const Divider(height: 1, indent: 72),
                          itemBuilder: (_, i) {
                            final u = _rows[i];
                            return ListTile(
                              leading: AppAvatar(url: u.avatarUrl, name: u.name),
                              title: UserNameRow(u),
                              subtitle: Text('@${u.username} • ${u.email ?? ''}', maxLines: 1, overflow: TextOverflow.ellipsis),
                              trailing: u.banned ? const Icon(Icons.block_rounded, color: kRed) : (u.role != 'USER' ? Text(u.role, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800)) : null),
                              onTap: () async {
                                await Navigator.push(context, MaterialPageRoute(builder: (_) => AdminUserPage(userId: u.id)));
                                _load();
                              },
                            );
                          },
                        ),
                      ),
      ),
    ]);
  }
}

class AdminUserPage extends StatefulWidget {
  final String userId;
  const AdminUserPage({super.key, required this.userId});
  @override
  State<AdminUserPage> createState() => _AdminUserPageState();
}

class _AdminUserPageState extends State<AdminUserPage> {
  AppUser? _u;
  Map<String, dynamic> _counts = {};
  Object? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final d = await api.getMap('/admin/users/${widget.userId}');
      if (!mounted) return;
      setState(() {
        _u = AppUser.maybe(d['user']);
        _counts = Map<String, dynamic>.from((d['counts'] as Map?) ?? {});
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() { _error = e; _loading = false; });
    }
  }

  Future<void> _patch(Map<String, dynamic> body) async {
    try {
      final d = await api.patch('/admin/users/${widget.userId}', body);
      if (!mounted) return;
      setState(() => _u = AppUser.maybe((d as Map)['user']));
      toast(context, context.tr('done'));
    } catch (e) {
      if (mounted) toast(context, errMsg(e), error: true);
    }
  }

  Future<void> _ban() async {
    final u = _u!;
    if (u.banned) return _patch({'banned': false});
    final reason = await promptDialog(context, title: context.tr('ban_user'), hint: context.tr('ban_reason'), allowEmpty: true);
    if (reason == null) return;
    await _patch({'banned': true, 'bannedReason': reason});
  }

  Future<void> _role() async {
    final r = await pickFromList<String>(context, title: context.tr('role'), items: const ['USER', 'MODERATOR', 'ADMIN'], label: (x) => context.tr('role_$x'));
    if (r != null) await _patch({'role': r});
  }

  Future<void> _reset() async {
    final ok = await confirmDialog(context, title: context.tr('reset_password'), message: context.tr('reset_password_msg'), confirmLabel: context.tr('reset_password'));
    if (!ok) return;
    try {
      final d = await api.post('/admin/users/${widget.userId}/reset-password', {});
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(ctx.tr('temp_password')),
          content: SelectableText((d as Map)['tempPassword'].toString(), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: 1.5)),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: Text(ctx.tr('ok')))],
        ),
      );
    } catch (e) {
      if (mounted) toast(context, errMsg(e), error: true);
    }
  }

  Future<void> _delete() async {
    final ok = await confirmDialog(context, title: context.tr('delete_account'), message: context.tr('delete_user_msg'), confirmLabel: context.tr('delete'), danger: true);
    if (!ok) return;
    try {
      await api.delete('/admin/users/${widget.userId}');
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) toast(context, errMsg(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final u = _u;
    final me = Session.I.user;
    final isAdmin = me?.isAdmin == true;
    final self = u?.id == me?.id;
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(u?.name ?? context.tr('manage_user'))),
      body: _loading
          ? const LoadingView()
          : u == null
              ? ErrorState(error: _error ?? 'x', onRetry: _load)
              : ListView(padding: const EdgeInsets.all(16), children: [
                  Center(child: AppAvatar(url: u.avatarUrl, name: u.name, radius: 42)),
                  const SizedBox(height: 8),
                  Center(child: UserNameRow(u, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900))),
                  Center(child: Text('@${u.username}', style: TextStyle(color: cs.onSurfaceVariant))),
                  Center(child: Text(u.email ?? '', style: TextStyle(color: cs.onSurfaceVariant))),
                  if (u.banned)
                    Card(color: kRed.withValues(alpha: 0.1), child: ListTile(leading: const Icon(Icons.block_rounded, color: kRed), title: Text(context.tr('banned')), subtitle: Text(u.bannedReason ?? ''))),
                  const SizedBox(height: 8),
                  Card(
                    child: Column(children: [
                      _kv(context.tr('role'), context.tr('role_${u.role}')),
                      _kv(context.tr('wilaya'), (u.wilaya ?? '').isEmpty ? '-' : wilayaDisplay(u.wilaya, context.lang)),
                      _kv(context.tr('phone'), (u.phone ?? '').isEmpty ? '-' : u.phone!),
                      _kv(context.tr('joined'), fmtDateTime(u.createdAt)),
                      _kv(context.tr('last_seen'), fmtDateTime(u.lastSeenAt)),
                      _kv(context.tr('posts'), '${_counts['posts'] ?? 0}'),
                      _kv(context.tr('reports'), '${_counts['reports'] ?? 0}'),
                      _kv(context.tr('comments'), '${_counts['comments'] ?? 0}'),
                      _kv(context.tr('flags'), '${_counts['flags'] ?? 0}'),
                    ]),
                  ),
                  const SizedBox(height: 10),
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    FilledButton.tonalIcon(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => UserProfilePage(userId: u.id))), icon: const Icon(Icons.person_rounded), label: Text(context.tr('view_profile'))),
                    if (!self) FilledButton.tonalIcon(onPressed: () => openChatWith(context, u), icon: const Icon(Icons.chat_bubble_rounded), label: Text(context.tr('message'))),
                    FilledButton.tonalIcon(onPressed: () => _patch({'isVerified': !u.verified}), icon: Icon(u.verified ? Icons.verified_outlined : Icons.verified_rounded), label: Text(context.tr(u.verified ? 'remove_verification' : 'verify_user'))),
                    if (!self) FilledButton.tonalIcon(onPressed: _ban, icon: Icon(u.banned ? Icons.lock_open_rounded : Icons.block_rounded), label: Text(context.tr(u.banned ? 'unban_user' : 'ban_user'))),
                    if (isAdmin && !self) FilledButton.tonalIcon(onPressed: _role, icon: const Icon(Icons.admin_panel_settings_rounded), label: Text(context.tr('change_role'))),
                    if (isAdmin && !self) FilledButton.tonalIcon(onPressed: _reset, icon: const Icon(Icons.lock_reset_rounded), label: Text(context.tr('reset_password'))),
                    if (isAdmin && !self) FilledButton.icon(style: FilledButton.styleFrom(backgroundColor: kRed), onPressed: _delete, icon: const Icon(Icons.delete_forever_rounded), label: Text(context.tr('delete'))),
                  ]),
                ]),
    );
  }

  Widget _kv(String k, String v) => ListTile(dense: true, title: Text(k, style: const TextStyle(fontWeight: FontWeight.w700)), trailing: Text(v));
}
