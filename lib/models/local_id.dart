import 'dart:math';

final _random = Random();

String generateLocalId() {
  final timestamp = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
  final randomPart = _random.nextInt(1 << 32).toRadixString(36);
  return '${timestamp}_$randomPart';
}
