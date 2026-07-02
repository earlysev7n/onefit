import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Result of an OpenAI recipe generation.
class OpenAIRecipe {
  final String title;
  final List<String> steps;
  final int readyInMinutes;
  final int servings;

  OpenAIRecipe({
    required this.title,
    required this.steps,
    this.readyInMinutes = 0,
    this.servings = 1,
  });
}

/// Wraps the OpenAI Chat Completions API to turn a Genetic-Algorithm meal
/// (a list of ingredients with gram portions) into step-by-step cooking
/// instructions — the "Transformer" natural-language layer described in the
/// capstone objective.
class OpenAIService {
  // TEST KEY — this was shared in plain text and should be treated as
  // compromised. Revoke/rotate it after the demo and move secrets to
  // environment config / Firebase Remote Config for any real build.
  static final String _apiKey = dotenv.env['OPENAI_API_KEY'] ?? '';
  static const String _endpoint = 'https://api.openai.com/v1/chat/completions';
  static const String _model = 'gpt-4o-mini';

  /// Generates step-by-step cooking instructions for [ingredients]
  /// (each a human string like "120g Chicken Breast") for the given [mealType].
  Future<OpenAIRecipe> generateRecipe({
    required List<String> ingredients,
    required String mealType,
  }) async {
    if (_apiKey.isEmpty) {
      throw Exception('OpenAI API key not configured.');
    }

    final ingredientList = ingredients.join(', ');
    final prompt =
        'Create a simple, healthy $mealType recipe using ONLY these ingredients '
        'with the given gram amounts: $ingredientList. You may assume basic '
        'pantry staples (salt, pepper, water, cooking oil). Respond as strict '
        'JSON with keys: "title" (string), "readyInMinutes" (integer), '
        '"servings" (integer), and "steps" (an ordered array of short '
        'instruction strings). Keep it to 4-8 clear, beginner-friendly steps.';

    final response = await http
        .post(
          Uri.parse(_endpoint),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $_apiKey',
          },
          body: jsonEncode({
            'model': _model,
            'messages': [
              {
                'role': 'system',
                'content':
                    'You are a concise cooking assistant that always replies with strict JSON.',
              },
              {'role': 'user', 'content': prompt},
            ],
            'response_format': {'type': 'json_object'},
            'temperature': 0.8,
          }),
        )
        .timeout(const Duration(seconds: 40));

    if (response.statusCode != 200) {
      throw Exception(
        'OpenAI request failed (${response.statusCode}). '
        'Check the API key, billing, or your connection.',
      );
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final content =
        body['choices']?[0]?['message']?['content'] as String? ?? '{}';
    final data = jsonDecode(content) as Map<String, dynamic>;

    final steps = (data['steps'] as List? ?? [])
        .map((s) => s.toString().trim())
        .where((s) => s.isNotEmpty)
        .toList();

    final title = (data['title'] as String?)?.trim();

    return OpenAIRecipe(
      title: (title != null && title.isNotEmpty) ? title : 'Generated Recipe',
      steps: steps.isEmpty
          ? ['Combine all ingredients and cook to your preference.']
          : steps,
      readyInMinutes: (data['readyInMinutes'] as num?)?.toInt() ?? 0,
      servings: (data['servings'] as num?)?.toInt() ?? 1,
    );
  }
}
