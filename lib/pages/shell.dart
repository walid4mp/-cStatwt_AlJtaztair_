import 'package:flutter/material.dart';

import '../core/config.dart';
import '../core/i18n.dart';
import '../core/notifier.dart';
import '../core/session.dart';
import 'chat.dart';
import 'home.dart';
import 'lostfound.dart';
import 'map.dart';
import 'posts.dart';
import 'profile.dart';
import 'reports.dart';

class Shell extends StatefulWidget {
  const Shell({super.key});
  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int _index = 0;
  final Set<int> _visited = {0};

  @override
  void initState() {
    super.initState();
    Session.I.refreshBadges();
    LocalNotifier.requestPermission();
  }

  Widget _page(int i) {
    if (!_visited.contains(i)) return const SizedBox.shrink();
    switch (i) {
      case 0:
        return const HomePage();
      case 1:
        return const ReportsPage();
      case 2:
        return const MapPage();
      case 3:
        return const MessagesPage();
      default:
        return const ProfilePage();
    }
  }

  void _select(int i) => setState(() {
        _index = i;
        _visited.add(i);
      });

  Future<void> _createMenu() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Align(alignment: AlignmentDirectional.centerStart, child: Text(ctx.tr('create_new'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900))),
          ),
          _MenuTile(icon: Icons.add_alert_rounded, color: kRed, title: ctx.tr('new_report'), subtitle: ctx.tr('new_report_sub'), onTap: () => Navigator.pop(ctx, 'report')),
          _MenuTile(icon: Icons.edit_note_rounded, color: kGreen, title: ctx.tr('new_post'), subtitle: ctx.tr('new_post_sub'), onTap: () => Navigator.pop(ctx, 'post')),
          _MenuTile(icon: Icons.manage_search_rounded, color: const Color(0xFF00838F), title: ctx.tr('new_lost_found'), subtitle: ctx.tr('new_lost_found_sub'), onTap: () => Navigator.pop(ctx, 'lf')),
          const SizedBox(height: 8),
        ]),
      ),
    );
    if (!mounted || choice == null) return;
    Widget? page;
    if (choice == 'report') page = const CreateReportPage();
    if (choice == 'post') page = const CreatePostPage();
    if (choice == 'lf') page = const CreateLostFoundPage();
    if (page == null) return;
    final created = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => page!));
    if (created == true) bumpContent();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _index == 0,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _select(0);
      },
      child: Scaffold(
        body: IndexedStack(index: _index, children: List.generate(5, _page)),
        floatingActionButton: (_index <= 2)
            ? FloatingActionButton.extended(
                heroTag: 'create_fab',
                backgroundColor: kGreen,
                foregroundColor: Colors.white,
                onPressed: _createMenu,
                icon: const Icon(Icons.add_rounded),
                label: Text(context.tr('create_new')),
              )
            : null,
        bottomNavigationBar: ListenableBuilder(
          listenable: Session.I,
          builder: (context, _) => NavigationBar(
            selectedIndex: _index,
            onDestinationSelected: _select,
            destinations: [
              NavigationDestination(icon: const Icon(Icons.home_outlined), selectedIcon: const Icon(Icons.home_rounded), label: context.tr('nav_home')),
              NavigationDestination(icon: const Icon(Icons.fact_check_outlined), selectedIcon: const Icon(Icons.fact_check_rounded), label: context.tr('nav_reports')),
              NavigationDestination(icon: const Icon(Icons.map_outlined), selectedIcon: const Icon(Icons.map_rounded), label: context.tr('nav_map')),
              NavigationDestination(
                icon: Badge(isLabelVisible: Session.I.unreadMessages > 0, label: Text('${Session.I.unreadMessages}'), child: const Icon(Icons.chat_bubble_outline_rounded)),
                selectedIcon: Badge(isLabelVisible: Session.I.unreadMessages > 0, label: Text('${Session.I.unreadMessages}'), child: const Icon(Icons.chat_bubble_rounded)),
                label: context.tr('nav_messages'),
              ),
              NavigationDestination(icon: const Icon(Icons.person_outline_rounded), selectedIcon: const Icon(Icons.person_rounded), label: context.tr('nav_account')),
            ],
          ),
        ),
      ),
    );
  }
}

class _MenuTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  const _MenuTile({required this.icon, required this.color, required this.title, required this.subtitle, required this.onTap});

  @override
  Widget build(BuildContext context) => ListTile(
        onTap: onTap,
        leading: Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(14)),
          child: Icon(icon, color: color),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
        subtitle: Text(subtitle),
      );
}
