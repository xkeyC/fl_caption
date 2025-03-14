import 'dart:async';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../common/whisper/models.dart';
import 'model_download_provider.dart';

class ModelDownloadDialog extends ConsumerStatefulWidget {
  final WhisperModelData model;
  final String savePath;

  const ModelDownloadDialog({
    super.key,
    required this.model,
    required this.savePath,
  });

  @override
  ConsumerState<ModelDownloadDialog> createState() =>
      _ModelDownloadDialogState();
}

class _ModelDownloadDialogState extends ConsumerState<ModelDownloadDialog> {
  Timer? _timer;
  DateTime? _startTime;
  Duration _estimatedTimeLeft = Duration.zero;
  double _downloadSpeed = 0.0; // KB/s

  @override
  void initState() {
    super.initState();
    _startTime = DateTime.now();
    _startEstimationTimer();
    () async {
      final ok =
          await ref
              .read(
                modelDownloadStateProvider(
                  widget.model.name,
                  widget.savePath,
                ).notifier,
              )
              .startDownload();
      if (!context.mounted) return;
      if (!mounted) return;
      if (ok) Navigator.maybePop(context, ok);
    }();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startEstimationTimer() {
    double lastProgress = 0;

    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      final downloadState = ref.read(
        modelDownloadStateProvider(widget.model.name, widget.savePath),
      );

      if (downloadState.progress > 0 && downloadState.progress < 100) {
        final elapsedSeconds = DateTime.now().difference(_startTime!).inSeconds;
        if (elapsedSeconds > 0) {
          final progressPercent = downloadState.progress / 100;
          if (progressPercent > 0) {
            final totalSeconds = (elapsedSeconds / progressPercent).round();
            final remainingSeconds = totalSeconds - elapsedSeconds;

            // 计算下载速度 (假设总大小从model.size中解析)
            final progressDiff = downloadState.progress - lastProgress;
            final totalSizeInBytes = _parseSize(widget.model.sizeInt);
            final bytesPerSecond = (progressDiff / 100) * totalSizeInBytes;

            setState(() {
              _estimatedTimeLeft = Duration(
                seconds: remainingSeconds > 0 ? remainingSeconds : 0,
              );
              _downloadSpeed = bytesPerSecond / 1024; // 转换为 KB/s
              lastProgress = downloadState.progress;
            });
          }
        }
      }
    });
  }

  double _parseSize(int size) {
    return size * 1024.0;
  }

  String _formatDuration(Duration duration) {
    if (duration.inSeconds < 60) {
      return "${duration.inSeconds}秒";
    } else if (duration.inMinutes < 60) {
      return "${duration.inMinutes}分 ${duration.inSeconds % 60}秒";
    } else {
      return "${duration.inHours}时 ${duration.inMinutes % 60}分";
    }
  }

  String _formatSpeed(double kbps) {
    if (kbps > 1024) {
      return "${(kbps / 1024).toStringAsFixed(1)} MB/s";
    } else {
      return "${kbps.toStringAsFixed(1)} KB/s";
    }
  }

  @override
  Widget build(BuildContext context) {
    final downloadState = ref.watch(
      modelDownloadStateProvider(widget.model.name, widget.savePath),
    );

    return ContentDialog(
      title: Text(
        '正在下载 ${widget.model.name}',
        style: FluentTheme.of(context).typography.subtitle,
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('模型大小: ${widget.model.size}'),
          const SizedBox(height: 20),

          ProgressBar(
            value: downloadState.progress,
            backgroundColor: FluentTheme.of(context).inactiveColor,
          ),

          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('${downloadState.progress.toStringAsFixed(1)}%'),
              if (_downloadSpeed > 0 && downloadState.progress < 100)
                Text(_formatSpeed(_downloadSpeed)),
            ],
          ),

          const SizedBox(height: 10),
          if (_estimatedTimeLeft.inSeconds > 0 && downloadState.progress < 100)
            Text('预计剩余时间: ${_formatDuration(_estimatedTimeLeft)}'),

          const SizedBox(height: 20),
          if (downloadState.errorText != null)
            Text(
              '错误: ${downloadState.errorText}',
              style: TextStyle(color: Colors.red),
            )
          else
            const Text(
              '请勿关闭此窗口，直到下载完成。',
              style: TextStyle(fontStyle: FontStyle.italic),
            ),
        ],
      ),
      actions: [
        Button(
          onPressed: () {
            Navigator.of(context).pop();
            ref
                .read(
                  modelDownloadStateProvider(
                    widget.model.name,
                    widget.savePath,
                  ).notifier,
                )
                .cancelDownload();
          },
          child: const Text('取消'),
        ),
      ],
    );
  }
}
