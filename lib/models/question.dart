class Question {
  const Question(this.text);

  final String text;
}

class QuestionCategory {
  const QuestionCategory({
    required this.name,
    required this.description,
    required this.questions,
  });

  final String name;
  final String description;
  final List<Question> questions;
}
