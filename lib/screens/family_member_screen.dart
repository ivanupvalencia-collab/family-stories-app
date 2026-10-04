import 'dart:async';

import 'package:flutter/material.dart';

import '../models/family_member.dart';
import '../models/family_story.dart';
import '../services/auth_service.dart';
import '../services/family_member_service.dart';
import '../services/family_story_storage.dart';
import '../services/invitation_service.dart';
import '../services/invitation_share_service.dart';
import 'questions_screen.dart';
import 'story_screen.dart';

class FamilyMemberScreen extends StatefulWidget {
  const FamilyMemberScreen({
    required this.familyMember,
    required this.authService,
    required this.familyMemberService,
    required this.invitationService,
    required this.invitationShareService,
    required this.isRemoteFamilyMember,
    this.familyStoryStorage,
    super.key,
  });

  final FamilyMember familyMember;
  final AuthService authService;
  final FamilyMemberService familyMemberService;
  final InvitationService invitationService;
  final InvitationShareService invitationShareService;
  final bool isRemoteFamilyMember;
  final FamilyStoryStorage? familyStoryStorage;

  @override
  State<FamilyMemberScreen> createState() => _FamilyMemberScreenState();
}

class _FamilyMemberScreenState extends State<FamilyMemberScreen> {
  late final FamilyStoryStorage _storyStorage;
  late FamilyMember _familyMember;
  final List<FamilyStory> _stories = [];
  bool _isLoading = true;
  bool _isRefreshingMember = false;

  @override
  void initState() {
    super.initState();
    _familyMember = widget.familyMember;
    _storyStorage = widget.familyStoryStorage ?? LocalFamilyStoryStorage();
    _loadStories();
    unawaited(_refreshRemoteFamilyMember());
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
    await _refreshRemoteFamilyMember();
    if (!mounted) {
      return;
    }
    final storySaved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (context) => QuestionsScreen(
          familyMember: _familyMember,
          familyStoryStorage: _storyStorage,
          authService: widget.authService,
          invitationService: widget.invitationService,
          invitationShareService: widget.invitationShareService,
          familyMemberService: widget.familyMemberService,
          isRemoteFamilyMember: widget.isRemoteFamilyMember,
        ),
      ),
    );
    if (storySaved == true && mounted) {
      setState(() => _isLoading = true);
      await _loadStories();
    }
    await _refreshRemoteFamilyMember();
  }

  Future<void> _refreshRemoteFamilyMember({bool showError = false}) async {
    final user = widget.authService.currentUser;
    if (!widget.isRemoteFamilyMember || user == null || _isRefreshingMember) {
      return;
    }

    setState(() => _isRefreshingMember = true);
    try {
      final familyMembers = await widget.familyMemberService.loadForOwner(
        user.id,
      );
      FamilyMember? refreshedMember;
      for (final familyMember in familyMembers) {
        if (familyMember.id == _familyMember.id) {
          refreshedMember = familyMember;
          break;
        }
      }
      if (mounted && refreshedMember != null) {
        setState(() => _familyMember = refreshedMember!);
      }
    } catch (_) {
      if (mounted && showError) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudo actualizar el familiar.')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isRefreshingMember = false);
      }
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
      appBar: AppBar(
        title: Text(_familyMember.name),
        actions: [
          if (widget.isRemoteFamilyMember)
            IconButton(
              onPressed: _isRefreshingMember
                  ? null
                  : () => _refreshRemoteFamilyMember(showError: true),
              tooltip: 'Actualizar familiar',
              icon: const Icon(Icons.refresh),
            ),
        ],
      ),
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
                  _familyMember.name,
                  textAlign: TextAlign.center,
                  style: textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _familyMember.relationship,
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
