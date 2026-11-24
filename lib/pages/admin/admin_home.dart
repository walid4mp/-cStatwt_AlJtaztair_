import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/config.dart';
import '../../core/i18n.dart';
import '../../core/models.dart';
import '../../core/session.dart';
import '../../core/wilayas.dart';
import '../../widgets/common.dart';
import '../posts.dart';
import '../reports.dart';
import 'admin_users.dart';

class AdminHome extends StatelessWidget {
  const AdminHome({super.key});

  @override
  Widget build(BuildContext context) {
    final isAdmin = Session.I.user?.isAdmin == true;
    final tabs = <(String, IconData, Widget)>[
      ('adm_dashboard', Icons.dashboard_rounded, const _Dashboard()),
      ('adm_reports', Icons.fact_check_rounded, const _AdminReports()),
      ('adm_users', Icons.people_alt_rounded, const AdminUsersTab()),
      ('adm_verification', Icons.verified_user_rounded, const _VerificationTab()),
      ('adm_flags', Icons.flag_rounded, const _FlagsTab()),
      ('adm_posts', Icons.dynamic_feed_rounded, const _AdminPosts()),
      if (isAdmin) ('adm_broadcast', Icons.campaign_rounded, const _BroadcastTab()),
      if (isAdmin) ('adm_settings', Icons.tune_rounded, const _SettingsTab()),
      ('adm_audit', Icons.history_rounded, const _AuditTab()),
    ];
    return DefaultTabController(
      length: tabs.length,
      child: Scaffold(
        appBar: AppBar(
          title: Text(context.tr('admin_center')),
          bottom: TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [for (final t in tabs) Tab(icon: Icon(t.$2, size: 20), text: context.tr(t.$1), height: 56)],
          ),
        ),
        body: TabBarView(children: [for (final t in tabs) t.$3]),
      ),
    );
  }
}

// ------------------------------------------------------------------ dashboard
class _Dashboard extends StatefulWidget {
  const _Dashboard();
  @override
  State<_Dashboard> createState() => _DashboardState();
}

class _DashboardState extends State<_Dashboard> {
  Map<String, dynamic>? _s;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final d = await api.getMap('/admin/stats');
      if (mounted) setState(() { _s = d; _error = null; });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = _s;
    if (s == null) return _error != null ? ErrorState(error: _error!, onRetry: _load) : const LoadingView();
    int n(String k) => (s[k] as num?)?.toInt() ?? 0;
    final byStatus = Map<String, dynamic>.from((s['byStatus'] as Map?) ?? {});
    final byWilaya = asMapList(s['byWilaya']);
    final series = Map<String, dynamic>.from((s['series'] as Map?) ?? {});
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(padding: const EdgeInsets.all(14), children: [
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          childAspectRatio: 1.9,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          children: [
            _Kpi(Icons.people_alt_rounded, context.tr('adm_users'), '${n('users')}', '+${n('newUsers7')} / 7d', kGreen),
            _Kpi(Icons.fact_check_rounded, context.tr('adm_reports'), '${n('reports')}', '+${n('newReports7')} / 7d', const Color(0xFF1565C0)),
            _Kpi(Icons.hourglass_top_rounded, context.tr('status_PENDING'), '${n('pendingReports')}', '', const Color(0xFFEF6C00)),
            _Kpi(Icons.dynamic_feed_rounded, context.tr('posts'), '${n('posts')}', '', const Color(0xFF6A1B9A)),
            _Kpi(Icons.flag_rounded, context.tr('adm_flags'), '${n('openFlags')}', '', kRed),
            _Kpi(Icons.verified_user_rounded, context.tr('adm_verification'), '${n('pendingVerifications')}', '', const Color(0xFF1E88E5)),
          ],
        ),
        SectionTitle(context.tr('reports_by_status')),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(children: [
              for (final st in kReportStatuses) _Bar(label: context.tr('status_$st'), value: (byStatus[st] as num?)?.toInt() ?? 0, max: n('reports'), color: statusColor(st)),
            ]),
          ),
        ),
        SectionTitle(context.tr('activity_14d')),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(children: [
              _Spark(label: context.tr('adm_reports'), rows: asMapList(series['reports']), color: const Color(0xFF1565C0)),
              const SizedBox(height: 10),
              _Spark(label: context.tr('adm_users'), rows: asMapList(series['users']), color: kGreen),
              const SizedBox(height: 10),
              _Spark(label: context.tr('posts'), rows: asMapList(series['posts']), color: const Color(0xFF6A1B9A)),
            ]),
          ),
        ),
        if (byWilaya.isNotEmpty) ...[
          SectionTitle(context.tr('top_wilayas')),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(children: [
                for (final w in byWilaya) _Bar(label: wilayaDisplay(w['wilaya']?.toString(), context.lang), value: (w['count'] as num?)?.toInt() ?? 0, max: (byWilaya.first['count'] as num?)?.toInt() ?? 1, color: kGreen),
              ]),
            ),
          ),
        ],
      ]),
    );
  }
}

class _Kpi extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final String sub;
  final Color color;
  const _Kpi(this.icon, this.label, this.value, this.sub, this.color);
  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            Container(width: 42, height: 42, decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)), child: Icon(icon, color: color)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
                Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                if (sub.isNotEmpty) Text(sub, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w700)),
              ]),
            ),
          ]),
        ),
      );
}

class _Bar extends StatelessWidget {
  final String label;
  final int value;
  final int max;
  final Color color;
  const _Bar({required this.label, required this.value, required this.max, required this.color});
  @override
  Widget build(BuildContext context) {
    final f = max <= 0 ? 0.0 : (value / max).clamp(0.0, 1.0);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(children: [
        SizedBox(width: 96, child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5))),
        Expanded(child: ClipRRect(borderRadius: BorderRadius.circular(6), child: LinearProgressIndicator(value: f, minHeight: 10, color: color, backgroundColor: color.withValues(alpha: 0.12)))),
        SizedBox(width: 40, child: Text('$value', textAlign: TextAlign.end, style: const TextStyle(fontWeight: FontWeight.w800))),
      ]),
    );
  }
}

class _Spark extends StatelessWidget {
  final String label;
  final List<Map<String, dynamic>> rows;
  final Color color;
  const _Spark({required this.label, required this.rows, required this.color});
  @override
  Widget build(BuildContext context) {
    final vals = rows.map((r) => (r['count'] as num?)?.toInt() ?? 0).toList();
    final peak = vals.isEmpty ? 1 : vals.reduce((a, b) => a > b ? a : b);
    final total = vals.fold<int>(0, (a, b) => a + b);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [Expanded(child: Text(label, style: const TextStyle(fontWeight: FontWeight.w700))), Text('$total', style: TextStyle(color: color, fontWeight: FontWeight.w900))]),
      const SizedBox(height: 6),
      SizedBox(
        height: 46,
        child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          for (final v in vals)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 1.5),
                child: FractionallySizedBox(heightFactor: peak == 0 ? 0.04 : (v / peak).clamp(0.04, 1.0), child: Container(decoration: BoxDecoration(color: color.withValues(alpha: v == 0 ? 0.25 : 0.85), borderRadius: BorderRadius.circular(3)))),
              ),
            ),
        ]),
      ),
    ]);
  }
}

// ------------------------------------------------------------------ reports
class _AdminReports extends StatefulWidget {
  const _AdminReports();
  @override
  State<_AdminReports> createState() => _AdminReportsState();
}

class _AdminReportsState extends State<_AdminReports> {
  String _status = 'PENDING';

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      SizedBox(
        height: 54,
        child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 10), children: [
          for (final s in ['ALL', ...kReportStatuses])
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 8),
              child: Center(child: ChoiceChip(label: Text(s == 'ALL' ? context.tr('all') : context.tr('status_$s')), selected: _status == s, onSelected: (_) => setState(() => _status = s))),
            ),
        ]),
      ),
      Expanded(child: ReportsList(key: ValueKey(_status), query: _status == 'ALL' ? '' : 'status=$_status')),
    ]);
  }
}

// ------------------------------------------------------------------ posts
class _AdminPosts extends StatefulWidget {
  const _AdminPosts();
  @override
  State<_AdminPosts> createState() => _AdminPostsState();
}

class _AdminPostsState extends State<_AdminPosts> {
  List<Post> _rows = [];
  bool _hiddenOnly = false;
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
      final rows = asMapList(await api.get('/admin/posts${_hiddenOnly ? '?hidden=1' : ''}')).map(Post.fromJson).toList();
      if (mounted) setState(() { _rows = rows; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e; _loading = false; });
    }
  }

  Future<void> _hide(Post p) async {
    try {
      await api.patch('/admin/posts/${p.id}', {'hidden': !p.hidden});
      _load();
    } catch (e) {
      if (mounted) toast(context, errMsg(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      SwitchListTile(dense: true, value: _hiddenOnly, title: Text(context.tr('hidden_only')), onChanged: (v) { setState(() => _hiddenOnly = v); _load(); }),
      Expanded(
        child: _loading
            ? const LoadingView()
            : _error != null
                ? ErrorState(error: _error!, onRetry: _load)
                : _rows.isEmpty
                    ? EmptyState(icon: Icons.dynamic_feed_rounded, title: context.tr('no_posts'))
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: ListView.builder(
                          itemCount: _rows.length,
                          itemBuilder: (_, i) {
                            final p = _rows[i];
                            return Card(
                              margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                              child: ListTile(
                                leading: AppAvatar(url: p.author?.avatarUrl, name: p.author?.name ?? '?'),
                                title: Text(p.title.isNotEmpty ? p.title : p.body, maxLines: 2, overflow: TextOverflow.ellipsis),
                                subtitle: Text('${p.author?.name ?? ''} • ${timeAgo(context, p.createdAt)}${p.hidden ? ' • ${context.tr('hidden')}' : ''}'),
                                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PostDetailPage(postId: p.id))),
                                trailing: IconButton(tooltip: context.tr(p.hidden ? 'unhide' : 'hide'), icon: Icon(p.hidden ? Icons.visibility_rounded : Icons.visibility_off_rounded), onPressed: () => _hide(p)),
                              ),
                            );
                          },
                        ),
                      ),
      ),
    ]);
  }
}

// ------------------------------------------------------------------ verification
class _VerificationTab extends StatefulWidget {
  const _VerificationTab();
  @override
  State<_VerificationTab> createState() => _VerificationTabState();
}

class _VerificationTabState extends State<_VerificationTab> {
  String _status = 'PENDING';
  List<Map<String, dynamic>> _rows = [];
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
      final rows = asMapList(await api.get('/admin/verification?status=$_status'));
      if (mounted) setState(() { _rows = rows; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e; _loading = false; });
    }
  }

  Future<void> _decide(Map<String, dynamic> r, String status) async {
    String? note;
    if (status == 'REJECTED') {
      note = await promptDialog(context, title: context.tr('rejection_note'), allowEmpty: true);
      if (note == null) return;
    }
    try {
      await api.patch('/admin/verification/${r['id']}', {'status': status, if (note != null) 'note': note});
      _load();
    } catch (e) {
      if (mounted) toast(context, errMsg(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      SizedBox(
        height: 54,
        child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 10), children: [
          for (final s in const ['PENDING', 'APPROVED', 'REJECTED'])
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 8),
              child: Center(child: ChoiceChip(label: Text(context.tr('ver_$s')), selected: _status == s, onSelected: (_) { setState(() => _status = s); _load(); })),
            ),
        ]),
      ),
      Expanded(
        child: _loading
            ? const LoadingView()
            : _error != null
                ? ErrorState(error: _error!, onRetry: _load)
                : _rows.isEmpty
                    ? EmptyState(icon: Icons.verified_user_outlined, title: context.tr('no_results'))
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: ListView.builder(
                          itemCount: _rows.length,
                          itemBuilder: (_, i) {
                            final r = _rows[i];
                            final u = AppUser.maybe(r['user']);
                            final doc = r['documentUrl']?.toString();
                            return Card(
                              margin: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  if (u != null) Row(children: [AppAvatar(url: u.avatarUrl, name: u.name), const SizedBox(width: 10), Expanded(child: UserNameRow(u)), Text(timeAgo(context, DateTime.tryParse('${r['createdAt']}')?.toLocal()), style: const TextStyle(fontSize: 12))]),
                                  const SizedBox(height: 8),
                                  Text((r['reason'] ?? '').toString()),
                                  if (doc != null && doc.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: GestureDetector(onTap: () => openImage(context, [doc]), child: ClipRRect(borderRadius: BorderRadius.circular(12), child: NetImage(doc, height: 150, width: double.infinity)))),
                                  const SizedBox(height: 8),
                                  Row(children: [
                                    if (_status != 'APPROVED') Expanded(child: FilledButton.icon(onPressed: () => _decide(r, 'APPROVED'), icon: const Icon(Icons.check_rounded), label: Text(context.tr('approve')))),
                                    if (_status == 'PENDING') const SizedBox(width: 8),
                                    if (_status != 'REJECTED') Expanded(child: OutlinedButton.icon(style: OutlinedButton.styleFrom(foregroundColor: kRed), onPressed: () => _decide(r, 'REJECTED'), icon: const Icon(Icons.close_rounded), label: Text(context.tr('reject')))),
                                  ]),
                                ]),
                              ),
                            );
                          },
                        ),
                      ),
      ),
    ]);
  }
}

// ------------------------------------------------------------------ flags
class _FlagsTab extends StatefulWidget {
  const _FlagsTab();
  @override
  State<_FlagsTab> createState() => _FlagsTabState();
}

class _FlagsTabState extends State<_FlagsTab> {
  String _status = 'OPEN';
  List<Map<String, dynamic>> _rows = [];
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
      final rows = asMapList(await api.get('/admin/flags?status=$_status'));
      if (mounted) setState(() { _rows = rows; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e; _loading = false; });
    }
  }

  Future<void> _handle(Map<String, dynamic> f, String status, {String? action}) async {
    try {
      await api.patch('/admin/flags/${f['id']}', {'status': status, if (action != null) 'action': action});
      _load();
    } catch (e) {
      if (mounted) toast(context, errMsg(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      SizedBox(
        height: 54,
        child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 10), children: [
          for (final s in const ['OPEN', 'RESOLVED', 'DISMISSED'])
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 8),
              child: Center(child: ChoiceChip(label: Text(context.tr('flag_$s')), selected: _status == s, onSelected: (_) { setState(() => _status = s); _load(); })),
            ),
        ]),
      ),
      Expanded(
        child: _loading
            ? const LoadingView()
            : _error != null
                ? ErrorState(error: _error!, onRetry: _load)
                : _rows.isEmpty
                    ? EmptyState(icon: Icons.flag_outlined, title: context.tr('no_results'))
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: ListView.builder(
                          itemCount: _rows.length,
                          itemBuilder: (_, i) {
                            final f = _rows[i];
                            final target = f['target'] is Map ? Map<String, dynamic>.from(f['target'] as Map) : null;
                            final type = '${f['targetType']}';
                            final reporter = AppUser.maybe(f['reporter']);
                            return Card(
                              margin: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Row(children: [
                                    Chip(label: Text(context.tr('target_$type')), visualDensity: VisualDensity.compact),
                                    const Spacer(),
                                    Text(timeAgo(context, DateTime.tryParse('${f['createdAt']}')?.toLocal()), style: const TextStyle(fontSize: 12)),
                                  ]),
                                  if (target != null) Container(width: double.infinity, margin: const EdgeInsets.symmetric(vertical: 6), padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(10)), child: Text('${target['text'] ?? ''}', maxLines: 4, overflow: TextOverflow.ellipsis))
                                  else Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: Text(context.tr('target_missing'), style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant))),
                                  if ((f['reason'] ?? '').toString().isNotEmpty) Text('${context.tr('reason')}: ${f['reason']}'),
                                  if (reporter != null) Text('${context.tr('reported_by')}: ${reporter.name}', style: const TextStyle(fontSize: 12)),
                                  if (_status == 'OPEN')
                                    Padding(
                                      padding: const EdgeInsets.only(top: 8),
                                      child: Wrap(spacing: 8, runSpacing: 4, children: [
                                        if (type == 'POST') OutlinedButton(onPressed: () => _handle(f, 'RESOLVED', action: 'HIDE_TARGET'), child: Text(context.tr('hide'))),
                                        if (type == 'POST' || type == 'COMMENT' || type == 'LOSTFOUND') OutlinedButton(style: OutlinedButton.styleFrom(foregroundColor: kRed), onPressed: () => _handle(f, 'RESOLVED', action: 'DELETE_TARGET'), child: Text(context.tr('delete'))),
                                        if (type == 'USER' || type == 'CONVERSATION') OutlinedButton(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => AdminUserPage(userId: '${f['targetId']}'))), child: Text(context.tr('manage_user'))),
                                        FilledButton.tonal(onPressed: () => _handle(f, 'RESOLVED'), child: Text(context.tr('resolve'))),
                                        TextButton(onPressed: () => _handle(f, 'DISMISSED'), child: Text(context.tr('dismiss'))),
                                      ]),
                                    ),
                                ]),
                              ),
                            );
                          },
                        ),
                      ),
      ),
    ]);
  }
}

// ------------------------------------------------------------------ broadcast
class _BroadcastTab extends StatefulWidget {
  const _BroadcastTab();
  @override
  State<_BroadcastTab> createState() => _BroadcastTabState();
}

class _BroadcastTabState extends State<_BroadcastTab> {
  final TextEditingController _title = TextEditingController();
  final TextEditingController _body = TextEditingController();
  final TextEditingController _user = TextEditingController();
  String _audience = 'ALL';
  String? _wilaya;
  bool _busy = false;
  List<Map<String, dynamic>> _history = [];

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    _user.dispose();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    try {
      final h = asMapList(await api.get('/admin/broadcasts'));
      if (mounted) setState(() => _history = h);
    } catch (_) {}
  }

  Future<void> _send() async {
    if (_title.text.trim().isEmpty || _body.text.trim().isEmpty) {
      toast(context, context.tr('err_MISSING_FIELDS'), error: true);
      return;
    }
    final ok = await confirmDialog(context, title: context.tr('send'), message: context.tr('broadcast_confirm'), confirmLabel: context.tr('send'));
    if (!ok) return;
    setState(() => _busy = true);
    try {
      final d = await api.post('/admin/broadcast', {
        'title': _title.text.trim(),
        'body': _body.text.trim(),
        'audience': _audience,
        if (_audience == 'WILAYA') 'wilaya': _wilaya ?? '',
        if (_audience == 'USER') 'userId': _user.text.trim(),
      });
      if (!mounted) return;
      toast(context, '${context.tr('sent_to')} ${(d as Map)['sent']}');
      _title.clear();
      _body.clear();
      _loadHistory();
    } catch (e) {
      if (mounted) toast(context, errMsg(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(padding: const EdgeInsets.all(14), children: [
      Wrap(spacing: 8, children: [
        for (final a in const ['ALL', 'WILAYA', 'USER', 'STAFF']) ChoiceChip(label: Text(context.tr('aud_$a')), selected: _audience == a, onSelected: (_) => setState(() => _audience = a)),
      ]),
      const SizedBox(height: 10),
      if (_audience == 'WILAYA')
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: OutlinedButton.icon(
            onPressed: () async {
              final w = await pickWilaya(context, current: _wilaya);
              if (w != null && w.isNotEmpty && mounted) setState(() => _wilaya = w);
            },
            icon: const Icon(Icons.location_city_rounded),
            label: Text(_wilaya == null ? context.tr('wilaya') : wilayaDisplay(_wilaya, context.lang)),
          ),
        ),
      if (_audience == 'USER') Padding(padding: const EdgeInsets.only(bottom: 10), child: TextField(controller: _user, decoration: InputDecoration(labelText: context.tr('username_or_id')))),
      TextField(controller: _title, maxLength: 120, decoration: InputDecoration(labelText: context.tr('title'))),
      TextField(controller: _body, maxLength: 500, maxLines: 4, decoration: InputDecoration(labelText: context.tr('message'), alignLabelWithHint: true)),
      const SizedBox(height: 8),
      BusyButton(busy: _busy, onPressed: _send, label: context.tr('send'), icon: Icons.campaign_rounded),
      SectionTitle(context.tr('broadcast_history')),
      for (final h in _history)
        Card(
          child: ListTile(
            title: Text('${h['title']}', maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text('${h['body']}', maxLines: 2, overflow: TextOverflow.ellipsis),
            trailing: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Text('${h['sentCount']}', style: const TextStyle(fontWeight: FontWeight.w900)), Text(context.tr('aud_${h['audience']}'), style: const TextStyle(fontSize: 10))]),
          ),
        ),
    ]);
  }
}

// ------------------------------------------------------------------ settings
class _SettingsTab extends StatefulWidget {
  const _SettingsTab();
  @override
  State<_SettingsTab> createState() => _SettingsTabState();
}

class _SettingsTabState extends State<_SettingsTab> {
  Map<String, dynamic>? _s;
  Object? _error;
  final TextEditingController _ann = TextEditingController();
  final TextEditingController _minV = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _ann.dispose();
    _minV.dispose();
    super.dispose();
  }

  bool _b(String k) => _s?[k] == true || _s?[k] == 'true';

  Future<void> _load() async {
    try {
      final d = await api.getMap('/admin/settings');
      if (!mounted) return;
      setState(() {
        _s = d;
        _ann.text = '${d['announcement'] ?? ''}';
        _minV.text = '${d['minAppVersion'] ?? ''}';
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _put(Map<String, dynamic> body) async {
    try {
      final d = await api.put('/admin/settings', body);
      if (mounted) {
        setState(() => _s = Map<String, dynamic>.from(d as Map));
        toast(context, context.tr('saved'));
      }
    } catch (e) {
      if (mounted) toast(context, errMsg(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_s == null) return _error != null ? ErrorState(error: _error!, onRetry: _load) : const LoadingView();
    final level = '${_s!['announcementLevel'] ?? 'info'}';
    return ListView(children: [
      SwitchListTile(title: Text(context.tr('set_require_review')), subtitle: Text(context.tr('set_require_review_hint')), value: _b('requireReportReview'), onChanged: (v) => _put({'requireReportReview': v})),
      SwitchListTile(title: Text(context.tr('set_registration')), value: _b('registrationOpen'), onChanged: (v) => _put({'registrationOpen': v})),
      SwitchListTile(title: Text(context.tr('set_anonymous')), value: _b('allowAnonymousReports'), onChanged: (v) => _put({'allowAnonymousReports': v})),
      SwitchListTile(title: Text(context.tr('set_maintenance')), subtitle: Text(context.tr('set_maintenance_hint')), value: _b('maintenance'), onChanged: (v) => _put({'maintenance': v})),
      const Divider(),
      Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(context.tr('set_announcement'), style: const TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          TextField(controller: _ann, maxLines: 3, maxLength: 500, decoration: InputDecoration(hintText: context.tr('set_announcement_hint'))),
          Wrap(spacing: 8, children: [for (final l in const ['info', 'warning', 'danger']) ChoiceChip(label: Text(context.tr('lvl_$l')), selected: level == l, onSelected: (_) => _put({'announcementLevel': l}))]),
          const SizedBox(height: 8),
          FilledButton(onPressed: () => _put({'announcement': _ann.text.trim()}), child: Text(context.tr('save'))),
          const SizedBox(height: 18),
          Text(context.tr('set_min_version'), style: const TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          TextField(controller: _minV, decoration: const InputDecoration(hintText: '2.0.0')),
          const SizedBox(height: 8),
          FilledButton.tonal(onPressed: () => _put({'minAppVersion': _minV.text.trim()}), child: Text(context.tr('save'))),
        ]),
      ),
    ]);
  }
}

// ------------------------------------------------------------------ audit
class _AuditTab extends StatefulWidget {
  const _AuditTab();
  @override
  State<_AuditTab> createState() => _AuditTabState();
}

class _AuditTabState extends State<_AuditTab> {
  List<Map<String, dynamic>> _rows = [];
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
      final rows = asMapList(await api.get('/admin/audit'));
      if (mounted) setState(() { _rows = rows; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e; _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const LoadingView();
    if (_error != null) return ErrorState(error: _error!, onRetry: _load);
    if (_rows.isEmpty) return EmptyState(icon: Icons.history_rounded, title: context.tr('no_results'));
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        itemCount: _rows.length,
        separatorBuilder: (_, i) => const Divider(height: 1),
        itemBuilder: (_, i) {
          final r = _rows[i];
          return ListTile(
            dense: true,
            leading: const Icon(Icons.history_rounded),
            title: Text('${r['action']}  •  ${r['targetType'] ?? ''}', style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text('${r['actorName'] ?? r['actorId'] ?? ''}${(r['detail'] ?? '').toString().isEmpty ? '' : '\n${r['detail']}'}\n${fmtDateTime(DateTime.tryParse('${r['createdAt']}')?.toLocal())}'),
            isThreeLine: true,
          );
        },
      ),
    );
  }
}
