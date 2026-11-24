import 'dart:async';

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_map/flutter_map.dart';

import '../core/api.dart';
import '../core/config.dart';
import '../core/i18n.dart';
import '../core/models.dart';
import '../core/session.dart';
import '../core/wilayas.dart';
import '../widgets/common.dart';
import '../widgets/header.dart';
import '../widgets/media_picker.dart';
import 'map.dart';
import 'profile.dart';

// ======================================================================== list
class ReportsList extends StatefulWidget {
  final String query; // already url-encoded filters, e.g. "wilaya=...&type=..."
  final EdgeInsets padding;
  const ReportsList({super.key, this.query = '', this.padding = const EdgeInsets.fromLTRB(14, 4, 14, 100)});
  @override
  State<ReportsList> createState() => _ReportsListState();
}

class _ReportsListState extends State<ReportsList> {
  final List<Report> _rows = [];
  final ScrollController _sc = ScrollController();
  bool _loading = true;
  bool _more = true;
  bool _loadingMore = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _sc.addListener(() {
      if (_sc.hasClients && _sc.position.pixels > _sc.position.maxScrollExtent - 500) _loadMore();
    });
    contentRefresh.addListener(_silent);
    _load();
  }

  @override
  void didUpdateWidget(covariant ReportsList old) {
    super.didUpdateWidget(old);
    if (old.query != widget.query) _load();
  }

  @override
  void dispose() {
    contentRefresh.removeListener(_silent);
    _sc.dispose();
    super.dispose();
  }

  void _silent() => _load(silent: true);

  String _path({String? before}) {
    final q = <String>['limit=20'];
    if (widget.query.isNotEmpty) q.add(widget.query);
    if (before != null) q.add('before=${Uri.encodeComponent(before)}');
    return '/reports?${q.join('&')}';
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) setState(() { _loading = true; _error = null; });
    try {
      final rows = asMapList(await api.get(_path())).map(Report.fromJson).toList();
      if (!mounted) return;
      setState(() {
        _rows..clear()..addAll(rows);
        _more = rows.length >= 20;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() { _error = e; _loading = false; });
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_more || _rows.isEmpty || _rows.last.createdAt == null) return;
    setState(() => _loadingMore = true);
    try {
      final rows = asMapList(await api.get(_path(before: _rows.last.createdAt!.toUtc().toIso8601String()))).map(Report.fromJson).toList();
      if (!mounted) return;
      setState(() {
        _rows.addAll(rows);
        _more = rows.length >= 20;
      });
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const LoadingView();
    if (_error != null && _rows.isEmpty) return ErrorState(error: _error!, onRetry: _load);
    return RefreshIndicator(
      onRefresh: () => _load(silent: true),
      child: _rows.isEmpty
          ? ListView(children: [const SizedBox(height: 60), EmptyState(icon: Icons.fact_check_outlined, title: context.tr('no_reports'), subtitle: context.tr('no_reports_sub'))])
          : ListView.separated(
              controller: _sc,
              padding: widget.padding,
              physics: const AlwaysScrollableScrollPhysics(),
              itemCount: _rows.length + (_loadingMore ? 1 : 0),
              separatorBuilder: (_, i) => const SizedBox(height: 10),
              itemBuilder: (_, i) {
                if (i >= _rows.length) return const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator(strokeWidth: 2)));
                return ReportCard(report: _rows[i]);
              },
            ),
    );
  }
}

class ReportCard extends StatelessWidget {
  final Report report;
  const ReportCard({super.key, required this.report});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final c = typeColor(report.type);
    final thumb = report.mediaUrl != null && report.mediaType != 'VIDEO' && report.mediaType != 'FILE';
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ReportDetailsPage(report: report))),
        child: IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Container(width: 6, color: c),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [TypeChip(report.type), const SizedBox(width: 6), StatusChip(report.status), const Spacer(), if (report.mine) const Icon(Icons.person_pin_rounded, size: 18, color: kGreen)]),
                  const SizedBox(height: 8),
                  Text(report.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 4),
                  Text(report.description, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: cs.onSurfaceVariant, height: 1.35)),
                  const SizedBox(height: 8),
                  Row(children: [
                    Icon(Icons.location_on_outlined, size: 16, color: cs.onSurfaceVariant),
                    const SizedBox(width: 3),
                    Flexible(child: Text([wilayaDisplay(report.wilaya, context.lang), if ((report.city ?? '').isNotEmpty) report.city!].join(' • '), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant))),
                    const Spacer(),
                    Text(timeAgo(context, report.createdAt), style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                  ]),
                ]),
              ),
            ),
            if (thumb) SizedBox(width: 92, child: NetImage(report.mediaUrl!, width: 92, fit: BoxFit.cover)),
          ]),
        ),
      ),
    );
  }
}

// ======================================================================== search tab
class ReportsPage extends StatefulWidget {
  const ReportsPage({super.key});
  @override
  State<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends State<ReportsPage> {
  final TextEditingController _q = TextEditingController();
  final Debouncer _deb = Debouncer();
  String _text = '';
  String? _wilaya;
  String? _type;
  String? _status;
  bool _mine = false;

  @override
  void dispose() {
    _deb.dispose();
    _q.dispose();
    super.dispose();
  }

  String get _query {
    final p = <String>[];
    if (_text.isNotEmpty) p.add('q=${Uri.encodeComponent(_text)}');
    if (_wilaya != null) p.add('wilaya=${Uri.encodeComponent(_wilaya!)}');
    if (_type != null) p.add('type=${Uri.encodeComponent(_type!)}');
    if (_status != null) p.add('status=$_status');
    if (_mine) p.add('mine=1');
    return p.join('&');
  }

  bool get _hasFilters => _wilaya != null || _type != null || _status != null || _mine || _text.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      TopHeader(title: context.tr('reports'), subtitle: context.tr('reports_sub')),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: TextField(
          controller: _q,
          onChanged: (v) => _deb.run(() => setState(() => _text = v.trim())),
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: context.tr('search_reports'),
            prefixIcon: const Icon(Icons.search_rounded),
            suffixIcon: _q.text.isEmpty ? null : IconButton(icon: const Icon(Icons.close_rounded), onPressed: () { _q.clear(); setState(() => _text = ''); }),
          ),
        ),
      ),
      SizedBox(
        height: 54,
        child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), children: [
          _chip(context.tr('my_reports'), _mine, Icons.person_rounded, () => setState(() => _mine = !_mine)),
          _chip(_wilaya == null ? context.tr('all_wilayas') : wilayaDisplay(_wilaya, context.lang), _wilaya != null, Icons.location_city_rounded, () async {
            final w = await pickWilaya(context, current: _wilaya, allowAll: true);
            if (w != null && mounted) setState(() => _wilaya = w.isEmpty ? null : w);
          }),
          _chip(_type == null ? context.tr('all_types') : reportTypeLabel(context, _type!), _type != null, Icons.category_rounded, () async {
            final t = await pickFromList<String>(context, title: context.tr('report_type'), items: ['', ...kReportTypes], label: (x) => x.isEmpty ? context.tr('all_types') : reportTypeLabel(context, x), current: _type ?? '', icon: (x) => x.isEmpty ? Icons.apps_rounded : typeIcon(x));
            if (t != null && mounted) setState(() => _type = t.isEmpty ? null : t);
          }),
          _chip(_status == null ? context.tr('all_statuses') : context.tr('status_$_status'), _status != null, Icons.flag_circle_rounded, () async {
            final s = await pickFromList<String>(context, title: context.tr('status'), items: ['', ...kReportStatuses], label: (x) => x.isEmpty ? context.tr('all_statuses') : context.tr('status_$x'), current: _status ?? '');
            if (s != null && mounted) setState(() => _status = s.isEmpty ? null : s);
          }),
          if (_hasFilters)
            Padding(
              padding: const EdgeInsetsDirectional.only(start: 4),
              child: ActionChip(
                avatar: const Icon(Icons.clear_all_rounded, size: 18),
                label: Text(context.tr('clear')),
                onPressed: () { _q.clear(); setState(() { _text = ''; _wilaya = null; _type = null; _status = null; _mine = false; }); },
              ),
            ),
        ]),
      ),
      Expanded(child: ReportsList(query: _query)),
    ]);
  }

  Widget _chip(String label, bool selected, IconData icon, VoidCallback onTap) => Padding(
        padding: const EdgeInsetsDirectional.only(end: 8),
        child: FilterChip(
          avatar: Icon(icon, size: 17, color: selected ? kGreen : null),
          label: Text(label),
          selected: selected,
          showCheckmark: false,
          selectedColor: kGreen.withValues(alpha: 0.18),
          onSelected: (_) => onTap(),
        ),
      );
}

// ======================================================================== details
class ReportDetailsPage extends StatefulWidget {
  final Report? report;
  final String? reportId;
  const ReportDetailsPage({super.key, this.report, this.reportId});
  @override
  State<ReportDetailsPage> createState() => _ReportDetailsPageState();
}

class _ReportDetailsPageState extends State<ReportDetailsPage> {
  Report? _r;
  Object? _error;
  bool _loading = false;

  String get _id => widget.report?.id ?? widget.reportId ?? '';

  @override
  void initState() {
    super.initState();
    _r = widget.report;
    _load();
  }

  Future<void> _load() async {
    if (_r == null) setState(() { _loading = true; _error = null; });
    try {
      final d = Report.fromJson(Map<String, dynamic>.from(await api.get('/reports/$_id') as Map));
      if (mounted) setState(() { _r = d; _loading = false; _error = null; });
    } catch (e) {
      if (mounted) setState(() { _loading = false; if (_r == null) _error = e; });
    }
  }

  Future<void> _delete() async {
    final ok = await confirmDialog(context, title: context.tr('delete_report'), message: context.tr('delete_report_msg'), confirmLabel: context.tr('delete'), danger: true);
    if (!ok || !mounted) return;
    try {
      await api.delete('/reports/$_id');
      bumpContent();
      if (mounted) {
        toast(context, context.tr('deleted'));
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) toast(context, errMsg(e), error: true);
    }
  }

  Future<void> _flag() async {
    final reason = await promptDialog(context, title: context.tr('report_content'), hint: context.tr('reason_hint'), allowEmpty: true);
    if (reason == null || !mounted) return;
    try {
      await api.post('/flags', {'targetType': 'REPORT', 'targetId': _id, 'reason': reason});
      if (mounted) toast(context, context.tr('flag_sent'));
    } catch (e) {
      if (mounted) toast(context, errMsg(e), error: true);
    }
  }

  Future<void> _changeStatus() async {
    final r = _r!;
    final s = await pickFromList<String>(context, title: context.tr('change_status'), items: kReportStatuses, label: (x) => context.tr('status_$x'), current: r.status);
    if (s == null || !mounted) return;
    final note = await promptDialog(context, title: context.tr('moderator_note'), hint: context.tr('moderator_note_hint'), initial: r.moderatorNote, allowEmpty: true);
    if (note == null || !mounted) return;
    try {
      final d = await api.patch('/reports/$_id/status', {'status': s, 'note': note});
      bumpContent();
      if (mounted) {
        setState(() => _r = Report.fromJson(Map<String, dynamic>.from(d as Map)));
        toast(context, context.tr('status_updated'));
      }
    } catch (e) {
      if (mounted) toast(context, errMsg(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = _r;
    final cs = Theme.of(context).colorScheme;
    final staff = Session.I.user?.isStaff == true;
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('report_details')),
        actions: [
          if (r != null)
            PopupMenuButton<String>(
              onSelected: (v) {
                if (v == 'delete') _delete();
                if (v == 'flag') _flag();
                if (v == 'status') _changeStatus();
              },
              itemBuilder: (_) => [
                if (staff) PopupMenuItem(value: 'status', child: Text(context.tr('change_status'))),
                if (staff || (r.mine && r.status == 'PENDING')) PopupMenuItem(value: 'delete', child: Text(context.tr('delete'))),
                if (!r.mine) PopupMenuItem(value: 'flag', child: Text(context.tr('report_content'))),
              ],
            ),
        ],
      ),
      body: _loading
          ? const LoadingView()
          : (r == null)
              ? ErrorState(error: _error ?? 'x', onRetry: _load)
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(padding: const EdgeInsets.all(16), children: [
                    Wrap(spacing: 8, runSpacing: 6, children: [TypeChip(r.type), StatusChip(r.status)]),
                    const SizedBox(height: 10),
                    Text(r.title, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, height: 1.25)),
                    const SizedBox(height: 6),
                    Row(children: [
                      Icon(Icons.location_on_outlined, size: 17, color: cs.onSurfaceVariant),
                      const SizedBox(width: 4),
                      Flexible(child: Text([wilayaDisplay(r.wilaya, context.lang), if ((r.city ?? '').isNotEmpty) r.city!].join(' • '), style: TextStyle(color: cs.onSurfaceVariant))),
                      const SizedBox(width: 12),
                      Icon(Icons.schedule_rounded, size: 17, color: cs.onSurfaceVariant),
                      const SizedBox(width: 4),
                      Text(fmtDateTime(r.createdAt), style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13)),
                    ]),
                    const SizedBox(height: 14),
                    if (r.allMedia.isNotEmpty) ...[MediaGallery(items: r.allMedia), const SizedBox(height: 14)],
                    Card(child: Padding(padding: const EdgeInsets.all(16), child: SizedBox(width: double.infinity, child: Text(r.description, style: const TextStyle(height: 1.55, fontSize: 15.5))))),
                    if ((r.moderatorNote ?? '').isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(color: const Color(0xFF1565C0).withValues(alpha: 0.10), borderRadius: BorderRadius.circular(16)),
                        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          const Icon(Icons.admin_panel_settings_rounded, color: Color(0xFF1565C0)),
                          const SizedBox(width: 10),
                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(context.tr('moderator_note'), style: const TextStyle(fontWeight: FontWeight.w900)), const SizedBox(height: 2), Text(r.moderatorNote!)])),
                        ]),
                      ),
                    ],
                    if (r.hasLocation) ...[
                      SectionTitle(context.tr('location')),
                      _MiniMap(report: r),
                    ],
                    SectionTitle(context.tr('reported_by')),
                    if (r.reporter != null)
                      Card(
                        child: ListTile(
                          leading: AppAvatar(url: r.reporter!.avatarUrl, name: r.reporter!.name),
                          title: UserNameRow(r.reporter!),
                          subtitle: Text('@${r.reporter!.username}${r.anonymous ? '  •  ${context.tr('anonymous')}' : ''}'),
                          trailing: const Icon(Icons.chevron_right_rounded),
                          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => UserProfilePage(userId: r.reporter!.id))),
                        ),
                      )
                    else
                      Card(child: ListTile(leading: const CircleAvatar(child: Icon(Icons.visibility_off_rounded)), title: Text(context.tr('anonymous')), subtitle: Text(context.tr('anonymous_sub')))),
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: cs.surfaceContainerHighest.withValues(alpha: 0.5), borderRadius: BorderRadius.circular(14)),
                      child: Row(children: [const Icon(Icons.info_outline_rounded, size: 18), const SizedBox(width: 8), Expanded(child: Text(context.tr('report_disclaimer'), style: const TextStyle(fontSize: 12.5)))]),
                    ),
                  ]),
                ),
    );
  }
}

class _MiniMap extends StatelessWidget {
  final Report report;
  const _MiniMap({required this.report});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final p = LatLng(report.lat!, report.lon!);
    return Column(children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: SizedBox(
          height: 200,
          child: Stack(children: [
            FlutterMap(
              options: MapOptions(initialCenter: p, initialZoom: report.approximate ? 13 : 15, interactionOptions: const InteractionOptions(flags: InteractiveFlag.none)),
              children: [
                buildTileLayer('street', dark),
                if (report.approximate) CircleLayer(circles: [CircleMarker(point: p, radius: 600, useRadiusInMeter: true, color: kRed.withValues(alpha: 0.15), borderColor: kRed, borderStrokeWidth: 2)]),
                MarkerLayer(markers: [pinMarker(p, color: typeColor(report.type))]),
                buildAttribution('street'),
              ],
            ),
            Positioned.fill(
              child: Material(
                color: Colors.transparent,
                child: InkWell(onTap: () => showLocationSheet(context, lat: report.lat!, lon: report.lon!, title: report.title, approximate: report.approximate)),
              ),
            ),
          ]),
        ),
      ),
      const SizedBox(height: 8),
      Row(children: [
        Expanded(child: OutlinedButton.icon(onPressed: () => showLocationSheet(context, lat: report.lat!, lon: report.lon!, title: report.title, approximate: report.approximate), icon: const Icon(Icons.fullscreen_rounded), label: Text(context.tr('view_map')))),
        const SizedBox(width: 8),
        Expanded(child: OutlinedButton.icon(onPressed: () => openInMaps(report.lat!, report.lon!, label: report.title), icon: const Icon(Icons.directions_rounded), label: Text(context.tr('directions')))),
      ]),
      if (report.approximate) Padding(padding: const EdgeInsets.only(top: 6), child: Text(context.tr('approx_location_note'), style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant))),
    ]);
  }
}

// ======================================================================== create
class CreateReportPage extends StatefulWidget {
  const CreateReportPage({super.key});
  @override
  State<CreateReportPage> createState() => _CreateReportPageState();
}

class _CreateReportPageState extends State<CreateReportPage> {
  final _form = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _desc = TextEditingController();
  final _city = TextEditingController();
  String _type = kReportTypes.first;
  String _wilaya = Session.I.user?.wilaya ?? kDefaultWilaya;
  bool _anonymous = false;
  bool _busy = false;
  LatLng? _picked;
  final List<PickedMedia> _media = [];

  @override
  void dispose() {
    _title.dispose();
    _desc.dispose();
    _city.dispose();
    super.dispose();
  }

  Future<void> _openPicker() async {
    final r = await Navigator.push<PickedLocation>(context, MaterialPageRoute(builder: (_) => LocationPickerPage(initial: _picked)));
    if (r == null || !mounted) return;
    setState(() {
      _picked = r.point;
      _wilaya = r.wilaya.ar;
      if ((r.city ?? '').isNotEmpty && _city.text.trim().isEmpty) _city.text = r.city!;
    });
  }

  Future<void> _useMine() async {
    final p = await getMyLocation(context);
    if (p == null || !mounted) return;
    setState(() {
      _picked = p;
      _wilaya = nearestWilaya(p).ar;
    });
    final city = await reverseCity(p);
    if (mounted && city != null && _city.text.trim().isEmpty) setState(() => _city.text = city);
  }

  Future<void> _addMedia() async {
    if (_media.length >= 6) {
      toast(context, context.tr('max_6_files'), error: true);
      return;
    }
    final m = await pickMediaSheet(context);
    if (m != null && mounted) setState(() => _media.add(m));
  }

  Future<void> _submit() async {
    if (!(_form.currentState?.validate() ?? false)) return;
    if (_picked == null) {
      toast(context, context.tr('pick_location_first'), error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      await api.multipart('POST', '/reports',
          fields: {
            'type': _type,
            'title': _title.text.trim(),
            'description': _desc.text.trim(),
            'wilaya': _wilaya,
            'city': _city.text.trim(),
            'anonymous': '$_anonymous',
            'latitude': '${_picked!.latitude}',
            'longitude': '${_picked!.longitude}',
          },
          files: [for (final m in _media) UploadFile('media', m.path)]);
      if (!mounted) return;
      toast(context, context.tr('report_sent'));
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) toast(context, errMsg(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('new_report'))),
      body: Form(
        key: _form,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: kDeepGreen, borderRadius: BorderRadius.circular(20)),
            child: Row(children: [
              const Icon(Icons.shield_rounded, color: Colors.white, size: 34),
              const SizedBox(width: 12),
              Expanded(child: Text(context.tr('report_warning'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, height: 1.35))),
            ]),
          ),
          SectionTitle(context.tr('report_type')),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final t in kReportTypes)
              ChoiceChip(
                avatar: Icon(typeIcon(t), size: 18, color: _type == t ? Colors.white : typeColor(t)),
                label: Text(reportTypeLabel(context, t)),
                labelStyle: TextStyle(color: _type == t ? Colors.white : null, fontWeight: FontWeight.w700),
                selected: _type == t,
                showCheckmark: false,
                selectedColor: typeColor(t),
                onSelected: (_) => setState(() => _type = t),
              ),
          ]),
          const SizedBox(height: 14),
          TextFormField(controller: _title, maxLength: 160, decoration: InputDecoration(labelText: context.tr('title')), validator: (v) => (v == null || v.trim().length < 3) ? context.tr('required') : null),
          const SizedBox(height: 6),
          TextFormField(controller: _desc, minLines: 4, maxLines: 8, maxLength: 5000, decoration: InputDecoration(labelText: context.tr('description'), alignLabelWithHint: true), validator: (v) => (v == null || v.trim().length < 10) ? context.tr('description_short') : null),
          const SizedBox(height: 6),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [const Icon(Icons.place_rounded, color: kRed), const SizedBox(width: 8), Text(context.tr('report_location'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900))]),
                const SizedBox(height: 4),
                Text(context.tr('report_location_hint'), style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13)),
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: SizedBox(
                    height: 170,
                    child: Stack(children: [
                      FlutterMap(
                        key: ValueKey(_picked),
                        options: MapOptions(initialCenter: _picked ?? kAlgeriaCenter, initialZoom: _picked == null ? 4.6 : 15, interactionOptions: const InteractionOptions(flags: InteractiveFlag.none)),
                        children: [buildTileLayer('street', dark), if (_picked != null) MarkerLayer(markers: [pinMarker(_picked!)]), buildAttribution('street')],
                      ),
                      Positioned.fill(child: Material(color: Colors.transparent, child: InkWell(onTap: _openPicker))),
                    ]),
                  ),
                ),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(child: FilledButton.icon(onPressed: _openPicker, icon: const Icon(Icons.map_rounded), label: Text(context.tr(_picked == null ? 'pick_on_map' : 'change_location')))),
                  const SizedBox(width: 8),
                  IconButton.filledTonal(onPressed: _useMine, tooltip: context.tr('my_location'), icon: const Icon(Icons.my_location_rounded)),
                ]),
                const SizedBox(height: 12),
                InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () async {
                    final w = await pickWilaya(context, current: _wilaya);
                    if (w != null && w.isNotEmpty && mounted) setState(() => _wilaya = w);
                  },
                  child: InputDecorator(
                    decoration: InputDecoration(labelText: context.tr('wilaya'), prefixIcon: const Icon(Icons.location_city_rounded), suffixIcon: const Icon(Icons.arrow_drop_down_rounded)),
                    child: Text(wilayaDisplay(_wilaya, context.lang)),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(controller: _city, decoration: InputDecoration(labelText: context.tr('city_optional'), prefixIcon: const Icon(Icons.home_work_outlined))),
              ]),
            ),
          ),
          SectionTitle(context.tr('attachments')),
          Wrap(spacing: 10, runSpacing: 10, children: [
            for (var i = 0; i < _media.length; i++) PickedTile(media: _media[i], onRemove: () => setState(() => _media.removeAt(i))),
            InkWell(
              onTap: _busy ? null : _addMedia,
              borderRadius: BorderRadius.circular(14),
              child: Container(
                width: 84,
                height: 84,
                decoration: BoxDecoration(border: Border.all(color: kGreen, width: 1.5), borderRadius: BorderRadius.circular(14), color: kGreen.withValues(alpha: 0.06)),
                child: const Icon(Icons.add_a_photo_rounded, color: kGreen),
              ),
            ),
          ]),
          if (Session.I.settings.allowAnonymousReports)
            SwitchListTile(contentPadding: EdgeInsets.zero, value: _anonymous, onChanged: (v) => setState(() => _anonymous = v), title: Text(context.tr('send_anonymous')), subtitle: Text(context.tr('send_anonymous_sub'))),
          const SizedBox(height: 10),
          BusyButton(busy: _busy, onPressed: _submit, label: context.tr(_busy ? 'uploading' : 'send_report'), icon: Icons.send_rounded),
          const SizedBox(height: 30),
        ]),
      ),
    );
  }
}
