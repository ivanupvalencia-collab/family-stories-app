import 'package:flutter/material.dart';

import '../design/aritoria_design.dart';
import '../models/family_member.dart';
import '../models/family_story.dart';
import '../models/question.dart';
import '../models/profile_avatar.dart';
import '../services/family_member_photo_service.dart';
import '../services/story_photo_service.dart';
import '../services/visible_account_avatar_service.dart';
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
    this.photosForStory,
    this.avatars,
    super.key,
  });
  final FamilyMember member;
  final FamilyMemberPhotoService photos;
  final VisibleAccountAvatarService? avatars;
  final StoryPhotoService storyPhotos;
  final StoryPhotoService Function(FamilyStory)? photosForStory;
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
        _MemberHeader(
          member: member,
          photos: photos,
          avatars: avatars,
          menu: menu,
          onBack: onBack,
          onInvite: onInvite,
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
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
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Text(
                    'Sus historias irán encontrando su lugar aquí.',
                    style: AritoriaType.body.copyWith(
                      color: AritoriaColors.muted,
                    ),
                  ),
                )
              else
                ...stories
                    .take(3)
                    .map(
                      (story) => StoryMemoryRow(
                        story: story,
                        photos: photosForStory?.call(story) ?? storyPhotos,
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

// Reuse the existing account-scoped avatar metadata and image caches. Only
// the presentation changes when a linked account has an available avatar.
class _MemberHeader extends StatefulWidget {
  const _MemberHeader({
    required this.member,
    required this.photos,
    required this.avatars,
    required this.menu,
    required this.onBack,
    required this.onInvite,
  });
  final FamilyMember member;
  final FamilyMemberPhotoService photos;
  final VisibleAccountAvatarService? avatars;
  final Widget menu;
  final VoidCallback onBack, onInvite;

  @override
  State<_MemberHeader> createState() => _MemberHeaderState();
}

class _MemberHeaderState extends State<_MemberHeader> {
  VisibleAccountAvatarService? _avatars;
  Future<void>? _pending;

  @override
  void initState() {
    super.initState();
    _attach();
  }

  void _attach() {
    // A-3: injected from the graph; null renders the fallback.
    _avatars = widget.avatars;
    _avatars?.addListener(_changed);
    _pending = _loadAvatar();
  }

  Future<void> _loadAvatar() async {
    final account = widget.member.linkedAccountId;
    if (widget.member.photoPath != null || account == null) return;
    try {
      await _avatars?.load(account);
    } catch (_) {
      // Optional avatar metadata must not prevent opening a member's space.
    }
  }

  void _changed() {
    if (mounted) {
      setState(() {
        _pending = _loadAvatar();
      });
    }
  }

  @override
  void didUpdateWidget(_MemberHeader oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.avatars != widget.avatars) {
      _avatars?.removeListener(_changed);
      _attach();
    } else if (oldWidget.member.linkedAccountId !=
            widget.member.linkedAccountId ||
        oldWidget.member.photoPath != widget.member.photoPath) {
      _pending = _loadAvatar();
    }
  }

  @override
  void dispose() {
    _avatars?.removeListener(_changed);
    super.dispose();
  }

  Widget _controls() => SafeArea(
    bottom: false,
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _PhotoControl(
            child: IconButton(
              tooltip: 'Atrás',
              onPressed: widget.onBack,
              icon: const Icon(Icons.arrow_back),
            ),
          ),
          _PhotoControl(child: widget.menu),
        ],
      ),
    ),
  );

  Widget _photo({required bool large, double? width, double? height}) =>
      FamilyMemberPhotoView(
        member: widget.member,
        photoService: widget.photos,
        avatarService: _avatars,
        radius: 32,
        circular: !large,
        width: width,
        height: height,
        alignment: large ? const Alignment(0, -.15) : Alignment.center,
        fallback: ColoredBox(
          color: large ? AritoriaColors.cream : AritoriaColors.softOlive,
          child: Center(
            child: Text(
              widget.member.name.trim().isEmpty
                  ? '?'
                  : widget.member.name.trim().characters.first,
              style: AritoriaType.brand.copyWith(fontSize: 28),
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) => FutureBuilder<void>(
    future: _pending,
    builder: (context, snapshot) {
      final account = widget.member.linkedAccountId;
      final profile = account == null ? null : _avatars?.cached(account);
      final hasPhoto =
          widget.member.photoPath != null ||
          (profile?.avatarUrl?.trim().isNotEmpty ?? false) ||
          ProfileAvatarCatalog.findByKey(profile?.avatarKey) != null;
      final identity = _MemberIdentity(
        member: widget.member,
        onInvite: widget.onInvite,
      );
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final height = hasPhoto
                  ? (constraints.maxWidth * .86).clamp(
                      240.0,
                      (MediaQuery.sizeOf(context).height * .48).clamp(
                        240.0,
                        420.0,
                      ),
                    )
                  : (constraints.maxWidth * .46).clamp(
                      144.0,
                      (MediaQuery.sizeOf(context).height * .28).clamp(
                        144.0,
                        220.0,
                      ),
                    );
              return SizedBox(
                key: ValueKey(
                  hasPhoto ? 'member-photo-header' : 'member-initial-header',
                ),
                height: height,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (hasPhoto)
                      _photo(
                        large: true,
                        width: constraints.maxWidth,
                        height: height,
                      )
                    else
                      ColoredBox(
                        color: AritoriaColors.softOlive,
                        child: Center(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              widget.member.name.trim().isEmpty
                                  ? '?'
                                  : widget.member.name.trim().characters.first,
                              style: AritoriaType.brand.copyWith(
                                fontSize: 84,
                                color: AritoriaColors.sage,
                              ),
                            ),
                          ),
                        ),
                      ),
                    Align(alignment: Alignment.topCenter, child: _controls()),
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
            padding: EdgeInsets.fromLTRB(
              24,
              0,
              24,
              widget.member.linkedAccountId == null ? 20 : 32,
            ),
            child: identity,
          ),
        ],
      );
    },
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
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                minimumSize: const Size(0, 32),
              ),
            );
      if (constraints.maxWidth < 300 ||
          MediaQuery.textScalerOf(context).scale(1) > 1.3 ||
          member.linkedAccountId == null) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            identity,
            SizedBox(height: member.linkedAccountId == null ? 6 : 12),
            status,
          ],
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
  Widget build(BuildContext context) => CustomPaint(
    painter: const _MomentCardBackground(),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'PREGUNTA DEL MOMENTO',
            style: AritoriaType.caption.copyWith(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: .6,
              color: AritoriaColors.moss,
            ),
          ),
          const SizedBox(height: 12),
          QuestionText(question.text, style: AritoriaType.question),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: onAsk,
              label: const Text('Hacerle esta pregunta'),
              icon: const Icon(Icons.arrow_forward, size: 18),
              iconAlignment: IconAlignment.end,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 10),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _MomentCardBackground extends CustomPainter {
  const _MomentCardBackground();

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(20),
    );
    canvas.drawRRect(
      bounds,
      Paint()
        ..color = Color.lerp(
          AritoriaColors.cream,
          AritoriaColors.softOlive,
          .65,
        )!,
    );
    final curve = Path()
      ..moveTo(size.width * .62, size.height)
      ..cubicTo(
        size.width * .72,
        size.height * .87,
        size.width * .9,
        size.height * .99,
        size.width,
        size.height * .56,
      )
      ..lineTo(size.width, size.height)
      ..close();
    canvas.save();
    canvas.clipRRect(bounds);
    canvas.drawPath(
      curve,
      Paint()
        ..color = Color.lerp(
          AritoriaColors.softOlive,
          AritoriaColors.sage,
          .2,
        )!,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_MomentCardBackground oldDelegate) => false;
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
