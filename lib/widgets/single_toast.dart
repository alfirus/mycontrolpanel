// SPDX-License-Identifier: MIT
import 'package:flutter/material.dart';

/// Single-toast rail: every result toast clears the current one first,
/// so rapid approve-first actions never stack SnackBars.
void showSingleToast(
  BuildContext context,
  String message, {
  required Color foreground,
  Color? background,
  Duration duration = const Duration(seconds: 3),
}) {
  final messenger = ScaffoldMessenger.of(context);
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(
    SnackBar(
      backgroundColor:
          (background ?? foreground).withValues(alpha: 0.14),
      content: Text(
        message,
        style: TextStyle(fontSize: 12, color: foreground),
      ),
      duration: duration,
    ),
  );
}
