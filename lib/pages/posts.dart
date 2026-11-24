import 'dart:async';

import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/config.dart';
import '../core/i18n.dart';
import '../core/models.dart';
import '../core/session.dart';
import '../core/wilayas.dart';
import '../widgets/common.dart';
import '../widgets/media_picker.dart';
import 'map.dart';
import 'profile.dart';

// ======================================================================== feed
class PostsFeed extends StatefulWidget {
  final String scope; // all | following | mine
  final String? wilaya;
  final EdgeInsets padding;
  const PostsFeed({super.key, this.scope = 'all', this.wilaya, this.padding = const EdgeInsets.fromLTRB(14, 4, 14, 100)});
  @override
  State<PostsFeed> createState() => _PostsFeedState();
}

class _PostsFeedState extends State<PostsFeed> {
  final List<Post> _posts = [];
  final ScrollController _sc = ScrollController();
  bool _loading = true;
  bool _more = true;
  bool _loadingMore = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _sc.addListener(_onScroll);
    contentRefresh.addListener(_reload);
    _load(reset: true);
  }

  @override
  void didUpdateWidget(covariant PostsFeed old) {
    super.didUpdateWidget(old);
    if (old.scope != widget.scope || old.wilaya != widget.wilaya) _load(reset: true);
  }

  @override
  void dispose() {
    contentRefresh.removeListener(_reload);
    _sc.dispose();
    super.dispose();
  }

  void _reload() => _load(reset: true, silent: true);

  void _onScroll() {
    if (_sc.hasClients && _sc.position.pixels > _sc.position.maxScrollExtent - 500) _loadMore();
  }

  String _path({String? before}) {
    final q = <String>['scope=${widget.scope}', 'limit=15'];
    if (widget.wilaya != null && widget.wilaya!.isNotEmpty) q.add('wilaya=${Uri.encodeComponent(widget.wilaya!)}');
    if (before != null) q.add('before=${Uri.encodeComponent(before)}');
    return '/feed?${q.join('&')}';
  }

  Future<void> _load({bool reset = false, bool silent = false}) async {
    if (!silent) setState(() { _loading = true; _error = null; });
    try {
      final rows = asMapList(await api.get(_path())).map(Post.fromJson).toList();
      if (!mounted) return;
      setState(() {
        _posts..clear()..addAll(rows);
        _more = rows.length >= 15;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() { _error = e; _loading = false; });
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_more || _posts.isEmpty) return;
    final last = _posts.last.createdAt;
    if (last == null) return;
    setState(() => _loadingMore = true);
    try {
      final rows = asMapList(await api.get(_path(before: last.toUtc().toIso8601String()))).map(Post.fromJson).toList();
      if (!mounted) return;
      setState(() {
        _posts.addAll(rows);
        _more = rows.length >= 15;
      });
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const LoadingView();
    if (_error != null && _posts.isEmpty) return ErrorState(error: _error!, onRetry: () => _load(reset: true));
    return RefreshIndicator(
      onRefresh: () => _load(reset: true, silent: true),
      child: _posts.isEmpty
          ? ListView(children: [
              const SizedBox(height: 60),
              EmptyState(icon: Icons.dynamic_feed_rounded, title: context.tr(widget.scope == 'following' ? 'no_following_posts' : 'no_posts'), subtitle: context.tr('no_posts_sub')),
            ])
          : ListView.separated(
              controller: _sc,
              padding: widget.padding,
              physics: const AlwaysScrollableScrollPhysics(),
              itemCount: _posts.length + (_loadingMore ? 1 : 0),
              separatorBuilder: (_, i) => const SizedBox(height: 12),
              itemBuilder: (_, i) {
                if (i >= _posts.length) return const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator(strokeWidth: 2)));
                final p = _posts[i];
                return PostCard(key: ValueKey(p.id), post: p, onDeleted: () => setState(() => _posts.removeWhere((x) => x.id == p.id)));
              },
            ),
    );
  }
}

// ======================================================================== card
class PostCard extends StatefulWidget {
  final Post post;
  final VoidCallback? onDeleted;
  final bool detail;
  const PostCard({super.key, required this.post, this.onDeleted, this.detail = false});
  @override
  State<PostCard> createState() => _PostCardState();
}

class _PostCardState extends State<PostCard> {
  Post get p => widget.post;

  Future<void> _like() async {
    final prevLiked = p.likedByMe;
    final prevCount = p.likesCount;
    setState(() {
      p.likedByMe = !prevLiked;
      p.likesCount = prevCount + (prevLiked ? -1 : 1);
    });
    try {
      final d = await api.post('/posts/${p.id}/like');
      if (d is Map && mounted) {
        setState(() {
          p.likedByMe = d['liked'] == true;
          p.likesCount = (d['likesCount'] as num?)?.toInt() ?? p.likesCount;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          p.likedByMe = prevLiked;
          p.likesCount = prevCount;
        });
        toast(context, errMsg(e), error: true);
      }
    }
  }

  Future<void> _save() async {
    final prev = p.savedByMe;
    setState(() => p.savedByMe = !prev);
    try {
      final d = await api.post('/posts/${p.id}/save');
      if (d is Map && mounted) {
        setState(() => p.savedByMe = d['saved'] == true);
        toast(context, context.tr(p.savedByMe ? 'saved' : 'unsaved'));
      }
    } catch (e) {
      if (mounted) {
        setState(() => p.savedByMe = prev);
        toast(context, errMsg(e), error: true);
      }
    }
  }

  Future<void> _delete() async {
    final ok = await confirmDialog(context, title: context.tr('delete_post'), message: context.tr('delete_post_msg'), confirmLabel: context.tr('delete'), danger: true);
    if (!ok || !mounted) return;
    try {
      await api.delete('/posts/${p.id}');
      widget.onDeleted?.call();
      if (mounted) {
        toast(context, context.tr('deleted'));
        if (widget.detail) Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) toast(context, errMsg(e), error: true);
    }
  }

  Future<void> _flag() async {
    final reason = await promptDialog(context, title: context.tr('report_content'), hint: context.tr('reason_hint'), allowEmpty: true);
    if (reason == null || !mounted) return;
    try {
      await api.post('/flags', {'targetType': 'POST', 'targetId': p.id, 'reason': reason});
      if (mounted) toast(context, context.tr('flag_sent'));
    } catch (e) {
      if (mounted) toast(context, errMsg(e), error: true);
    }
  }

  Future<void> _hide() async {
    try {
      await api.patch('/admin/posts/${p.id}', {'hidden': true});
      widget.onDeleted?.call();
      if (mounted) toast(context, context.tr('hidden_done'));
    } catch (e) {
      if (mounted) toast(context, errMsg(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final author = p.author;
    final staff = Session.I.user?.isStaff == true;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            InkWell(
              borderRadius: BorderRadius.circular(30),
              onTap: author == null ? null : () => Navigator.push(context, MaterialPageRoute(builder: (_) => UserProfilePage(userId: author.id))),
              child: AppAvatar(url: author?.avatarUrl, name: author?.name ?? '?'),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (author != null) UserNameRow(author),
                Text(
                  [
                    if (author != null) '@${author.username}',
                    timeAgo(context, p.createdAt),
                    if (p.wilaya != null && p.wilaya!.isNotEmpty) wilayaDisplay(p.wilaya, context.lang),
                  ].join(' • '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
                ),
              ]),
            ),
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_horiz_rounded),
              onSelected: (v) {
                if (v == 'delete') _delete();
                if (v == 'flag') _flag();
                if (v == 'hide') _hide();
              },
              itemBuilder: (_) => [
                if (p.mine || staff) PopupMenuItem(value: 'delete', child: Text(context.tr('delete'))),
                if (staff && !p.mine) PopupMenuItem(value: 'hide', child: Text(context.tr('hide'))),
                if (!p.mine) PopupMenuItem(value: 'flag', child: Text(context.tr('report_content'))),
              ],
            ),
          ]),
          if (p.title.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 10), child: Text(p.title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17))),
          if (p.body.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Text(p.body, style: const TextStyle(height: 1.45))),
          if (p.mediaUrl != null && p.mediaUrl!.isNotEmpty) ...[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: p.mediaType == 'VIDEO'
                  ? VideoBox(url: p.mediaUrl!)
                  : GestureDetector(onTap: () => openImage(context, [p.mediaUrl!]), child: NetImage(p.mediaUrl!, width: double.infinity, height: 260)),
            ),
          ],
          const SizedBox(height: 6),
          Row(children: [
            _Action(icon: p.likedByMe ? Icons.favorite_rounded : Icons.favorite_border_rounded, color: p.likedByMe ? kRed : null, label: p.likesCount > 0 ? '${p.likesCount}' : '', onTap: _like),
            _Action(
              icon: Icons.chat_bubble_outline_rounded,
              label: p.commentsCount > 0 ? '${p.commentsCount}' : '',
              onTap: widget.detail ? null : () => Navigator.push(context, MaterialPageRoute(builder: (_) => PostDetailPage(post: p))).then((_) {
                    if (mounted) setState(() {});
                  }),
            ),
            _Action(icon: p.savedByMe ? Icons.bookmark_rounded : Icons.bookmark_border_rounded, color: p.savedByMe ? kGreen : null, label: '', onTap: _save),
            if (p.lat != null && p.lon != null) _Action(icon: Icons.location_on_outlined, color: kGreen, label: '', onTap: () => showLocationSheet(context, lat: p.lat!, lon: p.lon!, title: p.title.isNotEmpty ? p.title : context.tr('post_location'))),
          ]),
        ]),
      ),
    );
  }
}

class _Action extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color? color;
  final VoidCallback? onTap;
  const _Action({required this.icon, required this.label, this.color, this.onTap});
  @override
  Widget build(BuildContext context) => InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(children: [
            Icon(icon, size: 22, color: color),
            if (label.isNotEmpty) Padding(padding: const EdgeInsetsDirectional.only(start: 5), child: Text(label, style: const TextStyle(fontWeight: FontWeight.w700))),
          ]),
        ),
      );
}

// ======================================================================== detail + comments
class PostDetailPage extends StatefulWidget {
  final Post? post;
  final String? postId;
  const PostDetailPage({super.key, this.post, this.postId});
  @override
  State<PostDetailPage> createState() => _PostDetailPageState();
}

class _PostDetailPageState extends State<PostDetailPage> {
  Post? _post;
  final List<Comment> _comments = [];
  final _input = TextEditingController();
  bool _loading = true;
  bool _sending = false;
  Object? _error;

  String get _id => widget.post?.id ?? widget.postId ?? '';

  @override
  void initState() {
    super.initState();
    _post = widget.post;
    _load();
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      if (_post == null) _post = Post.fromJson(Map<String, dynamic>.from(await api.get('/posts/$_id') as Map));
      final rows = asMapList(await api.get('/posts/$_id/comments')).map(Comment.fromJson).toList();
      if (!mounted) return;
      setState(() {
        _comments..clear()..addAll(rows);
        _post!.commentsCount = rows.length;
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() { _error = e; _loading = false; });
    }
  }

  Future<void> _send() async {
    final t = _input.text.trim();
    if (t.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      final d = await api.post('/posts/$_id/comments', {'body': t});
      final c = Comment.fromJson(Map<String, dynamic>.from(d as Map));
      if (!mounted) return;
      setState(() {
        _comments.add(c);
        _post?.commentsCount = _comments.length;
        _input.clear();
      });
    } catch (e) {
      if (mounted) toast(context, errMsg(e), error: true);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _deleteComment(Comment c) async {
    final ok = await confirmDialog(context, title: context.tr('delete_comment'), confirmLabel: context.tr('delete'), danger: true);
    if (!ok || !mounted) return;
    try {
      await api.delete('/comments/${c.id}');
      if (mounted) setState(() { _comments.removeWhere((x) => x.id == c.id); _post?.commentsCount = _comments.length; });
    } catch (e) {
      if (mounted) toast(context, errMsg(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('post'))),
      body: Column(children: [
        Expanded(
          child: _loading
              ? const LoadingView()
              : (_error != null || _post == null)
                  ? ErrorState(error: _error ?? 'x', onRetry: _load)
                  : ListView(padding: const EdgeInsets.all(14), children: [
                      PostCard(post: _post!, detail: true, onDeleted: () => bumpContent()),
                      SectionTitle('${context.tr('comments')} (${_comments.length})'),
                      if (_comments.isEmpty) Padding(padding: const EdgeInsets.all(24), child: Center(child: Text(context.tr('no_comments'), style: TextStyle(color: cs.onSurfaceVariant)))),
                      for (final c in _comments)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: c.user == null ? null : GestureDetector(onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => UserProfilePage(userId: c.user!.id))), child: AppAvatar(url: c.user!.avatarUrl, name: c.user!.name, radius: 18)),
                          title: Row(children: [if (c.user != null) Flexible(child: UserNameRow(c.user!)), const SizedBox(width: 8), Text(timeAgo(context, c.createdAt), style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant))]),
                          subtitle: Text(c.body, style: TextStyle(color: cs.onSurface)),
                          trailing: (c.mine || Session.I.user?.isStaff == true || _post!.mine)
                              ? IconButton(icon: const Icon(Icons.delete_outline_rounded, size: 20), onPressed: () => _deleteComment(c))
                              : null,
                        ),
                    ]),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: EdgeInsets.fromLTRB(12, 6, 12, 8 + MediaQuery.of(context).viewInsets.bottom * 0),
            child: Row(children: [
              Expanded(child: TextField(controller: _input, minLines: 1, maxLines: 4, maxLength: 2000, buildCounter: (c, {required currentLength, required isFocused, maxLength}) => null, decoration: InputDecoration(hintText: context.tr('write_comment')))),
              const SizedBox(width: 8),
              IconButton.filled(
                style: IconButton.styleFrom(backgroundColor: kGreen),
                onPressed: _sending ? null : _send,
                icon: _sending ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.send_rounded, color: Colors.white),
              ),
            ]),
          ),
        ),
      ]),
    );
  }
}

// ======================================================================== create
class CreatePostPage extends StatefulWidget {
  const CreatePostPage({super.key});
  @override
  State<CreatePostPage> createState() => _CreatePostPageState();
}

class _CreatePostPageState extends State<CreatePostPage> {
  final _title = TextEditingController();
  final _body = TextEditingController();
  PickedMedia? _media;
  String? _wilaya;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _wilaya = Session.I.user?.wilaya;
  }

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_body.text.trim().isEmpty && _media == null) {
      toast(context, context.tr('err_EMPTY_POST'), error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      await api.multipart('POST', '/posts',
          fields: {
            'title': _title.text.trim(),
            'body': _body.text.trim(),
            if (_wilaya != null) 'wilaya': _wilaya!,
          },
          files: [if (_media != null) UploadFile('media', _media!.path)]);
      if (!mounted) return;
      toast(context, context.tr('post_published'));
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) toast(context, errMsg(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('new_post'))),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        TextField(controller: _title, maxLength: 160, decoration: InputDecoration(labelText: context.tr('post_title_optional'))),
        const SizedBox(height: 8),
        TextField(controller: _body, minLines: 5, maxLines: 10, maxLength: 5000, decoration: InputDecoration(labelText: context.tr('post_hint'), alignLabelWithHint: true)),
        const SizedBox(height: 8),
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
        const SizedBox(height: 14),
        if (_media != null)
          Align(alignment: AlignmentDirectional.centerStart, child: PickedTile(media: _media!, size: 120, onRemove: () => setState(() => _media = null)))
        else
          OutlinedButton.icon(
            onPressed: _busy ? null : () async {
              final m = await pickMediaSheet(context);
              if (m != null && mounted) setState(() => _media = m);
            },
            icon: const Icon(Icons.add_photo_alternate_rounded),
            label: Text(context.tr('add_media')),
          ),
        const SizedBox(height: 22),
        BusyButton(busy: _busy, onPressed: _submit, label: _busy ? context.tr('uploading') : context.tr('publish'), icon: Icons.send_rounded),
      ]),
    );
  }
}

// ======================================================================== saved
class SavedPostsPage extends StatefulWidget {
  const SavedPostsPage({super.key});
  @override
  State<SavedPostsPage> createState() => _SavedPostsPageState();
}

class _SavedPostsPageState extends State<SavedPostsPage> {
  List<Post> _posts = [];
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
      final rows = asMapList(await api.get('/me/saved')).map(Post.fromJson).toList();
      if (mounted) setState(() { _posts = rows; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e; _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('saved_posts'))),
      body: _loading
          ? const LoadingView()
          : _error != null
              ? ErrorState(error: _error!, onRetry: _load)
              : _posts.isEmpty
                  ? EmptyState(icon: Icons.bookmark_border_rounded, title: context.tr('no_saved'))
                  : ListView.separated(
                      padding: const EdgeInsets.all(14),
                      itemCount: _posts.length,
                      separatorBuilder: (_, i) => const SizedBox(height: 12),
                      itemBuilder: (_, i) => PostCard(key: ValueKey(_posts[i].id), post: _posts[i], onDeleted: () => setState(() => _posts.removeAt(i))),
                    ),
    );
  }
}
