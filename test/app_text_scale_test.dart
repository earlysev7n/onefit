// Pins the app-wide type scale. AppTextScale.resolve() is the single place the
// app's font sizes are lifted, and the only guard stopping the bump from
// stacking on top of an OS accessibility setting — every screen was verified on
// device at maxTotal, so a total above it is a size nothing has rendered at.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onefit/theme/app_text_scale.dart';

/// Effective multiplier a scaler applies, probed at body size.
double _factor(TextScaler s) => s.scale(14.0) / 14.0;

void main() {
  group('constants', () {
    test('bump lifts the authored sizes without inflating them', () {
      // Deliberately modest — the app was ~1-2pt under the platform norm, not
      // half a scale step. Above ~1.15 the Home calorie card starts clipping
      // "Remaining", so growing this is a layout change, not a text change.
      expect(AppTextScale.bump, greaterThan(1.0));
      expect(AppTextScale.bump, lessThanOrEqualTo(1.15));
    });

    test('the ceiling is at least the bump', () {
      // Otherwise a user at OS scale 1.0 would be clamped below the default.
      expect(AppTextScale.maxTotal, greaterThanOrEqualTo(AppTextScale.bump));
    });
  });

  group('resolve', () {
    test('applies the bump when the OS is not scaling', () {
      final f = _factor(AppTextScale.resolve(TextScaler.noScaling));
      expect(f, closeTo(AppTextScale.bump, 1e-9));
    });

    test('the most common body size lands on the platform baseline', () {
      // 13px is the app's dominant body size; the point of the bump is that it
      // renders at Material's 14px baseline.
      final s = AppTextScale.resolve(TextScaler.noScaling);
      expect(s.scale(13.0), closeTo(14.0, 0.15));
    });

    test('composes with OS scaling below the ceiling', () {
      final f = _factor(AppTextScale.resolve(const TextScaler.linear(1.1)));
      expect(f, closeTo(1.1 * AppTextScale.bump, 1e-9));
    });

    test('clamps the total so the bump cannot stack past the ceiling', () {
      // A user at max OS scaling must land exactly on maxTotal — not on
      // maxTotal * bump, which is a size nothing was checked at.
      for (final os in [1.3, 1.6, 2.0, 3.0]) {
        final f = _factor(AppTextScale.resolve(TextScaler.linear(os)));
        expect(
          f,
          closeTo(AppTextScale.maxTotal, 1e-9),
          reason: 'OS scale $os should clamp to maxTotal',
        );
      }
    });

    test('never scales below 1.0, so text cannot shrink under the design', () {
      for (final os in [0.5, 0.8, 1.0]) {
        final f = _factor(AppTextScale.resolve(TextScaler.linear(os)));
        expect(f, greaterThanOrEqualTo(1.0), reason: 'OS scale $os');
      }
    });

    test('is monotonic in the OS factor', () {
      double prev = 0;
      for (final os in [0.8, 1.0, 1.1, 1.2, 1.3, 2.0]) {
        final f = _factor(AppTextScale.resolve(TextScaler.linear(os)));
        expect(f, greaterThanOrEqualTo(prev));
        prev = f;
      }
    });
  });
}
