import 'package:flutter/material.dart';

import '../models/family_member.dart';
import '../models/family_story.dart';
import '../services/family_story_storage.dart';
import 'questions_screen.dart';
import 'story_screen.dart';

class FamilyMemberScreen extends StatefulWidget {
  const FamilyMemberScreen({
    required this.familyMember,
    this.familyStoryStorage,
    super.key,
  });

  final FamilyMember familyMember;
  final FamilyStoryStorage? familyStoryStorage;

  @override
  State<FamilyMemberScreen> createState() => _FamilyMemberScreenState();
}

class _FamilyMemberScreenState extends State<FamilyMemberScreen> {
  late final FamilyStoryStorage _storyStorage;
  final List<FamilyStory> _stories = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _storyStorage = widget.familyStoryStorage ?? LocalFamilyStoryStorage();
    _loadStories();
  }

  Future<void> _loadStories() async {
    try {
      final stories = await _storyStorage.loadForFamily(widget.familyMember.id);
      if (!mounted) {
        return;
      }
      setState(() {
        _stories
          ..clear()
          ..addAll(stories);
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudieron cargar sus historias.')),
      );
    }
  }

  Future<void> _openQuestions() async {
    final storySaved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (context) => QuestionsScreen(
          familyMember: widget.familyMember,
          familyStoryStorage: _storyStorage,
        ),
      ),
    );
    if (storySaved == true && mounted) {
      setState(() => _isLoading = true);
      await _loadStories();
    }
  }

  void _openStory(FamilyStory story) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (context) => StoryScreen(story: story)));
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes.toString().padLeft(2, '0');
    final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  String _formatDate(DateTime date) {
    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    return '$day/$month/${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;

    return Scaffold(
      appBar: AppBar(title: Text(widget.familyMember.name)),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                CircleAvatar(
                  radius: 40,
                  backgroundColor: theme.colorScheme.primaryContainer,
                  child: Icon(
                    Icons.person_outline,
                    size: 44,
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  widget.familyMember.name,
                  textAlign: TextAlign.center,
                  style: textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  widget.familyMember.relationship,
                  textAlign: TextAlign.center,
                  style: textTheme.titleMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 40),
                Text(
                  'Conoce su historia',
                  style: textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _openQuestions,
                  icon: const Icon(Icons.question_answer_outlined),
                  label: const Text('Responder una pregunta'),
                ),
                const SizedBox(height: 40),
                Text(
                  'Sus historias',
                  style: textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 24),
                if (_isLoading)
                  const Center(child: CircularProgressIndicator())
                else if (_stories.isEmpty)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        children: [
                          Icon(
                            Icons.auto_stories_outlined,
                            size: 40,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Aquí aparecerán sus historias cuando guarde sus respuestas.',
                            textAlign: TextAlign.center,
                            style: textTheme.bodyLarge?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  ..._stories.map(
                    (story) => Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: const CircleAvatar(
                          child: Icon(Icons.play_arrow),
                        ),
                        title: Text(story.question),
                        subtitle: Text(
                          '${_formatDate(story.createdAt)} · ${_formatDuration(story.duration)}',
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => _openStory(story),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
