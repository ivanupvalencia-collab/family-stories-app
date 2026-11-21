import 'dart:io';

/// C-11: opportunistic byte budget for the app-private disk caches.
///
/// Walks [root] and deletes the least recently modified files until the
/// total is at most [maxBytes]. Files modified within [freshFor] are never
/// deleted: they may still be mid-write (the audio cache stages nothing) or
/// be the very file the triggering write just produced. If everything is
/// that fresh nothing is removed and the next write reconciles the tree.
///
/// Best effort: any I/O error aborts the sweep without propagating — an
/// eviction must never fail the write that triggered it. A deleted file is
/// only a cache miss: the next read downloads it again.
Future<void> enforceDiskBudget(
  Directory root,
  int maxBytes, {
  Duration freshFor = const Duration(seconds: 5),
}) async {
  if (maxBytes <= 0) return;
  try {
    final cutoff = DateTime.now().subtract(freshFor);
    final entries = <({File file, int size, DateTime modified})>[];
    await for (final entity in root.list(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      try {
        final stat = await entity.stat();
        entries.add((file: entity, size: stat.size, modified: stat.modified));
      } catch (_) {
        // A file that vanished between listing and stat is not counted.
      }
    }
    var total = 0;
    for (final entry in entries) {
      total += entry.size;
    }
    if (total <= maxBytes) return;
    entries.sort((a, b) => a.modified.compareTo(b.modified));
    for (final entry in entries) {
      if (total <= maxBytes) break;
      if (entry.modified.isAfter(cutoff)) continue; // Sorted: the rest is fresh too.
      try {
        await entry.file.delete();
        total -= entry.size;
      } catch (_) {
        // Already gone or not deletable: keep sweeping the older files.
      }
    }
  } catch (_) {
    // A missing/unreadable tree is not a budget problem.
  }
}
