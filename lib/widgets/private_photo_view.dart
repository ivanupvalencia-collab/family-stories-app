import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../services/private_photo_service.dart';

class PrivatePhotoView<T> extends StatefulWidget {
  const PrivatePhotoView({
    required this.item,
    required this.identity,
    required this.reference,
    required this.service,
    required this.width,
    required this.height,
    required this.fallback,
    required this.label,
    this.circular = false,
    this.alignment = Alignment.center,
    this.previewBytes,
    super.key,
  });
  final T item;
  final String identity;
  final String? reference;
  final PrivatePhotoService<T> service;
  final double width, height;
  final Widget fallback;
  final String label;
  final bool circular;
  final Alignment alignment;
  final Uint8List? previewBytes;
  @override
  State<PrivatePhotoView<T>> createState() => _PrivatePhotoViewState<T>();
}

class _PrivatePhotoViewState<T> extends State<PrivatePhotoView<T>> {
  Future<Uint8List>? _future;
  Listenable? _changes;
  void _load() {
    _changes?.removeListener(_changed);
    _changes = widget.reference == null || widget.previewBytes != null
        ? null
        : widget.service.cacheChanges;
    _changes?.addListener(_changed);
    _future =
        widget.reference != null &&
            widget.previewBytes == null &&
            widget.service.cachedPhoto(widget.item) == null
        ? widget.service.load(widget.item)
        : null;
  }

  void _changed() {
    if (mounted) setState(() => _future = null);
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(PrivatePhotoView<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.identity != widget.identity ||
        oldWidget.reference != widget.reference ||
        oldWidget.service != widget.service ||
        oldWidget.previewBytes != widget.previewBytes) {
      _load();
    }
  }

  @override
  void dispose() {
    _changes?.removeListener(_changed);
    super.dispose();
  }

  Widget _image(Uint8List? bytes) => bytes == null || bytes.isEmpty
      ? widget.fallback
      : LayoutBuilder(
          builder: (context, constraints) => Image.memory(
            bytes,
            fit: BoxFit.cover,
            alignment: widget.alignment,
            gaplessPlayback: false,
            cacheWidth:
                ((constraints.hasBoundedWidth ? constraints.maxWidth : 80) *
                        MediaQuery.devicePixelRatioOf(context))
                    .ceil()
                    .clamp(1, 2048),
            errorBuilder: (_, _, _) => widget.fallback,
          ),
        );
  @override
  Widget build(BuildContext context) {
    final child = widget.previewBytes != null
        ? _image(widget.previewBytes)
        : FutureBuilder<Uint8List>(
            future: _future,
            builder: (_, snapshot) => _image(
              widget.reference == null
                  ? null
                  : widget.service.cachedPhoto(widget.item) ??
                        (_changes == null &&
                                snapshot.connectionState ==
                                    ConnectionState.done &&
                                !snapshot.hasError
                            ? snapshot.data
                            : null),
            ),
          );
    return Center(
      widthFactor: 1,
      heightFactor: 1,
      child: Semantics(
        label: widget.label,
        image: true,
        child: SizedBox(
          width: widget.width,
          height: widget.height,
          child: widget.circular
              ? ClipOval(child: child)
              : ClipRect(child: child),
        ),
      ),
    );
  }
}
