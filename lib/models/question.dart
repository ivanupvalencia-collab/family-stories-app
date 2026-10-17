class Question {
  const Question(this.text, {this.id});

  final String text;
  // Local catalog identity; never added to the stored story or RPC payload.
  final String? id;
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
