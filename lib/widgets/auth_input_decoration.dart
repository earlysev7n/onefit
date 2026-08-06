import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

/// Shared input styling for the auth screens.
///
/// Fixes the previous dark-on-dark fields (which had no visible border until
/// tapped) by giving every field a subtle rest border, a green focus ring, and
/// red error borders — reusing the app's [AppColors] tokens so it tracks the
/// active theme.
InputDecoration authInputDecoration(
  BuildContext context, {
  required String label,
  String? hint,
  Widget? suffixIcon,
}) {
  final c = context.colors;

  OutlineInputBorder border(Color color, {double width = 1}) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: color, width: width),
      );

  return InputDecoration(
    labelText: label,
    hintText: hint,
    filled: true,
    fillColor: c.inputFill,
    suffixIcon: suffixIcon,
    labelStyle: TextStyle(color: c.muted),
    hintStyle: TextStyle(color: c.muted),
    enabledBorder: border(c.border),
    focusedBorder: border(AppColors.primary, width: 1.5),
    errorBorder: border(AppColors.overTarget),
    focusedErrorBorder: border(AppColors.overTarget, width: 1.5),
  );
}
