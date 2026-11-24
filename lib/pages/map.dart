import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/api.dart';
import '../core/config.dart';
import '../core/i18n.dart';
import '../core/models.dart';
import '../core/session.dart';
import '../core/wilayas.dart';
import '../widgets/common.dart';
import '../widgets/header.dart';
import 'reports.dart';

const LatLng kAlgeriaCenter = LatLng(28.0339, 1.6596);

// ------------------------------------------------------------------ helpers
TileLayer buildTileLayer(String style, bool dark) {
  String url;
  List<String> sub = const ['a', 'b', 'c', 'd'];
  int nativeZoom = 19;
  switch (style) {
    case 'satellite':
      url = AppConfig.tileSatellite;
      break;
    case 'terrain':
      url = AppConfig.tileTerrain;
      sub = const ['a', 'b', 'c'];
      nativeZoom = 17;
      break;
    default:
      url = dark ? AppConfig.tileDark : AppConfig.tileStreet;
  }
  return TileLayer(
    urlTemplate: url,
    subdomains: sub,
    userAgentPackageName: 'dz.sawtaljazair.app',
    maxNativeZoom: nativeZoom,
    maxZoom: 19,
  );
}

Widget buildAttribution(String style) {
  final text = style == 'satellite' ? 'Esri, Maxar, Earthstar Geographics' : (style == 'terrain' ? '© OpenStreetMap, SRTM | OpenTopoMap' : '© OpenStreetMap, © CARTO');
  return RichAttributionWidget(
    showFlutterMapAttribution: false,
    attributions: [
      TextSourceAttribution(text, onTap: () => launchUrl(Uri.parse('https://www.openstreetmap.org/copyright'), mode: LaunchMode.externalApplication)),
    ],
  );
}

Marker pinMarker(LatLng p, {Color color = kRed, double size = 46, VoidCallback? onTap}) {
  return Marker(
    point: p,
    width: size,
    height: size,
    alignment: Alignment.topCenter,
    child: GestureDetector(
      onTap: onTap,
      child: Icon(Icons.location_pin, color: color, size: size, shadows: const [Shadow(color: Colors.black38, blurRadius: 6)]),
    ),
  );
}

Future<void> openInMaps(double lat, double lon, {String? label}) async {
  final name = Uri.encodeComponent(label ?? '');
  try {
    if (await launchUrl(Uri.parse('geo:$lat,$lon?q=$lat,$lon($name)'), mode: LaunchMode.externalApplication)) return;
  } catch (_) {}
  try {
    await launchUrl(Uri.parse('https://www.google.com/maps/search/?api=1&query=$lat,$lon'), mode: LaunchMode.externalApplication);
  } catch (_) {}
}

/// Current device position with friendly messages. Returns null when unavailable.
Future<LatLng?> getMyLocation(BuildContext context) async {
  try {
    if (!await Geolocator.isLocationServiceEnabled()) {
      if (context.mounted) {
        toast(context, context.tr('enable_location'), error: true);
        Geolocator.openLocationSettings();
      }
      return null;
    }
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
    if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
      if (context.mounted) toast(context, context.tr('allow_location'), error: true);
      if (perm == LocationPermission.deniedForever) Geolocator.openAppSettings();
      return null;
    }
    final p = await Geolocator.getCurrentPosition().timeout(const Duration(seconds: 20));
    return LatLng(p.latitude, p.longitude);
  } catch (_) {
    if (context.mounted) toast(context, context.tr('location_failed'), error: true);
    return null;
  }
}

class PlaceResult {
  final String name;
  final LatLng point;
  const PlaceResult(this.name, this.point);
}

Future<List<PlaceResult>> searchPlaces(String q) async {
  final uri = Uri.https('nominatim.openstreetmap.org', '/search', {
    'format': 'jsonv2',
    'q': q,
    'countrycodes': 'dz',
    'limit': '6',
    'accept-language': currentLang,
  });
  final r = await http.get(uri, headers: {'User-Agent': 'SawtAljazair/${AppConfig.appVersion} (dz.sawtaljazair.app)'}).timeout(const Duration(seconds: 10));
  if (r.statusCode != 200) return [];
  final list = jsonDecode(utf8.decode(r.bodyBytes));
  if (list is! List) return [];
  final out = <PlaceResult>[];
  for (final e in list) {
    if (e is! Map) continue;
    final la = double.tryParse('${e['lat']}');
    final lo = double.tryParse('${e['lon']}');
    if (la == null || lo == null) continue;
    out.add(PlaceResult('${e['display_name'] ?? ''}', LatLng(la, lo)));
  }
  return out;
}

/// Best-effort town/city name for a point (OpenStreetMap Nominatim).
Future<String?> reverseCity(LatLng p) async {
  try {
    final uri = Uri.https('nominatim.openstreetmap.org', '/reverse', {
      'format': 'jsonv2',
      'lat': '${p.latitude}',
      'lon': '${p.longitude}',
      'zoom': '14',
      'accept-language': currentLang,
    });
    final r = await http.get(uri, headers: {'User-Agent': 'SawtAljazair/${AppConfig.appVersion} (dz.sawtaljazair.app)'}).timeout(const Duration(seconds: 8));
    if (r.statusCode != 200) return null;
    final d = jsonDecode(utf8.decode(r.bodyBytes));
    if (d is! Map || d['address'] is! Map) return null;
    final a = Map<String, dynamic>.from(d['address'] as Map);
    for (final k in ['city', 'town', 'village', 'municipality', 'suburb', 'county']) {
      if (a[k] != null && '${a[k]}'.isNotEmpty) return '${a[k]}';
    }
  } catch (_) {}
  return null;
}

// ------------------------------------------------------------------ read-only location sheet
Future<void> showLocationSheet(BuildContext context, {required double lat, required double lon, required String title, bool approximate = false}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) {
      final dark = Theme.of(ctx).brightness == Brightness.dark;
      final p = LatLng(lat, lon);
      return SizedBox(
        height: MediaQuery.of(ctx).size.height * 0.72,
        child: Column(children: [
          Padding(padding: const EdgeInsets.fromLTRB(20, 0, 20, 10), child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900))),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: FlutterMap(
                options: MapOptions(initialCenter: p, initialZoom: approximate ? 13 : 15, minZoom: 3, maxZoom: 19),
                children: [
                  buildTileLayer('street', dark),
                  if (approximate) CircleLayer(circles: [CircleMarker(point: p, radius: 600, useRadiusInMeter: true, color: kRed.withValues(alpha: 0.15), borderColor: kRed, borderStrokeWidth: 2)]),
                  MarkerLayer(markers: [pinMarker(p)]),
                  buildAttribution('street'),
                ],
              ),
            ),
          ),
          if (approximate) Padding(padding: const EdgeInsets.fromLTRB(20, 8, 20, 0), child: Text(ctx.tr('approx_location_note'), style: TextStyle(fontSize: 12, color: Theme.of(ctx).colorScheme.onSurfaceVariant))),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(width: double.infinity, child: FilledButton.icon(onPressed: () => openInMaps(lat, lon, label: title), icon: const Icon(Icons.directions_rounded), label: Text(ctx.tr('open_in_maps')))),
            ),
          ),
        ]),
      );
    },
  );
}

// ------------------------------------------------------------------ main map tab
class _Cluster {
  final List<Report> items = [];
  LatLng get center {
    double la = 0, lo = 0;
    for (final r in items) {
      la += r.lat!;
      lo += r.lon!;
    }
    return LatLng(la / items.length, lo / items.length);
  }
}

class MapPage extends StatefulWidget {
  const MapPage({super.key});
  @override
  State<MapPage> createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> {
  final MapController _mc = MapController();
  final TextEditingController _search = TextEditingController();
  final Debouncer _deb = Debouncer();
  List<Report> _all = [];
  bool _loading = true;
  Object? _error;
  bool _ready = false;
  int _zoom = 5;
  String _style = 'street';
  final Set<String> _types = {};
  Report? _selected;
  LatLng? _me;
  List<PlaceResult> _places = [];
  List<Wilaya> _wilayaHits = [];
  bool _searching = false;

  @override
  void initState() {
    super.initState();
    _restoreStyle();
    _load();
    contentRefresh.addListener(_load);
  }

  @override
  void dispose() {
    contentRefresh.removeListener(_load);
    _deb.dispose();
    _search.dispose();
    super.dispose();
  }

  Future<void> _restoreStyle() async {
    try {
      final p = await SharedPreferences.getInstance();
      final s = p.getString('map_style');
      if (s != null && mounted) setState(() => _style = s);
    } catch (_) {}
  }

  Future<void> _setStyle(String s) async {
    setState(() => _style = s);
    try {
      (await SharedPreferences.getInstance()).setString('map_style', s);
    } catch (_) {}
  }

  Future<void> _load() async {
    if (_all.isEmpty) setState(() { _loading = true; _error = null; });
    try {
      final rows = asMapList(await api.get('/reports/map?limit=800')).map(Report.fromJson).where((r) => r.hasLocation).toList();
      if (!mounted) return;
      setState(() { _all = rows; _loading = false; _error = null; });
    } catch (e) {
      if (mounted) setState(() { _error = e; _loading = false; });
    }
  }

  List<Report> get _visible => _types.isEmpty ? _all : _all.where((r) => _types.contains(r.type)).toList();

  List<_Cluster> _clusters() {
    final items = _visible;
    if (_zoom >= 15) {
      return items.map((r) => _Cluster()..items.add(r)).toList();
    }
    final cell = 78.75 / math.pow(2, _zoom);
    final map = <String, _Cluster>{};
    for (final r in items) {
      final key = '${((r.lon! + 180) / cell).floor()}_${((r.lat! + 90) / cell).floor()}';
      (map[key] ??= _Cluster()).items.add(r);
    }
    return map.values.toList();
  }

  double get _zoomNow => _ready ? _mc.camera.zoom : 5.0;

  void _moveTo(LatLng p, double zoom) {
    if (!_ready) return;
    _mc.move(p, zoom);
  }

  Future<void> _locate() async {
    final p = await getMyLocation(context);
    if (p == null || !mounted) return;
    setState(() => _me = p);
    _moveTo(p, 14);
  }

  void _onSearch(String q) {
    final t = q.trim();
    if (t.isEmpty) {
      setState(() { _places = []; _wilayaHits = []; _searching = false; });
      return;
    }
    final lq = t.toLowerCase();
    setState(() {
      _wilayaHits = kWilayas.where((w) => w.ar.contains(t) || w.fr.toLowerCase().contains(lq)).take(4).toList();
    });
    _deb.run(() async {
      if (t.length < 3) return;
      if (mounted) setState(() => _searching = true);
      try {
        final r = await searchPlaces(t);
        if (mounted) setState(() => _places = r);
      } catch (_) {
      } finally {
        if (mounted) setState(() => _searching = false);
      }
    });
  }

  void _pickResult(LatLng p, double zoom) {
    FocusScope.of(context).unfocus();
    setState(() { _places = []; _wilayaHits = []; });
    _moveTo(p, zoom);
  }

  void _stylePicker() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          for (final s in const ['street', 'satellite', 'terrain'])
            ListTile(
              leading: Icon(s == 'street' ? Icons.map_rounded : (s == 'satellite' ? Icons.satellite_alt_rounded : Icons.terrain_rounded), color: kGreen),
              title: Text(ctx.tr('map_$s')),
              trailing: _style == s ? const Icon(Icons.check_rounded, color: kGreen) : null,
              onTap: () {
                Navigator.pop(ctx);
                _setStyle(s);
              },
            ),
          const SizedBox(height: 8),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final cs = Theme.of(context).colorScheme;
    final clusters = _clusters();
    return Column(children: [
      TopHeader(title: context.tr('map_title'), subtitle: context.tr('map_sub', {'n': '${_visible.length}'})),
      Expanded(
        child: Stack(children: [
          FlutterMap(
            mapController: _mc,
            options: MapOptions(
              initialCenter: kAlgeriaCenter,
              initialZoom: 5,
              minZoom: 4,
              maxZoom: 19,
              interactionOptions: const InteractionOptions(flags: InteractiveFlag.all & ~InteractiveFlag.rotate),
              onMapReady: () => _ready = true,
              onTap: (tp, pt) => setState(() => _selected = null),
              onPositionChanged: (camera, hasGesture) {
                final z = camera.zoom.floor();
                if (z != _zoom) setState(() => _zoom = z);
              },
            ),
            children: [
              buildTileLayer(_style, dark),
              MarkerLayer(markers: [
                for (final c in clusters)
                  if (c.items.length == 1)
                    pinMarker(
                      LatLng(c.items.first.lat!, c.items.first.lon!),
                      color: typeColor(c.items.first.type),
                      size: _selected?.id == c.items.first.id ? 58 : 44,
                      onTap: () => setState(() => _selected = c.items.first),
                    )
                  else
                    Marker(
                      point: c.center,
                      width: 46,
                      height: 46,
                      child: GestureDetector(
                        onTap: () => _moveTo(c.center, math.min(_zoom + 2.0, 18.0)),
                        child: Container(
                          decoration: BoxDecoration(color: kGreen, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 3), boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 6)]),
                          alignment: Alignment.center,
                          child: Text('${c.items.length}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
                        ),
                      ),
                    ),
                if (_me != null)
                  Marker(
                    point: _me!,
                    width: 26,
                    height: 26,
                    child: Container(decoration: BoxDecoration(color: const Color(0xFF1E88E5), shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 3), boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 6)])),
                  ),
              ]),
              buildAttribution(_style),
            ],
          ),
          // search
          PositionedDirectional(
            top: 10,
            start: 12,
            end: 12,
            child: Column(children: [
              Material(
                elevation: 3,
                borderRadius: BorderRadius.circular(16),
                color: cs.surface,
                child: TextField(
                  controller: _search,
                  onChanged: _onSearch,
                  decoration: InputDecoration(
                    hintText: context.tr('search_place'),
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffixIcon: _search.text.isEmpty
                        ? null
                        : IconButton(icon: const Icon(Icons.close_rounded), onPressed: () { _search.clear(); _onSearch(''); }),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    filled: false,
                  ),
                ),
              ),
              if (_wilayaHits.isNotEmpty || _places.isNotEmpty || _searching)
                Container(
                  margin: const EdgeInsets.only(top: 6),
                  constraints: const BoxConstraints(maxHeight: 260),
                  decoration: BoxDecoration(color: cs.surface, borderRadius: BorderRadius.circular(16), boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 8)]),
                  child: ListView(shrinkWrap: true, padding: EdgeInsets.zero, children: [
                    for (final w in _wilayaHits)
                      ListTile(dense: true, leading: const Icon(Icons.location_city_rounded, color: kGreen), title: Text(w.label(context.lang)), onTap: () => _pickResult(w.point, 9)),
                    for (final r in _places)
                      ListTile(dense: true, leading: const Icon(Icons.place_outlined), title: Text(r.name, maxLines: 2, overflow: TextOverflow.ellipsis), onTap: () => _pickResult(r.point, 15)),
                    if (_searching) const Padding(padding: EdgeInsets.all(12), child: Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)))),
                  ]),
                ),
              const SizedBox(height: 8),
              SizedBox(
                height: 38,
                child: ListView(scrollDirection: Axis.horizontal, children: [
                  for (final t in kReportTypes)
                    Padding(
                      padding: const EdgeInsetsDirectional.only(end: 6),
                      child: FilterChip(
                        showCheckmark: false,
                        avatar: Icon(typeIcon(t), size: 16, color: _types.contains(t) ? Colors.white : typeColor(t)),
                        label: Text(reportTypeLabel(context, t)),
                        labelStyle: TextStyle(color: _types.contains(t) ? Colors.white : null, fontWeight: FontWeight.w700, fontSize: 12.5),
                        selectedColor: typeColor(t),
                        backgroundColor: cs.surface,
                        selected: _types.contains(t),
                        onSelected: (v) => setState(() { v ? _types.add(t) : _types.remove(t); _selected = null; }),
                      ),
                    ),
                ]),
              ),
            ]),
          ),
          // controls
          PositionedDirectional(
            end: 12,
            bottom: _selected == null ? 24 : 190,
            child: Column(children: [
              _RoundBtn(icon: Icons.layers_rounded, tooltip: context.tr('map_layers'), onTap: _stylePicker),
              const SizedBox(height: 8),
              _RoundBtn(icon: Icons.add_rounded, tooltip: 'zoom in', onTap: () => _moveTo(_ready ? _mc.camera.center : kAlgeriaCenter, math.min(_zoomNow + 1.0, 19.0))),
              const SizedBox(height: 8),
              _RoundBtn(icon: Icons.remove_rounded, tooltip: 'zoom out', onTap: () => _moveTo(_ready ? _mc.camera.center : kAlgeriaCenter, math.max(_zoomNow - 1.0, 4.0))),
              const SizedBox(height: 8),
              _RoundBtn(icon: Icons.my_location_rounded, tooltip: context.tr('my_location'), onTap: _locate, color: kGreen),
            ]),
          ),
          PositionedDirectional(
            start: 12,
            bottom: _selected == null ? 24 : 190,
            child: _RoundBtn(icon: Icons.zoom_out_map_rounded, tooltip: context.tr('whole_country'), onTap: () => _moveTo(kAlgeriaCenter, 5)),
          ),
          if (_loading) const Center(child: CircularProgressIndicator()),
          if (_error != null && _all.isEmpty)
            Center(child: Card(child: Padding(padding: const EdgeInsets.all(8), child: SizedBox(width: 280, child: ErrorState(error: _error!, onRetry: _load))))),
          if (_selected != null)
            PositionedDirectional(
              start: 12,
              end: 12,
              bottom: 16,
              child: _SelectedCard(report: _selected!, onClose: () => setState(() => _selected = null)),
            ),
        ]),
      ),
    ]);
  }
}

class _RoundBtn extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final Color? color;
  const _RoundBtn({required this.icon, required this.tooltip, required this.onTap, this.color});
  @override
  Widget build(BuildContext context) => Material(
        elevation: 3,
        shape: const CircleBorder(),
        color: Theme.of(context).colorScheme.surface,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Tooltip(message: tooltip, child: SizedBox(width: 44, height: 44, child: Icon(icon, color: color))),
        ),
      );
}

class _SelectedCard extends StatelessWidget {
  final Report report;
  final VoidCallback onClose;
  const _SelectedCard({required this.report, required this.onClose});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      elevation: 6,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ReportDetailsPage(report: report))),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(color: typeColor(report.type).withValues(alpha: 0.14), borderRadius: BorderRadius.circular(16)),
              child: Icon(typeIcon(report.type), color: typeColor(report.type), size: 30),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text(report.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
                const SizedBox(height: 4),
                Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  StatusChip(report.status),
                  Text('${wilayaDisplay(report.wilaya, context.lang)} • ${timeAgo(context, report.createdAt)}', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                ]),
              ]),
            ),
            Column(children: [
              IconButton(visualDensity: VisualDensity.compact, onPressed: onClose, icon: const Icon(Icons.close_rounded, size: 20)),
              const Icon(Icons.chevron_right_rounded),
            ]),
          ]),
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------ picker used when creating a report
class PickedLocation {
  final LatLng point;
  final String? city;
  final Wilaya wilaya;
  const PickedLocation(this.point, this.city, this.wilaya);
}

class LocationPickerPage extends StatefulWidget {
  final LatLng? initial;
  const LocationPickerPage({super.key, this.initial});
  @override
  State<LocationPickerPage> createState() => _LocationPickerPageState();
}

class _LocationPickerPageState extends State<LocationPickerPage> {
  final MapController _mc = MapController();
  final TextEditingController _search = TextEditingController();
  final Debouncer _deb = Debouncer();
  late LatLng _selected = widget.initial ?? kAlgeriaCenter;
  bool _ready = false;
  bool _confirming = false;
  List<PlaceResult> _places = [];
  String _style = 'street';

  @override
  void dispose() {
    _deb.dispose();
    _search.dispose();
    super.dispose();
  }

  void _query(String q) {
    final t = q.trim();
    if (t.length < 3) {
      setState(() => _places = []);
      return;
    }
    _deb.run(() async {
      try {
        final r = await searchPlaces(t);
        if (mounted) setState(() => _places = r);
      } catch (_) {}
    });
  }

  Future<void> _useMine() async {
    final p = await getMyLocation(context);
    if (p == null || !mounted) return;
    setState(() => _selected = p);
    if (_ready) _mc.move(p, 16);
  }

  Future<void> _confirm() async {
    setState(() => _confirming = true);
    final city = await reverseCity(_selected);
    if (!mounted) return;
    Navigator.pop(context, PickedLocation(_selected, city, nearestWilaya(_selected)));
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('pick_location')),
        actions: [
          IconButton(
            tooltip: context.tr('map_layers'),
            icon: Icon(_style == 'street' ? Icons.satellite_alt_rounded : Icons.map_rounded),
            onPressed: () => setState(() => _style = _style == 'street' ? 'satellite' : 'street'),
          ),
        ],
      ),
      body: Stack(children: [
        FlutterMap(
          mapController: _mc,
          options: MapOptions(
            initialCenter: _selected,
            initialZoom: widget.initial == null ? 5 : 16,
            minZoom: 4,
            maxZoom: 19,
            interactionOptions: const InteractionOptions(flags: InteractiveFlag.all & ~InteractiveFlag.rotate),
            onMapReady: () => _ready = true,
            onTap: (tp, pt) => setState(() => _selected = pt),
          ),
          children: [
            buildTileLayer(_style, dark),
            MarkerLayer(markers: [pinMarker(_selected, size: 56)]),
            buildAttribution(_style),
          ],
        ),
        PositionedDirectional(
          top: 10,
          start: 12,
          end: 12,
          child: Column(children: [
            Material(
              elevation: 3,
              borderRadius: BorderRadius.circular(16),
              color: cs.surface,
              child: TextField(
                controller: _search,
                onChanged: _query,
                decoration: InputDecoration(hintText: context.tr('search_place'), prefixIcon: const Icon(Icons.search_rounded), border: InputBorder.none, enabledBorder: InputBorder.none, focusedBorder: InputBorder.none, filled: false),
              ),
            ),
            if (_places.isNotEmpty)
              Container(
                margin: const EdgeInsets.only(top: 6),
                constraints: const BoxConstraints(maxHeight: 240),
                decoration: BoxDecoration(color: cs.surface, borderRadius: BorderRadius.circular(16), boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 8)]),
                child: ListView(shrinkWrap: true, padding: EdgeInsets.zero, children: [
                  for (final r in _places)
                    ListTile(
                      dense: true,
                      leading: const Icon(Icons.place_outlined),
                      title: Text(r.name, maxLines: 2, overflow: TextOverflow.ellipsis),
                      onTap: () {
                        FocusScope.of(context).unfocus();
                        setState(() { _selected = r.point; _places = []; });
                        if (_ready) _mc.move(r.point, 16);
                      },
                    ),
                ]),
              ),
            const SizedBox(height: 8),
            Card(child: Padding(padding: const EdgeInsets.all(10), child: Row(children: [const Icon(Icons.touch_app_rounded, color: kGreen), const SizedBox(width: 8), Expanded(child: Text(context.tr('pick_location_hint'), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)))]))),
          ]),
        ),
        PositionedDirectional(end: 12, bottom: 96, child: _RoundBtn(icon: Icons.my_location_rounded, tooltip: context.tr('my_location'), color: kGreen, onTap: _useMine)),
        PositionedDirectional(
          start: 16,
          end: 16,
          bottom: 20,
          child: SafeArea(child: BusyButton(busy: _confirming, onPressed: _confirm, label: context.tr('confirm_location'), icon: Icons.check_rounded)),
        ),
      ]),
    );
  }
}
