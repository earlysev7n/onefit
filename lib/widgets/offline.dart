import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../providers/connectivity_provider.dart';
import '../theme/app_colors.dart';

/// Whether the app is currently offline (real connection loss or the
/// Developer-Mode Force-Offline toggle). Read this to gate network-only
/// features — logging, plan view/edit and everything Firestore-backed keeps
/// working from cache and must **not** be gated.
bool isOffline(BuildContext context) =>
    context.read<ConnectivityProvider>().isOffline;

/// Friendly "needs internet" snackbar for a blocked network-only action.
void showOfflineSnack(BuildContext context, [String? feature]) {
  final label = feature == null ? 'This' : feature;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      backgroundColor: const Color(0xFF1A1A1A),
      behavior: SnackBarBehavior.floating,
      content: Row(
        children: [
          const Icon(Icons.cloud_off_rounded, color: AppColors.amber, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              "$label needs an internet connection.",
              style: GoogleFonts.inter(color: Colors.white, fontSize: 13),
            ),
          ),
        ],
      ),
    ),
  );
}

/// Empty-state shown in place of network results (search, generation) while
/// offline. Reuses the app's muted-text style.
class OfflineNotice extends StatelessWidget {
  final String message;
  const OfflineNotice({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_rounded,
                color: AppColors.amber, size: 40),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                color: const Color(0xFF888888),
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
