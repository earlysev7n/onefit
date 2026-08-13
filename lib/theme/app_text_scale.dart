import 'package:flutter/material.dart';

/// App-wide type scale.
///
/// OneFit's type was authored with a 12–13px body floor — about 1–2pt under the
/// platform norm — so every inline `fontSize:` is lifted here rather than at the
/// 300-odd call sites that declare one. Flutter already multiplies every `Text`
/// by [MediaQuery.textScaler], so scaling the whole app is a single value.
///
/// This is the one knob for "is the text the right size".
class AppTextScale {
  AppTextScale._();

  /// Baked-in bump over the authored design sizes. Puts the app's most common
  /// body size (13) on the 14px platform baseline.
  ///
  /// Verified on device: this is the largest value at which every label on Home
  /// still fits. At 1.15 the calorie card runs out of room and "Remaining"
  /// clips to "Remaini…". Going higher means widening that card's label column
  /// first — it is not just a bigger number here.
  static const double bump = 1.08;

  /// Hard ceiling on the *total* scale (OS accessibility scaling × [bump]).
  ///
  /// Identical to the plain 1.3 cap this replaces, so this class raises the
  /// *default* without widening the range the layouts have to survive, and
  /// [bump] can never stack on top of an accessibility setting to reach a size
  /// nothing has rendered at. Raising it is a layout change, not a text change.
  static const double maxTotal = 1.30;

  /// Composes the platform's text scaling with [bump] and clamps the result.
  ///
  /// The OS factor is probed at a reference body size rather than read from a
  /// factor getter, so this behaves the same on Android's non-linear scaling
  /// curve as it does on iOS.
  static TextScaler resolve(TextScaler osScaler) {
    const probe = 14.0;
    final osFactor = osScaler.scale(probe) / probe;
    return TextScaler.linear((osFactor * bump).clamp(1.0, maxTotal));
  }
}
