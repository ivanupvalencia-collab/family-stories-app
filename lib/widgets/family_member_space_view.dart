import 'package:flutter/material.dart';

import '../design/aritoria_design.dart';
import '../models/family_member.dart';
import '../models/family_story.dart';
import '../models/question.dart';
import '../services/family_member_photo_service.dart';
import '../services/story_photo_service.dart';
import 'family_member_photo_view.dart';
import 'story_photo_view.dart';
import 'question_text.dart';

class StoryMemoryRow extends StatelessWidget {
  const StoryMemoryRow({
    required this.story,
    required this.photos,
    required this.onTap,
    super.key,
  });
  final FamilyStory story;
  final StoryPhotoService photos;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final date = story.createdAt.toLocal();
    final duration =
        '${story.duration.inMinutes.toString().padLeft(2, '0')}:${(story.duration.inSeconds % 60).toString().padLeft(2, '0')}';
    return Column(
      children: [
        InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Row(
              children: [
                StoryPhotoView(story: story, service: photos),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      QuestionText(story.question, style: AritoriaType.body),
                      const SizedBox(height: 6),
                      Text(
                        '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year} · $duration',
                        style: AritoriaType.caption,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(Icons.play_arrow, color: AritoriaColors.olive),
              ],
            ),
          ),
        ),
        const Divider(height: 1),
      ],
    );
  }
}

class FamilyMemberSpaceView extends StatelessWidget {
  const FamilyMemberSpaceView({
    required this.member,
    required this.photos,
    required this.storyPhotos,
    required this.stories,
    required this.question,
    required this.menu,
    required this.onBack,
    required this.onInvite,
    required this.onAsk,
    required this.onQuestions,
    required this.onStory,
    required this.onAllStories,
    required this.onRefresh,
    required this.loading,
    required this.failed,
    required this.onRetry,
    super.key,
  });
  final FamilyMember member;
  final FamilyMemberPhotoService photos;
  final StoryPhotoService storyPhotos;
  final List<FamilyStory> stories;
  final Question question;
  final Widget menu;
  final VoidCallback onBack,
      onInvite,
      onAsk,
      onQuestions,
      onAllStories,
      onRetry;
  final ValueChanged<FamilyStory> onStory;
  final Future<void> Function() onRefresh;
  final bool loading, failed;
  @override
  Widget build(BuildContext context) => RefreshIndicator(
    onRefresh: onRefresh,
    child: ListView(
      key: const ValueKey('member-space-scroll'),
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final height = (MediaQuery.sizeOf(context).height * .38).clamp(
              220.0,
              380.0,
            );
            return SizedBox(
              height: height,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  FamilyMemberPhotoView(
                    member: member,
                    photoService: photos,
                    circular: false,
                    width: constraints.maxWidth,
                    height: height,
                    alignment: const Alignment(0, -.15),
                    fallback: ColoredBox(
                      color: AritoriaColors.sand,
                      child: Center(
                        child: Text(
                          member.name.trim().isEmpty
                              ? '?'
                              : member.name.trim().characters.first,
                          style: AritoriaType.brand.copyWith(
                            fontSize: 72,
                            color: AritoriaColors.sage,
                          ),
                        ),
                      ),
                    ),
                  ),
                  Align(
                    alignment: Alignment.topCenter,
                    child: SafeArea(
                      bottom: false,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            _PhotoControl(
                              child: IconButton(
                                tooltip: 'Atrás',
                                onPressed: onBack,
                                icon: const Icon(Icons.arrow_back),
                              ),
                            ),
                            _PhotoControl(child: menu),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
        Padding(
          padding: const EdgeInsets.all(AritoriaSpace.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                member.name,
                style: AritoriaType.brand.copyWith(color: AritoriaColors.ink),
              ),
              const SizedBox(height: 8),
              Text(
                member.relationship,
                style: AritoriaType.body.copyWith(color: AritoriaColors.muted),
              ),
              const SizedBox(height: 12),
              if (member.linkedAccountId != null)
                const Row(
                  children: [
                    Icon(
                      Icons.check_circle_outline,
                      size: 15,
                      color: AritoriaColors.sage,
                    ),
                    SizedBox(width: 6),
                    Text('Vinculada', style: AritoriaType.caption),
                  ],
                )
              else
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: onInvite,
                    child: Text('Invitar a ${member.name}'),
                  ),
                ),
              const SizedBox(height: 32),
              const Text('Conoce su historia', style: AritoriaType.section),
              const SizedBox(height: 8),
              const Text(
                'Cada pregunta es una oportunidad para descubrir un nuevo recuerdo.',
                style: AritoriaType.body,
              ),
              const SizedBox(height: 24),
              const Text('PREGUNTA DEL MOMENTO', style: AritoriaType.caption),
              const SizedBox(height: 10),
              QuestionText(question.text, style: AritoriaType.section),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: onAsk,
                  label: const Text('Pregúntale'),
                  icon: const Icon(Icons.arrow_forward, size: 18),
                  iconAlignment: IconAlignment.end,
                ),
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: onQuestions,
                  label: const Text('Ver todas las preguntas'),
                  icon: const Icon(Icons.arrow_forward, size: 18),
                  iconAlignment: IconAlignment.end,
                ),
              ),
              const SizedBox(height: 32),
              const Text('Sus historias', style: AritoriaType.section),
              const SizedBox(height: 8),
              const Text(
                'Recuerdos que ya nos ha contado.',
                style: AritoriaType.body,
              ),
              const SizedBox(height: 16),
              if (loading && stories.isEmpty)
                const Center(child: CircularProgressIndicator())
              else if (failed && stories.isEmpty)
                Column(
                  children: [
                    const Text('No se pudieron cargar sus historias.'),
                    TextButton(
                      onPressed: onRetry,
                      child: const Text('Reintentar'),
                    ),
                  ],
                )
              else if (stories.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Text(
                    'Cada vida guarda recuerdos que merecen escucharse. Empieza con una pregunta.',
                    style: AritoriaType.body,
                  ),
                )
              else
                ...stories
                    .take(3)
                    .map(
                      (story) => StoryMemoryRow(
                        story: story,
                        photos: storyPhotos,
                        onTap: () => onStory(story),
                      ),
                    ),
              if (stories.length > 3)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: onAllStories,
                    label: const Text('Ver todas sus historias'),
                    icon: const Icon(Icons.arrow_forward, size: 18),
                    iconAlignment: IconAlignment.end,
                  ),
                ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ],
    ),
  );
}

class _PhotoControl extends StatelessWidget {
  const _PhotoControl({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: const BoxDecoration(
      color: AritoriaColors.cream,
      shape: BoxShape.circle,
    ),
    child: child,
  );
}
