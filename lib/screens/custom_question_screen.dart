import 'package:flutter/material.dart';

import '../models/family_member.dart';
import '../models/question.dart';
import '../services/family_story_storage.dart';
import 'question_screen.dart';

class CustomQuestionScreen extends StatefulWidget {
  const CustomQuestionScreen({
    required this.familyMember,
    required this.familyStoryStorage,
    super.key,
  });

  final FamilyMember familyMember;
  final FamilyStoryStorage familyStoryStorage;

  @override
  State<CustomQuestionScreen> createState() => _CustomQuestionScreenState();
}

class _CustomQuestionScreenState extends State<CustomQuestionScreen> {
  final _formKey = GlobalKey<FormState>();
  final _questionController = TextEditingController();

  @override
  void dispose() {
    _questionController.dispose();
    super.dispose();
  }

  Future<void> _continue() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final storySaved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (context) => QuestionScreen(
          familyMember: widget.familyMember,
          question: Question(_questionController.text.trim()),
          familyStoryStorage: widget.familyStoryStorage,
        ),
      ),
    );
    if (storySaved == true && mounted) {
      Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Tu pregunta')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      '¿Qué quieres preguntarle a ${widget.familyMember.name}?',
                      style: textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 24),
                    TextFormField(
                      controller: _questionController,
                      autofocus: true,
                      minLines: 3,
                      maxLines: 5,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: const InputDecoration(
                        labelText: 'Pregunta',
                        hintText: 'Escribe aquí tu pregunta',
                        alignLabelWithHint: true,
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Escribe una pregunta';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 32),
                    FilledButton(
                      onPressed: _continue,
                      child: const Text('Continuar'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
