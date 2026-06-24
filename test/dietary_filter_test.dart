import 'package:flutter_test/flutter_test.dart';
import 'package:onefit/services/dietary_filter.dart';

void main() {
  group('DietaryFilter.violates', () {
    test('no restrictions hides nothing', () {
      expect(DietaryFilter.violates('Pork loin, raw', const []), isFalse);
      expect(DietaryFilter.violates('Cheddar cheese', const []), isFalse);
    });

    test('Halal hides pork/processed-pork/gelatin/alcohol, keeps chicken', () {
      const r = ['Halal'];
      expect(DietaryFilter.violates('Pork loin, raw', r), isTrue);
      expect(DietaryFilter.violates('Bacon, cooked', r), isTrue);
      expect(DietaryFilter.violates('Ham, sliced', r), isTrue);
      expect(DietaryFilter.violates('Gelatin dessert', r), isTrue);
      expect(DietaryFilter.violates('Red wine vinegar', r), isTrue);
      expect(DietaryFilter.violates('Chicken breast, grilled', r), isFalse);
      expect(DietaryFilter.violates('Beef, ground', r), isFalse);
    });

    test('Vegetarian hides all meat/seafood, keeps dairy and eggs', () {
      const r = ['Vegetarian'];
      expect(DietaryFilter.violates('Beef, ground', r), isTrue);
      expect(DietaryFilter.violates('Salmon, Atlantic', r), isTrue);
      expect(DietaryFilter.violates('Chicken breast', r), isTrue);
      expect(DietaryFilter.violates('Cheddar cheese', r), isFalse);
      expect(DietaryFilter.violates('Egg, whole, raw', r), isFalse);
    });

    test('Vegan hides meat, dairy, eggs and honey; keeps plant foods', () {
      const r = ['Vegan'];
      expect(DietaryFilter.violates('Cheddar cheese', r), isTrue);
      expect(DietaryFilter.violates('Egg, whole, raw', r), isTrue);
      expect(DietaryFilter.violates('Honey, raw', r), isTrue);
      expect(DietaryFilter.violates('Chicken breast', r), isTrue);
      expect(DietaryFilter.violates('Tofu, firm', r), isFalse);
      expect(DietaryFilter.violates('Black beans, cooked', r), isFalse);
    });

    test('Lactose-intolerant hides dairy, keeps milkfish and plant milk', () {
      const r = ['Lactose-intolerant'];
      expect(DietaryFilter.violates('Milk, whole', r), isTrue);
      expect(DietaryFilter.violates('Cheddar cheese', r), isTrue);
      expect(DietaryFilter.violates('Butter, salted', r), isTrue);
      expect(DietaryFilter.violates('Milkfish, raw', r), isFalse);
      expect(DietaryFilter.violates('Almond milk, unsweetened', r), isFalse);
    });

    test('Nut-free hides tree nuts and peanut, keeps coconut and seeds', () {
      const r = ['Nut-free'];
      expect(DietaryFilter.violates('Almonds, raw', r), isTrue);
      expect(DietaryFilter.violates('Peanut butter', r), isTrue);
      expect(DietaryFilter.violates('Coconut, shredded', r), isFalse);
      expect(DietaryFilter.violates('Sunflower seed kernels', r), isFalse);
    });

    test('eggplant is not treated as egg', () {
      expect(DietaryFilter.violates('Eggplant, raw', const ['Vegan']), isFalse);
    });

    test('diet styles are ignored (no filtering)', () {
      expect(
        DietaryFilter.violates('Pork loin, raw', const ['High-protein']),
        isFalse,
      );
      expect(
        DietaryFilter.violates('Cheddar cheese', const ['Low-carb', 'Balanced']),
        isFalse,
      );
    });
  });

  group('DietaryFilter.filter', () {
    test('drops only violating items and preserves order', () {
      final items = [
        'Chicken breast',
        'Pork loin',
        'Brown rice',
        'Bacon strips',
      ];
      final result = DietaryFilter.filter(items, const ['Halal'], (s) => s);
      expect(result, ['Chicken breast', 'Brown rice']);
    });

    test('empty restrictions returns list unchanged', () {
      final items = ['Pork loin', 'Cheddar cheese'];
      expect(DietaryFilter.filter(items, const [], (s) => s), items);
    });
  });
}
