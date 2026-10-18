import 'dart:async';

import 'package:flutter/material.dart';

import '../models/family_story.dart';
import '../models/question_request.dart';
import '../services/audio_answer_service.dart';
import '../services/auth_service.dart';
import '../services/family_story_service.dart';
import '../services/question_request_service.dart';
import '../services/story_photo_service.dart';
import '../services/profile_image_picker.dart';
import 'story_screen.dart';

class AnswerScreen extends StatefulWidget {
  const AnswerScreen({
    required this.questionRequest,
    required this.questionRequestService,
    required this.familyStoryService,
    required this.authService,
    this.audioService,
    this.photoService,
    this.imagePicker,
    this.authorName,
    this.recipientName,
    super.key,
  });

  final QuestionRequest questionRequest;
  final QuestionRequestService questionRequestService;
  final FamilyStoryService familyStoryService;
  final AuthService authService;
  final AudioAnswerService? audioService;
  final StoryPhotoService? photoService;
  final ProfileImagePicker? imagePicker;
  final String? authorName, recipientName;

  @override
  State<AnswerScreen> createState() => _AnswerScreenState();
}

class _AnswerScreenState extends State<AnswerScreen> {
  late final StreamSubscription<AuthUser?> _authSubscription;
  FamilyStory? _story;
  bool _loading = true;
  int _loadRequest = 0;

  bool get _canLoad =>
      widget.authService.currentUser?.id ==
          widget.questionRequest.recipientId &&
      widget.questionRequest.status == QuestionRequestStatus.answered;

  @override
  void initState() {
    super.initState();
    _authSubscription = widget.authService.authStateChanges.listen((user) {
      if (mounted && user?.id != widget.questionRequest.recipientId) {
        _loadRequest++;
        setState(() {
          _story = null;
          _loading = false;
        });
      }
    });
    unawaited(_loadStory());
  }

  Future<void> _loadStory() async {
    final request = ++_loadRequest;
    setState(() => _loading = true);
    try {
      if (!_canLoad) throw StateError('Answer unavailable for this session.');
      final story = await widget.questionRequestService.loadAnswerStory(
        widget.questionRequest.id,
      );
      if (!mounted || request != _loadRequest || !_canLoad) return;
      if (story == null) throw StateError('Answer unavailable.');
      setState(() {
        _story = story;
        _loading = false;
      });
    } catch (_) {
      if (mounted && request == _loadRequest) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  void dispose() {
    unawaited(_authSubscription.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final story = _story;
    if (story != null) {
      return StoryScreen(
        story: story,
        authorName: widget.authorName,
        recipientName: widget.recipientName ?? 'quien te preguntó',
        remoteStoryService: widget.familyStoryService,
        audioService: widget.audioService,
        photoService: widget.photoService,
        imagePicker: widget.imagePicker,
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Tu respuesta')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: _loading
              ? const CircularProgressIndicator()
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('No se pudo abrir esta respuesta.'),
                    if (_canLoad)
                      TextButton.icon(
                        onPressed: _loadStory,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Reintentar'),
                      ),
                  ],
                ),
        ),
      ),
    );
  }
}
