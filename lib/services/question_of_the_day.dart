import 'dart:convert';

import '../data/predefined_questions.dart';
import '../models/family_story.dart';
import '../models/question.dart';

Question questionOfTheDay(
  String memberId,
  DateTime date,
  List<FamilyStory> stories,
) {
  final catalog = predefinedQuestionCategories
      .expand((c) => c.questions)
      .toList();
  final answered = stories.map((s) => s.question.trim()).toSet();
  var candidates = catalog
      .where((q) => !answered.contains(q.text.trim()))
      .toList();
  if (candidates.isEmpty) candidates = catalog;
  final day = '${date.year}-${date.month}-${date.day}';
  int score(Question question) {
    var hash = 2166136261;
    for (final byte in utf8.encode('$memberId:$day:${question.text}')) {
      hash = ((hash ^ byte) * 16777619) & 0xffffffff;
    }
    return hash;
  }

  // Ranking rather than list-index modulo: answering another question cannot
  // change today's selected question. Removing the selected one picks the next.
  candidates.sort((a, b) => score(b).compareTo(score(a)));
  return candidates.first;
}
