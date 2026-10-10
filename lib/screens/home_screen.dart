import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

import '../design/aritoria_design.dart';
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
import '../services/received_request_details_service.dart';
import '../services/remote_family_member_cache.dart';
import '../widgets/aritoria_home_view.dart';
import '../widgets/family_member_photo_view.dart';
import 'add_family_member_screen.dart';
import 'answer_screen.dart';
import 'family_member_screen.dart';
import 'profile_screen.dart';
import 'question_request_screen.dart';
import 'questions_screen.dart';

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
    this.receivedRequestDetailsService,
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
  final ReceivedRequestDetailsService? receivedRequestDetailsService;

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
  late final ReceivedRequestDetailsService _detailsService;
  late FamilyMemberPhotoService _photos;
  final Map<String, ReceivedRequestDetails> _details = {};
  int _detailsGeneration = 0;
  int _section = 0;
  int _questionTab = 0;
  bool _profileOpen = false;
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
  bool _hasMembersSnapshot = false;
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
    _detailsService =
        widget.receivedRequestDetailsService ??
        SupabaseReceivedRequestDetailsService();
    _user = _authService.currentUser;
    _photos = _photoServiceFor(_user);
    _authSubscription = _authService.authStateChanges.listen(_applyAuthUser);
    _loadFamilyMembers(cacheFirst: true);
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
      _hasMembersSnapshot = false;
      _questionRequests.clear();
      _answeredRequests.clear();
      _details.clear();
      _detailsGeneration++;
      _photos = _photoServiceFor(user);
    });
    _loadFamilyMembers(cacheFirst: true);
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
      if (mounted && _user?.id == user.id) setState(() {});
    } catch (_) {
      // ProfileScreen keeps its own retryable error state when opened.
    }
  }

  Future<void> _loadFamilyMembers({bool cacheFirst = false}) async {
    final request = ++_loadRequest;
    final user = _user;
    if (_isLoading != !_hasMembersSnapshot || _loadFailed) {
      setState(() {
        _isLoading = !_hasMembersSnapshot;
        _loadFailed = false;
      });
    }

    try {
      final service = _familyMemberService;
      if (cacheFirst && user != null && service is CachedFamilyMemberService) {
        final cached = await (service as CachedFamilyMemberService)
            .loadCachedForOwner(user.id);
        if (!mounted || request != _loadRequest || _user?.id != user.id) return;
        if (cached != null) {
          // Warm only the hero and first portraits before publishing the
          // snapshot. The rest read disk on demand, never holding up Home.
          final hero = selectHomeHero(cached);
          await _photos.warmCachedPhotos({...cached.take(6), ?hero}.toList());
          if (!mounted || request != _loadRequest || _user?.id != user.id) {
            return;
          }
          setState(() {
            _familyMembers
              ..clear()
              ..addAll(cached);
            _hasMembersSnapshot = true;
            _isLoading = false;
          });
        }
      }
      final familyMembers = user == null
          ? await _familyMemberStorage.load()
          : await _familyMemberService.loadForOwner(user.id);
      if (!mounted || request != _loadRequest) {
        return;
      }
      if (!_sameMembers(_familyMembers, familyMembers) ||
          _isLoading ||
          !_hasMembersSnapshot) {
        setState(() {
          if (!_sameMembers(_familyMembers, familyMembers)) {
            _familyMembers
              ..clear()
              ..addAll(familyMembers);
          }
          _hasMembersSnapshot = true;
          _isLoading = false;
        });
      }
      if (user != null) {
        // Full, authoritative lists prune old photo paths and deleted members.
        unawaited(
          _photos.retainPhotos(familyMembers).catchError((Object _) {}),
        );
      }
    } catch (_) {
      if (!mounted || request != _loadRequest) {
        return;
      }
      setState(() {
        _isLoading = false;
        _loadFailed = !_hasMembersSnapshot;
      });
    }
  }

  bool _sameMembers(List<FamilyMember> a, List<FamilyMember> b) =>
      a.length == b.length &&
      List.generate(
        a.length,
        (i) => mapEquals(a[i].toJson(), b[i].toJson()),
      ).every((same) => same);

  Future<void> _loadReceivedRequests() async {
    final generation = ++_detailsGeneration;
    final userId = _user?.id;
    await Future.wait([_loadQuestionRequests(), _loadAnsweredRequests()]);
    if (!mounted ||
        userId == null ||
        _user?.id != userId ||
        generation != _detailsGeneration) {
      return;
    }
    try {
      final details = await _detailsService.load([
        ..._questionRequests.map((r) => r.id),
        ..._answeredRequests.map((r) => r.id),
      ]);
      if (mounted &&
          _user?.id == userId &&
          generation == _detailsGeneration &&
          !_sameDetails(_details, details)) {
        setState(() {
          _details
            ..clear()
            ..addAll(details);
        });
      }
    } catch (_) {
      // Optional manual RPC: questions and playback work without enrichment.
    }
  }

  bool _sameDetails(
    Map<String, ReceivedRequestDetails> a,
    Map<String, ReceivedRequestDetails> b,
  ) =>
      a.length == b.length &&
      a.keys.every(
        (id) =>
            b.containsKey(id) &&
            a[id]!.senderName == b[id]!.senderName &&
            a[id]!.durationSeconds == b[id]!.durationSeconds,
      );

  bool _sameRequests(List<QuestionRequest> a, List<QuestionRequest> b) =>
      a.length == b.length &&
      List.generate(
        a.length,
        (i) =>
            a[i].id == b[i].id &&
            a[i].questionText == b[i].questionText &&
            a[i].senderId == b[i].senderId &&
            a[i].recipientId == b[i].recipientId &&
            a[i].familyMemberId == b[i].familyMemberId &&
            a[i].status == b[i].status &&
            a[i].createdAt == b[i].createdAt &&
            a[i].answeredAt == b[i].answeredAt,
      ).every((same) => same);

  Future<void> _loadAnsweredRequests() async {
    final request = ++_answersLoadRequest;
    final user = _user;
    setState(() {
      if (user == null) _answeredRequests.clear();
      _answersLoading = user != null && _answeredRequests.isEmpty;
      _answersLoadFailed = false;
    });
    if (user == null) return;
    try {
      final answers = await _questionRequestService.loadAnsweredForRecipient(
        user.id,
      );
      answers.sort((a, b) {
        if (a.answeredAt == null && b.answeredAt != null) return 1;
        if (a.answeredAt != null && b.answeredAt == null) return -1;
        return (b.answeredAt ?? b.createdAt).compareTo(
          a.answeredAt ?? a.createdAt,
        );
      });
      if (!mounted || request != _answersLoadRequest || _user?.id != user.id) {
        return;
      }
      if (!_sameRequests(_answeredRequests, answers) || _answersLoading) {
        setState(() {
          if (!_sameRequests(_answeredRequests, answers)) {
            _answeredRequests
              ..clear()
              ..addAll(answers);
          }
          _answersLoading = false;
        });
      }
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
      _questionsLoading = _questionRequests.isEmpty;
      _questionsLoadFailed = false;
    });

    try {
      final questionRequests = await _questionRequestService
          .loadPendingForRecipient(user.id);
      questionRequests.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      if (!mounted ||
          request != _questionsLoadRequest ||
          _user?.id != user.id) {
        return;
      }
      if (!_sameRequests(_questionRequests, questionRequests) ||
          _questionsLoading) {
        setState(() {
          if (!_sameRequests(_questionRequests, questionRequests)) {
            _questionRequests
              ..clear()
              ..addAll(questionRequests);
          }
          _questionsLoading = false;
        });
      }
    } catch (_) {
      if (!mounted ||
          request != _questionsLoadRequest ||
          _user?.id != user.id) {
        return;
      }
      setState(() {
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
    _loadRequest++; // An older refresh must not overwrite this new member.
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
        _hasMembersSnapshot = true;
        _isLoading = false;
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

  Future<void> _openProfile() async {
    if (_profileOpen) return;
    _profileOpen = true;
    await Navigator.of(context).push(
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
    _profileOpen = false;
    if (mounted) setState(() {});
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

  Future<void> _openQuestions(FamilyMember member) async {
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => QuestionsScreen(
          familyMember: member,
          familyStoryStorage:
              widget.familyStoryStorage ?? LocalFamilyStoryStorage(),
          authService: _authService,
          invitationService: _invitationService,
          invitationShareService: _invitationShareService,
          familyMemberService: _familyMemberService,
          questionRequestService: _questionRequestService,
          isRemoteFamilyMember: _user != null,
        ),
      ),
    );
    if (mounted) await _refreshHome();
  }

  void _selectSection(int index) {
    if (index == 2) {
      _quickCreate();
      return;
    }
    if (index == 4) {
      _openProfile();
      return;
    }
    setState(() => _section = index);
  }

  Future<void> _quickCreate() async {
    final action = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: AritoriaColors.cream,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.only(bottom: AritoriaSpace.md),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.mic_none),
                title: const Text('Grabar una historia'),
                onTap: () => Navigator.pop(context, 0),
              ),
              ListTile(
                leading: const Icon(Icons.chat_bubble_outline),
                title: const Text('Enviar una pregunta'),
                onTap: () => Navigator.pop(context, 1),
              ),
              ListTile(
                leading: const Icon(Icons.person_add_alt_1_outlined),
                title: const Text('Añadir ser querido'),
                onTap: () => Navigator.pop(context, 2),
              ),
            ],
          ),
        ),
      ),
    );
    if (!mounted || action == null) return;
    if (action == 2 || _familyMembers.isEmpty) {
      await _addFamilyMember();
      return;
    }
    final account = _user?.id;
    final member = await showModalBottomSheet<FamilyMember>(
      context: context,
      showDragHandle: true,
      backgroundColor: AritoriaColors.cream,
      builder: (_) => SafeArea(
        child: SizedBox(
          height: 360,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(AritoriaSpace.md),
                child: Text(
                  action == 0
                      ? '¿De quién quieres guardar una historia?'
                      : '¿A quién quieres preguntar?',
                ),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: _familyMembers.length,
                  itemBuilder: (_, index) {
                    final member = _familyMembers[index];
                    return ListTile(
                      title: Text(member.name),
                      subtitle: Text(member.relationship),
                      leading: FamilyMemberPhotoView(
                        member: member,
                        photoService: _photos,
                        radius: 22,
                      ),
                      onTap: () => Navigator.pop(context, member),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (!mounted || member == null || account != _user?.id) return;
    // Existing question selection offers both recording now and sending.
    await _openQuestions(member);
  }

  void _showRequests(int tab) => setState(() {
    _section = 3;
    _questionTab = tab;
  });

  Widget? _memberStatus() => _isLoading || _isSaving
      ? const Center(
          child: Padding(
            padding: EdgeInsets.all(AritoriaSpace.md),
            child: CircularProgressIndicator(),
          ),
        )
      : _loadFailed
      ? _FamilyMembersLoadError(onRetry: _loadFamilyMembers)
      : null;

  Widget? _requestStatus(bool answers) {
    if ((answers ? _answeredRequests : _questionRequests).isNotEmpty) {
      return null;
    }
    if (answers ? _answersLoading : _questionsLoading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(AritoriaSpace.md),
          child: CircularProgressIndicator(),
        ),
      );
    }
    if (answers ? _answersLoadFailed : _questionsLoadFailed) {
      return _QuestionRequestsLoadError(
        onRetry: _loadReceivedRequests,
        message: answers
            ? 'No se pudieron cargar tus respuestas.'
            : 'No se pudieron cargar tus preguntas.',
      );
    }
    return null;
  }

  Widget _membersView() => RefreshIndicator(
    onRefresh: _refreshHome,
    child: ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(AritoriaSpace.lg),
      children: [
        if (_memberStatus() != null)
          _memberStatus()!
        else if (_familyMembers.isEmpty)
          const Text('Todavía no has añadido ningún ser querido.')
        else
          for (final member in _familyMembers)
            ListTile(
              leading: FamilyMemberPhotoView(
                member: member,
                photoService: _photos,
                radius: 24,
              ),
              title: Text(member.name),
              subtitle: Text(member.relationship),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _openFamilyMember(member),
            ),
        TextButton.icon(
          onPressed: _isLoading || _isSaving ? null : _addFamilyMember,
          icon: const Icon(Icons.add),
          label: const Text('Añadir ser querido'),
        ),
      ],
    ),
  );

  Widget _requestsView() {
    final answers = _questionTab == 1;
    final requests = answers ? _answeredRequests : _questionRequests;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AritoriaSpace.lg),
          child: Wrap(
            spacing: AritoriaSpace.sm,
            children: [
              ChoiceChip(
                label: const Text('Preguntas para ti'),
                selected: !answers,
                onSelected: (_) => setState(() => _questionTab = 0),
              ),
              ChoiceChip(
                label: const Text('Historias que has contado'),
                selected: answers,
                onSelected: (_) => setState(() => _questionTab = 1),
              ),
            ],
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _refreshHome,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(AritoriaSpace.lg),
              children: [
                if (_user == null)
                  const Text(
                    'Inicia sesión desde tu perfil para recibir preguntas y consultar tus historias.',
                  )
                else if (_requestStatus(answers) != null)
                  _requestStatus(answers)!
                else if (requests.isEmpty)
                  Text(
                    answers
                        ? 'Todavía no has contado ninguna historia.'
                        : 'No tienes preguntas pendientes.',
                  )
                else
                  for (final request in requests)
                    ReceivedRequestRow(
                      request: request,
                      details: _details[request.id],
                      onTap: () => answers
                          ? _openAnswer(request)
                          : _openQuestionRequest(request),
                    ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => Theme(
    data: AritoriaDesign.theme(),
    child: PopScope(
      canPop: _section == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _section != 0) setState(() => _section = 0);
      },
      child: Scaffold(
        appBar: _section == 0
            ? null
            : AppBar(
                title: Text(_section == 1 ? 'Seres queridos' : 'Preguntas'),
              ),
        body: SafeArea(
          bottom: false,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: AritoriaSpace.maxWidth,
              ),
              child: _section == 1
                  ? _membersView()
                  : _section == 3
                  ? _requestsView()
                  : AritoriaHomeView(
                      members: _familyMembers,
                      photos: _photos,
                      profile: _user == null
                          ? null
                          : _profileService.cachedForUser(_user!.id),
                      authenticated: _user != null,
                      questions: _questionRequests,
                      answers: _answeredRequests,
                      details: _details,
                      memberStatus: _memberStatus(),
                      questionStatus: _requestStatus(false),
                      answerStatus: _requestStatus(true),
                      onRefresh: _refreshHome,
                      onProfile: _openProfile,
                      onAdd: _addFamilyMember,
                      onMember: _openFamilyMember,
                      onHero: () {
                        final member = selectHomeHero(_familyMembers);
                        if (_isLoading || _isSaving || _loadFailed) return;
                        if (member == null) {
                          _addFamilyMember();
                        } else {
                          _openQuestions(member);
                        }
                      },
                      onAllMembers: () => _selectSection(1),
                      onAllQuestions: () => _showRequests(0),
                      onAllAnswers: () => _showRequests(1),
                      onQuestion: _openQuestionRequest,
                      onAnswer: _openAnswer,
                    ),
            ),
          ),
        ),
        bottomNavigationBar: AritoriaNavigation(
          selected: _section,
          onSelect: _selectSection,
        ),
      ),
    ),
  );
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

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AritoriaSpace.md),
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
    );
  }
}
