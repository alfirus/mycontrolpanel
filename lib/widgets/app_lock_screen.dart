import 'package:flutter/material.dart';
import '../services/app_lock.dart';
import '../theme/app_theme.dart';

/// Full-screen lock overlay shown when [AppLock.locked] is true.
/// Rebuilds off the [AppLock] notifier; the Unlock button delegates to
/// [AppLock.unlock] (biometrics with device-PIN fallback).
class AppLockScreen extends StatelessWidget {
  const AppLockScreen({super.key, required this.lock});

  final AppLock lock;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: lock,
      builder: (context, _) => Scaffold(
        backgroundColor: AppColors.pitchBlack,
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: AppColors.surface2,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: const Icon(
                      Icons.lock_outline,
                      size: 32,
                      color: AppColors.accentCyan,
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'Locked',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    lock.message ??
                        'Authenticate with biometrics or your device PIN to continue.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textMuted,
                    ),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: lock.busy ? null : () => lock.unlock(),
                      icon: lock.busy
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                              ),
                            )
                          : const Icon(Icons.fingerprint, size: 16),
                      label: Text(lock.busy ? 'Waiting…' : 'Unlock'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
