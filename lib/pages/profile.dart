import 'dart:io';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/api.dart';
import '../core/config.dart';
import '../core/i18n.dart';
import '../core/models.dart';
import '../core/session.dart';
import '../core/wilayas.dart';
import '../widgets/common.dart';
import '../widgets/header.dart';
import '../widgets/media_picker.dart';
import 'admin/admin_home.dart';
import 'admin/admin_users.dart';
import 'auth.dart';
import 'chat.dart';
import 'lostfound.dart';
import 'notifications.dart';
import 'posts.dart';
import 'reports.dart';
import 'settings.dart';
import 'verification.dart';

Future<void> launchContact(BuildContext context, String value, {bool whatsapp = false}) async {
  final digits = value.replaceAll(RegExp(r'[^0-9+]'), '');
  var normalized = digits;
  if (digits.startsWith('+')) {
    normalized = digits.substring(1);
  } else if (digits.startsWith('00')) {
    normalized = digits.substring(2);
  } else if (digits.startsWith('0')) {
    normalized = '213${digits.substring(1)}';
  }
  final uri = whatsapp ? Uri.parse('https://wa.me/$normalized') : Uri(scheme: 'tel', path: digits);
  try {
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) toast(context, context.tr('cannot_open'), error: true);
  } catch (_) {
    if (context.mounted) toast(context, context.tr('cannot_open'), error: true);
  }
}

Future<void> openChatWith(BuildContext context, AppUser other) async {
  try {
    final d = await api.post('/conversations', {'userId': other.id});
    final c = Conversation.fromJson(Map<String, dynamic>.from(d as Map));
    if (!context.mounted) return;
    Navigator.push(context, MaterialPageRoute(builder: (_) => ChatPage(conversationId: c.id, conversation: c)));
  } catch (e) {
    if (context.mounted) toast(context, errMsg(e), error: true);
  }
}

// ======================================================================== my profile tab
class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});
  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  Map<String, dynamic> _stats = {};
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      await Session.I.refreshMe();
      final id = Session.I.userId;
      if (id != null) {
        final d = await api.getMap('/users/$id');
        if (mounted) setState(() => _stats = Map<String, dynamic>.from((d['stats'] as Map?) ?? {}));
      }
      if (mounted) setState(() => _error = null);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _edit() async {
    final u = Session.I.user;
    if (u == null) return;
    final updated = await Navigator.push<AppUser>(context, MaterialPageRoute(builder: (_) => EditProfilePage(user: u)));
    if (updated != null && mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Session.I,
      builder: (context, _) {
        final user = Session.I.user;
        final cs = Theme.of(context).colorScheme;
        return Column(children: [
          TopHeader(title: context.tr('nav_account'), subtitle: context.tr('account_sub')),
          Expanded(
            child: user == null
                ? (_error != null ? ErrorState(error: _error!, onRetry: _load) : const LoadingView())
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 100), children: [
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(18),
                          child: Column(children: [
                            Row(children: [
                              GestureDetector(
                                onTap: user.avatarUrl == null ? null : () => openImage(context, [user.avatarUrl!]),
                                child: AppAvatar(url: user.avatarUrl, name: user.name, radius: 40),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  UserNameRow(user, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
                                  Text('@${user.username}', style: TextStyle(color: cs.onSurfaceVariant)),
                                  if ((user.wilaya ?? '').isNotEmpty) Row(children: [Icon(Icons.location_on_outlined, size: 15, color: cs.onSurfaceVariant), const SizedBox(width: 2), Text(wilayaDisplay(user.wilaya, context.lang), style: TextStyle(color: cs.onSurfaceVariant))]),
                                ]),
                              ),
                            ]),
                            if ((user.bio ?? '').isNotEmpty) Padding(padding: const EdgeInsets.only(top: 12), child: SizedBox(width: double.infinity, child: Text(user.bio!, style: const TextStyle(height: 1.4)))),
                            const SizedBox(height: 14),
                            Row(children: [
                              _Stat(value: '${_stats['posts'] ?? 0}', label: context.tr('posts')),
                              _Stat(value: '${_stats['followers'] ?? 0}', label: context.tr('followers')),
                              _Stat(value: '${_stats['following'] ?? 0}', label: context.tr('following')),
                            ]),
                            const SizedBox(height: 14),
                            SizedBox(width: double.infinity, child: FilledButton.icon(onPressed: _edit, icon: const Icon(Icons.edit_rounded), label: Text(context.tr('edit_profile')))),
                          ]),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Card(
                        clipBehavior: Clip.antiAlias,
                        child: Column(children: [
                          if (user.isStaff) _Tile(Icons.admin_panel_settings_rounded, context.tr('admin_center'), kRed, () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminHome()))),
                          _Tile(Icons.fact_check_rounded, context.tr('my_reports'), kGreen, () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MyReportsPage()))),
                          _Tile(Icons.dynamic_feed_rounded, context.tr('my_posts'), kGreen, () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MyPostsPage()))),
                          _Tile(Icons.bookmark_rounded, context.tr('saved_posts'), const Color(0xFF6A1B9A), () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SavedPostsPage()))),
                          _Tile(Icons.manage_search_rounded, context.tr('lost_found'), const Color(0xFF00838F), () => Navigator.push(context, MaterialPageRoute(builder: (_) => const LostFoundPage()))),
                          _Tile(Icons.notifications_rounded, context.tr('notifications'), const Color(0xFFEF6C00), () => Navigator.push(context, MaterialPageRoute(builder: (_) => const NotificationsPage()))),
                          _Tile(Icons.verified_user_rounded, context.tr('request_verification'), const Color(0xFF1E88E5), () => Navigator.push(context, MaterialPageRoute(builder: (_) => const VerificationPage()))),
                          _Tile(Icons.settings_rounded, context.tr('settings'), cs.onSurfaceVariant, () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsPage()))),
                        ]),
                      ),
                      const SizedBox(height: 14),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(foregroundColor: kRed, side: const BorderSide(color: kRed)),
                        onPressed: () async {
                          final ok = await confirmDialog(context, title: context.tr('logout'), message: context.tr('logout_msg'), confirmLabel: context.tr('logout'), danger: true);
                          if (!ok) return;
                          await Session.I.logout();
                          navigatorKey.currentState?.pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const WelcomePage()), (r) => false);
                        },
                        icon: const Icon(Icons.logout_rounded),
                        label: Text(context.tr('logout')),
                      ),
                    ]),
                  ),
          ),
        ]);
      },
    );
  }
}

class _Stat extends StatelessWidget {
  final String value;
  final String label;
  const _Stat({required this.value, required this.label});
  @override
  Widget build(BuildContext context) => Expanded(
        child: Column(children: [
          Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
          Text(label, style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ]),
      );
}

class _Tile extends StatelessWidget {
  final IconData icon;
  final String title;
  final Color color;
  final VoidCallback onTap;
  const _Tile(this.icon, this.title, this.color, this.onTap);
  @override
  Widget build(BuildContext context) => ListTile(
        leading: Container(width: 38, height: 38, decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)), child: Icon(icon, color: color, size: 22)),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: onTap,
      );
}

class MyReportsPage extends StatelessWidget {
  const MyReportsPage({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: Text(context.tr('my_reports'))), body: const ReportsList(query: 'mine=1'));
}

class MyPostsPage extends StatelessWidget {
  const MyPostsPage({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: Text(context.tr('my_posts'))), body: const PostsFeed(scope: 'mine'));
}

// ======================================================================== edit profile
class EditProfilePage extends StatefulWidget {
  final AppUser user;
  const EditProfilePage({super.key, required this.user});
  @override
  State<EditProfilePage> createState() => _EditProfilePageState();
}

class _EditProfilePageState extends State<EditProfilePage> {
  late final TextEditingController _name = TextEditingController(text: widget.user.name);
  late final TextEditingController _bio = TextEditingController(text: widget.user.bio ?? '');
  late final TextEditingController _phone = TextEditingController(text: widget.user.phone ?? '');
  late final TextEditingController _wa = TextEditingController(text: widget.user.whatsapp ?? '');
  late String? _wilaya = widget.user.wilaya;
  PickedMedia? _avatar;
  bool _removeAvatar = false;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _bio.dispose();
    _phone.dispose();
    _wa.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    final m = await pickMediaSheet(context, allowVideo: false);
    if (m != null && mounted) setState(() { _avatar = m; _removeAvatar = false; });
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      toast(context, context.tr('err_NAME_REQUIRED'), error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      final d = await api.multipart('PATCH', '/me/profile',
          fields: {
            'displayName': _name.text.trim(),
            'bio': _bio.text.trim(),
            'phone': _phone.text.trim(),
            'whatsapp': _wa.text.trim(),
            'wilaya': _wilaya ?? '',
            if (_removeAvatar) 'removeAvatar': 'true',
          },
          files: [if (_avatar != null) UploadFile('avatar', _avatar!.path)]);
      final u = AppUser.fromJson(Map<String, dynamic>.from((d as Map)['user'] as Map));
      Session.I.updateUser(u);
      if (!mounted) return;
      toast(context, context.tr('profile_saved'));
      Navigator.pop(context, u);
    } catch (e) {
      if (mounted) toast(context, errMsg(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final showUrl = _removeAvatar ? null : widget.user.avatarUrl;
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('edit_profile'))),
      body: ListView(padding: const EdgeInsets.all(18), children: [
        Center(
          child: Stack(children: [
            if (_avatar != null)
              CircleAvatar(radius: 56, backgroundImage: FileImage(File(_avatar!.path)))
            else
              AppAvatar(url: showUrl, name: _name.text.isEmpty ? '?' : _name.text, radius: 56),
            PositionedDirectional(bottom: 0, end: 0, child: IconButton.filled(style: IconButton.styleFrom(backgroundColor: kGreen), onPressed: _pick, icon: const Icon(Icons.camera_alt_rounded, color: Colors.white, size: 20))),
          ]),
        ),
        if (_avatar != null || (showUrl != null))
          Center(child: TextButton(onPressed: () => setState(() { _avatar = null; _removeAvatar = true; }), child: Text(context.tr('remove_photo')))),
        const SizedBox(height: 14),
        TextField(controller: _name, maxLength: 80, decoration: InputDecoration(labelText: context.tr('full_name'), prefixIcon: const Icon(Icons.badge_outlined))),
        const SizedBox(height: 6),
        TextField(controller: _bio, maxLines: 4, maxLength: 500, decoration: InputDecoration(labelText: context.tr('bio'), alignLabelWithHint: true)),
        const SizedBox(height: 6),
        InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () async {
            final w = await pickWilaya(context, current: _wilaya, allowAll: true);
            if (w != null && mounted) setState(() => _wilaya = w.isEmpty ? null : w);
          },
          child: InputDecorator(
            decoration: InputDecoration(labelText: context.tr('wilaya'), prefixIcon: const Icon(Icons.location_city_rounded), suffixIcon: const Icon(Icons.arrow_drop_down_rounded)),
            child: Text(_wilaya == null ? context.tr('not_specified') : wilayaDisplay(_wilaya, context.lang)),
          ),
        ),
        const SizedBox(height: 12),
        TextField(controller: _phone, keyboardType: TextInputType.phone, decoration: InputDecoration(labelText: context.tr('phone'), prefixIcon: const Icon(Icons.phone_rounded), helperText: context.tr('contact_public_hint'))),
        const SizedBox(height: 12),
        TextField(controller: _wa, keyboardType: TextInputType.phone, decoration: InputDecoration(labelText: context.tr('whatsapp'), prefixIcon: const Icon(Icons.chat_rounded))),
        const SizedBox(height: 22),
        BusyButton(busy: _busy, onPressed: _save, label: context.tr(_busy ? 'saving' : 'save'), icon: Icons.save_rounded),
      ]),
    );
  }
}

// ======================================================================== other user
class UserProfilePage extends StatefulWidget {
  final String userId;
  const UserProfilePage({super.key, required this.userId});
  @override
  State<UserProfilePage> createState() => _UserProfilePageState();
}

class _UserProfilePageState extends State<UserProfilePage> {
  AppUser? _user;
  Map<String, dynamic> _stats = {};
  bool _following = false;
  bool _isMe = false;
  bool _loading = true;
  bool _busyFollow = false;
  Object? _error;
  List<Post> _posts = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final d = await api.getMap('/users/${widget.userId}');
      final posts = asMapList(await api.get('/users/${widget.userId}/posts')).map(Post.fromJson).toList();
      if (!mounted) return;
      setState(() {
        _user = AppUser.maybe(d['user']);
        _stats = Map<String, dynamic>.from((d['stats'] as Map?) ?? {});
        _following = d['isFollowing'] == true;
        _isMe = d['isMe'] == true;
        _posts = posts;
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() { _error = e; _loading = false; });
    }
  }

  Future<void> _toggleFollow() async {
    setState(() => _busyFollow = true);
    try {
      final d = await api.post('/follow/${widget.userId}');
      if (d is Map && mounted) {
        setState(() {
          _following = d['following'] == true;
          _stats['followers'] = d['followers'] ?? _stats['followers'];
        });
      }
    } catch (e) {
      if (mounted) toast(context, errMsg(e), error: true);
    } finally {
      if (mounted) setState(() => _busyFollow = false);
    }
  }

  Future<void> _flag() async {
    final reason = await promptDialog(context, title: context.tr('report_user'), hint: context.tr('reason_hint'), allowEmpty: true);
    if (reason == null || !mounted) return;
    try {
      await api.post('/flags', {'targetType': 'USER', 'targetId': widget.userId, 'reason': reason});
      if (mounted) toast(context, context.tr('flag_sent'));
    } catch (e) {
      if (mounted) toast(context, errMsg(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final u = _user;
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(u?.name ?? ''),
        actions: [
          if (u != null && !_isMe)
            PopupMenuButton<String>(
              onSelected: (v) {
                if (v == 'flag') _flag();
                if (v == 'admin') Navigator.push(context, MaterialPageRoute(builder: (_) => AdminUserPage(userId: widget.userId)));
              },
              itemBuilder: (_) => [
                PopupMenuItem(value: 'flag', child: Text(context.tr('report_user'))),
                if (Session.I.user?.isStaff == true) PopupMenuItem(value: 'admin', child: Text(context.tr('manage_user'))),
              ],
            ),
        ],
      ),
      body: _loading
          ? const LoadingView()
          : (u == null)
              ? ErrorState(error: _error ?? 'x', onRetry: _load)
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(padding: const EdgeInsets.all(16), children: [
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(18),
                        child: Column(children: [
                          GestureDetector(onTap: u.avatarUrl == null ? null : () => openImage(context, [u.avatarUrl!]), child: AppAvatar(url: u.avatarUrl, name: u.name, radius: 44)),
                          const SizedBox(height: 10),
                          UserNameRow(u, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w900)),
                          Text('@${u.username}', style: TextStyle(color: cs.onSurfaceVariant)),
                          if ((u.wilaya ?? '').isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text(wilayaDisplay(u.wilaya, context.lang), style: TextStyle(color: cs.onSurfaceVariant))),
                          if ((u.bio ?? '').isNotEmpty) Padding(padding: const EdgeInsets.only(top: 10), child: Text(u.bio!, textAlign: TextAlign.center, style: const TextStyle(height: 1.4))),
                          const SizedBox(height: 14),
                          Row(children: [
                            _Stat(value: '${_stats['posts'] ?? 0}', label: context.tr('posts')),
                            _Stat(value: '${_stats['followers'] ?? 0}', label: context.tr('followers')),
                            _Stat(value: '${_stats['following'] ?? 0}', label: context.tr('following')),
                          ]),
                          if (!_isMe) ...[
                            const SizedBox(height: 14),
                            Row(children: [
                              Expanded(
                                child: _following
                                    ? OutlinedButton.icon(onPressed: _busyFollow ? null : _toggleFollow, icon: const Icon(Icons.check_rounded), label: Text(context.tr('following_btn')))
                                    : FilledButton.icon(onPressed: _busyFollow ? null : _toggleFollow, icon: const Icon(Icons.person_add_alt_1_rounded), label: Text(context.tr('follow'))),
                              ),
                              const SizedBox(width: 8),
                              Expanded(child: FilledButton.tonalIcon(onPressed: () => openChatWith(context, u), icon: const Icon(Icons.chat_bubble_rounded), label: Text(context.tr('message')))),
                            ]),
                            if ((u.phone ?? '').isNotEmpty || (u.whatsapp ?? '').isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: Row(children: [
                                  if ((u.phone ?? '').isNotEmpty) Expanded(child: OutlinedButton.icon(onPressed: () => launchContact(context, u.phone!), icon: const Icon(Icons.phone_rounded), label: Text(context.tr('call')))),
                                  if ((u.phone ?? '').isNotEmpty && (u.whatsapp ?? '').isNotEmpty) const SizedBox(width: 8),
                                  if ((u.whatsapp ?? '').isNotEmpty) Expanded(child: OutlinedButton.icon(onPressed: () => launchContact(context, u.whatsapp!, whatsapp: true), icon: const Icon(Icons.chat_rounded), label: Text(context.tr('whatsapp')))),
                                ]),
                              ),
                          ],
                        ]),
                      ),
                    ),
                    SectionTitle(context.tr('posts')),
                    if (_posts.isEmpty) Padding(padding: const EdgeInsets.all(24), child: Center(child: Text(context.tr('no_posts'), style: TextStyle(color: cs.onSurfaceVariant)))),
                    for (final p in _posts) Padding(padding: const EdgeInsets.only(bottom: 12), child: PostCard(key: ValueKey(p.id), post: p, onDeleted: () => setState(() => _posts.removeWhere((x) => x.id == p.id)))),
                  ]),
                ),
    );
  }
}

// ======================================================================== search people
class UserSearchPage extends StatefulWidget {
  const UserSearchPage({super.key});
  @override
  State<UserSearchPage> createState() => _UserSearchPageState();
}

class _UserSearchPageState extends State<UserSearchPage> {
  final TextEditingController _q = TextEditingController();
  final Debouncer _deb = Debouncer();
  List<AppUser> _rows = [];
  bool _loading = false;
  bool _searched = false;
  Object? _error;

  @override
  void dispose() {
    _deb.dispose();
    _q.dispose();
    super.dispose();
  }

  void _onChanged(String v) {
    _deb.run(() async {
      final t = v.trim();
      if (t.isEmpty) {
        if (mounted) setState(() { _rows = []; _searched = false; });
        return;
      }
      setState(() { _loading = true; _error = null; });
      try {
        final rows = asMapList(await api.get('/users/search?q=${Uri.encodeComponent(t)}')).map(AppUser.fromJson).where((u) => u.id != Session.I.userId).toList();
        if (mounted) setState(() { _rows = rows; _searched = true; _loading = false; });
      } catch (e) {
        if (mounted) setState(() { _error = e; _loading = false; });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _q,
          autofocus: true,
          onChanged: _onChanged,
          decoration: InputDecoration(hintText: context.tr('search_people'), border: InputBorder.none, enabledBorder: InputBorder.none, focusedBorder: InputBorder.none, filled: false),
        ),
      ),
      body: _loading
          ? const LoadingView()
          : _error != null
              ? ErrorState(error: _error!, onRetry: () => _onChanged(_q.text))
              : !_searched
                  ? EmptyState(icon: Icons.group_rounded, title: context.tr('search_people_hint'))
                  : _rows.isEmpty
                      ? EmptyState(icon: Icons.person_search_rounded, title: context.tr('no_results'))
                      : ListView.separated(
                          itemCount: _rows.length,
                          separatorBuilder: (_, i) => const Divider(indent: 72),
                          itemBuilder: (_, i) {
                            final u = _rows[i];
                            return ListTile(
                              leading: AppAvatar(url: u.avatarUrl, name: u.name),
                              title: UserNameRow(u),
                              subtitle: Text('@${u.username}${(u.wilaya ?? '').isNotEmpty ? ' • ${wilayaDisplay(u.wilaya, context.lang)}' : ''}'),
                              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => UserProfilePage(userId: u.id))),
                            );
                          },
                        ),
    );
  }
}
