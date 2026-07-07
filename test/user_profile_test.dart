// Round-trip tests for UserProfile Firestore serialization.
// Run with `flutter test test/user_profile_test.dart`.
import 'package:flutter_test/flutter_test.dart';
import 'package:onefit/models/user_profile.dart';

UserProfile _base({DateTime? createdAt}) => UserProfile(
      uid: 'u1',
      name: 'Test',
      gender: 'Male',
      age: 30,
      weight: 80,
      height: 180,
      fitnessGoal: 'General Fitness',
      experienceLevel: 'Beginner',
      workoutLocation: 'Gym',
      equipment: const [],
      dietaryRestrictions: const [],
      createdAt: createdAt,
    );

void main() {
  group('UserProfile createdAt', () {
    test('survives toMap/fromMap round-trip', () {
      final created = DateTime(2026, 7, 7, 9, 30);
      final restored = UserProfile.fromMap(_base(createdAt: created).toMap());
      expect(restored.createdAt, created);
    });

    test('null createdAt round-trips as null (legacy profiles)', () {
      final restored = UserProfile.fromMap(_base().toMap());
      expect(restored.createdAt, isNull);
    });

    test('fromMap tolerates a document with no createdAt key', () {
      final map = _base(createdAt: DateTime(2026, 1, 1)).toMap()
        ..remove('createdAt');
      expect(UserProfile.fromMap(map).createdAt, isNull);
    });

    test('copyWith preserves createdAt when not overridden', () {
      final created = DateTime(2026, 7, 7);
      final edited = _base(createdAt: created).copyWith(name: 'Renamed');
      expect(edited.createdAt, created);
      expect(edited.name, 'Renamed');
    });
  });
}
