// Pins FoodItem's recipeName round-trip. AI-generated meals stamp a human
// recipe name on every ingredient FoodItem so the Meal-tab card can title the
// meal; it must survive toMap/fromMap and default to '' for legacy docs.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onefit/models/food_item.dart';

FoodItem sample({String recipeName = ''}) => FoodItem(
  id: 'id1',
  userId: 'u1',
  name: 'Rice Flour',
  barcode: 'ai_generated',
  servingSize: 74,
  servingSizeUnit: 'g',
  calories: 271,
  protein: 6,
  carbs: 58,
  fat: 1,
  loggedAt: DateTime(2026, 8, 20),
  mealType: 'breakfast',
  recipeName: recipeName,
);

void main() {
  test('recipeName survives toMap/fromMap round-trip', () {
    final item = sample(recipeName: 'Chicken Rice Flour Cakes');
    final restored = FoodItem.fromMap(item.toMap(), item.id);
    expect(restored.recipeName, 'Chicken Rice Flour Cakes');
  });

  test('recipeName defaults to empty for legacy docs without the field', () {
    final map = sample().toMap()..remove('recipeName');
    final restored = FoodItem.fromMap(map, 'id1');
    expect(restored.recipeName, '');
  });

  test('copyWith preserves recipeName when not overridden', () {
    final item = sample(recipeName: 'Papaya Bowl');
    expect(item.copyWith(quantity: 2).recipeName, 'Papaya Bowl');
    expect(item.copyWith(recipeName: 'New Name').recipeName, 'New Name');
  });

  test('toMap writes recipeName key', () {
    expect(sample(recipeName: 'X').toMap()['recipeName'], 'X');
    // Timestamp is written for loggedAt (sanity that the map is Firestore-shaped)
    expect(sample().toMap()['loggedAt'], isA<Timestamp>());
  });
}
