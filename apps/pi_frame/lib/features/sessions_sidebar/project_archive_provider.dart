import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class ProjectArchiveState {
  final Map<String, String> names;
  final Set<String> projects;
  final Set<String> sessions;
  const ProjectArchiveState({this.names = const {}, this.projects = const {}, this.sessions = const {}});
}

class ProjectArchiveNotifier extends StateNotifier<ProjectArchiveState> {
  final File? storageFile;
  ProjectArchiveNotifier({this.storageFile}) : super(const ProjectArchiveState()) { _load(); }

  File? get _file {
    if (storageFile != null) return storageFile;
    if (kIsWeb) return null;
    final home = Platform.isWindows ? Platform.environment['USERPROFILE'] : Platform.environment['HOME'];
    if (home == null || home.isEmpty) return null;
    return File('$home/.piframe/project_archive.json');
  }

  void _load() {
    try {
      final file = _file;
      if (file == null || !file.existsSync()) return;
      final data = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      state = ProjectArchiveState(
        names: Map<String, String>.from(data['names'] as Map? ?? {}),
        projects: Set<String>.from(data['projects'] as List? ?? []),
        sessions: Set<String>.from(data['sessions'] as List? ?? []),
      );
    } catch (error) { debugPrint('Cannot load project archive: $error'); }
  }

  void _save(ProjectArchiveState next) {
    final file = _file;
    if (file != null) {
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(jsonEncode({'names': next.names, 'projects': next.projects.toList(), 'sessions': next.sessions.toList()}));
    }
    state = next;
  }

  void renameProject(String path, String name) {
    _save(ProjectArchiveState(names: {...state.names, path: name}, projects: state.projects, sessions: state.sessions));
  }

  void toggleProject(String path) {
    final projects = {...state.projects};
    if (!projects.remove(path)) projects.add(path);
    _save(ProjectArchiveState(names: state.names, projects: projects, sessions: state.sessions));
  }

  void toggleSession(String id) {
    final sessions = {...state.sessions};
    if (!sessions.remove(id)) sessions.add(id);
    _save(ProjectArchiveState(names: state.names, projects: state.projects, sessions: sessions));
  }
}

final projectArchiveProvider = StateNotifierProvider<ProjectArchiveNotifier, ProjectArchiveState>((ref) => ProjectArchiveNotifier());
