DateTime? _dt(dynamic v) {
  if (v == null) return null;
  return DateTime.tryParse(v.toString())?.toLocal();
}

double? _d(dynamic v) => v is num ? v.toDouble() : null;
int _i(dynamic v) => v is num ? v.toInt() : 0;
String? _s(dynamic v) => v == null ? null : v.toString();
Map<String, dynamic> _m(dynamic v) => v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

class AppUser {
  final String id;
  final String username;
  final String name;
  final String? bio;
  final String? avatarUrl;
  final String? phone;
  final String? whatsapp;
  final String? wilaya;
  final String? email;
  final String? language;
  final String role;
  final bool verified;
  final bool banned;
  final String? bannedReason;
  final DateTime? createdAt;
  final DateTime? lastSeenAt;

  const AppUser({
    required this.id,
    required this.username,
    required this.name,
    this.bio,
    this.avatarUrl,
    this.phone,
    this.whatsapp,
    this.wilaya,
    this.email,
    this.language,
    this.role = 'USER',
    this.verified = false,
    this.banned = false,
    this.bannedReason,
    this.createdAt,
    this.lastSeenAt,
  });

  bool get isStaff => role == 'ADMIN' || role == 'MODERATOR';
  bool get isAdmin => role == 'ADMIN';

  factory AppUser.fromJson(Map<String, dynamic> j) => AppUser(
        id: _s(j['id']) ?? '',
        username: _s(j['username']) ?? '',
        name: _s(j['name']) ?? _s(j['username']) ?? '',
        bio: _s(j['bio']),
        avatarUrl: _s(j['avatarUrl']),
        phone: _s(j['phone']),
        whatsapp: _s(j['whatsapp']),
        wilaya: _s(j['wilaya']),
        email: _s(j['email']),
        language: _s(j['language']),
        role: _s(j['role']) ?? 'USER',
        verified: j['isVerified'] == true,
        banned: j['banned'] == true,
        bannedReason: _s(j['bannedReason']),
        createdAt: _dt(j['createdAt']),
        lastSeenAt: _dt(j['lastSeenAt']),
      );

  static AppUser? maybe(dynamic v) => v is Map ? AppUser.fromJson(Map<String, dynamic>.from(v)) : null;
}

class Post {
  final String id;
  final String title;
  final String body;
  final String? wilaya;
  final String? city;
  final double? lat;
  final double? lon;
  final String? mediaUrl;
  final String? mediaType;
  final bool hidden;
  final DateTime? createdAt;
  final AppUser? author;
  int likesCount;
  int commentsCount;
  bool likedByMe;
  bool savedByMe;
  final bool mine;

  Post({
    required this.id,
    this.title = '',
    this.body = '',
    this.wilaya,
    this.city,
    this.lat,
    this.lon,
    this.mediaUrl,
    this.mediaType,
    this.hidden = false,
    this.createdAt,
    this.author,
    this.likesCount = 0,
    this.commentsCount = 0,
    this.likedByMe = false,
    this.savedByMe = false,
    this.mine = false,
  });

  factory Post.fromJson(Map<String, dynamic> j) => Post(
        id: _s(j['id']) ?? '',
        title: _s(j['title']) ?? '',
        body: _s(j['body']) ?? '',
        wilaya: _s(j['wilaya']),
        city: _s(j['city']),
        lat: _d(j['latitude']),
        lon: _d(j['longitude']),
        mediaUrl: _s(j['mediaUrl']),
        mediaType: _s(j['mediaType']),
        hidden: j['hidden'] == true,
        createdAt: _dt(j['createdAt']),
        author: AppUser.maybe(j['author']),
        likesCount: _i(j['likesCount']),
        commentsCount: _i(j['commentsCount']),
        likedByMe: j['likedByMe'] == true,
        savedByMe: j['savedByMe'] == true,
        mine: j['mine'] == true,
      );
}

class Comment {
  final String id;
  final String body;
  final DateTime? createdAt;
  final AppUser? user;
  final bool mine;
  Comment({required this.id, required this.body, this.createdAt, this.user, this.mine = false});
  factory Comment.fromJson(Map<String, dynamic> j) => Comment(
        id: _s(j['id']) ?? '',
        body: _s(j['body']) ?? '',
        createdAt: _dt(j['createdAt']),
        user: AppUser.maybe(j['user']),
        mine: j['mine'] == true,
      );
}

class Evidence {
  final String url;
  final String type;
  const Evidence(this.url, this.type);
}

class Report {
  final String id;
  final String type;
  final String title;
  final String description;
  final String wilaya;
  final String? city;
  final double? lat;
  final double? lon;
  final bool approximate;
  final String? mediaUrl;
  final String? mediaType;
  final bool anonymous;
  final String status;
  final String? moderatorNote;
  final DateTime? createdAt;
  final List<Evidence> evidence;
  final AppUser? reporter;
  final bool mine;

  const Report({
    required this.id,
    required this.type,
    required this.title,
    this.description = '',
    this.wilaya = '',
    this.city,
    this.lat,
    this.lon,
    this.approximate = true,
    this.mediaUrl,
    this.mediaType,
    this.anonymous = false,
    this.status = 'PENDING',
    this.moderatorNote,
    this.createdAt,
    this.evidence = const [],
    this.reporter,
    this.mine = false,
  });

  bool get hasLocation => lat != null && lon != null;

  /// All media (main + evidence) as (url,type) pairs.
  List<Evidence> get allMedia {
    final out = <Evidence>[];
    if (mediaUrl != null && mediaUrl!.isNotEmpty) out.add(Evidence(mediaUrl!, mediaType ?? 'IMAGE'));
    out.addAll(evidence);
    return out;
  }

  factory Report.fromJson(Map<String, dynamic> j) {
    final ev = <Evidence>[];
    final raw = j['evidence'];
    if (raw is List) {
      for (final e in raw) {
        final m = _m(e);
        final u = _s(m['url']);
        if (u != null) ev.add(Evidence(u, _s(m['type']) ?? 'IMAGE'));
      }
    }
    return Report(
      id: _s(j['id']) ?? '',
      type: _s(j['type']) ?? '',
      title: _s(j['title']) ?? '',
      description: _s(j['description']) ?? '',
      wilaya: _s(j['wilaya']) ?? '',
      city: _s(j['city']),
      lat: _d(j['latitude']),
      lon: _d(j['longitude']),
      approximate: j['approximate'] != false,
      mediaUrl: _s(j['mediaUrl']),
      mediaType: _s(j['mediaType']),
      anonymous: j['anonymous'] == true,
      status: _s(j['status']) ?? 'PENDING',
      moderatorNote: _s(j['moderatorNote']),
      createdAt: _dt(j['createdAt']),
      evidence: ev,
      reporter: AppUser.maybe(j['reporter']),
      mine: j['mine'] == true,
    );
  }
}

class ChatMessage {
  final String id;
  final String conversationId;
  final String senderId;
  final String body;
  final String? mediaUrl;
  final String? mediaType;
  final DateTime? createdAt;
  DateTime? readAt;
  final String? senderName;

  ChatMessage({
    required this.id,
    required this.conversationId,
    required this.senderId,
    this.body = '',
    this.mediaUrl,
    this.mediaType,
    this.createdAt,
    this.readAt,
    this.senderName,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> j) => ChatMessage(
        id: _s(j['id']) ?? '',
        conversationId: _s(j['conversationId']) ?? '',
        senderId: _s(j['senderId']) ?? '',
        body: _s(j['body']) ?? '',
        mediaUrl: _s(j['mediaUrl']),
        mediaType: _s(j['mediaType']),
        createdAt: _dt(j['createdAt']),
        readAt: _dt(j['readAt']),
        senderName: _s(j['senderName']),
      );
}

class Conversation {
  final String id;
  final AppUser? other;
  ChatMessage? lastMessage;
  int unread;
  bool muted;
  bool blockedByMe;
  bool blockedMe;

  Conversation({
    required this.id,
    this.other,
    this.lastMessage,
    this.unread = 0,
    this.muted = false,
    this.blockedByMe = false,
    this.blockedMe = false,
  });

  factory Conversation.fromJson(Map<String, dynamic> j) => Conversation(
        id: _s(j['id']) ?? '',
        other: AppUser.maybe(j['other']),
        lastMessage: j['lastMessage'] is Map ? ChatMessage.fromJson(_m(j['lastMessage'])) : null,
        unread: _i(j['unread']),
        muted: j['muted'] == true,
        blockedByMe: j['blockedByMe'] == true,
        blockedMe: j['blockedMe'] == true,
      );
}

class AppNotification {
  final String? id;
  final String type;
  final String title;
  final String body;
  bool read;
  final DateTime? createdAt;
  final Map<String, dynamic> data;

  AppNotification({
    this.id,
    this.type = '',
    this.title = '',
    this.body = '',
    this.read = false,
    this.createdAt,
    this.data = const {},
  });

  factory AppNotification.fromJson(Map<String, dynamic> j) => AppNotification(
        id: _s(j['id']),
        type: _s(j['type']) ?? '',
        title: _s(j['title']) ?? '',
        body: _s(j['body']) ?? '',
        read: j['read'] == true,
        createdAt: _dt(j['createdAt']),
        data: _m(j['data']),
      );
}

class LostFoundItem {
  final String id;
  final String kind; // LOST | FOUND
  final String title;
  final String description;
  final String category;
  final String wilaya;
  final String? city;
  final double? lat;
  final double? lon;
  final String? imageUrl;
  final String? contactHint;
  final String status;
  final DateTime? createdAt;
  final AppUser? user;
  final bool mine;

  const LostFoundItem({
    required this.id,
    required this.kind,
    required this.title,
    this.description = '',
    this.category = 'other',
    this.wilaya = '',
    this.city,
    this.lat,
    this.lon,
    this.imageUrl,
    this.contactHint,
    this.status = 'OPEN',
    this.createdAt,
    this.user,
    this.mine = false,
  });

  factory LostFoundItem.fromJson(Map<String, dynamic> j) => LostFoundItem(
        id: _s(j['id']) ?? '',
        kind: _s(j['kind']) ?? 'LOST',
        title: _s(j['title']) ?? '',
        description: _s(j['description']) ?? '',
        category: _s(j['category']) ?? 'other',
        wilaya: _s(j['wilaya']) ?? '',
        city: _s(j['city']),
        lat: _d(j['latitude']),
        lon: _d(j['longitude']),
        imageUrl: _s(j['imageUrl']),
        contactHint: _s(j['contactHint']),
        status: _s(j['status']) ?? 'OPEN',
        createdAt: _dt(j['createdAt']),
        user: AppUser.maybe(j['user']),
        mine: j['mine'] == true,
      );
}

class PublicSettings {
  final String announcement;
  final String announcementLevel;
  final bool maintenance;
  final bool registrationOpen;
  final bool allowAnonymousReports;
  const PublicSettings({
    this.announcement = '',
    this.announcementLevel = 'info',
    this.maintenance = false,
    this.registrationOpen = true,
    this.allowAnonymousReports = true,
  });

  factory PublicSettings.fromJson(Map<String, dynamic> j) => PublicSettings(
        announcement: _s(j['announcement']) ?? '',
        announcementLevel: _s(j['announcementLevel']) ?? 'info',
        maintenance: j['maintenance'] == true,
        registrationOpen: j['registrationOpen'] != false,
        allowAnonymousReports: j['allowAnonymousReports'] != false,
      );
}

List<Map<String, dynamic>> asMapList(dynamic v) {
  if (v is! List) return <Map<String, dynamic>>[];
  return v.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
}
