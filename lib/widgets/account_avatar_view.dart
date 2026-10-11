import 'package:flutter/material.dart';

import '../models/user_profile.dart';
import '../services/visible_account_avatar_service.dart';
import 'profile_avatar_view.dart';

/// An account avatar used only as a display fallback, never as an owned photo.
class AccountAvatarView extends StatefulWidget {
  const AccountAvatarView({
    required this.accountId,
    required this.fallback,
    this.service,
    this.fallbackBuilder,
    this.radius = 24,
    this.width,
    this.height,
    this.circular = true,
    this.alignment = Alignment.center,
    super.key,
  });

  final String accountId;
  final Widget fallback;
  final Widget Function(UserProfile?)? fallbackBuilder;
  final VisibleAccountAvatarService? service;
  final double radius;
  final double? width;
  final double? height;
  final bool circular;
  final Alignment alignment;

  @override
  State<AccountAvatarView> createState() => _AccountAvatarViewState();
}

class _AccountAvatarViewState extends State<AccountAvatarView> {
  VisibleAccountAvatarService? _service;
  Future<UserProfile?>? _future;

  @override
  void initState() {
    super.initState();
    _attach();
  }

  void _attach() {
    _service = widget.service ?? SupabaseVisibleAccountAvatarService.shared;
    _service?.addListener(_changed);
    _future = _service?.load(widget.accountId);
  }

  void _changed() {
    if (mounted) {
      setState(() {
        _future = _service?.load(widget.accountId);
      });
    }
  }

  @override
  void didUpdateWidget(AccountAvatarView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.accountId != widget.accountId ||
        oldWidget.service != widget.service) {
      _service?.removeListener(_changed);
      _attach();
    }
  }

  @override
  void dispose() {
    _service?.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    width: widget.width ?? widget.radius * 2,
    height: widget.height ?? widget.radius * 2,
    child: FutureBuilder<UserProfile?>(
      future: _future,
      builder: (context, snapshot) {
        // Never retain FutureBuilder's old-account snapshot on account changes.
        final profile = _service?.cached(widget.accountId);
        return ProfileAvatarView(
          avatarKey: profile?.avatarKey,
          avatarUrl: profile?.avatarUrl,
          radius: widget.radius,
          width: widget.width,
          height: widget.height,
          circular: widget.circular,
          alignment: widget.alignment,
          fallback: widget.fallbackBuilder?.call(profile) ?? widget.fallback,
        );
      },
    ),
  );
}
