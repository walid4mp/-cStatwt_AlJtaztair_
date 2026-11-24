import 'package:flutter/material.dart';

const kGreen = Color(0xFF087F3E);
const kDeepGreen = Color(0xFF064E2A);
const kRed = Color(0xFFD71920);
const kInk = Color(0xFF10251A);

class AppConfig {
  static const String _api = String.fromEnvironment('API_URL');
  static const String productionBase = 'https://cstatwt-aljtaztair.onrender.com';
  static const String appVersion = '2.0.0';
  static const String tileStreet = String.fromEnvironment(
    'MAP_TILE_URL',
    defaultValue: 'https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}.png',
  );
  static const String tileDark = 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}.png';
  static const String tileSatellite =
      'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}';
  static const String tileTerrain = 'https://{s}.tile.opentopomap.org/{z}/{x}/{y}.png';

  static String get apiBase {
    final v = _api.trim();
    if (v.isEmpty) return productionBase;
    return v.replaceFirst(RegExp(r'/+$'), '');
  }
}
