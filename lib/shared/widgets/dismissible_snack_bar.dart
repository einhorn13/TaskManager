import 'package:flutter/material.dart';

/// A short-lived notification that can also be dismissed by clicking anywhere
/// on its message. Actions keep their normal behavior.
SnackBar dismissibleSnackBar(
  BuildContext context, {
  required Widget content,
  Duration duration = const Duration(seconds: 4),
  SnackBarAction? action,
}) {
  final messenger = ScaffoldMessenger.of(context);
  return SnackBar(
    duration: duration,
    showCloseIcon: true,
    content: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: messenger.hideCurrentSnackBar,
      child: content,
    ),
    action: action,
  );
}
