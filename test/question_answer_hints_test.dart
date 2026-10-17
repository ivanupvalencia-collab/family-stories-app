import 'package:family_stories_app/data/predefined_questions.dart';
import 'package:family_stories_app/data/question_answer_hints.dart';
import 'package:family_stories_app/models/question.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'all 21 catalog entries have unique stable IDs and distinct specific hints',
    () {
      final questions = predefinedQuestionCategories
          .expand((category) => category.questions)
          .toList();
      final ids = questions.map((question) => question.id).toSet();
      expect(questions, hasLength(21));
      expect(ids, hasLength(21));
      expect(ids, isNot(contains(null)));
      expect(predefinedQuestionAnswerHints.keys.toSet(), ids);
      expect(questions.map(answerHintFor).toSet(), hasLength(21));
      for (final question in questions) {
        expect(answerHintFor(question), startsWith('Cuéntale '));
        expect(questionForReceivedRequest(question.text), same(question));
      }
      expect(
        answerHintFor(questions.first),
        'Cuéntale dónde estaba, cómo eran las habitaciones, quién vivía contigo y qué recuerdos guardas de ella.',
      );
    },
  );

  test('hints use catalog identity, not wording; custom questions get the exact generic hint', () {
    expect(
      answerHintFor(const Question('Texto revisado', id: 'first_job')),
      predefinedQuestionAnswerHints['first_job'],
    );
    expect(
      answerHintFor(const Question('Una pregunta personalizada')),
      customQuestionAnswerHint,
    );
    expect(
      answerHintFor(
        Question(predefinedQuestionCategories.first.questions.first.text),
      ),
      customQuestionAnswerHint,
    );
    final custom = questionForReceivedRequest('¿Qué merendabas en verano?');
    expect(custom.id, isNull);
    expect(custom.text, '¿Qué merendabas en verano?');
    expect(
      answerHintFor(custom),
      'Tómate tu tiempo. Cuéntale lo que recuerdes y cualquier detalle que te venga a la memoria.',
    );
    // No approximate/substring matching of custom requests.
    expect(
      questionForReceivedRequest(
        '¿Cómo era tu casa cuando eras pequeño/a? Cuéntame más.',
      ).id,
      isNull,
    );
  });
}
