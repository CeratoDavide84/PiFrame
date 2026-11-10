import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import '../daemon/daemon_providers.dart';

final taskbarWorkingSessionsProvider = StateProvider<Set<String>>(
  (ref) => <String>{},
);
final taskbarAttentionSessionsProvider = StateProvider<Set<String>>(
  (ref) => <String>{},
);
final taskbarErrorSessionsProvider = StateProvider<Set<String>>(
  (ref) => <String>{},
);
final taskbarPendingQuestionsProvider =
    StateProvider<List<Map<String, dynamic>>>((ref) => const []);

class TaskbarStatusReporter extends ConsumerStatefulWidget {
  const TaskbarStatusReporter({super.key});
  @override
  ConsumerState<TaskbarStatusReporter> createState() =>
      _TaskbarStatusReporterState();
}

class _TaskbarStatusReporterState extends ConsumerState<TaskbarStatusReporter> {
  static const _channel = MethodChannel('dev.piframe/taskbar');
  bool _handlerInstalled = false;

  Future<dynamic> _handleNativeCall(MethodCall call) async {
    final args = call.arguments is Map
        ? Map<String, dynamic>.from(call.arguments as Map)
        : <String, dynamic>{};
    final sessionId = args['sessionId']?.toString() ?? '';
    if (call.method == 'openQuestion') {
      if (sessionId.isNotEmpty) {
        ref.read(activeSessionIdProvider.notifier).state = sessionId;
      }
      await windowManager.show();
      await windowManager.focus();
      return true;
    }
    if (call.method == 'answerQuestion') {
      final client = ref.read(pcpClientProvider);
      if (client == null || sessionId.isEmpty) return false;
      final requestId = args['requestId']?.toString() ?? '';
      final claim = await client.claimUiRequest(sessionId, requestId);
      if ((claim['data'] as Map?)?['claimed'] == false) return false;
      await client.respondUiRequest(
        sessionId,
        requestId,
        value: args['value'],
        confirmed: args['confirmed'] as bool?,
        cancelled: args['cancelled'] as bool?,
      );
      return true;
    }
    return null;
  }

  void _send() {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows) {
      final questions = ref.read(taskbarPendingQuestionsProvider);
      if (!_handlerInstalled) {
        _handlerInstalled = true;
        _channel.setMethodCallHandler(_handleNativeCall);
      }
      _channel
          .invokeMethod<void>('setStatus', {
            'working': ref.read(taskbarWorkingSessionsProvider).isNotEmpty,
            'notifications': questions.length,
            'errors': ref.read(taskbarErrorSessionsProvider).length,
            'questions': questions,
          })
          .catchError((_) {});
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _send();
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(taskbarWorkingSessionsProvider, (_, __) => _send());
    ref.listen(taskbarAttentionSessionsProvider, (_, __) => _send());
    ref.listen(taskbarErrorSessionsProvider, (_, __) => _send());
    ref.listen(taskbarPendingQuestionsProvider, (_, __) => _send());
    return const SizedBox.shrink();
  }
}
