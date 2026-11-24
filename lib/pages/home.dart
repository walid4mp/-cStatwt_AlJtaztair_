import 'package:flutter/material.dart';

import '../core/config.dart';
import '../core/i18n.dart';
import '../core/session.dart';
import '../widgets/header.dart';
import 'lostfound.dart';
import 'posts.dart';
import 'reports.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _tab = 0; // 0 posts, 1 following, 2 latest reports

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(children: [
      TopHeader(title: context.tr('app_name'), subtitle: context.tr('tagline_short')),
      ListenableBuilder(
        listenable: Session.I,
        builder: (context, _) {
          final s = Session.I.settings;
          if (s.announcement.isEmpty) return const SizedBox.shrink();
          final color = s.announcementLevel == 'critical' ? kRed : (s.announcementLevel == 'warning' ? const Color(0xFFEF6C00) : const Color(0xFF1565C0));
          return Container(
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(16), border: Border.all(color: color.withValues(alpha: 0.4))),
            child: Row(children: [
              Icon(Icons.campaign_rounded, color: color),
              const SizedBox(width: 10),
              Expanded(child: Text(s.announcement, style: const TextStyle(fontWeight: FontWeight.w700, height: 1.35))),
            ]),
          );
        },
      ),
      SizedBox(
        height: 92,
        child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4), children: [
          _Quick(icon: Icons.add_alert_rounded, color: kRed, label: context.tr('new_report'), onTap: () => _push(const CreateReportPage())),
          _Quick(icon: Icons.edit_note_rounded, color: kGreen, label: context.tr('new_post'), onTap: () => _push(const CreatePostPage())),
          _Quick(icon: Icons.manage_search_rounded, color: const Color(0xFF00838F), label: context.tr('lost_found'), onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const LostFoundPage()))),
          _Quick(icon: Icons.bookmark_rounded, color: const Color(0xFF6A1B9A), label: context.tr('saved_posts'), onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SavedPostsPage()))),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 2, 16, 8),
        child: SegmentedButton<int>(
          showSelectedIcon: false,
          segments: [
            ButtonSegment(value: 0, label: Text(context.tr('tab_posts')), icon: const Icon(Icons.dynamic_feed_rounded, size: 18)),
            ButtonSegment(value: 1, label: Text(context.tr('tab_following')), icon: const Icon(Icons.group_rounded, size: 18)),
            ButtonSegment(value: 2, label: Text(context.tr('tab_reports')), icon: const Icon(Icons.fact_check_rounded, size: 18)),
          ],
          selected: {_tab},
          onSelectionChanged: (v) => setState(() => _tab = v.first),
          style: ButtonStyle(
            visualDensity: VisualDensity.compact,
            backgroundColor: WidgetStateProperty.resolveWith((st) => st.contains(WidgetState.selected) ? kGreen.withValues(alpha: 0.18) : cs.surface),
          ),
        ),
      ),
      Expanded(
        child: _tab == 2
            ? const ReportsList(key: ValueKey('home_reports'))
            : PostsFeed(key: ValueKey('home_posts_$_tab'), scope: _tab == 1 ? 'following' : 'all'),
      ),
    ]);
  }

  Future<void> _push(Widget page) async {
    final r = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => page));
    if (r == true) bumpContent();
  }
}

class _Quick extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback onTap;
  const _Quick({required this.icon, required this.color, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.only(end: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          width: 92,
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
          decoration: BoxDecoration(color: color.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(18)),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(height: 6),
            Text(label, maxLines: 2, textAlign: TextAlign.center, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: color)),
          ]),
        ),
      ),
    );
  }
}
