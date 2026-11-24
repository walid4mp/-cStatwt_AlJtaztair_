import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'config.dart';

class ApiException implements Exception {
  final int status;
  final String code;
  final String message;
  const ApiException(this.status, this.code, this.message);
  @override
  String toString() => message;
}

class UploadFile {
  final String field;
  final String path;
  const UploadFile(this.field, this.path);
}

/// Flutter's MultipartFile defaults to application/octet-stream, which is why uploads
/// used to be rejected. We always send a real content type.
MediaType mediaTypeFor(String path) {
  final p = path.toLowerCase();
  if (p.endsWith('.jpg') || p.endsWith('.jpeg')) return MediaType('image', 'jpeg');
  if (p.endsWith('.png')) return MediaType('image', 'png');
  if (p.endsWith('.webp')) return MediaType('image', 'webp');
  if (p.endsWith('.gif')) return MediaType('image', 'gif');
  if (p.endsWith('.heic') || p.endsWith('.heif')) return MediaType('image', 'heic');
  if (p.endsWith('.mp4') || p.endsWith('.m4v')) return MediaType('video', 'mp4');
  if (p.endsWith('.mov')) return MediaType('video', 'quicktime');
  if (p.endsWith('.3gp')) return MediaType('video', '3gpp');
  if (p.endsWith('.webm')) return MediaType('video', 'webm');
  if (p.endsWith('.pdf')) return MediaType('application', 'pdf');
  return MediaType('application', 'octet-stream');
}

class Api {
  Api._();
  static final Api instance = Api._();

  String? token;

  /// Called when the server says the session is no longer valid (401 / banned).
  void Function(String reason)? onAuthLost;

  static String get base => AppConfig.apiBase;

  /// Resolve a media URL that may be relative ("/media/abc.jpg").
  static String url(String? path) {
    if (path == null || path.isEmpty) return '';
    if (path.startsWith('http://') || path.startsWith('https://')) return path;
    return '$base${path.startsWith('/') ? '' : '/'}$path';
  }

  Future<void> loadToken() async {
    final p = await SharedPreferences.getInstance();
    token = p.getString('token');
  }

  Future<void> saveToken(String t) async {
    token = t;
    final p = await SharedPreferences.getInstance();
    await p.setString('token', t);
  }

  Future<void> clearToken() async {
    token = null;
    final p = await SharedPreferences.getInstance();
    await p.remove('token');
  }

  Map<String, String> _headers({bool json = false}) => {
        'Accept': 'application/json',
        if (json) 'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      };

  Uri _uri(String path) => Uri.parse('$base$path');

  Future<dynamic> _handle(Future<http.Response> Function() call, {Duration timeout = const Duration(seconds: 45)}) async {
    http.Response r;
    try {
      r = await call().timeout(timeout);
    } on TimeoutException {
      throw const ApiException(0, 'TIMEOUT', 'Request timed out');
    } on SocketException {
      throw const ApiException(0, 'NETWORK', 'No connection');
    } on http.ClientException {
      throw const ApiException(0, 'NETWORK', 'No connection');
    } on HandshakeException {
      throw const ApiException(0, 'NETWORK', 'Secure connection failed');
    }
    return _decode(r);
  }

  Future<dynamic> _decode(http.Response r) async {
    dynamic data;
    if (r.bodyBytes.isNotEmpty) {
      try {
        data = jsonDecode(utf8.decode(r.bodyBytes));
      } catch (_) {
        data = null;
      }
    }
    if (r.statusCode >= 400) {
      final map = data is Map ? data : const {};
      final code = (map['code'] ?? 'HTTP_${r.statusCode}').toString();
      final msg = (map['error'] ?? 'Error ${r.statusCode}').toString();
      if (token != null && (r.statusCode == 401 || code == 'BANNED')) {
        await clearToken();
        onAuthLost?.call(code);
      }
      throw ApiException(r.statusCode, code, msg);
    }
    return data;
  }

  Future<dynamic> get(String path) => _handle(() => http.get(_uri(path), headers: _headers()));

  Future<dynamic> post(String path, [Map<String, dynamic>? body]) =>
      _handle(() => http.post(_uri(path), headers: _headers(json: true), body: jsonEncode(body ?? {})));

  Future<dynamic> put(String path, [Map<String, dynamic>? body]) =>
      _handle(() => http.put(_uri(path), headers: _headers(json: true), body: jsonEncode(body ?? {})));

  Future<dynamic> patch(String path, [Map<String, dynamic>? body]) =>
      _handle(() => http.patch(_uri(path), headers: _headers(json: true), body: jsonEncode(body ?? {})));

  Future<dynamic> delete(String path, [Map<String, dynamic>? body]) =>
      _handle(() => http.delete(_uri(path), headers: _headers(json: true), body: jsonEncode(body ?? {})));

  Future<dynamic> multipart(
    String method,
    String path, {
    Map<String, String> fields = const {},
    List<UploadFile> files = const [],
  }) {
    return _handle(() async {
      final req = http.MultipartRequest(method, _uri(path));
      req.headers.addAll(_headers());
      req.fields.addAll(fields);
      for (final f in files) {
        req.files.add(await http.MultipartFile.fromPath(f.field, f.path, contentType: mediaTypeFor(f.path)));
      }
      final streamed = await req.send();
      return http.Response.fromStream(streamed);
    }, timeout: const Duration(minutes: 4));
  }

  Future<List<Map<String, dynamic>>> getList(String path) async {
    final d = await get(path);
    if (d is! List) return <Map<String, dynamic>>[];
    return d.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }

  Future<Map<String, dynamic>> getMap(String path) async {
    final d = await get(path);
    return d is Map ? Map<String, dynamic>.from(d) : <String, dynamic>{};
  }
}

final api = Api.instance;
