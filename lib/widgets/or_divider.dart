import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_colors.dart';

/// "──── or ────" separator used between primary and social sign-in.
class OrDivider extends StatelessWidget {
  const OrDivider({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Row(
      children: [
        Expanded(child: Divider(color: c.border, thickness: 1)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            'or',
            style: GoogleFonts.inter(color: c.muted, fontSize: 13),
          ),
        ),
        Expanded(child: Divider(color: c.border, thickness: 1)),
      ],
    );
  }
}
