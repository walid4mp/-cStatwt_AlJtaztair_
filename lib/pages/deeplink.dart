import 'package:flutter/material.dart';

import '../core/session.dart';
import 'admin/admin_home.dart';
import 'chat.dart';
import 'lostfound.dart';
import 'notifications.dart';
import 'posts.dart';
import 'profile.dart';
import 'reports.dart';
import 'verification.dart';

/// Opens the screen related to a notification (in-app banner, system notification or list).
void openTarget(String type, Map<String, dynamic> data) {
  final nav = navigatorKey.currentState;
  if (nav == null || !Session.I.loggedIn) return;
  String? s(String k) => data[k]?.toString();
  Widget page;
  switch (type) {
    case 'message':
      final id = s('conversationId');
      page = id == null ? const NotificationsPage() : ChatPage(conversationId: id);
      break;
    case 'like':
    case 'comment':
      final id = s('postId');
      page = id == null ? const NotificationsPage() : PostDetailPage(postId: id);
      break;
    case 'follow':
      final id = s('userId');
      page = id == null ? const NotificationsPage() : UserProfilePage(userId: id);
      break;
    case 'report_status':
    case 'new_report':
      final id = s('reportId');
      if (type == 'new_report' && Session.I.user?.isStaff == true) {
        page = const AdminHome();
      } else {
        page = id == null ? const NotificationsPage() : ReportDetailsPage(reportId: id);
      }
      break;
    case 'verification':
      page = const VerificationPage();
      break;
    case 'lf_match':
      final id = s('lostFoundId');
      page = id == null ? const NotificationsPage() : LostFoundDetailPage(itemId: id);
      break;
    case 'new_flag':
    case 'new_verification':
      page = Session.I.user?.isStaff == true ? const AdminHome() : const NotificationsPage();
      break;
    default:
      page = const NotificationsPage();
  }
  nav.push(MaterialPageRoute(builder: (_) => page));
}
