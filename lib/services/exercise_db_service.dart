import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/exercise.dart';

class ExerciseDBService {
  static const _base = 'https://oss.exercisedb.dev/api/v1';
  static const _cacheCollection = 'exercises';
  static const _metaDoc = 'cache_meta';
  static const _cacheTtlDays = 30;

  /// Bump this when the upstream API/media host changes so the existing
  /// Firestore cache (which may hold dead gifUrls) is treated as stale and
  /// refreshed exactly once. v2 = AscendAPI / oss.exercisedb.dev migration.
  static const _cacheVersion = 2;

  final _db = FirebaseFirestore.instance;

  // ── Public API ──────────────────────────────────────────────────────────────

  /// Returns exercises from Firestore cache; refreshes if stale or empty.
  Future<List<Exercise>> getExercises() async {
    final meta = await _db
        .collection(_cacheCollection)
        .doc(_metaDoc)
        .get();

    final needsRefresh = _isCacheStale(meta);
    if (!needsRefresh) {
      final cached = await _loadFromFirestore();
      if (cached.isNotEmpty) return cached;
    }

    // Fetch from API and cache
    final fresh = await _fetchFromApi();
    if (fresh.isNotEmpty) {
      await _saveToFirestore(fresh);
    }
    return fresh.isNotEmpty ? fresh : await _loadFromFirestore();
  }

  // ── Firestore cache ─────────────────────────────────────────────────────────

  Future<List<Exercise>> _loadFromFirestore() async {
    final snap = await _db.collection(_cacheCollection).get();
    return snap.docs
        .where((d) => d.id != _metaDoc)
        .map((d) => Exercise.fromMap(d.data()))
        .toList();
  }

  Future<void> _saveToFirestore(List<Exercise> exercises) async {
    const chunkSize = 499; // Firestore batch limit is 500 ops
    for (int i = 0; i < exercises.length; i += chunkSize) {
      final chunk = exercises.sublist(i, (i + chunkSize).clamp(0, exercises.length));
      final batch = _db.batch();
      for (final ex in chunk) {
        final rawId = ex.id.isNotEmpty ? ex.id : ex.name;
        final safeId = rawId.replaceAll(RegExp(r'[/\\.#\[\]*?]'), '_');
        if (safeId.isEmpty) continue;
        final ref = _db.collection(_cacheCollection).doc(safeId);
        batch.set(ref, ex.toMap());
      }
      await batch.commit();
    }

    // Write cache metadata in a separate batch
    await _db.collection(_cacheCollection).doc(_metaDoc).set(
      {
        'updatedAt': FieldValue.serverTimestamp(),
        'count': exercises.length,
        'version': _cacheVersion,
      },
    );
  }

  bool _isCacheStale(DocumentSnapshot meta) {
    if (!meta.exists) return true;
    final data = meta.data() as Map<String, dynamic>?;
    if (data == null) return true;
    // Cache written by an older app version (or no version) → force a refresh
    // so dead gifUrls from the retired host get overwritten.
    if (data['version'] != _cacheVersion) return true;
    final ts = data['updatedAt'];
    if (ts == null) return true;
    final updatedAt = (ts as Timestamp).toDate();
    return DateTime.now().difference(updatedAt).inDays >= _cacheTtlDays;
  }

  // ── HTTP fetch ──────────────────────────────────────────────────────────────

  // The AscendAPI free tier serves a fixed 25 exercises per page and ignores
  // `limit`/`offset`; pages are walked with `?after=<meta.nextCursor>`.
  Future<List<Exercise>> _fetchFromApi() async {
    const maxPages = 100; // safety stop (~1500 exercises / 25 ≈ 60 pages)
    final exercises = <Exercise>[];
    String? cursor;

    try {
      for (int page = 0; page < maxPages; page++) {
        final uri = Uri.parse('$_base/exercises').replace(
          queryParameters: cursor == null ? null : {'after': cursor},
        );
        final response = await http
            .get(uri, headers: {'Content-Type': 'application/json'})
            .timeout(const Duration(seconds: 30));

        if (response.statusCode != 200) break;

        final json = jsonDecode(response.body) as Map<String, dynamic>;
        final rawList = json['data'] as List? ?? [];
        exercises.addAll(rawList.cast<Map<String, dynamic>>().map(_mapToExercise));

        final meta = json['meta'] as Map<String, dynamic>? ?? {};
        final hasNext = meta['hasNextPage'] == true;
        cursor = meta['nextCursor'] as String?;
        if (!hasNext || cursor == null || cursor.isEmpty) break;
      }
    } catch (_) {
      // Return whatever was gathered before the failure.
    }

    return exercises;
  }

  // ── Mapping ─────────────────────────────────────────────────────────────────

  Exercise _mapToExercise(Map<String, dynamic> raw) {
    final bodyParts = List<String>.from(raw['bodyParts'] ?? raw['bodyPart'] is String ? [raw['bodyPart']] : []);
    final equipments = List<String>.from(raw['equipments'] ?? raw['equipment'] is String ? [raw['equipment']] : []);
    final targetMuscles = List<String>.from(raw['targetMuscles'] ?? raw['target'] is String ? [raw['target']] : []);
    final secondaryMuscles = List<String>.from(raw['secondaryMuscles'] ?? []);
    final instructions = raw['instructions'] is List
        ? (raw['instructions'] as List).cast<String>().join('\n')
        : (raw['instructions'] as String? ?? '');
    final name = (raw['name'] as String? ?? '').toLowerCase();

    return Exercise(
      id: raw['exerciseId']?.toString() ?? raw['id']?.toString() ?? name.hashCode.toString(),
      name: _titleCase(name),
      category: bodyParts.isNotEmpty ? bodyParts.first : 'Other',
      primaryMuscles: targetMuscles,
      secondaryMuscles: secondaryMuscles,
      equipment: _normalizeEquipment(equipments),
      difficulty: _inferDifficulty(name, targetMuscles),
      goals: _inferGoals(bodyParts, name),
      locations: _inferLocations(equipments),
      instructions: instructions,
      gifUrl: raw['gifUrl'] as String?,
    );
  }

  // Maps ExerciseDB equipment names to app's format
  List<String> _normalizeEquipment(List<String> raw) {
    const map = {
      'body weight': 'Bodyweight',
      'dumbbell': 'Dumbbells',
      'barbell': 'Barbell',
      'kettlebell': 'Kettlebells',
      'resistance band': 'Resistance Bands',
      'pull-up bar': 'Pull-up Bar',
      'cable': 'Cable Machine',
      'machine': 'Machine',
      'band': 'Resistance Bands',
      'assisted': 'Machine',
    };
    final normalized = raw.map((e) => map[e.toLowerCase()] ?? _titleCase(e)).toList();
    return normalized.isEmpty ? ['Bodyweight'] : normalized;
  }

  // Infers workout goal tags from body parts / exercise name
  List<String> _inferGoals(List<String> bodyParts, String name) {
    final goals = <String>[];
    final bp = bodyParts.map((b) => b.toLowerCase()).toList();

    if (bp.contains('cardio') || name.contains('run') || name.contains('jump')) {
      goals.add('weight_loss');
      goals.add('endurance');
    }
    if (bp.any((b) => ['chest', 'back', 'shoulders', 'upper arms', 'upper legs'].contains(b))) {
      goals.add('muscle_gain');
      goals.add('general');
    }
    if (bp.contains('waist') || bp.contains('lower legs')) {
      goals.add('weight_loss');
      goals.add('general');
    }
    if (goals.isEmpty) goals.addAll(['general', 'muscle_gain']);
    return goals.toSet().toList();
  }

  // Infers home/gym from equipment
  List<String> _inferLocations(List<String> raw) {
    final gymOnly = {'barbell', 'cable', 'machine', 'assisted', 'smith machine', 'leverage machine'};
    final hasGymEquip = raw.any((e) => gymOnly.contains(e.toLowerCase()));
    return hasGymEquip ? ['gym'] : ['home', 'gym'];
  }

  // Simple difficulty heuristic from exercise name keywords
  String _inferDifficulty(String name, List<String> muscles) {
    const advanced = ['muscle up', 'pistol squat', 'handstand', 'planche', 'one arm'];
    const beginner = ['walk', 'sit up', 'crunch', 'stretch', 'raise', 'curl'];
    if (advanced.any((kw) => name.contains(kw))) return 'advanced';
    if (beginner.any((kw) => name.contains(kw))) return 'beginner';
    return 'intermediate';
  }

  String _titleCase(String s) => s.split(' ').map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}').join(' ');
}
