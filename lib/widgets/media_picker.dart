import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../core/config.dart';
import '../core/i18n.dart';
import 'common.dart';

const int kMaxUploadBytes = 50 * 1024 * 1024;

class PickedMedia {
  final String path;
  final bool isVideo;
  const PickedMedia(this.path, this.isVideo);
  String get name => path.split('/').last;
}

/// Bottom sheet: camera / gallery / video. Returns null when cancelled.
Future<PickedMedia?> pickMediaSheet(BuildContext context, {bool allowVideo = true}) async {
  final choice = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        ListTile(leading: const Icon(Icons.photo_camera_rounded, color: kGreen), title: Text(ctx.tr('take_photo')), onTap: () => Navigator.pop(ctx, 'camera')),
        ListTile(leading: const Icon(Icons.photo_library_rounded, color: kGreen), title: Text(ctx.tr('choose_photo')), onTap: () => Navigator.pop(ctx, 'gallery')),
        if (allowVideo) ...[
          ListTile(leading: const Icon(Icons.videocam_rounded, color: kGreen), title: Text(ctx.tr('record_video')), onTap: () => Navigator.pop(ctx, 'record')),
          ListTile(leading: const Icon(Icons.video_library_rounded, color: kGreen), title: Text(ctx.tr('choose_video')), onTap: () => Navigator.pop(ctx, 'video')),
        ],
        const SizedBox(height: 8),
      ]),
    ),
  );
  if (choice == null || !context.mounted) return null;
  try {
    final picker = ImagePicker();
    XFile? x;
    var video = false;
    switch (choice) {
      case 'camera':
        x = await picker.pickImage(source: ImageSource.camera, imageQuality: 82, maxWidth: 1920, maxHeight: 1920);
        break;
      case 'gallery':
        x = await picker.pickImage(source: ImageSource.gallery, imageQuality: 82, maxWidth: 1920, maxHeight: 1920);
        break;
      case 'record':
        video = true;
        x = await picker.pickVideo(source: ImageSource.camera, maxDuration: const Duration(minutes: 2));
        break;
      default:
        video = true;
        x = await picker.pickVideo(source: ImageSource.gallery, maxDuration: const Duration(minutes: 5));
    }
    if (x == null) return null;
    final size = await File(x.path).length();
    if (size > kMaxUploadBytes) {
      if (context.mounted) toast(context, context.tr('err_FILE_TOO_LARGE'), error: true);
      return null;
    }
    return PickedMedia(x.path, video);
  } catch (_) {
    if (context.mounted) toast(context, context.tr('err_pick_failed'), error: true);
    return null;
  }
}

/// Small preview tile for a picked file with a remove button.
class PickedTile extends StatelessWidget {
  final PickedMedia media;
  final VoidCallback onRemove;
  final double size;
  const PickedTile({super.key, required this.media, required this.onRemove, this.size = 84});

  @override
  Widget build(BuildContext context) {
    return Stack(children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: SizedBox(
          width: size,
          height: size,
          child: media.isVideo
              ? Container(color: Colors.black87, child: const Center(child: Icon(Icons.play_circle_fill_rounded, color: Colors.white, size: 36)))
              : Image.file(File(media.path), fit: BoxFit.cover, errorBuilder: (c, e, s) => const Icon(Icons.broken_image_outlined)),
        ),
      ),
      PositionedDirectional(
        top: 2,
        end: 2,
        child: InkWell(
          onTap: onRemove,
          child: Container(
            decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
            padding: const EdgeInsets.all(3),
            child: const Icon(Icons.close_rounded, color: Colors.white, size: 16),
          ),
        ),
      ),
    ]);
  }
}
