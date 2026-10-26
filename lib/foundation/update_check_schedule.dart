/// Startup-only throttling. Manual checks record admission but are never throttled.
class UpdateCheckSchedule {
  UpdateCheckSchedule({
    required this.read,
    required this.update,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  // The legacy timestamp belongs exclusively to comic source updates.
  static const sourceKey = 'lastCheckUpdate';
  static const applicationKey = 'lastCheckApplicationUpdate';
  static const interval = Duration(hours: 24);

  final Map<String, dynamic> Function() read;
  final Future<bool> Function(bool Function(Map<String, dynamic>) change)
  update;
  final DateTime Function() _now;

  int? _timestamp(Map<String, dynamic> data, String key) {
    final value = data[key];
    return value is int && value >= 0 ? value : null;
  }

  bool _due(Map<String, dynamic> data, String key, int now) {
    final last = _timestamp(data, key);
    return last == null || now - last >= interval.inMilliseconds;
  }

  Future<bool> _reserve(String key) {
    final now = _now().millisecondsSinceEpoch;
    if (!_due(read(), key, now)) return Future.value(false);
    return update((data) {
      if (!_due(data, key, now)) return false;
      data[key] = now;
      return true;
    });
  }

  Future<bool> reserveSourceCheck() => _reserve(sourceKey);
  Future<bool> reserveApplicationCheck() => _reserve(applicationKey);

  Future<void> recordManualCheck() async {
    // Capture admission time before entering the serialized data operation queue.
    final now = _now().millisecondsSinceEpoch;
    await update((data) {
      final latest = _timestamp(data, applicationKey);
      if (latest == null || now > latest) data[applicationKey] = now;
      return true;
    });
  }
}
