import 'package:flutter/material.dart';

import '../core/config.dart';
import '../core/i18n.dart';
import '../core/session.dart';
import '../pages/notifications.dart';
import '../pages/profile.dart';

class AppMark extends StatelessWidget {
  final double size;
  const AppMark({super.key, this.size = 44});
  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(size * 0.3),
          gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [kDeepGreen, kGreen]),
          boxShadow: [BoxShadow(color: kDeepGreen.withValues(alpha: 0.25), blurRadius: 10, offset: const Offset(0, 4))],
        ),
        child: Icon(Icons.shield_rounded, color: Colors.white, size: size * 0.58),
      );
}

class TopHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final List<Widget> actions;
  const TopHeader({super.key, required this.title, this.subtitle, this.actions = const []});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 8, 8),
        child: Row(children: [
          const AppMark(),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
              if (subtitle != null) Text(subtitle!, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12.5)),
            ]),
          ),
          ...actions,
          IconButton(
            tooltip: context.tr('search_people'),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const UserSearchPage())),
            icon: const Icon(Icons.search_rounded),
          ),
          const NotificationBell(),
        ]),
      ),
    );
  }
}

class NotificationBell extends StatelessWidget {
  const NotificationBell({super.key});
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Session.I,
      builder: (context, _) {
        final n = Session.I.unreadNotifications;
        return IconButton(
          tooltip: context.tr('notifications'),
          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const NotificationsPage())),
          icon: Badge(
            isLabelVisible: n > 0,
            label: Text(n > 99 ? '99+' : '$n'),
            child: const Icon(Icons.notifications_none_rounded),
          ),
        );
      },
    );
  }
}
