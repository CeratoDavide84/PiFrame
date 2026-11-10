import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final sessionGoalProvider =
    StateNotifierProvider.family<SessionGoalNotifier, String?, String>(
      (ref, sessionId) => SessionGoalNotifier(sessionId),
    );

class SessionGoalNotifier extends StateNotifier<String?> {
  SessionGoalNotifier(this.sessionId) : super(null) {
    _loaded = _load();
  }
  final String sessionId;
  late final Future<void> _loaded;
  static Future<void> _writes = Future.value();
  static String _filePath() {
    final home =
        Platform.environment['USERPROFILE'] ??
        Platform.environment['HOME'] ??
        '.';
    final dir = Platform.isWindows
        ? (Platform.environment['APPDATA'] ?? '$home/.piframe')
        : '$home/.piframe';
    return '$dir/goals.json';
  }

  Future<void> _load() async {
    try {
      final file = File(_filePath());
      if (!await file.exists()) return;
      final data = jsonDecode(await file.readAsString());
      if (data is Map && data[sessionId] is String && mounted) {
        state = data[sessionId] as String;
      }
    } catch (error) {
      debugPrint('Could not load session goal: $error');
    }
  }

  Future<void> setGoal(String? goal) async {
    await _loaded;
    final cleaned = goal?.trim();
    state = cleaned == null || cleaned.isEmpty ? null : cleaned;
    final path = _filePath();
    _writes = _writes.catchError((_) {}).then((_) async {
      final file = File(path);
      await file.parent.create(recursive: true);
      Map<String, dynamic> values = {};
      if (await file.exists()) {
        try {
          values = Map<String, dynamic>.from(
            jsonDecode(await file.readAsString()) as Map,
          );
        } catch (_) {}
      }
      if (cleaned == null || cleaned.isEmpty) {
        values.remove(sessionId);
      } else {
        values[sessionId] = cleaned;
      }
      final temp = File('$path.tmp.${DateTime.now().microsecondsSinceEpoch}');
      await temp.writeAsString(jsonEncode(values), flush: true);
      if (await file.exists()) await file.delete();
      await temp.rename(path);
    });
    await _writes;
  }
}
