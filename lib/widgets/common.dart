import 'dart:async';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../core/api.dart';
import '../core/config.dart';
import '../core/i18n.dart';
import '../core/models.dart';
import '../core/wilayas.dart';

// ------------------------------------------------------------------ feedback
void toast(BuildContext context, String message, {bool error = false}) {
  final m = ScaffoldMessenger.maybeOf(context);
  if (m == null) return;
  m.hideCurrentSnackBar();
  m.showSnackBar(SnackBar(
    content: Text(message),
    backgroundColor: error ? const Color(0xFFB3261E) : null,
    duration: Duration(seconds: error ? 4 : 3),
  ));
}

Future<bool> confirmDialog(
  BuildContext context, {
  required String title,
  String? message,
  String? confirmLabel,
  bool danger = false,
}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: message == null ? null : Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(ctx.tr('cancel'))),
        FilledButton(
          style: danger ? FilledButton.styleFrom(backgroundColor: kRed) : null,
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(confirmLabel ?? ctx.tr('confirm')),
        ),
      ],
    ),
  );
  return r == true;
}

Future<String?> promptDialog(
  BuildContext context, {
  required String title,
  String? hint,
  String? initial,
  int maxLines = 3,
  bool allowEmpty = false,
}) async {
  final c = TextEditingController(text: initial ?? '');
  final r = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(controller: c, maxLines: maxLines, minLines: 1, autofocus: true, decoration: InputDecoration(hintText: hint)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: Text(ctx.tr('cancel'))),
        FilledButton(
          onPressed: () {
            if (!allowEmpty && c.text.trim().isEmpty) return;
            Navigator.pop(ctx, c.text.trim());
          },
          child: Text(ctx.tr('ok')),
        ),
      ],
    ),
  );
  c.dispose();
  return r;
}

// ------------------------------------------------------------------ time
String _two(int n) => n < 10 ? '0$n' : '$n';

String fmtDateTime(DateTime? d) {
  if (d == null) return '';
  return '${_two(d.day)}/${_two(d.month)}/${d.year} ${_two(d.hour)}:${_two(d.minute)}';
}

String fmtTime(DateTime? d) => d == null ? '' : '${_two(d.hour)}:${_two(d.minute)}';

String timeAgo(BuildContext context, DateTime? d) {
  if (d == null) return '';
  final diff = DateTime.now().difference(d);
  if (diff.inSeconds < 60) return context.tr('time_now');
  if (diff.inMinutes < 60) return context.tr('time_min', {'n': '${diff.inMinutes}'});
  if (diff.inHours < 24) return context.tr('time_hour', {'n': '${diff.inHours}'});
  if (diff.inDays < 7) return context.tr('time_day', {'n': '${diff.inDays}'});
  return fmtDateTime(d).substring(0, 10);
}

// ------------------------------------------------------------------ report styling
Color typeColor(String type) {
  switch (reportTypeKey(type)) {
    case 'civic':
      return const Color(0xFF1565C0);
    case 'safety':
      return kRed;
    case 'traffic':
      return const Color(0xFFEF6C00);
    case 'env':
      return const Color(0xFF2E7D32);
    case 'services':
      return const Color(0xFF6A1B9A);
    case 'fraud':
      return const Color(0xFFAD1457);
    case 'lost':
      return const Color(0xFF00838F);
    default:
      return const Color(0xFF546E7A);
  }
}

IconData typeIcon(String type) {
  switch (reportTypeKey(type)) {
    case 'civic':
      return Icons.account_balance_rounded;
    case 'safety':
      return Icons.shield_rounded;
    case 'traffic':
      return Icons.traffic_rounded;
    case 'env':
      return Icons.eco_rounded;
    case 'services':
      return Icons.build_circle_rounded;
    case 'fraud':
      return Icons.gpp_maybe_rounded;
    case 'lost':
      return Icons.search_rounded;
    default:
      return Icons.flag_rounded;
  }
}

Color statusColor(String status) {
  switch (status) {
    case 'REVIEWED':
      return const Color(0xFF1565C0);
    case 'VERIFIED':
      return const Color(0xFF00897B);
    case 'RESOLVED':
      return kGreen;
    case 'REJECTED':
      return kRed;
    default:
      return const Color(0xFFEF6C00);
  }
}

class StatusChip extends StatelessWidget {
  final String status;
  const StatusChip(this.status, {super.key});

  @override
  Widget build(BuildContext context) {
    final c = statusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: c.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(20)),
      child: Text(context.tr('status_$status'), style: TextStyle(color: c, fontSize: 11.5, fontWeight: FontWeight.w800)),
    );
  }
}

class TypeChip extends StatelessWidget {
  final String type;
  const TypeChip(this.type, {super.key});

  @override
  Widget build(BuildContext context) {
    final c = typeColor(type);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(color: c.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(typeIcon(type), size: 14, color: c),
        const SizedBox(width: 4),
        Text(reportTypeLabel(context, type), style: TextStyle(color: c, fontSize: 11.5, fontWeight: FontWeight.w800)),
      ]),
    );
  }
}

// ------------------------------------------------------------------ avatar / badges
class AppAvatar extends StatelessWidget {
  final String? url;
  final String name;
  final double radius;
  const AppAvatar({super.key, this.url, required this.name, this.radius = 22});

  @override
  Widget build(BuildContext context) {
    final has = url != null && url!.isNotEmpty;
    final initial = name.trim().isEmpty ? '?' : String.fromCharCode(name.trim().runes.first);
    return CircleAvatar(
      radius: radius,
      backgroundColor: kGreen,
      foregroundImage: has ? NetworkImage(Api.url(url)) : null,
      onForegroundImageError: has ? (e, s) {} : null,
      child: Text(initial, style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: radius * 0.8)),
    );
  }
}

class VerifiedBadge extends StatelessWidget {
  final double size;
  const VerifiedBadge({super.key, this.size = 17});
  @override
  Widget build(BuildContext context) => Icon(Icons.verified_rounded, size: size, color: const Color(0xFF1E88E5));
}

class UserNameRow extends StatelessWidget {
  final AppUser user;
  final TextStyle? style;
  const UserNameRow(this.user, {super.key, this.style});
  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        Flexible(
          child: Text(user.name,
              maxLines: 1, overflow: TextOverflow.ellipsis, style: style ?? const TextStyle(fontWeight: FontWeight.w800)),
        ),
        if (user.verified) const Padding(padding: EdgeInsetsDirectional.only(start: 4), child: VerifiedBadge()),
        if (user.isStaff)
          Padding(
            padding: const EdgeInsetsDirectional.only(start: 4),
            child: Icon(Icons.shield_rounded, size: 15, color: user.isAdmin ? kRed : kGreen),
          ),
      ]);
}

// ------------------------------------------------------------------ states
class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? action;
  const EmptyState({super.key, required this.icon, required this.title, this.subtitle, this.action});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 84,
            height: 84,
            decoration: BoxDecoration(color: kGreen.withValues(alpha: 0.10), shape: BoxShape.circle),
            child: Icon(icon, size: 40, color: kGreen),
          ),
          const SizedBox(height: 16),
          Text(title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          if (subtitle != null) ...[
            const SizedBox(height: 6),
            Text(subtitle!, textAlign: TextAlign.center, style: TextStyle(color: cs.onSurfaceVariant)),
          ],
          if (action != null) ...[const SizedBox(height: 16), action!],
        ]),
      ),
    );
  }
}

class ErrorState extends StatelessWidget {
  final Object error;
  final VoidCallback onRetry;
  const ErrorState({super.key, required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final net = error is ApiException && (error as ApiException).status == 0;
    return EmptyState(
      icon: net ? Icons.wifi_off_rounded : Icons.error_outline_rounded,
      title: errMsg(error),
      subtitle: net ? context.tr('err_retry_hint') : null,
      action: OutlinedButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh_rounded), label: Text(context.tr('retry'))),
    );
  }
}

class LoadingView extends StatelessWidget {
  const LoadingView({super.key});
  @override
  Widget build(BuildContext context) => const Center(child: Padding(padding: EdgeInsets.all(40), child: CircularProgressIndicator()));
}

class SectionTitle extends StatelessWidget {
  final String text;
  final Widget? trailing;
  const SectionTitle(this.text, {super.key, this.trailing});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 14, 4, 8),
        child: Row(children: [
          Expanded(child: Text(text, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900))),
          if (trailing != null) trailing!,
        ]),
      );
}

class BusyButton extends StatelessWidget {
  final bool busy;
  final VoidCallback? onPressed;
  final String label;
  final IconData? icon;
  final Color? color;
  const BusyButton({super.key, required this.busy, required this.onPressed, required this.label, this.icon, this.color});

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      style: color == null ? null : FilledButton.styleFrom(backgroundColor: color),
      onPressed: busy ? null : onPressed,
      child: Row(mainAxisAlignment: MainAxisAlignment.center, mainAxisSize: MainAxisSize.min, children: [
        if (busy)
          const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
        else if (icon != null)
          Icon(icon, size: 20),
        const SizedBox(width: 8),
        Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
      ]),
    );
  }
}

// ------------------------------------------------------------------ language menu
class LanguageButton extends StatelessWidget {
  final Color? color;
  final void Function(String code) onSelected;
  const LanguageButton({super.key, this.color, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: context.tr('language'),
      icon: Icon(Icons.language_rounded, color: color),
      onSelected: onSelected,
      itemBuilder: (_) => kLanguages
          .map((c) => PopupMenuItem<String>(
                value: c,
                child: Row(children: [
                  Icon(c == context.lang ? Icons.radio_button_checked : Icons.radio_button_off, size: 18, color: kGreen),
                  const SizedBox(width: 10),
                  Text(kLanguageNames[c] ?? c),
                ]),
              ))
          .toList(),
    );
  }
}

// ------------------------------------------------------------------ images / video
class NetImage extends StatelessWidget {
  final String url;
  final double? width;
  final double? height;
  final BoxFit fit;
  final double radius;
  const NetImage(this.url, {super.key, this.width, this.height, this.fit = BoxFit.cover, this.radius = 0});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final img = Image.network(
      Api.url(url),
      width: width,
      height: height,
      fit: fit,
      loadingBuilder: (c, child, p) {
        if (p == null) return child;
        final total = p.expectedTotalBytes;
        return Container(
          width: width,
          height: height ?? 160,
          color: cs.surfaceContainerHighest,
          child: Center(child: CircularProgressIndicator(strokeWidth: 2, value: total == null ? null : p.cumulativeBytesLoaded / total)),
        );
      },
      errorBuilder: (c, e, s) => Container(
        width: width,
        height: height ?? 160,
        color: cs.surfaceContainerHighest,
        child: Icon(Icons.broken_image_outlined, color: cs.onSurfaceVariant, size: 36),
      ),
    );
    if (radius <= 0) return img;
    return ClipRRect(borderRadius: BorderRadius.circular(radius), child: img);
  }
}

class VideoBox extends StatefulWidget {
  final String url;
  const VideoBox({super.key, required this.url});
  @override
  State<VideoBox> createState() => _VideoBoxState();
}

class _VideoBoxState extends State<VideoBox> {
  VideoPlayerController? _c;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final c = VideoPlayerController.networkUrl(Uri.parse(Api.url(widget.url)));
    _c = c;
    try {
      await c.initialize();
      c.addListener(_tick);
      if (mounted) setState(() {});
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  void _tick() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _c?.removeListener(_tick);
    _c?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _c;
    if (_failed) {
      return Container(
        height: 200,
        color: Colors.black12,
        child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.videocam_off_rounded, size: 36),
          const SizedBox(height: 6),
          Text(context.tr('video_failed')),
        ])),
      );
    }
    if (c == null || !c.value.isInitialized) {
      return Container(height: 200, color: Colors.black, child: const Center(child: CircularProgressIndicator(color: Colors.white)));
    }
    final ratio = c.value.aspectRatio <= 0 ? 16 / 9 : c.value.aspectRatio;
    return AspectRatio(
      aspectRatio: ratio,
      child: GestureDetector(
        onTap: () => c.value.isPlaying ? c.pause() : c.play(),
        child: Stack(alignment: Alignment.center, children: [
          VideoPlayer(c),
          if (!c.value.isPlaying)
            Container(
              decoration: const BoxDecoration(color: Colors.black45, shape: BoxShape.circle),
              padding: const EdgeInsets.all(8),
              child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 46),
            ),
          Positioned(left: 0, right: 0, bottom: 0, child: VideoProgressIndicator(c, allowScrubbing: true, padding: const EdgeInsets.only(top: 6))),
        ]),
      ),
    );
  }
}

class ImageViewerPage extends StatefulWidget {
  final List<String> urls;
  final int index;
  const ImageViewerPage({super.key, required this.urls, this.index = 0});
  @override
  State<ImageViewerPage> createState() => _ImageViewerPageState();
}

class _ImageViewerPageState extends State<ImageViewerPage> {
  late final PageController _pc = PageController(initialPage: widget.index);
  late int _i = widget.index;

  @override
  void dispose() {
    _pc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: widget.urls.length > 1 ? Text('${_i + 1} / ${widget.urls.length}', style: const TextStyle(color: Colors.white)) : null,
      ),
      body: PageView.builder(
        controller: _pc,
        itemCount: widget.urls.length,
        onPageChanged: (i) => setState(() => _i = i),
        itemBuilder: (_, i) => InteractiveViewer(
          minScale: 1,
          maxScale: 5,
          child: Center(child: Image.network(Api.url(widget.urls[i]), fit: BoxFit.contain, errorBuilder: (c, e, s) => const Icon(Icons.broken_image_outlined, color: Colors.white54, size: 60))),
        ),
      ),
    );
  }
}

void openImage(BuildContext context, List<String> urls, [int index = 0]) {
  Navigator.push(context, MaterialPageRoute(builder: (_) => ImageViewerPage(urls: urls, index: index)));
}

/// Swipeable gallery of images / videos.
class MediaGallery extends StatefulWidget {
  final List<Evidence> items;
  final double height;
  const MediaGallery({super.key, required this.items, this.height = 240});
  @override
  State<MediaGallery> createState() => _MediaGalleryState();
}

class _MediaGalleryState extends State<MediaGallery> {
  int _i = 0;

  @override
  Widget build(BuildContext context) {
    final items = widget.items;
    if (items.isEmpty) return const SizedBox.shrink();
    final imageUrls = items.where((e) => e.type != 'VIDEO').map((e) => e.url).toList();
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: SizedBox(
        height: widget.height,
        child: Stack(children: [
          PageView.builder(
            itemCount: items.length,
            onPageChanged: (i) => setState(() => _i = i),
            itemBuilder: (_, i) {
              final e = items[i];
              if (e.type == 'VIDEO') return Container(color: Colors.black, child: Center(child: VideoBox(url: e.url)));
              if (e.type == 'FILE') {
                return Container(
                  color: Colors.black12,
                  child: const Center(child: Icon(Icons.picture_as_pdf_rounded, size: 56)),
                );
              }
              return GestureDetector(
                onTap: () => openImage(context, imageUrls, imageUrls.indexOf(e.url).clamp(0, imageUrls.length - 1)),
                child: NetImage(e.url, width: double.infinity, height: widget.height),
              );
            },
          ),
          if (items.length > 1)
            Positioned(
              bottom: 8,
              left: 0,
              right: 0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                  items.length,
                  (i) => Container(
                    width: i == _i ? 18 : 7,
                    height: 7,
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    decoration: BoxDecoration(color: i == _i ? Colors.white : Colors.white54, borderRadius: BorderRadius.circular(4)),
                  ),
                ),
              ),
            ),
        ]),
      ),
    );
  }
}

// ------------------------------------------------------------------ wilaya picker
/// Returns the Arabic wilaya name; '' when "all" is chosen; null when cancelled.
Future<String?> pickWilaya(BuildContext context, {String? current, bool allowAll = false}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => _WilayaSheet(current: current, allowAll: allowAll),
  );
}

class _WilayaSheet extends StatefulWidget {
  final String? current;
  final bool allowAll;
  const _WilayaSheet({this.current, required this.allowAll});
  @override
  State<_WilayaSheet> createState() => _WilayaSheetState();
}

class _WilayaSheetState extends State<_WilayaSheet> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final lang = context.lang;
    final q = _q.trim().toLowerCase();
    final list = kWilayas.where((w) => q.isEmpty || w.ar.contains(q) || w.fr.toLowerCase().contains(q) || '${w.code}' == q).toList();
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.78,
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextField(
              onChanged: (v) => setState(() => _q = v),
              decoration: InputDecoration(prefixIcon: const Icon(Icons.search_rounded), hintText: context.tr('search_wilaya')),
            ),
          ),
          Expanded(
            child: ListView(children: [
              if (widget.allowAll)
                ListTile(
                  leading: const Icon(Icons.public_rounded, color: kGreen),
                  title: Text(context.tr('all_wilayas')),
                  trailing: (widget.current == null || widget.current!.isEmpty) ? const Icon(Icons.check_rounded, color: kGreen) : null,
                  onTap: () => Navigator.pop(context, ''),
                ),
              for (final w in list)
                ListTile(
                  title: Text(w.label(lang)),
                  trailing: widget.current == w.ar ? const Icon(Icons.check_rounded, color: kGreen) : null,
                  onTap: () => Navigator.pop(context, w.ar),
                ),
            ]),
          ),
        ]),
      ),
    );
  }
}

Future<T?> pickFromList<T>(BuildContext context, {required String title, required List<T> items, required String Function(T) label, T? current, IconData? Function(T)? icon}) {
  return showModalBottomSheet<T>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (ctx) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.7),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(padding: const EdgeInsets.fromLTRB(20, 0, 20, 8), child: Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900))),
          Flexible(
            child: ListView(shrinkWrap: true, children: [
              for (final it in items)
                ListTile(
                  leading: icon == null || icon(it) == null ? null : Icon(icon(it), color: kGreen),
                  title: Text(label(it)),
                  trailing: it == current ? const Icon(Icons.check_rounded, color: kGreen) : null,
                  onTap: () => Navigator.pop(ctx, it),
                ),
            ]),
          ),
        ]),
      ),
    ),
  );
}

/// Debounce helper for search boxes.
class Debouncer {
  final Duration delay;
  Timer? _t;
  Debouncer([this.delay = const Duration(milliseconds: 450)]);
  void run(VoidCallback fn) {
    _t?.cancel();
    _t = Timer(delay, fn);
  }

  void dispose() => _t?.cancel();
}
