import 'package:family_stories_app/models/question.dart';
import 'package:family_stories_app/widgets/question_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('only transforms slash words for display', () {
    expect(
      questionDisplayText('¿Eras pequeño/a? ¿Y abuelo/a?'),
      '¿Eras pequeño\u2060/\u2060a? ¿Y abuelo\u2060/\u2060a?',
    );
    expect(
      questionDisplayText('Una pregunta sin barras.'),
      'Una pregunta sin barras.',
    );
    expect(questionDisplayText('uno / dos'), 'uno / dos');
  });

  for (final word in ['pequeño/a', 'abuelo/a', 'niño/a', 'amigo/a', 'y/o']) {
    testWidgets('$word moves as a whole to the next line', (tester) async {
      const prefix = 'Era ';
      final question = Question('$prefix$word ayer');
      final original = question.text;
      // This width fits the prefix and everything up to '/', but not the suffix.
      final width = (prefix.length + word.length - 1) * 20.0;
      const style = TextStyle(fontFamily: 'Ahem', fontSize: 20, height: 1);
      final protectedKey = UniqueKey();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                SizedBox(
                  width: width,
                  child: QuestionText(
                    question.text,
                    key: protectedKey,
                    style: style,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      final protected = tester.renderObject<RenderParagraph>(
        find.descendant(
          of: find.byKey(protectedKey),
          matching: find.byType(RichText),
        ),
      );
      final boxes = protected.getBoxesForSelection(
        TextSelection(
          baseOffset: prefix.length,
          extentOffset: prefix.length + word.length + 2,
        ),
      );
      expect(boxes.map((box) => box.top).toSet(), hasLength(1));
      final prefixBoxes = protected.getBoxesForSelection(
        const TextSelection(baseOffset: 0, extentOffset: 3),
      );
      expect(boxes.first.top, greaterThan(prefixBoxes.first.top));
      expect(question.text, original);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('accessibility reads the original without invisible joiners', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    const original = '¿Cómo eras de pequeño/a?';
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: QuestionText(original))),
    );
    expect(tester.getSemantics(find.byType(QuestionText)).label, original);
    semantics.dispose();
  });
}
