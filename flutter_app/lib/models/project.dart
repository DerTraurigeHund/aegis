class Project {
  final int? id;
  final String name;
  final String type;
  final Map<String, dynamic> config;
  final String status;
  final int? pid;
  final String? containerId;
  final int maxRestarts;
  final int restartCount;
  final int restartResetMinutes;
  final String? lastStartedAt;
  final String? lastStoppedAt;
  final int totalUptimeSeconds;
  final String? createdAt;

  Project({
    this.id,
    required this.name,
    required this.type,
    this.config = const {},
    this.status = 'stopped',
    this.pid,
    this.containerId,
    this.maxRestarts = 3,
    this.restartCount = 0,
    this.restartResetMinutes = 5,
    this.lastStartedAt,
    this.lastStoppedAt,
    this.totalUptimeSeconds = 0,
    this.createdAt,
  });

  factory Project.fromJson(Map<String, dynamic> json) => Project(
    id: json['id'] as int?,
    name: json['name'] as String,
    type: json['type'] as String,
    config: json['config'] is Map<String, dynamic>
        ? json['config']
        : (json['config'] is String ? {} : {}),
    status: json['status'] as String? ?? 'stopped',
    pid: json['pid'] as int?,
    containerId: json['container_id'] as String?,
    maxRestarts: json['max_restarts'] as int? ?? 3,
    restartCount: json['restart_count'] as int? ?? 0,
    restartResetMinutes: json['restart_reset_minutes'] as int? ?? 5,
    lastStartedAt: json['last_started_at'] as String?,
    lastStoppedAt: json['last_stopped_at'] as String?,
    totalUptimeSeconds: json['total_uptime_seconds'] as int? ?? 0,
    createdAt: json['created_at'] as String?,
  );

  Duration get _currentSessionDuration {
    if (status != 'running' || lastStartedAt == null) return Duration.zero;
    try {
      final started = DateTime.parse(lastStartedAt!);
      // Ensure UTC comparison
      final now = DateTime.now().toUtc();
      final startUtc = started.isUtc ? started : DateTime.parse('${lastStartedAt!}Z');
      return now.difference(startUtc);
    } catch (_) {
      return Duration.zero;
    }
  }

  String get uptimeFormatted {
    final total = totalUptimeSeconds + _currentSessionDuration.inSeconds;
    final hours = total ~/ 3600;
    final minutes = (total % 3600) ~/ 60;
    return '${hours}h ${minutes}m';
  }

  String get currentUptimeFormatted {
    if (status != 'running') return '-';
    final d = _currentSessionDuration;
    final h = d.inHours;
    final m = d.inMinutes % 60;
    final s = d.inSeconds % 60;
    if (h > 0) return '${h}h ${m}m';
    if (m > 0) return '${m}m ${s}s';
    return '${s}s';
  }
}
