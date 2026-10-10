import 'dart:async';

import 'package:flutter/material.dart';

import '../models/family_member.dart';
import '../models/family_story.dart';
import '../services/auth_service.dart';
import '../services/family_member_service.dart';
import '../services/family_member_storage.dart';
import '../services/family_member_photo_service.dart';
import '../services/profile_image_picker.dart';
import '../widgets/family_member_photo_view.dart';
import '../services/family_story_storage.dart';
import '../services/family_story_service.dart';
import '../services/invitation_service.dart';
import '../services/invitation_share_service.dart';
import '../services/question_request_service.dart';
import 'questions_screen.dart';
import 'story_screen.dart';

class FamilyMemberScreen extends StatefulWidget {
  const FamilyMemberScreen({
    required this.familyMember,
    required this.authService,
    required this.familyMemberService,
    required this.invitationService,
    required this.invitationShareService,
    required this.questionRequestService,
    required this.isRemoteFamilyMember,
    this.familyStoryStorage,
    this.familyStoryService,
    this.familyMemberStorage,
    this.photoService,
    this.imagePicker,
    super.key,
  });

  final FamilyMember familyMember;
  final AuthService authService;
  final FamilyMemberService familyMemberService;
  final InvitationService invitationService;
  final InvitationShareService invitationShareService;
  final QuestionRequestService questionRequestService;
  final bool isRemoteFamilyMember;
  final FamilyStoryStorage? familyStoryStorage;
  final FamilyStoryService? familyStoryService;
  final FamilyMemberStorage? familyMemberStorage;
  final FamilyMemberPhotoService? photoService;
  final ProfileImagePicker? imagePicker;

  @override
  State<FamilyMemberScreen> createState() => _FamilyMemberScreenState();
}

class _FamilyMemberScreenState extends State<FamilyMemberScreen> {
  late final FamilyStoryStorage _storyStorage;
  late final FamilyStoryService? _remoteStoryService;
  late FamilyMember _familyMember;
  final List<FamilyStory> _stories = [];
  bool _isLoading = true;
  bool _storiesLoadFailed = false;
  bool _isRefreshingMember = false;
  int _storiesLoadRequest = 0;
  late final FamilyMemberPhotoService _photoService;
  late final String? _photoOwnerId;
  late final StreamSubscription<AuthUser?> _photoAuthSubscription;
  bool _photoBusy = false;

  bool get _canManagePhoto => widget.isRemoteFamilyMember
      ? _photoOwnerId != null &&
            widget.authService.currentUser?.id == _photoOwnerId
      : widget.authService.currentUser == null;

  @override
  void initState() {
    super.initState();
    _familyMember = widget.familyMember;
    _photoOwnerId = widget.authService.currentUser?.id;
    _photoService =
        widget.photoService ??
        (widget.isRemoteFamilyMember
            ? SupabaseFamilyMemberPhotoService(
                ownerId: _photoOwnerId ?? '',
                memberService: widget.familyMemberService,
              )
            : LocalFamilyMemberPhotoService(
                storage:
                    widget.familyMemberStorage ??
                    SharedPreferencesFamilyMemberStorage(),
              ));
    _photoAuthSubscription = widget.authService.authStateChanges.listen((_) {
      if (mounted) setState(() {});
    });
    _storyStorage = widget.familyStoryStorage ?? LocalFamilyStoryStorage();
    _remoteStoryService = widget.isRemoteFamilyMember
        ? widget.familyStoryService ?? SupabaseFamilyStoryService()
        : null;
    _loadStories();
    unawaited(_refreshRemoteFamilyMember());
  }

  @override
  void dispose() {
    unawaited(_photoAuthSubscription.cancel());
    super.dispose();
  }

  Future<void> _managePhoto(bool remove) async {
    if (!_canManagePhoto || _photoBusy || _isRefreshingMember) return;
    setState(() => _photoBusy = true);
    try {
      final image = remove
          ? null
          : await (widget.imagePicker ?? DeviceProfileImagePicker())
                .pickFromGallery();
      if (!mounted || !_canManagePhoto || (!remove && image == null)) return;
      final updated = await _photoService.save(_familyMember, image);
      if (mounted && _canManagePhoto) setState(() => _familyMember = updated);
    } catch (_) {
      if (mounted && _canManagePhoto) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'No se pudo guardar la foto. Usa una imagen de hasta 10 MB e inténtalo de nuevo.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _photoBusy = false);
    }
  }

  Future<void> _loadStories() async {
    final request = ++_storiesLoadRequest;
    setState(() {
      _isLoading = true;
      _storiesLoadFailed = false;
    });
    try {
      final stories =
          await (_remoteStoryService?.loadForFamily(widget.familyMember.id) ??
              _storyStorage.loadForFamily(widget.familyMember.id));
      if (!mounted || request != _storiesLoadRequest) {
        return;
      }
      setState(() {
        _stories
          ..clear()
          ..addAll(stories);
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted || request != _storiesLoadRequest) {
        return;
      }
      setState(() {
        _stories.clear();
        _isLoading = false;
        _storiesLoadFailed = true;
      });
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
          questionRequestService: widget.questionRequestService,
          familyMemberService: widget.familyMemberService,
          isRemoteFamilyMember: widget.isRemoteFamilyMember,
        ),
      ),
    );
    if (mounted && (storySaved == true || widget.isRemoteFamilyMember)) {
      await _loadStories();
    }
    await _refreshRemoteFamilyMember();
  }

  Future<void> _refreshRemoteFamilyMember({bool showError = false}) async {
    final user = widget.authService.currentUser;
    if (!widget.isRemoteFamilyMember ||
        user == null ||
        _isRefreshingMember ||
        _photoBusy) {
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

  Future<void> _openStory(FamilyStory story) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) =>
            StoryScreen(story: story, remoteStoryService: _remoteStoryService),
      ),
    );
    if (mounted && widget.isRemoteFamilyMember) {
      await _loadStories();
    }
  }

  Future<void> _refreshRemoteData() async {
    await Future.wait([
      _refreshRemoteFamilyMember(showError: true),
      _loadStories(),
    ]);
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
          PopupMenuButton<bool>(
            tooltip: 'Foto del familiar',
            enabled: _canManagePhoto && !_photoBusy && !_isRefreshingMember,
            onSelected: _managePhoto,
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: false,
                child: Text('Elegir foto de la galería'),
              ),
              if (_familyMember.photoPath != null)
                const PopupMenuItem(value: true, child: Text('Eliminar foto')),
            ],
            icon: const Icon(Icons.photo_camera_outlined),
          ),
          if (widget.isRemoteFamilyMember)
            IconButton(
              onPressed: _isRefreshingMember ? null : _refreshRemoteData,
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
                FamilyMemberPhotoView(
                  member: _canManagePhoto
                      ? _familyMember
                      : _familyMember.withPhotoPath(null),
                  photoService: _photoService,
                  radius: 40,
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
                else if (_storiesLoadFailed)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        children: [
                          Text(
                            'No se pudieron cargar sus historias.',
                            textAlign: TextAlign.center,
                            style: textTheme.bodyLarge?.copyWith(
                              color: theme.colorScheme.error,
                            ),
                          ),
                          const SizedBox(height: 8),
                          TextButton.icon(
                            onPressed: _loadStories,
                            icon: const Icon(Icons.refresh),
                            label: const Text('Reintentar'),
                          ),
                        ],
                      ),
                    ),
                  )
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
