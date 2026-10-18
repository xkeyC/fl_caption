import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'windows.dart';

/// The caption status as the settings window sees it: pushed by the main
/// window (which runs the captions) whenever it changes.
class RemoteStatus {
  const RemoteStatus({
    this.status = 'idle',
    this.message = '',
    this.provider = '',
    this.device = '',
    this.lastError = '',
    this.lines = 0,
    this.pending = false,
  });

  /// `idle`, `loading`, `running` or `failed`.
  final String status;
  final String message;
  final String provider;
  final String device;
  final String lastError;

  /// Final lines kept for the context export.
  final int lines;

  /// The running captions use other models than the ones now selected.
  final bool pending;

  bool get active => status == 'loading' || status == 'running';

  factory RemoteStatus.fromMap(Map<String, dynamic> m) => RemoteStatus(
    status: m['status'] as String? ?? 'idle',
    message: m['message'] as String? ?? '',
    provider: m['provider'] as String? ?? '',
    device: m['device'] as String? ?? '',
    lastError: m['lastError'] as String? ?? '',
    lines: m['lines'] as int? ?? 0,
    pending: m['pending'] as bool? ?? false,
  );
}

class RemoteStatusNotifier extends Notifier<RemoteStatus> {
  @override
  RemoteStatus build() => const RemoteStatus();

  void receive(Map<String, dynamic> map) => state = RemoteStatus.fromMap(map);

  Future<void> refresh() async {
    try {
      final map = await mainChannel.invokeMethod<Map>('caption_status');
      if (map != null) receive(Map<String, dynamic>.from(map));
    } catch (_) {}
  }

  /// Asks the main window to do `method` (start/stop captions, the context).
  Future<void> call(String method) async {
    try {
      await mainChannel.invokeMethod(method);
    } catch (_) {}
    await refresh();
  }
}

final remoteStatusProvider = NotifierProvider<RemoteStatusNotifier, RemoteStatus>(RemoteStatusNotifier.new);
