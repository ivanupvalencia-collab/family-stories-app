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
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Row(
              children: [
                StoryPhotoView(
                  story: story,
                  service: photos,
                  width: 68,
                  height: 68,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      QuestionText(
                        story.question,
                        style: AritoriaType.memoryTitle,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year} · $duration',
                        style: AritoriaType.caption.copyWith(fontSize: 13),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                const SizedBox.square(
                  dimension: 40,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: AritoriaColors.softOlive,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.play_arrow_rounded,
                      color: AritoriaColors.moss,
                      size: 25,
                    ),
                  ),
                ),
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
            final height = (constraints.maxWidth * .86).clamp(
              240.0,
              (MediaQuery.sizeOf(context).height * .48).clamp(240.0, 420.0),
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
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: -1,
                    height: 24,
                    child: ClipPath(
                      clipper: _PhotoEdge(),
                      child: const ColoredBox(color: AritoriaColors.cream),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _MemberIdentity(member: member, onInvite: onInvite),
              const SizedBox(height: 32),
              Text(
                'Conoce su historia',
                style: AritoriaType.section.copyWith(fontSize: 26),
              ),
              const SizedBox(height: 8),
              Text(
                'Cada pregunta es una oportunidad para descubrir un nuevo recuerdo.',
                style: AritoriaType.body.copyWith(color: AritoriaColors.muted),
              ),
              const SizedBox(height: 24),
              _MomentCard(question: question, onAsk: onAsk),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.center,
                child: TextButton.icon(
                  onPressed: onQuestions,
                  label: const Text('Ver todas las preguntas'),
                  icon: const Icon(Icons.chevron_right, size: 20),
                  iconAlignment: IconAlignment.end,
                ),
              ),
              const SizedBox(height: 32),
              Text(
                'Sus historias',
                style: AritoriaType.section.copyWith(fontSize: 26),
              ),
              const SizedBox(height: 8),
              Text(
                'Recuerdos que ya nos ha contado.',
                style: AritoriaType.body.copyWith(color: AritoriaColors.muted),
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
              if (stories.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: TextButton.icon(
                    style: TextButton.styleFrom(
                      backgroundColor: AritoriaColors.softOlive,
                      foregroundColor: AritoriaColors.ink,
                      minimumSize: const Size(double.infinity, 48),
                      shape: const StadiumBorder(),
                    ),
                    onPressed: onAllStories,
                    label: const Text('Ver todas sus historias'),
                    icon: const Icon(Icons.chevron_right, size: 20),
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

class _PhotoEdge extends CustomClipper<Path> {
  @override
  Path getClip(Size size) => Path()
    ..moveTo(0, size.height * .25)
    ..cubicTo(
      size.width * .28,
      size.height,
      size.width * .7,
      size.height * .1,
      size.width,
      size.height * .4,
    )
    ..lineTo(size.width, size.height)
    ..lineTo(0, size.height)
    ..close();
  @override
  bool shouldReclip(_PhotoEdge oldClipper) => false;
}

class _MemberIdentity extends StatelessWidget {
  const _MemberIdentity({required this.member, required this.onInvite});
  final FamilyMember member;
  final VoidCallback onInvite;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final identity = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(member.name, style: AritoriaType.memberName),
          const SizedBox(height: 6),
          Text(
            member.relationship,
            style: AritoriaType.body.copyWith(
              fontSize: 18,
              color: AritoriaColors.muted,
            ),
          ),
        ],
      );
      final status = member.linkedAccountId != null
          ? Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AritoriaColors.softOlive,
                borderRadius: BorderRadius.circular(30),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.link, size: 17, color: AritoriaColors.moss),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      'Vinculada',
                      style: AritoriaType.action.copyWith(
                        color: AritoriaColors.moss,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            )
          : TextButton.icon(
              onPressed: onInvite,
              icon: const Icon(Icons.link, size: 17),
              label: Text('Invitar a ${member.name}'),
              style: TextButton.styleFrom(
                backgroundColor: AritoriaColors.softOlive,
                foregroundColor: AritoriaColors.moss,
                shape: const StadiumBorder(),
              ),
            );
      if (constraints.maxWidth < 300 ||
          MediaQuery.textScalerOf(context).scale(1) > 1.3 ||
          member.linkedAccountId == null) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [identity, const SizedBox(height: 12), status],
        );
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(child: identity),
          const SizedBox(width: 12),
          status,
        ],
      );
    },
  );
}

class _MomentCard extends StatelessWidget {
  const _MomentCard({required this.question, required this.onAsk});
  final Question question;
  final VoidCallback onAsk;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: AritoriaColors.card,
      borderRadius: BorderRadius.circular(20),
      boxShadow: const [
        BoxShadow(
          color: Color(0x0D433B28),
          blurRadius: 20,
          offset: Offset(0, 6),
        ),
      ],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox.square(
              dimension: 46,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: AritoriaColors.cream,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.spa_outlined,
                  color: AritoriaColors.moss,
                  size: 29,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'PREGUNTA DEL MOMENTO',
                    style: AritoriaType.caption.copyWith(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: .6,
                      color: AritoriaColors.moss,
                    ),
                  ),
                  const SizedBox(height: 8),
                  QuestionText(question.text, style: AritoriaType.question),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: onAsk,
          style: FilledButton.styleFrom(
            backgroundColor: AritoriaColors.moss,
            foregroundColor: AritoriaColors.onPhoto,
            minimumSize: const Size(0, 50),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            shape: const StadiumBorder(),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(
                child: Text(
                  'Pregúntale',
                  style: AritoriaType.body.copyWith(
                    fontSize: 17,
                    color: AritoriaColors.onPhoto,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              const Icon(Icons.arrow_forward, size: 20),
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
