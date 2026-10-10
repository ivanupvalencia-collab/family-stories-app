import 'dart:async';

import 'package:flutter/material.dart';

import '../design/aritoria_design.dart';
import '../widgets/family_member_space_view.dart';
import '../services/question_of_the_day.dart';
import '../services/story_photo_service.dart';
import '../models/question.dart';
import 'edit_family_member_screen.dart';
import 'invitation_details_screen.dart';
import 'answer_options_screen.dart';

import '../models/family_member.dart';
import '../models/family_story.dart';
import '../services/auth_service.dart';
import '../services/family_member_service.dart';
import '../services/family_member_deletion_service.dart';
import '../services/family_member_storage.dart';
import '../services/family_member_photo_service.dart';
import '../services/profile_image_picker.dart';
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
    this.storyPhotoService,
    this.deletionService,
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
  final StoryPhotoService? storyPhotoService;
  final FamilyMemberDeletionService? deletionService;

  @override
  State<FamilyMemberScreen> createState() => _FamilyMemberScreenState();
}

class _FamilyMemberScreenState extends State<FamilyMemberScreen>
    with WidgetsBindingObserver {
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
  bool _deleting = false;
  bool _deleteDialogOpen = false;
  late final FamilyMemberDeletionService _deletionService;
  late final StoryPhotoService _storyPhotos;
  DateTime _day = DateTime.now();

  bool get _canManagePhoto => widget.isRemoteFamilyMember
      ? _photoOwnerId != null &&
            widget.authService.currentUser?.id == _photoOwnerId
      : widget.authService.currentUser == null;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _familyMember = widget.familyMember;
    _deletionService =
        widget.deletionService ?? SupabaseFamilyMemberDeletionService();
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
      if (mounted) {
        setState(() {
          if (!_canManagePhoto) {
            _storiesLoadRequest++;
            _stories.clear();
            _isLoading = false;
          }
        });
      }
    });
    _storyStorage = widget.familyStoryStorage ?? LocalFamilyStoryStorage();
    _storyPhotos =
        widget.storyPhotoService ??
        (widget.isRemoteFamilyMember
            ? SupabaseStoryPhotoService()
            : LocalStoryPhotoService(storage: _storyStorage));
    _remoteStoryService = widget.isRemoteFamilyMember
        ? widget.familyStoryService ?? SupabaseFamilyStoryService()
        : null;
    _loadStories();
    unawaited(_refreshRemoteFamilyMember());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_photoAuthSubscription.cancel());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        mounted &&
        _canManagePhoto &&
        !_deleting) {
      unawaited(_refreshRemoteData());
    }
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
        _day = DateTime.now();
        _stories
          ..clear()
          ..addAll(stories);
        _stories.sort((a, b) => b.createdAt.compareTo(a.createdAt));
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

  Future<void> _openQuestions({Question? question}) async {
    await _refreshRemoteFamilyMember();
    if (!mounted) {
      return;
    }
    final storySaved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (context) => question == null
            ? QuestionsScreen(
                familyMember: _familyMember,
                familyStoryStorage: _storyStorage,
                authService: widget.authService,
                invitationService: widget.invitationService,
                invitationShareService: widget.invitationShareService,
                questionRequestService: widget.questionRequestService,
                familyMemberService: widget.familyMemberService,
                isRemoteFamilyMember: widget.isRemoteFamilyMember,
              )
            : AnswerOptionsScreen(
                familyMember: _familyMember,
                question: question,
                familyStoryStorage: _storyStorage,
                authService: widget.authService,
                invitationService: widget.invitationService,
                invitationShareService: widget.invitationShareService,
                familyMemberService: widget.familyMemberService,
                questionRequestService: widget.questionRequestService,
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
      if (mounted && _canManagePhoto && refreshedMember != null) {
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
        builder: (context) => StoryScreen(
          story: story,
          remoteStoryService: _remoteStoryService,
          photoService: _storyPhotos,
          imagePicker: widget.imagePicker,
        ),
      ),
    );
    if (mounted) {
      await _loadStories();
    }
  }

  Future<void> _refreshRemoteData() async {
    await Future.wait([
      _refreshRemoteFamilyMember(showError: true),
      _loadStories(),
    ]);
  }

  Future<void> _invite() async {
    if (!widget.isRemoteFamilyMember || !_canManagePhoto) {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Necesitas iniciar sesión'),
          content: const Text(
            'Inicia sesión para invitar y conectar con otras personas.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Entendido'),
            ),
          ],
        ),
      );
      return;
    }
    try {
      final invitation = await widget.invitationService.createInvitation(
        _familyMember.id,
      );
      if (mounted && _canManagePhoto) {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => InvitationDetailsScreen(
              familyMemberName: _familyMember.name,
              invitation: invitation,
              shareService: widget.invitationShareService,
            ),
          ),
        );
      }
    } catch (_) {
      _message('No se pudo crear la invitación. Inténtalo de nuevo.');
    }
    if (mounted) await _refreshRemoteFamilyMember();
  }

  void _message(String text) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    }
  }

  Future<void> _edit() async {
    if (!_canManagePhoto) return;
    final edited = await Navigator.push<FamilyMember>(
      context,
      MaterialPageRoute(
        builder: (_) => Theme(
          data: AritoriaDesign.theme(),
          child: EditFamilyMemberScreen(member: _familyMember),
        ),
      ),
    );
    if (!mounted || !_canManagePhoto || edited == null) return;
    try {
      FamilyMember updated;
      if (widget.isRemoteFamilyMember) {
        final service = widget.familyMemberService;
        if (service is! FamilyMemberInfoEditor) {
          throw StateError('Editor unavailable');
        }
        updated = await (service as FamilyMemberInfoEditor).editInformation(
          ownerId: _photoOwnerId!,
          familyMemberId: edited.id,
          name: edited.name,
          relationship: edited.relationship,
        );
      } else {
        final storage =
            widget.familyMemberStorage ??
            SharedPreferencesFamilyMemberStorage();
        final members = await storage.load();
        final index = members.indexWhere((m) => m.id == edited.id);
        if (index < 0) throw StateError('Member unavailable');
        final current = members[index];
        updated = FamilyMember(
          id: current.id,
          name: edited.name,
          relationship: edited.relationship,
          linkedAccountId: current.linkedAccountId,
          photoPath: current.photoPath,
        );
        members[index] = updated;
        await storage.save(members);
      }
      if (mounted && _canManagePhoto) setState(() => _familyMember = updated);
    } catch (_) {
      _message('No se pudo guardar la información. Inténtalo de nuevo.');
    }
  }

  Future<void> _delete() async {
    if (!_canManagePhoto || _deleting || _deleteDialogOpen || _photoBusy) {
      return;
    }
    if (widget.isRemoteFamilyMember && !_deletionService.enabled) {
      _message(
        'La eliminación de seres queridos de tu cuenta todavía no está disponible.',
      );
      return;
    }
    _deleteDialogOpen = true;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar ser querido'),
        content: Text(
          'Se eliminarán ${_familyMember.name}, sus historias y sus archivos. Esta acción no se puede deshacer.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Eliminar', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    _deleteDialogOpen = false;
    if (confirmed != true || !mounted || !_canManagePhoto) return;
    setState(() => _deleting = true);
    try {
      if (widget.isRemoteFamilyMember) {
        final account = _photoOwnerId!;
        final plan = await _deletionService.delete(
          ownerId: account,
          familyMemberId: _familyMember.id,
        );
        final service = widget.familyMemberService;
        if (service is FamilyMemberCacheRemover) {
          await (service as FamilyMemberCacheRemover).forgetMember(
            account,
            _familyMember.id,
          );
        }
        await _photoService.forgetPhotos(
          account,
          plan.resources
              .where((r) => r.bucket == 'family-member-photos')
              .map((r) => r.path),
        );
        await _storyPhotos.forgetPhotos(
          account,
          plan.resources
              .where((r) => r.bucket == 'story-photos')
              .map((r) => r.path),
        );
        await _remoteStoryService?.clearAudioCache();
      } else {
        if (_storyStorage is! LocalFamilyStoryStorage) {
          throw StateError('Safe deletion unavailable');
        }
        await (_storyStorage).deleteFamily(
          _familyMember.id,
          widget.familyMemberStorage ?? SharedPreferencesFamilyMemberStorage(),
        );
      }
      _storiesLoadRequest++;
      _stories.clear();
      if (mounted && _canManagePhoto) Navigator.pop(context);
    } catch (_) {
      if (mounted && _canManagePhoto && widget.isRemoteFamilyMember) {
        await _refreshRemoteFamilyMember();
        if (mounted && _canManagePhoto) await _loadStories();
      }
      _message(
        'No se ha confirmado la eliminación. Puedes volver a intentarlo para completar la limpieza.',
      );
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  void _menuAction(String action) {
    switch (action) {
      case 'edit':
        _edit();
      case 'photo':
        _managePhoto(false);
      case 'removePhoto':
        _managePhoto(true);
      case 'delete':
        _delete();
      case 'refresh':
        _refreshRemoteData();
    }
  }

  Future<void> _allStories() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Theme(
          data: AritoriaDesign.theme(),
          child: Scaffold(
            appBar: AppBar(title: const Text('Sus historias')),
            body: StatefulBuilder(
              builder: (listContext, updateList) => ListView(
                padding: const EdgeInsets.all(24),
                children: _stories
                    .map(
                      (story) => StoryMemoryRow(
                        story: story,
                        photos: _storyPhotos,
                        onTap: () async {
                          await _openStory(story);
                          if (listContext.mounted) updateList(() {});
                        },
                      ),
                    )
                    .toList(),
              ),
            ),
          ),
        ),
      ),
    );
    if (mounted) await _loadStories();
  }

  @override
  Widget build(BuildContext context) => Theme(
    data: AritoriaDesign.theme(),
    child: Scaffold(
      body: PopScope(
        canPop: !_deleting,
        child: Stack(
          children: [
            AbsorbPointer(
              absorbing: _deleting,
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: AritoriaSpace.maxWidth,
                  ),
                  child: FamilyMemberSpaceView(
                    member: _canManagePhoto
                        ? _familyMember
                        : _familyMember.withPhotoPath(null),
                    photos: _photoService,
                    storyPhotos: _storyPhotos,
                    stories: _stories,
                    question: questionOfTheDay(
                      _familyMember.id,
                      _day,
                      _stories,
                    ),
                    loading: _isLoading,
                    failed: _storiesLoadFailed,
                    onRetry: _loadStories,
                    onBack: () => Navigator.maybePop(context),
                    onInvite: _invite,
                    onAsk: () => _openQuestions(
                      question: questionOfTheDay(
                        _familyMember.id,
                        _day,
                        _stories,
                      ),
                    ),
                    onQuestions: _openQuestions,
                    onStory: _openStory,
                    onAllStories: _allStories,
                    onRefresh: _refreshRemoteData,
                    menu: PopupMenuButton<String>(
                      tooltip: 'Opciones del ser querido',
                      enabled:
                          _canManagePhoto &&
                          !_photoBusy &&
                          !_isRefreshingMember &&
                          !_deleting,
                      icon: const Icon(Icons.more_horiz),
                      onSelected: _menuAction,
                      itemBuilder: (_) => [
                        const PopupMenuItem(
                          value: 'edit',
                          child: Text('Editar informaci\u00f3n'),
                        ),
                        const PopupMenuItem(
                          value: 'photo',
                          child: Text('Cambiar foto'),
                        ),
                        if (_familyMember.photoPath != null)
                          const PopupMenuItem(
                            value: 'removePhoto',
                            child: Text('Eliminar foto'),
                          ),
                        PopupMenuItem(
                          value: 'delete',
                          child: Text(
                            'Eliminar ser querido',
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ),
                        if (widget.isRemoteFamilyMember)
                          const PopupMenuItem(
                            value: 'refresh',
                            child: Text('Actualizar familiar'),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            if (_deleting)
              const Positioned.fill(
                child: ColoredBox(
                  color: Color(0x66000000),
                  child: Center(child: CircularProgressIndicator()),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}
