import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/i18n.dart';
import '../widgets/common.dart';
import '../widgets/media_picker.dart';

class VerificationPage extends StatefulWidget {
  const VerificationPage({super.key});
  @override
  State<VerificationPage> createState() => _VerificationPageState();
}

class _VerificationPageState extends State<VerificationPage> {
  Map<String, dynamic>? _req;
  final TextEditingController _reason = TextEditingController();
  PickedMedia? _doc;
  bool _loading = true;
  bool _busy = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final d = await api.get('/verification/me');
      if (!mounted) return;
      setState(() {
        _req = d is Map ? Map<String, dynamic>.from(d) : null;
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() { _error = e; _loading = false; });
    }
  }

  Future<void> _submit() async {
    if (_reason.text.trim().length < 10) {
      toast(context, context.tr('verification_reason_short'), error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      await api.multipart('POST', '/verification/request', fields: {'reason': _reason.text.trim()}, files: [if (_doc != null) UploadFile('document', _doc!.path)]);
      if (!mounted) return;
      toast(context, context.tr('verification_sent'));
      _doc = null;
      await _load();
    } catch (e) {
      if (mounted) toast(context, errMsg(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = _req?['status']?.toString();
    final approved = status == 'APPROVED';
    final pending = status == 'PENDING';
    final rejected = status == 'REJECTED';
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('request_verification'))),
      body: _loading
          ? const LoadingView()
          : _error != null
              ? ErrorState(error: _error!, onRetry: _load)
              : ListView(padding: const EdgeInsets.all(18), children: [
                  Center(child: Icon(approved ? Icons.verified_rounded : Icons.verified_user_outlined, size: 72, color: approved ? const Color(0xFF1E88E5) : Colors.grey)),
                  const SizedBox(height: 10),
                  Text(context.tr('verification_intro'), textAlign: TextAlign.center, style: const TextStyle(height: 1.5)),
                  const SizedBox(height: 16),
                  if (status != null)
                    Card(
                      color: approved ? Colors.green.withValues(alpha: 0.12) : (rejected ? Colors.red.withValues(alpha: 0.1) : Colors.orange.withValues(alpha: 0.12)),
                      child: ListTile(
                        leading: Icon(approved ? Icons.check_circle_rounded : (rejected ? Icons.cancel_rounded : Icons.hourglass_top_rounded)),
                        title: Text(context.tr(approved ? 'verification_approved' : (rejected ? 'verification_rejected' : 'verification_pending')), style: const TextStyle(fontWeight: FontWeight.w800)),
                        subtitle: (_req?['note'] ?? '').toString().isEmpty ? null : Text(_req!['note'].toString()),
                      ),
                    ),
                  if (!approved && !pending) ...[
                    const SizedBox(height: 14),
                    TextField(controller: _reason, maxLines: 5, maxLength: 1000, decoration: InputDecoration(labelText: context.tr('verification_reason'), alignLabelWithHint: true)),
                    const SizedBox(height: 8),
                    if (_doc != null)
                      Align(alignment: AlignmentDirectional.centerStart, child: PickedTile(media: _doc!, onRemove: () => setState(() => _doc = null), size: 110))
                    else
                      OutlinedButton.icon(
                        onPressed: () async {
                          final m = await pickMediaSheet(context, allowVideo: false);
                          if (m != null && mounted) setState(() => _doc = m);
                        },
                        icon: const Icon(Icons.attach_file_rounded),
                        label: Text(context.tr('attach_document')),
                      ),
                    const SizedBox(height: 18),
                    BusyButton(busy: _busy, onPressed: _submit, label: context.tr('send'), icon: Icons.send_rounded),
                  ],
                ]),
    );
  }
}
