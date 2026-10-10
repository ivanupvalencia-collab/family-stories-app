import 'package:flutter/material.dart';

// Presentation only: WORD JOINER prevents a line break on either side of a
// slash inside a word. Models, submission and accessibility keep the original.
String questionDisplayText(String text) =>
    text.replaceAllMapped(RegExp(r'(?<=\S)/(?=\S)'), (_) => '\u2060/\u2060');

class QuestionText extends Text {
  QuestionText(
    String text, {
    super.key,
    super.style,
    super.textAlign,
    super.maxLines,
    super.overflow,
  }) : super(questionDisplayText(text), semanticsLabel: text);
}
