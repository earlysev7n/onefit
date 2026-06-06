import 'package:cloud_firestore/cloud_firestore.dart';

class FoodItem {
  final String id;
  final String userId;
  final String name;
  final String barcode;
  final double servingSize;
  final String servingSizeUnit;
  final double calories;
  final double protein;
  final double carbs;
  final double fat;
  final double fiber;
  final double sugar;
  final double sodium;
  // Vitamins (units noted per field)
  final double vitaminA; // mcg RAE
  final double vitaminC; // mg
  final double vitaminD; // mcg
  final double vitaminE; // mg
  final double vitaminK; // mcg
  final double vitaminB6; // mg
  final double vitaminB12; // mcg
  final double folate; // mcg DFE
  // Minerals (mg)
  final double iron;
  final double calcium;
  final double magnesium;
  final double potassium;
  final double zinc;
  final double phosphorus;

  final DateTime loggedAt;
  final String mealType;
  final double quantity;

  FoodItem({
    required this.id,
    required this.userId,
    required this.name,
    required this.barcode,
    required this.servingSize,
    required this.servingSizeUnit,
    required this.calories,
    required this.protein,
    required this.carbs,
    required this.fat,
    this.fiber = 0,
    this.sugar = 0,
    this.sodium = 0,
    this.vitaminA = 0,
    this.vitaminC = 0,
    this.vitaminD = 0,
    this.vitaminE = 0,
    this.vitaminK = 0,
    this.vitaminB6 = 0,
    this.vitaminB12 = 0,
    this.folate = 0,
    this.iron = 0,
    this.calcium = 0,
    this.magnesium = 0,
    this.potassium = 0,
    this.zinc = 0,
    this.phosphorus = 0,
    required this.loggedAt,
    required this.mealType,
    this.quantity = 1.0,
  });

  // ── Macros ─────────────────────────────────────────────────────────────────
  double get totalCalories => calories * quantity;
  double get totalProtein => protein * quantity;
  double get totalCarbs => carbs * quantity;
  double get totalFat => fat * quantity;
  double get totalFiber => fiber * quantity;
  double get totalSugar => sugar * quantity;
  double get totalSodium => sodium * quantity;

  // ── Vitamins ───────────────────────────────────────────────────────────────
  double get totalVitaminA => vitaminA * quantity;
  double get totalVitaminC => vitaminC * quantity;
  double get totalVitaminD => vitaminD * quantity;
  double get totalVitaminE => vitaminE * quantity;
  double get totalVitaminK => vitaminK * quantity;
  double get totalVitaminB6 => vitaminB6 * quantity;
  double get totalVitaminB12 => vitaminB12 * quantity;
  double get totalFolate => folate * quantity;

  // ── Minerals ───────────────────────────────────────────────────────────────
  double get totalIron => iron * quantity;
  double get totalCalcium => calcium * quantity;
  double get totalMagnesium => magnesium * quantity;
  double get totalPotassium => potassium * quantity;
  double get totalZinc => zinc * quantity;
  double get totalPhosphorus => phosphorus * quantity;

  factory FoodItem.fromMap(Map<String, dynamic> map, String id) {
    return FoodItem(
      id: id,
      userId: map['userId'] ?? '',
      name: map['name'] ?? '',
      barcode: map['barcode'] ?? '',
      servingSize: (map['servingSize'] ?? 100).toDouble(),
      servingSizeUnit: map['servingSizeUnit'] ?? 'g',
      calories: (map['calories'] ?? 0).toDouble(),
      protein: (map['protein'] ?? 0).toDouble(),
      carbs: (map['carbs'] ?? 0).toDouble(),
      fat: (map['fat'] ?? 0).toDouble(),
      fiber: (map['fiber'] ?? 0).toDouble(),
      sugar: (map['sugar'] ?? 0).toDouble(),
      sodium: (map['sodium'] ?? 0).toDouble(),
      vitaminA: (map['vitaminA'] ?? 0).toDouble(),
      vitaminC: (map['vitaminC'] ?? 0).toDouble(),
      vitaminD: (map['vitaminD'] ?? 0).toDouble(),
      vitaminE: (map['vitaminE'] ?? 0).toDouble(),
      vitaminK: (map['vitaminK'] ?? 0).toDouble(),
      vitaminB6: (map['vitaminB6'] ?? 0).toDouble(),
      vitaminB12: (map['vitaminB12'] ?? 0).toDouble(),
      folate: (map['folate'] ?? 0).toDouble(),
      iron: (map['iron'] ?? 0).toDouble(),
      calcium: (map['calcium'] ?? 0).toDouble(),
      magnesium: (map['magnesium'] ?? 0).toDouble(),
      potassium: (map['potassium'] ?? 0).toDouble(),
      zinc: (map['zinc'] ?? 0).toDouble(),
      phosphorus: (map['phosphorus'] ?? 0).toDouble(),
      loggedAt: (map['loggedAt'] as Timestamp).toDate(),
      mealType: map['mealType'] ?? 'snack',
      quantity: (map['quantity'] ?? 1.0).toDouble(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'name': name,
      'barcode': barcode,
      'servingSize': servingSize,
      'servingSizeUnit': servingSizeUnit,
      'calories': calories,
      'protein': protein,
      'carbs': carbs,
      'fat': fat,
      'fiber': fiber,
      'sugar': sugar,
      'sodium': sodium,
      'vitaminA': vitaminA,
      'vitaminC': vitaminC,
      'vitaminD': vitaminD,
      'vitaminE': vitaminE,
      'vitaminK': vitaminK,
      'vitaminB6': vitaminB6,
      'vitaminB12': vitaminB12,
      'folate': folate,
      'iron': iron,
      'calcium': calcium,
      'magnesium': magnesium,
      'potassium': potassium,
      'zinc': zinc,
      'phosphorus': phosphorus,
      'loggedAt': Timestamp.fromDate(loggedAt),
      'mealType': mealType,
      'quantity': quantity,
    };
  }

  FoodItem copyWith({
    String? id,
    String? userId,
    String? name,
    String? barcode,
    double? servingSize,
    String? servingSizeUnit,
    double? calories,
    double? protein,
    double? carbs,
    double? fat,
    double? fiber,
    double? sugar,
    double? sodium,
    double? vitaminA,
    double? vitaminC,
    double? vitaminD,
    double? vitaminE,
    double? vitaminK,
    double? vitaminB6,
    double? vitaminB12,
    double? folate,
    double? iron,
    double? calcium,
    double? magnesium,
    double? potassium,
    double? zinc,
    double? phosphorus,
    DateTime? loggedAt,
    String? mealType,
    double? quantity,
  }) {
    return FoodItem(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      name: name ?? this.name,
      barcode: barcode ?? this.barcode,
      servingSize: servingSize ?? this.servingSize,
      servingSizeUnit: servingSizeUnit ?? this.servingSizeUnit,
      calories: calories ?? this.calories,
      protein: protein ?? this.protein,
      carbs: carbs ?? this.carbs,
      fat: fat ?? this.fat,
      fiber: fiber ?? this.fiber,
      sugar: sugar ?? this.sugar,
      sodium: sodium ?? this.sodium,
      vitaminA: vitaminA ?? this.vitaminA,
      vitaminC: vitaminC ?? this.vitaminC,
      vitaminD: vitaminD ?? this.vitaminD,
      vitaminE: vitaminE ?? this.vitaminE,
      vitaminK: vitaminK ?? this.vitaminK,
      vitaminB6: vitaminB6 ?? this.vitaminB6,
      vitaminB12: vitaminB12 ?? this.vitaminB12,
      folate: folate ?? this.folate,
      iron: iron ?? this.iron,
      calcium: calcium ?? this.calcium,
      magnesium: magnesium ?? this.magnesium,
      potassium: potassium ?? this.potassium,
      zinc: zinc ?? this.zinc,
      phosphorus: phosphorus ?? this.phosphorus,
      loggedAt: loggedAt ?? this.loggedAt,
      mealType: mealType ?? this.mealType,
      quantity: quantity ?? this.quantity,
    );
  }
}
