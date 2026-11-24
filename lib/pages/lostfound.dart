import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../core/api.dart';
import '../core/config.dart';
import '../core/i18n.dart';
import '../core/models.dart';
import '../core/session.dart';
import '../core/wilayas.dart';
import '../widgets/common.dart';
import '../widgets/media_picker.dart';
import 'chat.dart';
import 'map.dart';
import 'profile.dart';

IconData lostCategoryIcon(String c) {
  switch (c) {
    case 'phone':
      return Icons.smartphone_rounded;
    case 'documents':
      return Icons.description_rounded;
    case 'wallet':
      return Icons.account_balance_wallet_rounded;
    case 'keys':
      return Icons.vpn_key_rounded;
    case 'bag':
      return Icons.backpack_rounded;
    case 'vehicle':
      return Icons.directions_car_rounded;
    case 'pet':
      return Icons.pets_rounded;
    case 'person':
      return Icons.person_search_rounded;
    case 'jewelry':
      return Icons.diamond_rounded;
    case 'electronics':
      return Icons.devices_rounded;
    default:
      return Icons.inventory_2_rounded;
  }
}

Color _kindColor(String kind) => kind == 'LOST' ? kRed : kGreen;

class LostFoundPage extends StatefulWidget {
  const LostFoundPage({super.key});
  @override
  State<LostFoundPage> createState() => _LostFoundPageState();
}

class _LostFoundPageState extends State<LostFoundPage> {
  String _kind = 'ALL';
  bool _mine = false;
  String? _wilaya;
  final TextEditingController _q = TextEditingController();
  final Debouncer _deb = Debouncer();
  List<LostFoundItem> _items = [];
  bool _loading = true;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _deb.dispose();
    _q.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final qs = <String>[
        if (_kind != 'ALL') 'kind=$_kind',
        if (_mine) 'mine=1',
        if (_wilaya != null) 'wilaya=${Uri.encodeComponent(_wilaya!)}',
        if (_q.text.trim().isNotEmpty) 'q=${Uri.encodeComponent(_q.text.trim())}',
      ];
      final rows = asMapList(await api.get('/lost-found${qs.isEmpty ? '' : '?${qs.join('&')}'}')).map(LostFoundItem.fromJson).toList();
      if (mounted) setState(() { _items = rows; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e; _loading = false; });
    }
  }

  Future<void> _create() async {
    final ok = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => const CreateLostFoundPage()));
    if (ok == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('lost_found'))),
      floatingActionButton: FloatingActionButton.extended(onPressed: _create, icon: const Icon(Icons.add_rounded), label: Text(context.tr('add_item'))),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
          child: TextField(
            controller: _q,
            onChanged: (_) => _deb.run(_load),
            decoration: InputDecoration(hintText: context.tr('search'), prefixIcon: const Icon(Icons.search_rounded), isDense: true),
          ),
        ),
        SizedBox(
          height: 52,
          child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12), children: [
            for (final k in const ['ALL', 'LOST', 'FOUND'])
              Padding(
                padding: const EdgeInsetsDirectional.only(end: 8),
                child: Center(child: ChoiceChip(label: Text(context.tr(k == 'ALL' ? 'all' : (k == 'LOST' ? 'lost' : 'found'))), selected: _kind == k, onSelected: (_) { setState(() => _kind = k); _load(); })),
              ),
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 8),
              child: Center(child: FilterChip(label: Text(context.tr('mine')), selected: _mine, onSelected: (v) { setState(() => _mine = v); _load(); })),
            ),
            Center(
              child: ActionChip(
                avatar: const Icon(Icons.location_on_outlined, size: 18),
                label: Text(_wilaya == null ? context.tr('all_wilayas') : wilayaDisplay(_wilaya, context.lang)),
                onPressed: () async {
                  final w = await pickWilaya(context, current: _wilaya, allowAll: true);
                  if (w == null) return;
                  setState(() => _wilaya = w.isEmpty ? null : w);
                  _load();
                },
              ),
            ),
          ]),
        ),
        Expanded(
          child: _loading
              ? const LoadingView()
              : _error != null
                  ? ErrorState(error: _error!, onRetry: _load)
                  : _items.isEmpty
                      ? EmptyState(icon: Icons.manage_search_rounded, title: context.tr('no_items'))
                      : RefreshIndicator(
                          onRefresh: _load,
                          child: ListView.builder(
                            padding: const EdgeInsets.fromLTRB(14, 4, 14, 100),
                            itemCount: _items.length,
                            itemBuilder: (_, i) => _ItemCard(item: _items[i], onChanged: _load),
                          ),
                        ),
        ),
      ]),
      backgroundColor: cs.surface,
    );
  }
}

class _ItemCard extends StatelessWidget {
  final LostFoundItem item;
  final VoidCallback onChanged;
  const _ItemCard({required this.item, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final c = _kindColor(item.kind);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () async {
          await Navigator.push(context, MaterialPageRoute(builder: (_) => LostFoundDetailPage(itemId: item.id)));
          onChanged();
        },
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: item.imageUrl != null
                  ? NetImage(item.imageUrl!, width: 82, height: 82)
                  : Container(width: 82, height: 82, color: c.withValues(alpha: 0.1), child: Icon(lostCategoryIcon(item.category), color: c, size: 34)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(color: c.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
                    child: Text(context.tr(item.kind == 'LOST' ? 'lost' : 'found'), style: TextStyle(color: c, fontWeight: FontWeight.w800, fontSize: 12)),
                  ),
                  if (item.status != 'OPEN') ...[
                    const SizedBox(width: 6),
                    Text(context.tr('resolved'), style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
                  ],
                ]),
                const SizedBox(height: 4),
                Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5)),
                Text(item.description, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13)),
                const SizedBox(height: 4),
                Text('${wilayaDisplay(item.wilaya, context.lang)} • ${timeAgo(context, item.createdAt)}', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------- create
class CreateLostFoundPage extends StatefulWidget {
  const CreateLostFoundPage({super.key});
  @override
  State<CreateLostFoundPage> createState() => _CreateLostFoundPageState();
}

class _CreateLostFoundPageState extends State<CreateLostFoundPage> {
  String _kind = 'LOST';
  String _category = 'other';
  final TextEditingController _title = TextEditingController();
  final TextEditingController _desc = TextEditingController();
  final TextEditingController _hint = TextEditingController();
  String? _wilaya = Session.I.user?.wilaya;
  String? _city;
  LatLng? _point;
  PickedMedia? _image;
  bool _busy = false;

  @override
  void dispose() {
    _title.dispose();
    _desc.dispose();
    _hint.dispose();
    super.dispose();
  }

  Future<void> _pickLocation() async {
    final r = await Navigator.push<PickedLocation>(context, MaterialPageRoute(builder: (_) => LocationPickerPage(initial: _point)));
    if (r != null && mounted) setState(() { _point = r.point; _city = r.city; _wilaya = r.wilaya.ar; });
  }

  Future<void> _submit() async {
    if (_title.text.trim().isEmpty || _desc.text.trim().isEmpty || _wilaya == null) {
      toast(context, context.tr('err_MISSING_FIELDS'), error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      await api.multipart('POST', '/lost-found',
          fields: {
            'kind': _kind,
            'category': _category,
            'title': _title.text.trim(),
            'description': _desc.text.trim(),
            'wilaya': _wilaya!,
            if (_city != null) 'city': _city!,
            if (_point != null) 'latitude': '${_point!.latitude}',
            if (_point != null) 'longitude': '${_point!.longitude}',
            if (_hint.text.trim().isNotEmpty) 'contactHint': _hint.text.trim(),
          },
          files: [if (_image != null) UploadFile('image', _image!.path)]);
      if (!mounted) return;
      toast(context, context.tr('item_published'));
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
      appBar: AppBar(title: Text(context.tr('add_item'))),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        SegmentedButton<String>(
          segments: [
            ButtonSegment(value: 'LOST', label: Text(context.tr('lost')), icon: const Icon(Icons.search_off_rounded)),
            ButtonSegment(value: 'FOUND', label: Text(context.tr('found')), icon: const Icon(Icons.check_circle_outline_rounded)),
          ],
          selected: {_kind},
          onSelectionChanged: (s) => setState(() => _kind = s.first),
        ),
        const SizedBox(height: 14),
        Wrap(spacing: 8, runSpacing: 4, children: [
          for (final c in kLostCategories)
            ChoiceChip(avatar: Icon(lostCategoryIcon(c), size: 18), label: Text(context.tr('cat_$c')), selected: _category == c, onSelected: (_) => setState(() => _category = c)),
        ]),
        const SizedBox(height: 14),
        TextField(controller: _title, maxLength: 160, decoration: InputDecoration(labelText: context.tr('title'))),
        const SizedBox(height: 6),
        TextField(controller: _desc, maxLines: 5, maxLength: 3000, decoration: InputDecoration(labelText: context.tr('description'), alignLabelWithHint: true)),
        const SizedBox(height: 6),
        TextField(controller: _hint, decoration: InputDecoration(labelText: context.tr('contact_hint'), prefixIcon: const Icon(Icons.contact_phone_outlined))),
        const SizedBox(height: 12),
        InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () async {
            final w = await pickWilaya(context, current: _wilaya);
            if (w != null && w.isNotEmpty && mounted) setState(() => _wilaya = w);
          },
          child: InputDecorator(
            decoration: InputDecoration(labelText: context.tr('wilaya'), prefixIcon: const Icon(Icons.location_city_rounded), suffixIcon: const Icon(Icons.arrow_drop_down_rounded)),
            child: Text(_wilaya == null ? context.tr('not_specified') : wilayaDisplay(_wilaya, context.lang)),
          ),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: _pickLocation,
          icon: const Icon(Icons.pin_drop_rounded),
          label: Text(_point == null ? context.tr('pick_location') : '${_city ?? ''} ${_point!.latitude.toStringAsFixed(4)}, ${_point!.longitude.toStringAsFixed(4)}'),
        ),
        const SizedBox(height: 10),
        if (_image != null)
          Align(alignment: AlignmentDirectional.centerStart, child: PickedTile(media: _image!, onRemove: () => setState(() => _image = null), size: 110))
        else
          OutlinedButton.icon(
            onPressed: () async {
              final m = await pickMediaSheet(context, allowVideo: false);
              if (m != null && mounted) setState(() => _image = m);
            },
            icon: const Icon(Icons.add_a_photo_rounded),
            label: Text(context.tr('add_photo')),
          ),
        const SizedBox(height: 22),
        BusyButton(busy: _busy, onPressed: _submit, label: context.tr(_busy ? 'publishing' : 'publish'), icon: Icons.send_rounded),
      ]),
    );
  }
}

// ---------------------------------------------------------------------- detail
class LostFoundDetailPage extends StatefulWidget {
  final String itemId;
  const LostFoundDetailPage({super.key, required this.itemId});
  @override
  State<LostFoundDetailPage> createState() => _LostFoundDetailPageState();
}

class _LostFoundDetailPageState extends State<LostFoundDetailPage> {
  LostFoundItem? _item;
  List<LostFoundItem> _matches = [];
  Object? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final d = await api.getMap('/lost-found/${widget.itemId}');
      if (!mounted) return;
      setState(() {
        _item = LostFoundItem.fromJson(Map<String, dynamic>.from(d['item'] as Map));
        _matches = asMapList(d['matches']).map(LostFoundItem.fromJson).toList();
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() { _error = e; _loading = false; });
    }
  }

  Future<void> _toggleResolved() async {
    final it = _item!;
    try {
      await api.patch('/lost-found/${it.id}', {'status': it.status == 'OPEN' ? 'RESOLVED' : 'OPEN'});
      _load();
    } catch (e) {
      if (mounted) toast(context, errMsg(e), error: true);
    }
  }

  Future<void> _delete() async {
    final ok = await confirmDialog(context, title: context.tr('delete'), message: context.tr('delete_confirm'), confirmLabel: context.tr('delete'), danger: true);
    if (!ok) return;
    try {
      await api.delete('/lost-found/${_item!.id}');
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) toast(context, errMsg(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final it = _item;
    final cs = Theme.of(context).colorScheme;
    final canManage = it != null && (it.mine || Session.I.user?.isStaff == true);
    return Scaffold(
      appBar: AppBar(title: Text(it?.title ?? context.tr('lost_found')), actions: [
        if (canManage) IconButton(tooltip: context.tr('delete'), onPressed: _delete, icon: const Icon(Icons.delete_outline_rounded)),
      ]),
      body: _loading
          ? const LoadingView()
          : it == null
              ? ErrorState(error: _error ?? 'x', onRetry: _load)
              : ListView(padding: const EdgeInsets.all(16), children: [
                  if (it.imageUrl != null)
                    GestureDetector(onTap: () => openImage(context, [it.imageUrl!]), child: ClipRRect(borderRadius: BorderRadius.circular(18), child: NetImage(it.imageUrl!, height: 230, width: double.infinity))),
                  const SizedBox(height: 12),
                  Wrap(spacing: 8, children: [
                    Chip(label: Text(context.tr(it.kind == 'LOST' ? 'lost' : 'found')), backgroundColor: _kindColor(it.kind).withValues(alpha: 0.12)),
                    Chip(avatar: Icon(lostCategoryIcon(it.category), size: 16), label: Text(context.tr('cat_${it.category}'))),
                    if (it.status != 'OPEN') Chip(label: Text(context.tr('resolved'))),
                  ]),
                  Text(it.title, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 6),
                  Text(it.description, style: const TextStyle(height: 1.5, fontSize: 15)),
                  const SizedBox(height: 10),
                  Row(children: [Icon(Icons.location_on_outlined, size: 18, color: cs.onSurfaceVariant), const SizedBox(width: 4), Expanded(child: Text('${wilayaDisplay(it.wilaya, context.lang)}${(it.city ?? '').isNotEmpty ? ' • ${it.city}' : ''}'))]),
                  if ((it.contactHint ?? '').isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Row(children: [Icon(Icons.contact_phone_outlined, size: 18, color: cs.onSurfaceVariant), const SizedBox(width: 4), Expanded(child: Text(it.contactHint!))])),
                  if (it.lat != null && it.lon != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: OutlinedButton.icon(onPressed: () => openInMaps(it.lat!, it.lon!, label: it.title), icon: const Icon(Icons.map_rounded), label: Text(context.tr('open_in_maps'))),
                    ),
                  const SizedBox(height: 12),
                  if (it.user != null)
                    Card(
                      child: ListTile(
                        leading: AppAvatar(url: it.user!.avatarUrl, name: it.user!.name),
                        title: UserNameRow(it.user!),
                        subtitle: Text('@${it.user!.username}'),
                        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => UserProfilePage(userId: it.user!.id))),
                        trailing: it.mine ? null : IconButton.filledTonal(onPressed: () => openChatWith(context, it.user!), icon: const Icon(Icons.chat_bubble_rounded)),
                      ),
                    ),
                  if (canManage)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: FilledButton.icon(
                        onPressed: _toggleResolved,
                        icon: Icon(it.status == 'OPEN' ? Icons.task_alt_rounded : Icons.restart_alt_rounded),
                        label: Text(context.tr(it.status == 'OPEN' ? 'mark_resolved' : 'reopen')),
                      ),
                    ),
                  if (_matches.isNotEmpty) ...[
                    SectionTitle(context.tr('possible_matches')),
                    for (final m in _matches) _ItemCard(item: m, onChanged: _load),
                  ],
                ]),
    );
  }
}
