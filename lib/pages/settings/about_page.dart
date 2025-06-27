import 'package:fl_caption/common/utils/window_util.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class AboutPage extends HookConsumerWidget {
  const AboutPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Center(
      child: Column(
        children: [
          Row(children: [Text("FL Caption", style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold))]),
          SizedBox(height: 16),
          Text("xkeyC", style: TextStyle(fontSize: 16)),
          SizedBox(height: 32),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Button(
                onPressed: () {
                  MultiWindowWindowUtil.launchUrl("https://github.com/xkeyC/fl_caption");
                },
                child: Text("https://github.com/xkeyC/fl_caption", style: TextStyle(fontSize: 14, color: Colors.blue)),
              ),
              SizedBox(width: 24),
              Button(
                onPressed: () {
                  MultiWindowWindowUtil.launchUrl(
                    "https://qm.qq.com/cgi-bin/qm/qr?k=-E8jpcZGpqiOrKPrIuM5iuMrd8l4KRR9&jump_from=webapi&authKey=ogrmD+T7tLSiL9NvGzN+mPBvIb6He12JaN93iwBuGN59PXzwSLOpmE734Q2frUD",
                  );
                },
                child: Text("QQ Group: 1037016702", style: TextStyle(fontSize: 14)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
