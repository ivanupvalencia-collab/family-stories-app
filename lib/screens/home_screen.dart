import 'dart:async';

import 'package:flutter/material.dart';

import '../models/family_member.dart';
import '../models/question_request.dart';
import '../services/auth_service.dart';
import '../services/avatar_storage_service.dart';
import '../services/family_member_service.dart';
import '../services/family_member_photo_service.dart';
import '../services/family_member_storage.dart';
import '../services/family_story_storage.dart';
import '../services/family_story_service.dart';
import '../services/invitation_service.dart';
import '../services/invitation_share_service.dart';
import '../services/profile_image_picker.dart';
import '../services/profile_service.dart';
import '../services/question_request_service.dart';
import 'add_family_member_screen.dart';
import 'answer_screen.dart';
import 'family_member_screen.dart';
import 'profile_screen.dart';
import 'question_request_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    this.authService,
    this.profileService,
    this.profileImagePicker,
    this.avatarStorageService,
    this.familyMemberStorage,
    this.familyMemberService,
    this.familyMemberPhotoService,
    this.familyStoryStorage,
    this.familyStoryService,
    this.invitationService,
    this.invitationShareService,
    this.questionRequestService,
    super.key,
  });

  final AuthService? authService;
  final ProfileService? profileService;
  final ProfileImagePicker? profileImagePicker;
  final AvatarStorageService? avatarStorageService;
  final FamilyMemberStorage? familyMemberStorage;
  final FamilyMemberService? familyMemberService;
  final FamilyMemberPhotoService? familyMemberPhotoService;
  final FamilyStoryStorage? familyStoryStorage;
  final FamilyStoryService? familyStoryService;
  final InvitationService? invitationService;
  final InvitationShareService? invitationShareService;
  final QuestionRequestService? questionRequestService;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  late final AuthService _authService;
  late final FamilyMemberStorage _familyMemberStorage;
  late final FamilyMemberService _familyMemberService;
  late final InvitationService _invitationService;
  late final InvitationShareService _invitationShareService;
  late final QuestionRequestService _questionRequestService;
  late final FamilyStoryService _familyStoryService;
  late final ProfileService _profileService;
  late final StreamSubscription<AuthUser?> _authSubscription;
  StreamSubscription<void>? _questionRealtimeSubscription;
  String? _questionRealtimeUserId;
  int _questionRealtimeGeneration = 0;
  Timer? _questionRealtimeDebounce;
  final List<FamilyMember> _familyMembers = [];
  final List<QuestionRequest> _questionRequests = [];
  final List<QuestionRequest> _answeredRequests = [];
  bool _answersLoading = false;
  bool _answersLoadFailed = false;
  int _answersLoadRequest = 0;
  AuthUser? _user;
  bool _isLoading = true;
  bool _isSaving = false;
  bool _loadFailed = false;
  int _loadRequest = 0;
  bool _questionsLoading = false;
  bool _questionsLoadFailed = false;
  int _questionsLoadRequest = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _authService = widget.authService ?? SupabaseGoogleAuthService();
    _familyMemberStorage =
        widget.familyMemberStorage ?? SharedPreferencesFamilyMemberStorage();
    _familyMemberService =
        widget.familyMemberService ?? SupabaseFamilyMemberService();
    _invitationService =
        widget.invitationService ?? SupabaseInvitationService();
    _invitationShareService =
        widget.invitationShareService ?? PlatformInvitationShareService();
    _questionRequestService =
        widget.questionRequestService ?? SupabaseQuestionRequestService();
    _familyStoryService =
        widget.familyStoryService ?? SupabaseFamilyStoryService();
    _profileService = widget.profileService ?? SupabaseProfileService();
    _user = _authService.currentUser;
    _authSubscription = _authService.authStateChanges.listen(_applyAuthUser);
    _loadFamilyMembers();
    _loadReceivedRequests();
    _replaceQuestionRealtimeSubscription(_user);
    unawaited(_preloadProfile(_user));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _questionRealtimeGeneration++;
    _questionRealtimeDebounce?.cancel();
    unawaited(_questionRealtimeSubscription?.cancel());
    _authSubscription.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      unawaited(_refreshHome());
    }
  }

  void _applyAuthUser(AuthUser? user) {
    if (!mounted || _user?.id == user?.id) {
      return;
    }

    if (_user != null) {
      _profileService.clearCache();
    }
    unawaited(_familyStoryService.clearAudioCache());
    setState(() {
      _user = user;
      _familyMembers.clear();
      _questionRequests.clear();
      _answeredRequests.clear();
    });
    _loadFamilyMembers();
    _loadReceivedRequests();
    _replaceQuestionRealtimeSubscription(user);
    unawaited(_preloadProfile(user));
  }

  void _replaceQuestionRealtimeSubscription(AuthUser? user) {
    if (user != null &&
        _questionRealtimeUserId == user.id &&
        _questionRealtimeSubscription != null) {
      return;
    }

    final generation = ++_questionRealtimeGeneration;
    _questionRealtimeDebounce?.cancel();
    final previousSubscription = _questionRealtimeSubscription;
    _questionRealtimeSubscription = null;
    _questionRealtimeUserId = null;
    unawaited(previousSubscription?.cancel());

    if (!mounted ||
        generation != _questionRealtimeGeneration ||
        user == null ||
        _user?.id != user.id) {
      return;
    }

    try {
      _questionRealtimeUserId = user.id;
      _questionRealtimeSubscription = _questionRequestService
          .watchChangesForRecipient(user.id)
          .listen(
            (_) => _scheduleQuestionRequestsRefresh(user.id, generation),
            onError: (_) {
              // Normal loads and pull-to-refresh remain available.
            },
          );
    } catch (_) {
      _questionRealtimeUserId = null;
      _questionRealtimeSubscription = null;
    }
  }

  void _scheduleQuestionRequestsRefresh(String userId, int generation) {
    if (!mounted ||
        generation != _questionRealtimeGeneration ||
        _user?.id != userId) {
      return;
    }
    _questionRealtimeDebounce?.cancel();
    _questionRealtimeDebounce = Timer(const Duration(milliseconds: 150), () {
      if (mounted &&
          generation == _questionRealtimeGeneration &&
          _user?.id == userId) {
        unawaited(_loadReceivedRequests());
      }
    });
  }

  Future<void> _refreshHome() async {
    _questionRealtimeDebounce?.cancel();
    await Future.wait([_loadFamilyMembers(), _loadReceivedRequests()]);
  }

  Future<void> _preloadProfile(AuthUser? user) async {
    if (user == null) {
      return;
    }

    try {
      await _profileService.loadForUser(user.id);
    } catch (_) {
      // ProfileScreen keeps its own retryable error state when opened.
    }
  }

  Future<void> _loadFamilyMembers() async {
    final request = ++_loadRequest;
    final user = _user;
    setState(() {
      _isLoading = true;
      _loadFailed = false;
    });

    try {
      final familyMembers = user == null
          ? await _familyMemberStorage.load()
          : await _familyMemberService.loadForOwner(user.id);
      if (!mounted || request != _loadRequest) {
        return;
      }
      setState(() {
        _familyMembers
          ..clear()
          ..addAll(familyMembers);
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted || request != _loadRequest) {
        return;
      }
      setState(() {
        _familyMembers.clear();
        _isLoading = false;
        _loadFailed = true;
      });
    }
  }

  Future<void> _loadReceivedRequests() async {
    await Future.wait([_loadQuestionRequests(), _loadAnsweredRequests()]);
  }

  Future<void> _loadAnsweredRequests() async {
    final request = ++_answersLoadRequest;
    final user = _user;
    setState(() {
      _answeredRequests.clear();
      _answersLoading = user != null;
      _answersLoadFailed = false;
    });
    if (user == null) return;
    try {
      final answers = await _questionRequestService.loadAnsweredForRecipient(
        user.id,
      );
      if (!mounted || request != _answersLoadRequest || _user?.id != user.id) {
        return;
      }
      setState(() {
        _answeredRequests.addAll(answers);
        _answersLoading = false;
      });
    } catch (_) {
      if (!mounted || request != _answersLoadRequest || _user?.id != user.id) {
        return;
      }
      setState(() {
        _answersLoading = false;
        _answersLoadFailed = true;
      });
    }
  }

  void _openAnswer(QuestionRequest request) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => AnswerScreen(
          questionRequest: request,
          questionRequestService: _questionRequestService,
          familyStoryService: _familyStoryService,
          authService: _authService,
        ),
      ),
    );
  }

  String _answerDate(DateTime date) {
    final local = date.toLocal();
    return '${local.day.toString().padLeft(2, '0')}/'
        '${local.month.toString().padLeft(2, '0')}/${local.year}';
  }

  Future<void> _loadQuestionRequests() async {
    final request = ++_questionsLoadRequest;
    final user = _user;
    if (user == null) {
      setState(() {
        _questionRequests.clear();
        _questionsLoading = false;
        _questionsLoadFailed = false;
      });
      return;
    }

    setState(() {
      _questionRequests.clear();
      _questionsLoading = true;
      _questionsLoadFailed = false;
    });

    try {
      final questionRequests = await _questionRequestService
          .loadPendingForRecipient(user.id);
      if (!mounted ||
          request != _questionsLoadRequest ||
          _user?.id != user.id) {
        return;
      }
      setState(() {
        _questionRequests.addAll(questionRequests);
        _questionsLoading = false;
      });
    } catch (_) {
      if (!mounted ||
          request != _questionsLoadRequest ||
          _user?.id != user.id) {
        return;
      }
      setState(() {
        _questionRequests.clear();
        _questionsLoading = false;
        _questionsLoadFailed = true;
      });
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _addFamilyMember() async {
    final creationUser = _user;
    final photoService = _photoServiceFor(creationUser);
    final draft = await Navigator.of(context).push<FamilyMemberDraft>(
      MaterialPageRoute(
        builder: (context) => AddFamilyMemberScreen(
          imagePicker: widget.profileImagePicker ?? DeviceProfileImagePicker(),
          photoService: photoService,
        ),
      ),
    );

    if (draft == null || !mounted || _user?.id != creationUser?.id) {
      return;
    }

    final familyMember = draft.member;
    final user = _user;
    setState(() => _isSaving = true);
    try {
      var savedMember = user == null
          ? await _saveLocalFamilyMember(familyMember)
          : await _familyMemberService.create(
              ownerId: user.id,
              name: familyMember.name,
              relationship: familyMember.relationship,
            );
      if (!mounted || _user?.id != user?.id) {
        return;
      }
      if (draft.photo != null) {
        try {
          savedMember = await photoService.save(savedMember, draft.photo);
        } catch (_) {
          if (mounted && _user?.id == user?.id) {
            _showMessage(
              'El familiar se ha guardado, pero no su foto. Puedes añadirla desde su perfil.',
            );
          }
        }
      }
      if (!mounted || _user?.id != user?.id) return;
      setState(() {
        _familyMembers.add(savedMember);
      });
    } catch (_) {
      if (mounted) {
        _showMessage('No se pudo guardar el familiar. Inténtalo de nuevo.');
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Future<FamilyMember> _saveLocalFamilyMember(FamilyMember familyMember) async {
    final current = await _familyMemberStorage.load();
    await _familyMemberStorage.save([...current, familyMember]);
    return familyMember;
  }

  FamilyMemberPhotoService _photoServiceFor(AuthUser? user) =>
      widget.familyMemberPhotoService ??
      (user == null
          ? LocalFamilyMemberPhotoService(storage: _familyMemberStorage)
          : SupabaseFamilyMemberPhotoService(
              ownerId: user.id,
              memberService: _familyMemberService,
            ));

  Future<void> _openFamilyMember(FamilyMember familyMember) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => FamilyMemberScreen(
          familyMember: familyMember,
          authService: _authService,
          familyMemberService: _familyMemberService,
          invitationService: _invitationService,
          invitationShareService: _invitationShareService,
          questionRequestService: _questionRequestService,
          isRemoteFamilyMember: _user != null,
          familyStoryStorage: widget.familyStoryStorage,
          familyStoryService: _familyStoryService,
          familyMemberStorage: _familyMemberStorage,
          photoService: _photoServiceFor(_user),
          imagePicker: widget.profileImagePicker ?? DeviceProfileImagePicker(),
        ),
      ),
    );
    if (mounted) {
      await _loadFamilyMembers();
    }
  }

  void _openProfile() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => ProfileScreen(
          authService: _authService,
          profileService: _profileService,
          profileImagePicker: widget.profileImagePicker,
          avatarStorageService: widget.avatarStorageService,
          invitationService: _invitationService,
        ),
      ),
    );
  }

  Future<void> _openQuestionRequest(QuestionRequest questionRequest) async {
    final sent = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (context) => QuestionRequestScreen(
          questionRequest: questionRequest,
          questionRequestService: _questionRequestService,
        ),
      ),
    );
    if (sent == true && mounted) {
      _showMessage('Respuesta enviada');
      await _loadReceivedRequests();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;

    return Scaffold(
      appBar: AppBar(
        actions: [
          IconButton(
            onPressed: _openProfile,
            tooltip: 'Perfil',
            icon: const Icon(Icons.account_circle_outlined),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 24),
                  Text(
                    'Family Stories',
                    style: textTheme.displaySmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Conserva las historias de las personas que quieres.',
                    style: textTheme.titleMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 32),
                  FilledButton.icon(
                    onPressed: _isLoading || _isSaving
                        ? null
                        : _addFamilyMember,
                    icon: const Icon(Icons.person_add_alt_1),
                    label: const Text('Añadir familiar'),
                  ),
                  const SizedBox(height: 32),
                  Expanded(
                    child: RefreshIndicator(
                      onRefresh: _refreshHome,
                      child: ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: [
                          if (_user != null &&
                              (_questionsLoading ||
                                  _questionsLoadFailed ||
                                  _questionRequests.isNotEmpty)) ...[
                            Text(
                              'Preguntas para ti',
                              style: textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 16),
                            if (_questionsLoading)
                              const Center(
                                child: Padding(
                                  padding: EdgeInsets.all(16),
                                  child: CircularProgressIndicator(),
                                ),
                              )
                            else if (_questionsLoadFailed)
                              _QuestionRequestsLoadError(
                                onRetry: _loadQuestionRequests,
                              )
                            else
                              ..._questionRequests.map(
                                (questionRequest) => Card(
                                  margin: const EdgeInsets.only(bottom: 8),
                                  child: ListTile(
                                    leading: const CircleAvatar(
                                      child: Icon(Icons.markunread_outlined),
                                    ),
                                    title: Text(questionRequest.questionText),
                                    subtitle: const Text(
                                      'Enviada por otro familiar · Pendiente',
                                    ),
                                    trailing: const Icon(Icons.chevron_right),
                                    onTap: () =>
                                        _openQuestionRequest(questionRequest),
                                  ),
                                ),
                              ),
                            const SizedBox(height: 32),
                          ],
                          if (_user != null) ...[
                            Text(
                              'Tus respuestas',
                              style: textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 16),
                            if (_answersLoading)
                              const Center(child: CircularProgressIndicator())
                            else if (_answersLoadFailed)
                              _QuestionRequestsLoadError(
                                message:
                                    'No se pudieron cargar tus respuestas.',
                                onRetry: _loadAnsweredRequests,
                              )
                            else if (_answeredRequests.isEmpty)
                              const Text(
                                'Todavía no has enviado ninguna respuesta.',
                              )
                            else
                              ..._answeredRequests.map(
                                (answer) => Card(
                                  margin: const EdgeInsets.only(bottom: 8),
                                  child: ListTile(
                                    leading: const CircleAvatar(
                                      child: Icon(Icons.headphones_outlined),
                                    ),
                                    title: Text(answer.questionText),
                                    subtitle: answer.answeredAt == null
                                        ? null
                                        : Text(
                                            'Respondida el ${_answerDate(answer.answeredAt!)}',
                                          ),
                                    trailing: const Icon(Icons.chevron_right),
                                    onTap: () => _openAnswer(answer),
                                  ),
                                ),
                              ),
                            const SizedBox(height: 32),
                          ],
                          Text(
                            'Tus familiares',
                            style: textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 16),
                          if (_isLoading)
                            const Center(
                              child: Padding(
                                padding: EdgeInsets.all(32),
                                child: CircularProgressIndicator(),
                              ),
                            )
                          else if (_loadFailed)
                            _FamilyMembersLoadError(onRetry: _loadFamilyMembers)
                          else if (_familyMembers.isEmpty)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 32),
                              child: Text(
                                'Todavía no has añadido ningún familiar.',
                                textAlign: TextAlign.center,
                                style: textTheme.bodyLarge?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            )
                          else
                            ..._familyMembers.map(
                              (familyMember) => Card(
                                margin: const EdgeInsets.only(bottom: 8),
                                child: ListTile(
                                  leading: const CircleAvatar(
                                    child: Icon(Icons.person_outline),
                                  ),
                                  title: Text(familyMember.name),
                                  subtitle: Text(familyMember.relationship),
                                  trailing: const Icon(Icons.chevron_right),
                                  onTap: () => _openFamilyMember(familyMember),
                                ),
                              ),
                            ),
                        ],
                      ),
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
}

class _FamilyMembersLoadError extends StatelessWidget {
  const _FamilyMembersLoadError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'No se pudieron cargar los familiares.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          TextButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('Reintentar'),
          ),
        ],
      ),
    );
  }
}

class _QuestionRequestsLoadError extends StatelessWidget {
  const _QuestionRequestsLoadError({
    required this.onRetry,
    this.message = 'No se pudieron cargar tus preguntas.',
  });

  final String message;

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
            TextButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Reintentar'),
            ),
          ],
        ),
      ),
    );
  }
}
