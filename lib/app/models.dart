import 'dart:async';

import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../src/rust/api/app.dart' as rs_app;
import '../src/rust/api/models.dart' as rs;
import 'settings.dart';

final runtimeInfoProvider = Provider<rs_app.RuntimeInfo>((ref) => throw UnimplementedError('overridden in main'));

/// Pushes the model locations to the engine whenever they change.
void configureModelStore(AppSettings s, AppPaths paths) {
  final imported = s.importedModels.entries
      .map((e) => rs_app.ModelPath(id: e.key, dir: e.value))
      .toList(growable: false);
  rs_app.configureModels(
    root: s.modelsDir.isEmpty ? paths.defaultModelsDir : s.modelsDir,
    imported: imported,
    hfEndpoint: s.hfEndpoint,
  );
}

class ModelsController extends AsyncNotifier<List<rs.ModelInfo>> {
  @override
  Future<List<rs.ModelInfo>> build() async {
    final s = ref.watch(settingsProvider.select((s) => (s.modelsDir, s.importedModels, s.hfEndpoint)));
    configureModelStore(ref.read(settingsProvider), ref.read(appPathsProvider));
    final _ = s;
    return rs.listModels();
  }

  Future<void> refresh() async {
    state = AsyncData(await rs.listModels());
  }
}

final modelsProvider = AsyncNotifierProvider<ModelsController, List<rs.ModelInfo>>(ModelsController.new);

class DownloadState {
  const DownloadState({required this.event, this.error});

  final rs.DownloadEvent event;
  final String? error;

  double get fraction => event.total > BigInt.zero ? event.downloaded.toInt() / event.total.toInt() : 0;
}

class DownloadsController extends Notifier<Map<String, DownloadState>> {
  final _subscriptions = <String, StreamSubscription<rs.DownloadEvent>>{};

  @override
  Map<String, DownloadState> build() {
    ref.onDispose(() {
      for (final s in _subscriptions.values) {
        s.cancel();
      }
    });
    return const {};
  }

  void start(String id) {
    if (_subscriptions.containsKey(id)) return;
    _subscriptions[id] = rs.downloadModel(id: id).listen((event) {
      if (event.done) {
        _subscriptions.remove(id)?.cancel();
        final next = {...state};
        if (event.error == null) {
          next.remove(id);
        } else {
          next[id] = DownloadState(event: event, error: event.error);
        }
        state = next;
        ref.read(modelsProvider.notifier).refresh();
      } else {
        state = {...state, id: DownloadState(event: event)};
      }
    });
    ref.read(modelsProvider.notifier).refresh();
  }

  Future<void> cancel(String id) async {
    await rs.cancelDownload(id: id);
  }

  void dismissError(String id) => state = {...state}..remove(id);
}

final downloadsProvider = NotifierProvider<DownloadsController, Map<String, DownloadState>>(DownloadsController.new);

/// GPU memory the chosen models would take together, in MB.
int estimateVram(List<rs.ModelInfo> models, AppSettings s, int cudaContextMb) {
  var total = 0;
  var gpu = false;
  for (final m in models) {
    if (m.id == s.asrModel && s.asrGpu && m.vramMb > BigInt.zero) {
      total += m.vramMb.toInt();
      gpu = true;
    }
    if (s.translationEnabled && s.translator == TranslatorKind.local && m.id == s.localTranslator && s.localGpu) {
      final extra = m.kvKbPerToken.toInt() * (s.contextTokens - m.defaultContext.toInt()) ~/ 1024;
      total += m.vramMb.toInt() + extra;
      gpu = true;
    }
  }
  return gpu ? total + cudaContextMb : 0;
}
