import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'question_text.dart';

import '../design/aritoria_design.dart';
import '../models/family_member.dart';
import '../models/profile_avatar.dart';
import '../models/question_request.dart';
import '../models/user_profile.dart';
import '../services/family_member_photo_service.dart';
import '../services/received_request_details_service.dart';
import 'family_member_photo_view.dart';
import 'account_avatar_view.dart';
import '../services/visible_account_avatar_service.dart';

FamilyMember? selectHomeHero(
  List<FamilyMember> members, {
  UserProfile? Function(String accountId)? linkedProfile,
}) {
  if (members.isEmpty) return null;
  return members.firstWhere((member) {
    if (member.photoPath != null) return true;
    final accountId = member.linkedAccountId;
    final profile = accountId == null ? null : linkedProfile?.call(accountId);
    return (profile?.avatarUrl?.trim().isNotEmpty ?? false) ||
        ProfileAvatarCatalog.findByKey(profile?.avatarKey) != null;
  }, orElse: () => members.first);
}

String requestDate(DateTime date) {
  final local = date.toLocal();
  return '${local.day.toString().padLeft(2, '0')}/${local.month.toString().padLeft(2, '0')}/${local.year}';
}

String requestSubtitle(
  QuestionRequest request,
  ReceivedRequestDetails? details,
) {
  final name = details?.senderName;
  final answered = request.status == QuestionRequestStatus.answered;
  final parts = <String>[
    if (name != null)
      '${answered ? 'Para' : 'De'} $name'
    else
      answered ? 'Para quien te preguntó' : 'Una pregunta para ti',
    if (answered && request.answeredAt != null)
      requestDate(request.answeredAt!)
    else if (!answered)
      requestDate(request.createdAt),
    if (answered && details?.durationSeconds != null)
      '${details!.durationSeconds! ~/ 60}:${(details.durationSeconds! % 60).toString().padLeft(2, '0')}',
  ];
  return parts.join(' · ');
}

class AritoriaHomeView extends StatelessWidget {
  const AritoriaHomeView({
    required this.members,
    required this.photos,
    required this.profile,
    required this.authenticated,
    required this.questions,
    required this.answers,
    required this.details,
    required this.memberStatus,
    required this.questionStatus,
    required this.answerStatus,
    required this.onRefresh,
    required this.onNotifications,
    required this.onAdd,
    required this.onMember,
    required this.onHero,
    required this.onAllMembers,
    required this.onAllQuestions,
    required this.onAllAnswers,
    required this.onQuestion,
    required this.onAnswer,
    this.avatarService,
    super.key,
  });

  final List<FamilyMember> members;
  final FamilyMemberPhotoService photos;
  final VisibleAccountAvatarService? avatarService;
  final UserProfile? profile;
  final bool authenticated;
  final List<QuestionRequest> questions;
  final List<QuestionRequest> answers;
  final Map<String, ReceivedRequestDetails> details;
  final Widget? memberStatus, questionStatus, answerStatus;
  final Future<void> Function() onRefresh;
  final VoidCallback onNotifications,
      onAdd,
      onAllMembers,
      onAllQuestions,
      onAllAnswers;
  final ValueChanged<FamilyMember> onMember;
  final ValueChanged<FamilyMember?> onHero;
  final ValueChanged<QuestionRequest> onQuestion, onAnswer;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        key: const ValueKey('home-scroll'),
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(
          AritoriaSpace.lg,
          AritoriaSpace.lg,
          AritoriaSpace.lg,
          AritoriaSpace.xl,
        ),
        children: [
          Row(
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Aritoria', style: AritoriaType.brand),
                    SizedBox(height: AritoriaSpace.xs),
                    Text('Family Stories', style: AritoriaType.caption),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Notificaciones',
                onPressed: onNotifications,
                icon: Badge(
                  isLabelVisible: authenticated && questions.isNotEmpty,
                  smallSize: 7,
                  backgroundColor: const Color(0xFFB75D48),
                  child: const Icon(
                    Icons.notifications_none_outlined,
                    size: 27,
                    color: AritoriaColors.ink,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AritoriaSpace.xl),
          _AutomaticHero(
            members: List.of(members),
            photos: photos,
            avatars: authenticated
                ? avatarService ?? SupabaseVisibleAccountAvatarService.shared
                : null,
            onTap: onHero,
          ),
          const SizedBox(height: AritoriaSpace.section),
          _SectionTitle(
            title: 'Tus seres queridos',
            action: 'Ver todos',
            onTap: onAllMembers,
          ),
          const SizedBox(height: AritoriaSpace.md),
          if (memberStatus != null)
            memberStatus!
          else
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final member in members)
                    Padding(
                      padding: const EdgeInsets.only(right: AritoriaSpace.md),
                      child: _Person(
                        member: member,
                        photos: photos,
                        onTap: () => onMember(member),
                      ),
                    ),
                  SizedBox(
                    width: 80,
                    child: InkWell(
                      onTap: onAdd,
                      borderRadius: BorderRadius.circular(AritoriaSpace.sm),
                      child: Column(
                        children: [
                          Container(
                            width: 64,
                            height: 64,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: AritoriaColors.taupe),
                            ),
                            child: const Icon(
                              Icons.add,
                              color: AritoriaColors.olive,
                            ),
                          ),
                          const SizedBox(height: AritoriaSpace.sm),
                          const Text('Añadir', style: AritoriaType.action),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          if (authenticated) ...[
            const SizedBox(height: AritoriaSpace.section),
            _SectionTitle(
              title: 'Preguntas para ti',
              action: questions.isNotEmpty ? 'Ver todas' : null,
              onTap: onAllQuestions,
            ),
            const SizedBox(height: AritoriaSpace.sm),
            if (questionStatus != null)
              questionStatus!
            else if (questions.isEmpty)
              const _Empty('No tienes preguntas pendientes.')
            else
              for (final request in questions.take(2))
                ReceivedRequestRow(
                  request: request,
                  details: details[request.id],
                  onTap: () => onQuestion(request),
                ),
            const SizedBox(height: AritoriaSpace.xl),
            _SectionTitle(
              title: 'Historias contadas',
              action: answers.length > 2 ? 'Ver todas' : null,
              onTap: onAllAnswers,
            ),
            const SizedBox(height: AritoriaSpace.sm),
            if (answerStatus != null)
              answerStatus!
            else if (answers.isEmpty)
              const _Empty('Todavía no has contado ninguna historia.')
            else
              for (final request in answers.take(2))
                ReceivedRequestRow(
                  request: request,
                  details: details[request.id],
                  onTap: () => onAnswer(request),
                ),
          ],
        ],
      ),
    );
  }
}

// Resolve linked metadata independently of the rest of Home. Reuse its
// account-scoped cache for both selection and the rendered hero image.
class _AutomaticHero extends StatefulWidget {
  const _AutomaticHero({
    required this.members,
    required this.photos,
    required this.avatars,
    required this.onTap,
  });

  final List<FamilyMember> members;
  final FamilyMemberPhotoService photos;
  final VisibleAccountAvatarService? avatars;
  final ValueChanged<FamilyMember?> onTap;

  @override
  State<_AutomaticHero> createState() => _AutomaticHeroState();
}

class _AutomaticHeroState extends State<_AutomaticHero> {
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    widget.avatars?.addListener(_avatarsChanged);
    unawaited(_loadAvatars());
  }

  Future<void> _loadAvatars() async {
    final generation = ++_generation;
    final service = widget.avatars;
    if (service == null) return;
    final accounts = {
      for (final member in widget.members)
        if (member.photoPath == null && member.linkedAccountId != null)
          member.linkedAccountId!,
    };
    await Future.wait(
      accounts.map((account) async {
        try {
          await service.load(account);
        } catch (_) {
          // Optional metadata: keep selecting from the available own photos.
        }
      }),
    );
    if (mounted && generation == _generation) setState(() {});
  }

  void _avatarsChanged() {
    setState(() {});
    unawaited(_loadAvatars());
  }

  @override
  void didUpdateWidget(_AutomaticHero oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.avatars != widget.avatars) {
      oldWidget.avatars?.removeListener(_avatarsChanged);
      widget.avatars?.addListener(_avatarsChanged);
    }
    if (oldWidget.avatars != widget.avatars ||
        !listEquals(oldWidget.members, widget.members)) {
      unawaited(_loadAvatars());
    }
  }

  @override
  void dispose() {
    _generation++;
    widget.avatars?.removeListener(_avatarsChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final member = selectHomeHero(
      widget.members,
      linkedProfile: widget.avatars?.cached,
    );
    return _Hero(
      member: member,
      photos: widget.photos,
      avatars: widget.avatars,
      onTap: () => widget.onTap(member),
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({
    required this.member,
    required this.photos,
    required this.onTap,
    this.avatars,
  });
  final FamilyMember? member;
  final FamilyMemberPhotoService photos;
  final VisibleAccountAvatarService? avatars;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, layout) => ClipRRect(
      key: const ValueKey('home-hero'),
      borderRadius: BorderRadius.circular(AritoriaSpace.heroRadius),
      child: Stack(
        children: [
          Positioned.fill(
            child: LayoutBuilder(
              builder: (context, constraints) => member == null
                  ? const ColoredBox(color: AritoriaColors.sand)
                  : FamilyMemberPhotoView(
                      member: member!,
                      photoService: photos,
                      avatarService: avatars,
                      circular: false,
                      alignment: const Alignment(0, -0.15),
                      width: constraints.maxWidth,
                      height: constraints.maxHeight,
                      fallback: const ColoredBox(color: AritoriaColors.sand),
                    ),
            ),
          ),
          Positioned.fill(
            child: LayoutBuilder(
              builder: (context, photo) => DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      AritoriaColors.transparent,
                      AritoriaColors.photoShadeMid,
                      AritoriaColors.photoShade,
                    ],
                    // Reach the readable shade where the title actually starts,
                    // including when accessibility text makes the hero taller.
                    stops: [
                      0,
                      ((layout.maxWidth * 0.15).clamp(
                                AritoriaSpace.heroAirMin,
                                AritoriaSpace.heroAirMax,
                              ) +
                              AritoriaSpace.lg) /
                          photo.maxHeight,
                      1,
                    ],
                  ),
                ),
              ),
            ),
          ),
          ConstrainedBox(
            constraints: const BoxConstraints(
              minHeight: AritoriaSpace.heroMinHeight,
            ),
            child: Padding(
              padding: const EdgeInsets.all(AritoriaSpace.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Keep photographic air proportional to width; content can grow
                  // freely for long names and larger accessibility text sizes.
                  SizedBox(
                    height: (layout.maxWidth * 0.15).clamp(
                      AritoriaSpace.heroAirMin,
                      AritoriaSpace.heroAirMax,
                    ),
                  ),
                  if (member == null)
                    const Text(
                      'Las historias de tu familia empiezan aquí',
                      style: AritoriaType.editorial,
                    )
                  else
                    _HeroTitle(name: member!.name),
                  const SizedBox(height: AritoriaSpace.md),
                  TextButton(
                    onPressed: onTap,
                    style: TextButton.styleFrom(
                      foregroundColor: AritoriaColors.onPhoto,
                      padding: EdgeInsets.zero,
                      alignment: Alignment.centerLeft,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            member == null
                                ? 'Añadir ser querido'
                                : 'Conoce su historia',
                            style: AritoriaType.action.copyWith(
                              color: AritoriaColors.onPhoto,
                            ),
                          ),
                        ),
                        const SizedBox(width: AritoriaSpace.sm),
                        const Icon(Icons.arrow_forward, size: 18),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _HeroTitle extends StatelessWidget {
  const _HeroTitle({required this.name});
  final String name;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      const opening = 'Hay historias que solo';
      final original = '$opening\n$name puede contarte';
      final style = DefaultTextStyle.of(context).style
          .merge(AritoriaType.editorial);
      final painter = TextPainter(
        text: TextSpan(text: opening, style: style),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
      )..layout();
      final fontSize =
          (style.fontSize! * (constraints.maxWidth - 1) / painter.width).clamp(
            style.fontSize! * AritoriaSpace.heroTitleMinScale,
            style.fontSize!,
          );
      final adjusted = style.copyWith(fontSize: fontSize);
      painter.text = TextSpan(text: opening, style: adjusted);
      painter.layout();
      final fits = painter.width <= constraints.maxWidth;
      painter.dispose();
      // A modest reduction keeps the opening on one line on normal mobile widths.
      // At narrow widths or large accessibility scales, keep "que solo" together
      // rather than shrinking the editorial title indefinitely.
      return Text(
        fits ? original : original.replaceFirst('que solo', 'que\u00a0solo'),
        style: adjusted,
        semanticsLabel: original,
      );
    },
  );
}

class _Person extends StatelessWidget {
  const _Person({
    required this.member,
    required this.photos,
    required this.onTap,
  });
  final FamilyMember member;
  final FamilyMemberPhotoService photos;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 80,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AritoriaSpace.sm),
      child: Column(
        children: [
          FamilyMemberPhotoView(
            member: member,
            photoService: photos,
            radius: AritoriaSpace.photoRadius,
          ),
          const SizedBox(height: AritoriaSpace.sm),
          Text(
            member.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: AritoriaType.body.copyWith(fontSize: 14),
          ),
        ],
      ),
    ),
  );
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, required this.onTap, this.action});
  final String title;
  final String? action;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => Row(
      children: [
        Expanded(child: Text(title, style: AritoriaType.homeSection)),
        if (action != null) ...[
          const SizedBox(width: AritoriaSpace.sm),
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: constraints.maxWidth * .4),
            child: TextButton(
              onPressed: onTap,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      action!,
                      style: AritoriaType.action.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(Icons.chevron_right, size: 18),
                ],
              ),
            ),
          ),
        ],
      ],
    ),
  );
}

class _Empty extends StatelessWidget {
  const _Empty(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: AritoriaSpace.md),
    child: Text(text, style: AritoriaType.caption.copyWith(fontSize: 14)),
  );
}

class ReceivedRequestRow extends StatelessWidget {
  const ReceivedRequestRow({
    required this.request,
    required this.onTap,
    this.details,
    this.avatarService,
    super.key,
  });
  final QuestionRequest request;
  final ReceivedRequestDetails? details;
  final VisibleAccountAvatarService? avatarService;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Column(
    children: [
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: request.status == QuestionRequestStatus.pending
            ? AccountAvatarView(
                accountId: request.senderId,
                service: avatarService,
                fallbackBuilder: (profile) =>
                    _SenderInitial(name: profile?.name ?? details?.senderName),
                fallback: _SenderInitial(name: details?.senderName),
              )
            : null,
        title: QuestionText(
          request.questionText,
          style: AritoriaType.body.copyWith(fontSize: 17, height: 1.3),
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: AritoriaSpace.xs),
          child: Text(
            requestSubtitle(request, details),
            style: AritoriaType.caption,
          ),
        ),
        trailing: Icon(
          request.status == QuestionRequestStatus.answered
              ? Icons.play_circle_outline
              : Icons.chevron_right,
          color: AritoriaColors.olive,
        ),
        onTap: onTap,
      ),
      const Divider(height: 1),
    ],
  );
}

class _SenderInitial extends StatelessWidget {
  const _SenderInitial({this.name});
  final String? name;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: AritoriaColors.softOlive,
    child: Center(
      child: Text(
        (name?.trim().isNotEmpty ?? false)
            ? name!.trim().characters.first.toUpperCase()
            : '?',
        style: AritoriaType.body.copyWith(
          fontSize: 22,
          color: AritoriaColors.moss,
        ),
      ),
    ),
  );
}

class AritoriaNavigation extends StatelessWidget {
  const AritoriaNavigation({
    required this.selected,
    required this.onSelect,
    super.key,
  });
  final int selected;
  final ValueChanged<int> onSelect;
  @override
  Widget build(BuildContext context) => Material(
    color: AritoriaColors.cream,
    child: SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AritoriaSpace.sm,
          vertical: AritoriaSpace.sm,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            _item(0, 'Inicio', Icons.home_outlined),
            _item(1, 'Familia', Icons.people_outline),
            Expanded(
              child: Center(
                heightFactor: 1,
                child: IconButton.filled(
                  tooltip: 'Crear',
                  onPressed: () => onSelect(2),
                  style: IconButton.styleFrom(
                    backgroundColor: AritoriaColors.olive,
                    foregroundColor: AritoriaColors.onPhoto,
                    fixedSize: const Size(48, 48),
                  ),
                  icon: const Icon(Icons.add),
                ),
              ),
            ),
            _item(3, 'Preguntas', Icons.chat_bubble_outline),
            _item(4, 'Perfil', Icons.person_outline),
          ],
        ),
      ),
    ),
  );

  Widget _item(int index, String label, IconData icon) => Expanded(
    child: Tooltip(
      message: label,
      child: Semantics(
        selected: selected == index,
        button: true,
        child: InkWell(
          onTap: () => onSelect(index),
          borderRadius: BorderRadius.circular(AritoriaSpace.sm),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AritoriaSpace.sm),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: 23,
                  color: selected == index
                      ? AritoriaColors.olive
                      : AritoriaColors.muted,
                ),
                const SizedBox(height: AritoriaSpace.xs),
                Text(
                  label,
                  textAlign: TextAlign.center,
                  style: AritoriaType.caption.copyWith(
                    fontSize: 10,
                    color: selected == index
                        ? AritoriaColors.olive
                        : AritoriaColors.muted,
                    fontWeight: selected == index
                        ? FontWeight.w700
                        : FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
