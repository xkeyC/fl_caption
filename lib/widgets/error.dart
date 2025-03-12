import 'package:fl_caption/common/whisper/provider.dart';
import 'package:flutter/material.dart';

class HomeErrorWidget extends StatelessWidget {
  final DartWhisperClientError? errorType;

  final dynamic errorInfo;

  const HomeErrorWidget({super.key, this.errorType, this.errorInfo});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (errorType == DartWhisperClientError.modelNotFound) ...[
          Text("未找到模型文件，点击右侧设置图标检查设置", style: TextStyle(fontSize: 18)),
        ],
        if (errorInfo != null)
          Text(
            "Error: ${errorInfo.toString()}",
            style: TextStyle(color: Colors.red, fontSize: 18),
          ),
      ],
    );
  }
}
