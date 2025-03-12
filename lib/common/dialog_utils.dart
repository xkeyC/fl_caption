import 'package:fluent_ui/fluent_ui.dart';

Future showToast(
  BuildContext context,
  String msg, {
  BoxConstraints? constraints,
  String? title,
}) async {
  return showBaseDialog(
    context,
    title: title ?? "提示",
    content: Text(msg),
    actions: [
      FilledButton(
        child: Padding(
          padding: const EdgeInsets.only(top: 2, bottom: 2, left: 8, right: 8),
          child: Text("我知道了"),
        ),
        onPressed: () => Navigator.pop(context),
      ),
    ],
    constraints: constraints,
  );
}

Future<bool> showConfirmDialogs(
  BuildContext context,
  String title,
  Widget content, {
  String confirm = "",
  String cancel = "",
  BoxConstraints? constraints,
}) async {
  if (confirm.isEmpty) confirm = "确定";
  if (cancel.isEmpty) cancel = "取消";

  final r = await showBaseDialog(
    context,
    title: title,
    content: content,
    actions: [
      if (confirm.isNotEmpty)
        FilledButton(
          child: Padding(
            padding: const EdgeInsets.only(
              top: 2,
              bottom: 2,
              left: 8,
              right: 8,
            ),
            child: Text(confirm),
          ),
          onPressed: () => Navigator.pop(context, true),
        ),
      if (cancel.isNotEmpty)
        Button(
          child: Padding(
            padding: const EdgeInsets.only(
              top: 2,
              bottom: 2,
              left: 8,
              right: 8,
            ),
            child: Text(cancel),
          ),
          onPressed: () => Navigator.pop(context, false),
        ),
    ],
    constraints: constraints,
  );
  return r == true;
}

Future showBaseDialog(
  BuildContext context, {
  required String title,
  required Widget content,
  List<Widget>? actions,
  BoxConstraints? constraints,
}) async {
  return await showDialog(
    context: context,
    builder:
        (context) => ContentDialog(
          title: Text(title),
          content: content,
          constraints:
              constraints ??
              const BoxConstraints(maxWidth: 512, maxHeight: 756.0),
          actions: actions,
        ),
  );
}
