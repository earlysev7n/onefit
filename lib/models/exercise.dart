class Exercise {
  final String id;
  final String name;
  final String category;
  final List<String> primaryMuscles;
  final List<String> secondaryMuscles;
  final List<String> equipment;
  final String difficulty;
  final List<String> goals;
  final List<String> locations;
  final String instructions;
  final String? gifUrl;

  Exercise({
    required this.id,
    required this.name,
    required this.category,
    required this.primaryMuscles,
    required this.secondaryMuscles,
    required this.equipment,
    required this.difficulty,
    required this.goals,
    required this.locations,
    required this.instructions,
    this.gifUrl,
  });

  factory Exercise.fromMap(Map<String, dynamic> map) {
    return Exercise(
      id: map['id'] ?? '',
      name: map['name'] ?? '',
      category: map['category'] ?? '',
      primaryMuscles: List<String>.from(map['primaryMuscles'] ?? []),
      secondaryMuscles: List<String>.from(map['secondaryMuscles'] ?? []),
      equipment: List<String>.from(map['equipment'] ?? []),
      difficulty: map['difficulty'] ?? 'beginner',
      goals: List<String>.from(map['goals'] ?? []),
      locations: List<String>.from(map['locations'] ?? []),
      instructions: map['instructions'] ?? '',
      gifUrl: map['gifUrl'] as String?,
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'name': name,
    'category': category,
    'primaryMuscles': primaryMuscles,
    'secondaryMuscles': secondaryMuscles,
    'equipment': equipment,
    'difficulty': difficulty,
    'goals': goals,
    'locations': locations,
    'instructions': instructions,
    if (gifUrl != null) 'gifUrl': gifUrl,
  };
}
