import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';
import '../models/server.dart';
import '../models/project.dart';
import '../services/api_service.dart';

class ProjectDashboardScreen extends StatefulWidget {
  final Server server;
  const ProjectDashboardScreen({super.key, required this.server});

  @override
  State<ProjectDashboardScreen> createState() => _ProjectDashboardScreenState();
}

class _ProjectDashboardScreenState extends State<ProjectDashboardScreen> {
  List<Project> _projects = [];
  bool _loading = true;
  String? _error;
  String _searchQuery = '';
  String? _filterStatus;

  // System stats (server load)
  Map<String, dynamic>? _systemStats;
  bool _sysStatsLoading = false;

  @override
  void initState() {
    super.initState();
    _loadProjects();
  }

  Future<void> _loadSystemStats() async {
    if (_sysStatsLoading) return;
    setState(() => _sysStatsLoading = true);
    try {
      final api = context.read<ApiService>();
      final stats = await api.getSystemStats(widget.server.baseUrl, widget.server.apiKey);
      if (mounted) setState(() { _systemStats = stats; _sysStatsLoading = false; });
    } catch (_) {
      if (mounted) setState(() => _sysStatsLoading = false);
    }
  }

  Future<void> _loadProjects() async {
    setState(() { _loading = true; _error = null; });
    try {
      final api = context.read<ApiService>();
      final projects = await api.getProjects(widget.server.baseUrl, widget.server.apiKey);
      if (mounted) setState(() { _projects = projects; _loading = false; });
      // Load system stats after projects succeed
      _loadSystemStats();
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  List<Project> get _filteredProjects {
    var list = _projects;
    if (_filterStatus != null) {
      list = list.where((p) => p.status == _filterStatus).toList();
    }
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      list = list.where((p) => p.name.toLowerCase().contains(q)).toList();
    }
    return list;
  }

  void _showAddProjectDialog() {
    final nameCtrl = TextEditingController();
    final cmdCtrl = TextEditingController();
    final cwdCtrl = TextEditingController();
    final containerCtrl = TextEditingController();
    final imageCtrl = TextEditingController();
    final runCmdCtrl = TextEditingController();
    String type = 'shell';
    int maxRestarts = 3;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: Container(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Projekt anlegen', style: GoogleFonts.inter(fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                const SizedBox(height: 20),
                TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Name', prefixIcon: Icon(Icons.label_rounded))),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: type,
                  items: const [
                    DropdownMenuItem(value: 'shell', child: Text('Shell')),
                    DropdownMenuItem(value: 'docker', child: Text('Docker')),
                  ],
                  onChanged: (v) => setDialogState(() => type = v!),
                  decoration: const InputDecoration(labelText: 'Typ', prefixIcon: Icon(Icons.category_rounded)),
                ),
                const SizedBox(height: 12),
                if (type == 'shell') ...[
                  TextField(controller: cmdCtrl, decoration: const InputDecoration(labelText: 'Command', hintText: 'npm start', prefixIcon: Icon(Icons.terminal_rounded))),
                  const SizedBox(height: 12),
                  TextField(controller: cwdCtrl, decoration: const InputDecoration(labelText: 'Working Directory', hintText: '/opt/app', prefixIcon: Icon(Icons.folder_rounded))),
                ] else ...[
                  TextField(controller: containerCtrl, decoration: const InputDecoration(labelText: 'Container Name', prefixIcon: Icon(Icons.inventory_2_rounded))),
                  const SizedBox(height: 12),
                  TextField(controller: imageCtrl, decoration: const InputDecoration(labelText: 'Image', hintText: 'redis:7-alpine', prefixIcon: Icon(Icons.layers_rounded))),
                  const SizedBox(height: 12),
                  TextField(controller: runCmdCtrl, decoration: const InputDecoration(labelText: 'Run Options', hintText: '-p 6379:6379', prefixIcon: Icon(Icons.settings_rounded))),
                ],
                const SizedBox(height: 12),
                Row(children: [
                  const Text('Max Restarts: ', style: TextStyle(color: AppColors.textSecondary)),
                  const SizedBox(width: 8),
                  DropdownButton<int>(
                    value: maxRestarts,
                    items: [1, 2, 3, 5, 10].map((v) => DropdownMenuItem(value: v, child: Text('$v'))).toList(),
                    onChanged: (v) => setDialogState(() => maxRestarts = v!),
                  ),
                ]),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: () async {
                    final api = context.read<ApiService>();
                    Map<String, dynamic> config;
                    if (type == 'shell') {
                      config = {'command': cmdCtrl.text, if (cwdCtrl.text.isNotEmpty) 'cwd': cwdCtrl.text};
                    } else {
                      config = {
                        'container_name': containerCtrl.text,
                        if (imageCtrl.text.isNotEmpty) 'image': imageCtrl.text,
                        if (runCmdCtrl.text.isNotEmpty) 'run_command': runCmdCtrl.text,
                      };
                    }
                    try {
                      await api.createProject(widget.server.baseUrl, widget.server.apiKey, {
                        'name': nameCtrl.text, 'type': type, 'config': config, 'max_restarts': maxRestarts,
                      });
                      if (mounted) { Navigator.pop(ctx); _loadProjects(); }
                    } catch (e) {
                      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fehler: $e')));
                    }
                  },
                  child: const Text('Erstellen'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _deleteProject(Project project) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Projekt löschen?', style: GoogleFonts.inter(fontWeight: FontWeight.w700)),
        content: Text('${project.name} wird unwiderruflich gelöscht.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Löschen', style: GoogleFonts.inter(color: AppColors.danger, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
    if (confirm == true) {
      final api = context.read<ApiService>();
      await api.deleteProject(widget.server.baseUrl, widget.server.apiKey, project.id!);
      _loadProjects();
    }
  }

  void _showEditProjectDialog(Project project) {
    if (project.status == 'running') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Projekt muss gestoppt sein zum Bearbeiten!')),
      );
      return;
    }

    final nameCtrl = TextEditingController(text: project.name);
    final cmdCtrl = TextEditingController(text: project.config['command'] ?? '');
    final cwdCtrl = TextEditingController(text: project.config['cwd'] ?? '');
    final containerCtrl = TextEditingController(text: project.config['container_name'] ?? '');
    final imageCtrl = TextEditingController(text: project.config['image'] ?? '');
    final runCmdCtrl = TextEditingController(text: project.config['run_command'] ?? '');
    int maxRestarts = project.maxRestarts;
    int restartResetMinutes = project.restartResetMinutes;
    final type = project.type;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: Container(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Projekt bearbeiten', style: GoogleFonts.inter(fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                const SizedBox(height: 4),
                Text('Typ: ${type.toUpperCase()}', style: GoogleFonts.inter(fontSize: 13, color: AppColors.textSecondary)),
                const SizedBox(height: 20),
                TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Name', prefixIcon: Icon(Icons.label_rounded))),
                const SizedBox(height: 12),
                if (type == 'shell') ...[
                  TextField(controller: cmdCtrl, decoration: const InputDecoration(labelText: 'Command', hintText: 'npm start', prefixIcon: Icon(Icons.terminal_rounded))),
                  const SizedBox(height: 12),
                  TextField(controller: cwdCtrl, decoration: const InputDecoration(labelText: 'Working Directory', hintText: '/opt/app', prefixIcon: Icon(Icons.folder_rounded))),
                ] else ...[
                  TextField(controller: containerCtrl, decoration: const InputDecoration(labelText: 'Container Name', prefixIcon: Icon(Icons.inventory_2_rounded))),
                  const SizedBox(height: 12),
                  TextField(controller: imageCtrl, decoration: const InputDecoration(labelText: 'Image', hintText: 'redis:7-alpine', prefixIcon: Icon(Icons.layers_rounded))),
                  const SizedBox(height: 12),
                  TextField(controller: runCmdCtrl, decoration: const InputDecoration(labelText: 'Run Options', hintText: '-p 6379:6379', prefixIcon: Icon(Icons.settings_rounded))),
                ],
                const SizedBox(height: 12),
                Row(children: [
                  const Text('Max Restarts: ', style: TextStyle(color: AppColors.textSecondary)),
                  const SizedBox(width: 8),
                  DropdownButton<int>(
                    value: maxRestarts,
                    items: [1, 2, 3, 5, 10].map((v) => DropdownMenuItem(value: v, child: Text('$v'))).toList(),
                    onChanged: (v) => setDialogState(() => maxRestarts = v!),
                  ),
                ]),
                Row(children: [
                  const Text('Restart Reset (Min): ', style: TextStyle(color: AppColors.textSecondary)),
                  const SizedBox(width: 8),
                  DropdownButton<int>(
                    value: restartResetMinutes,
                    items: [1, 2, 3, 5, 10, 15, 30].map((v) => DropdownMenuItem(value: v, child: Text('$v'))).toList(),
                    onChanged: (v) => setDialogState(() => restartResetMinutes = v!),
                  ),
                ]),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: () async {
                    final api = context.read<ApiService>();
                    Map<String, dynamic> config;
                    if (type == 'shell') {
                      config = {'command': cmdCtrl.text, if (cwdCtrl.text.isNotEmpty) 'cwd': cwdCtrl.text};
                    } else {
                      config = {
                        'container_name': containerCtrl.text,
                        if (imageCtrl.text.isNotEmpty) 'image': imageCtrl.text,
                        if (runCmdCtrl.text.isNotEmpty) 'run_command': runCmdCtrl.text,
                      };
                    }
                    try {
                      await api.updateProject(widget.server.baseUrl, widget.server.apiKey, project.id!, {
                        'name': nameCtrl.text,
                        'config': config,
                        'max_restarts': maxRestarts,
                        'restart_reset_minutes': restartResetMinutes,
                      });
                      if (mounted) { Navigator.pop(ctx); _loadProjects(); }
                    } catch (e) {
                      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fehler: $e')));
                    }
                  },
                  child: const Text('Speichern'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final running = _projects.where((p) => p.status == 'running').length;
    final crashed = _projects.where((p) => p.status == 'crashed' || p.status == 'failed').length;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          // Header
          SliverToBoxAdapter(
            child: Container(
              padding: const EdgeInsets.fromLTRB(20, 60, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: Container(
                          width: 40, height: 40,
                          decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(12)),
                          child: const Icon(Icons.arrow_back_rounded, color: AppColors.textPrimary, size: 20),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(widget.server.name, style: GoogleFonts.inter(fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
                            Text(widget.server.baseUrl.replaceAll(RegExp(r'^https?://'), ''), style: GoogleFonts.inter(fontSize: 13, color: AppColors.textSecondary)),
                          ],
                        ),
                      ),
                      _HeaderButton(icon: Icons.refresh_rounded, onTap: _loadProjects),
                      const SizedBox(width: 8),
                      _HeaderButton(icon: Icons.add_rounded, onTap: _showAddProjectDialog, highlight: true),
                    ],
                  ),
                  if (_projects.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        _MiniStat(label: 'Projekte', value: '${_projects.length}', icon: Icons.folder_rounded, color: AppColors.primary),
                        const SizedBox(width: 10),
                        _MiniStat(label: 'Läuft', value: '$running', icon: Icons.play_circle_rounded, color: AppColors.success),
                        const SizedBox(width: 10),
                        _MiniStat(label: 'Crash', value: '$crashed', icon: Icons.error_rounded, color: AppColors.danger),
                      ],
                    ),
                    // ── Server Load Section ──
                    const SizedBox(height: 14),
                    _SystemLoadSection(
                      stats: _systemStats,
                      loading: _sysStatsLoading,
                      onRefresh: _loadSystemStats,
                    ),
                    const SizedBox(height: 12),
                    // Search bar
                    TextField(
                      onChanged: (v) => setState(() => _searchQuery = v),
                      decoration: InputDecoration(
                        hintText: 'Projekte suchen...',
                        prefixIcon: const Icon(Icons.search_rounded, size: 20),
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        filled: true,
                        fillColor: AppColors.surface,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                      ),
                    ),
                    const SizedBox(height: 8),
                    // Filter chips
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          _FilterChip(label: 'Alle', selected: _filterStatus == null, onTap: () => setState(() => _filterStatus = null)),
                          const SizedBox(width: 6),
                          _FilterChip(label: 'Läuft', selected: _filterStatus == 'running', onTap: () => setState(() => _filterStatus = _filterStatus == 'running' ? null : 'running'), color: AppColors.success),
                          const SizedBox(width: 6),
                          _FilterChip(label: 'Gestoppt', selected: _filterStatus == 'stopped', onTap: () => setState(() => _filterStatus = _filterStatus == 'stopped' ? null : 'stopped'), color: AppColors.textSecondary),
                          const SizedBox(width: 6),
                          _FilterChip(label: 'Crash', selected: _filterStatus == 'crashed', onTap: () => setState(() => _filterStatus = _filterStatus == 'crashed' ? null : 'crashed'), color: AppColors.danger),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),

          // Content
          if (_loading)
            const SliverFillRemaining(child: Center(child: CircularProgressIndicator(color: AppColors.primary)))
          else if (_error != null)
            SliverFillRemaining(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.error_outline_rounded, size: 48, color: AppColors.danger),
                    const SizedBox(height: 12),
                    Text(_error!, style: GoogleFonts.inter(color: AppColors.danger)),
                    const SizedBox(height: 16),
                    FilledButton(onPressed: _loadProjects, child: const Text('Erneut versuchen')),
                  ],
                ),
              ),
            )
          else if (_projects.isEmpty)
            SliverFillRemaining(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 80, height: 80,
                      decoration: BoxDecoration(color: AppColors.primary.withOpacity(0.1), borderRadius: BorderRadius.circular(22)),
                      child: const Icon(Icons.inbox_rounded, size: 40, color: AppColors.primary),
                    ),
                    const SizedBox(height: 16),
                    Text('Keine Projekte', style: GoogleFonts.inter(fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                    const SizedBox(height: 8),
                    FilledButton.icon(onPressed: _showAddProjectDialog, icon: const Icon(Icons.add_rounded), label: const Text('Projekt anlegen')),
                  ],
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (ctx, i) => _ProjectCard(
                    project: _filteredProjects[i],
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => ProjectDetailScreen(
                        server: widget.server,
                        project: _filteredProjects[i],
                        onRefresh: _loadProjects,
                        onEdit: () => _showEditProjectDialog(_filteredProjects[i]),
                      )),
                    ),
                    onEdit: () => _showEditProjectDialog(_filteredProjects[i]),
                    onDelete: () => _deleteProject(_filteredProjects[i]),
                  ),
                  childCount: _filteredProjects.length,
                ),
              ),
            ),

          const SliverToBoxAdapter(child: SizedBox(height: 40)),
        ],
      ),
    );
  }
}

// ─── Helper Widgets ───

class _HeaderButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final bool highlight;
  const _HeaderButton({required this.icon, required this.onTap, this.highlight = false});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 42, height: 42,
        decoration: BoxDecoration(
          color: highlight ? AppColors.primary : AppColors.surface,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: highlight ? Colors.white : AppColors.textSecondary, size: 22),
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  final String label, value;
  final IconData icon;
  final Color color;
  const _MiniStat({required this.label, required this.value, required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(12)),
        child: Row(
          children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(width: 8),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(value, style: GoogleFonts.inter(fontWeight: FontWeight.w800, fontSize: 16, color: color)),
              Text(label, style: GoogleFonts.inter(fontSize: 11, color: AppColors.textSecondary)),
            ]),
          ],
        ),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Color? color;
  const _FilterChip({required this.label, required this.selected, required this.onTap, this.color});

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppColors.primary;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? c.withOpacity(0.2) : AppColors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: selected ? c : AppColors.surfaceLighter, width: 1.5),
        ),
        child: Text(label, style: GoogleFonts.inter(fontSize: 13, fontWeight: selected ? FontWeight.w600 : FontWeight.w400, color: selected ? c : AppColors.textSecondary)),
      ),
    );
  }
}

// ─── Project Card ───

class _ProjectCard extends StatelessWidget {
  final Project project;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  const _ProjectCard({required this.project, required this.onTap, required this.onEdit, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final sc = statusColor(project.status);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: sc.withOpacity(0.15)),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                // Status dot + type badge
                Column(
                  children: [
                    Container(
                      width: 44, height: 44,
                      decoration: BoxDecoration(color: sc.withOpacity(0.15), borderRadius: BorderRadius.circular(13)),
                      child: Icon(statusIcon(project.status), color: sc, size: 24),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(color: AppColors.surfaceLight, borderRadius: BorderRadius.circular(6)),
                      child: Text(project.type.toUpperCase(), style: GoogleFonts.inter(fontSize: 9, fontWeight: FontWeight.w700, color: AppColors.textSecondary)),
                    ),
                  ],
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(project.name, style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 15, color: AppColors.textPrimary)),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Container(
                            width: 7, height: 7,
                            decoration: BoxDecoration(color: sc, shape: BoxShape.circle),
                          ),
                          const SizedBox(width: 6),
                          Text(statusLabel(project.status), style: GoogleFonts.inter(fontSize: 13, color: sc, fontWeight: FontWeight.w500)),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text('Uptime: ${project.uptimeFormatted}', style: GoogleFonts.inter(fontSize: 12, color: AppColors.textSecondary)),
                    ],
                  ),
                ),
                // Restart count
                if (project.restartCount > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(color: AppColors.warning.withOpacity(0.15), borderRadius: BorderRadius.circular(8)),
                    child: Text('${project.restartCount}/${project.maxRestarts}', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.warning)),
                  ),
                IconButton(
                  icon: const Icon(Icons.more_vert_rounded, color: AppColors.textSecondary, size: 20),
                  onPressed: () => _showActions(context),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showActions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(project.name, style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w700)),
            ),
            ListTile(
              leading: const Icon(Icons.edit_rounded, color: AppColors.primary),
              title: const Text('Bearbeiten'),
              onTap: () { Navigator.pop(ctx); onEdit(); },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline_rounded, color: AppColors.danger),
              title: const Text('Löschen'),
              onTap: () { Navigator.pop(ctx); onDelete(); },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════
// ─── Project Detail Screen ────────────
// ═══════════════════════════════════════

class ProjectDetailScreen extends StatefulWidget {
  final Server server;
  final Project project;
  final VoidCallback onRefresh;
  final VoidCallback? onEdit;
  const ProjectDetailScreen({super.key, required this.server, required this.project, required this.onRefresh, this.onEdit});

  @override
  State<ProjectDetailScreen> createState() => _ProjectDetailScreenState();
}

class _ProjectDetailScreenState extends State<ProjectDetailScreen> {
  Project? _project;
  bool _loading = true;
  int _tabIndex = 0;

  @override
  void initState() {
    super.initState();
    _project = widget.project;
    _refresh();
    // Auto-refresh every 15s
    Future.delayed(const Duration(seconds: 15), _tick);
  }

  void _tick() {
    if (mounted) {
      _refresh();
      Future.delayed(const Duration(seconds: 15), _tick);
    }
  }

  Future<void> _refresh() async {
    final api = context.read<ApiService>();
    try {
      final p = await api.getProject(widget.server.baseUrl, widget.server.apiKey, _project!.id!);
      if (mounted) setState(() { _project = p; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _doAction(String action) async {
    final api = context.read<ApiService>();
    try {
      switch (action) {
        case 'start': await api.startProject(widget.server.baseUrl, widget.server.apiKey, _project!.id!); break;
        case 'stop': await api.stopProject(widget.server.baseUrl, widget.server.apiKey, _project!.id!); break;
        case 'restart': await api.restartProject(widget.server.baseUrl, widget.server.apiKey, _project!.id!); break;
      }
      _refresh();
      widget.onRefresh();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fehler: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = _project!;
    final sc = statusColor(p.status);

    return Scaffold(
      body: Column(
        children: [
          // Header
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(20, 60, 20, 24),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [sc.withOpacity(0.15), AppColors.background],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        width: 40, height: 40,
                        decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(12)),
                        child: const Icon(Icons.arrow_back_rounded, color: AppColors.textPrimary, size: 20),
                      ),
                    ),
                    const Spacer(),
                    if (p.status != 'running')
                      GestureDetector(
                        onTap: widget.onEdit,
                        child: Container(
                          width: 40, height: 40,
                          decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(12)),
                          child: const Icon(Icons.edit_rounded, color: AppColors.primary, size: 20),
                        ),
                      ),
                    if (p.status != 'running') const SizedBox(width: 8),
                    GestureDetector(
                      onTap: _refresh,
                      child: Container(
                        width: 40, height: 40,
                        decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(12)),
                        child: const Icon(Icons.refresh_rounded, color: AppColors.textSecondary, size: 20),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Container(
                  width: 64, height: 64,
                  decoration: BoxDecoration(color: sc.withOpacity(0.2), borderRadius: BorderRadius.circular(20)),
                  child: Icon(statusIcon(p.status), color: sc, size: 32),
                ),
                const SizedBox(height: 12),
                Text(p.name, style: GoogleFonts.inter(fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
                const SizedBox(height: 4),
                Text(statusLabel(p.status), style: GoogleFonts.inter(fontSize: 15, color: sc, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _InfoChip(label: p.type.toUpperCase()),
                    const SizedBox(width: 8),
                    _InfoChip(label: 'PID: ${p.pid ?? "-"}'),
                    const SizedBox(width: 8),
                    _InfoChip(label: 'Restarts: ${p.restartCount}/${p.maxRestarts}'),
                  ],
                ),
              ],
            ),
          ),

          // Action buttons
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Row(
              children: [
                Expanded(
                  child: _ActionButton(
                    label: 'Start',
                    icon: Icons.play_arrow_rounded,
                    color: AppColors.success,
                    enabled: p.status != 'running',
                    onTap: () => _doAction('start'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _ActionButton(
                    label: 'Stop',
                    icon: Icons.stop_rounded,
                    color: AppColors.danger,
                    enabled: p.status == 'running' || p.status == 'restarting',
                    onTap: () => _doAction('stop'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _ActionButton(
                    label: 'Restart',
                    icon: Icons.refresh_rounded,
                    color: AppColors.warning,
                    enabled: p.status == 'running' || p.status == 'stopped',
                    onTap: () => _doAction('restart'),
                  ),
                ),
              ],
            ),
          ),

          // Uptime bar
          if (p.status == 'running')
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(12)),
                child: Row(
                  children: [
                    Icon(Icons.timer_rounded, color: AppColors.info, size: 18),
                    const SizedBox(width: 8),
                    Text('Session: ${p.currentUptimeFormatted}', style: GoogleFonts.inter(fontSize: 13, color: AppColors.info)),
                    const Spacer(),
                    Text('Gesamt: ${p.uptimeFormatted}', style: GoogleFonts.inter(fontSize: 13, color: AppColors.textSecondary)),
                  ],
                ),
              ),
            ),

          const SizedBox(height: 12),
          // Tabs
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 20),
            decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(12)),
            child: Row(
              children: [
                _TabBtn(label: 'Logs', icon: Icons.terminal_rounded, selected: _tabIndex == 0, onTap: () => setState(() => _tabIndex = 0)),
                _TabBtn(label: 'Events', icon: Icons.history_rounded, selected: _tabIndex == 1, onTap: () => setState(() => _tabIndex = 1)),
                _TabBtn(label: 'Stats', icon: Icons.bar_chart_rounded, selected: _tabIndex == 2, onTap: () => setState(() => _tabIndex = 2)),
              ],
            ),
          ),
          const SizedBox(height: 8),

          // Tab content
          Expanded(child: _tabContent()),
        ],
      ),
    );
  }

  Widget _tabContent() {
    if (_tabIndex == 0) return _LogsTab(server: widget.server, projectId: _project!.id!);
    if (_tabIndex == 1) return _EventsTab(server: widget.server, projectId: _project!.id!);
    return _StatsTab(server: widget.server, projectId: _project!.id!);
  }
}

// ─── Tab Button ───

class _TabBtn extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  const _TabBtn({required this.label, required this.icon, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected ? AppColors.primary.withOpacity(0.15) : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 16, color: selected ? AppColors.primary : AppColors.textSecondary),
              const SizedBox(width: 6),
              Text(label, style: GoogleFonts.inter(fontSize: 13, fontWeight: selected ? FontWeight.w600 : FontWeight.w400, color: selected ? AppColors.primary : AppColors.textSecondary)),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Info Chip ───

class _InfoChip extends StatelessWidget {
  final String label;
  const _InfoChip({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: AppColors.surfaceLighter, borderRadius: BorderRadius.circular(8)),
      child: Text(label, style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
    );
  }
}

// ─── Action Button ───

class _ActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final bool enabled;
  final VoidCallback onTap;
  const _ActionButton({required this.label, required this.icon, required this.color, required this.enabled, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: enabled ? color.withOpacity(0.15) : AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: enabled ? color.withOpacity(0.3) : Colors.transparent),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: enabled ? color : AppColors.textSecondary, size: 18),
            const SizedBox(width: 6),
            Text(label, style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: enabled ? color : AppColors.textSecondary)),
          ],
        ),
      ),
    );
  }
}

// ─── Logs Tab ───

class _LogsTab extends StatefulWidget {
  final Server server; final int projectId;
  const _LogsTab({required this.server, required this.projectId});
  @override State<_LogsTab> createState() => _LogsTabState();
}

class _LogsTabState extends State<_LogsTab> {
  List<String> _logs = [];
  bool _loading = true;

  @override void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final api = context.read<ApiService>();
    try {
      final logs = await api.getLogs(widget.server.baseUrl, widget.server.apiKey, widget.projectId);
      if (mounted) setState(() { _logs = logs; _loading = false; });
    } catch (_) { if (mounted) setState(() => _loading = false); }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator(color: AppColors.primary));
    if (_logs.isEmpty) return Center(
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.article_outlined, size: 48, color: AppColors.textSecondary),
        const SizedBox(height: 12),
        Text('Keine Logs', style: GoogleFonts.inter(color: AppColors.textSecondary)),
      ]),
    );
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: const Color(0xFF0D0D17), borderRadius: BorderRadius.circular(12)),
      child: ListView.builder(
        itemCount: _logs.length,
        itemBuilder: (ctx, i) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 1),
          child: SelectableText(_logs[i], style: GoogleFonts.jetBrainsMono(fontSize: 12, color: const Color(0xFFB8B8D0))),
        ),
      ),
    );
  }
}

// ─── Events Tab ───

class _EventsTab extends StatefulWidget {
  final Server server; final int projectId;
  const _EventsTab({required this.server, required this.projectId});
  @override State<_EventsTab> createState() => _EventsTabState();
}

class _EventsTabState extends State<_EventsTab> {
  List<Map<String, dynamic>> _events = [];
  bool _loading = true;

  @override void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final api = context.read<ApiService>();
    try {
      final events = await api.getEvents(widget.server.baseUrl, widget.server.apiKey, widget.projectId);
      if (mounted) setState(() { _events = events; _loading = false; });
    } catch (_) { if (mounted) setState(() => _loading = false); }
  }

  Color _eventColor(String type) {
    switch (type) {
      case 'start': case 'recovered': return AppColors.success;
      case 'stop': return AppColors.textSecondary;
      case 'restart': return AppColors.warning;
      case 'crash': return AppColors.danger;
      case 'failed_permanent': return const Color(0xFF991B1B);
      default: return AppColors.textSecondary;
    }
  }

  String _eventLabel(String type) {
    switch (type) {
      case 'start': return 'Gestartet';
      case 'stop': return 'Gestoppt';
      case 'restart': return 'Neustart';
      case 'crash': return 'Crash';
      case 'recovered': return 'Erholt';
      case 'failed_permanent': return 'Dauerhaft fehlgeschlagen';
      default: return type;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator(color: AppColors.primary));
    if (_events.isEmpty) return Center(
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.history_rounded, size: 48, color: AppColors.textSecondary),
        const SizedBox(height: 12),
        Text('Keine Events', style: GoogleFonts.inter(color: AppColors.textSecondary)),
      ]),
    );
    return ListView.builder(
      itemCount: _events.length,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      itemBuilder: (ctx, i) {
        final e = _events[i];
        final c = _eventColor(e['type'] ?? '');
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(12)),
          child: Row(
            children: [
              Container(
                width: 36, height: 36,
                decoration: BoxDecoration(color: c.withOpacity(0.15), borderRadius: BorderRadius.circular(10)),
                child: Icon(_eventIcon(e['type'] ?? ''), color: c, size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_eventLabel(e['type'] ?? ''), style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 13, color: c)),
                    if (e['message'] != null)
                      Text(e['message'], style: GoogleFonts.inter(fontSize: 12, color: AppColors.textSecondary), maxLines: 2, overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
              Text(
                _formatTime(e['timestamp']?.toString() ?? ''),
                style: GoogleFonts.inter(fontSize: 11, color: AppColors.textSecondary),
              ),
            ],
          ),
        );
      },
    );
  }

  IconData _eventIcon(String type) {
    switch (type) {
      case 'start': return Icons.play_arrow_rounded;
      case 'stop': return Icons.stop_rounded;
      case 'restart': return Icons.refresh_rounded;
      case 'crash': return Icons.error_rounded;
      case 'recovered': return Icons.healing_rounded;
      case 'failed_permanent': return Icons.cancel_rounded;
      default: return Icons.info_rounded;
    }
  }

  String _formatTime(String ts) {
    if (ts.isEmpty) return '';
    try { return ts.substring(11, 19); } catch (_) { return ts; }
  }
}

// ─── Stats Tab ───

class _StatsTab extends StatefulWidget {
  final Server server; final int projectId;
  const _StatsTab({required this.server, required this.projectId});
  @override State<_StatsTab> createState() => _StatsTabState();
}

class _StatsTabState extends State<_StatsTab> {
  Map<String, dynamic>? _stats;
  bool _loading = true;

  @override void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final api = context.read<ApiService>();
    try {
      _stats = await api.getStats(widget.server.baseUrl, widget.server.apiKey, widget.projectId);
      if (mounted) setState(() => _loading = false);
    } catch (_) { if (mounted) setState(() => _loading = false); }
  }

  String _formatDuration(int seconds) {
    final d = seconds ~/ 86400;
    final h = (seconds % 86400) ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    if (d > 0) return '${d}d ${h}h ${m}m';
    if (h > 0) return '${h}h ${m}m';
    return '${m}m';
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator(color: AppColors.primary));
    if (_stats == null) return Center(
      child: Text('Stats nicht verfügbar', style: GoogleFonts.inter(color: AppColors.textSecondary)),
    );

    final data = _stats!;
    final uptime = data['total_uptime_seconds'] as int? ?? 0;
    final currentUptime = data['current_uptime_seconds'] as int? ?? 0;
    final crashes = data['total_crashes'] as int? ?? 0;
    final restarts = data['total_restarts'] as int? ?? 0;

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      children: [
        // Stats grid
        Row(
          children: [
            Expanded(child: _StatCard(label: 'Gesamte Uptime', value: _formatDuration(uptime), icon: Icons.access_time_rounded, color: AppColors.info)),
            const SizedBox(width: 10),
            Expanded(child: _StatCard(label: 'Aktuelle Session', value: _formatDuration(currentUptime), icon: Icons.timer_rounded, color: AppColors.success)),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(child: _StatCard(label: 'Crashes', value: '$crashes', icon: Icons.error_rounded, color: AppColors.danger)),
            const SizedBox(width: 10),
            Expanded(child: _StatCard(label: 'Restarts', value: '$restarts', icon: Icons.refresh_rounded, color: AppColors.warning)),
          ],
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label, value;
  final IconData icon;
  final Color color;
  const _StatCard({required this.label, required this.value, required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(14)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(height: 12),
          Text(value, style: GoogleFonts.inter(fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
          const SizedBox(height: 2),
          Text(label, style: GoogleFonts.inter(fontSize: 12, color: AppColors.textSecondary)),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════
// ─── System Load Section ──────────────
// ═══════════════════════════════════════

class _SystemLoadSection extends StatelessWidget {
  final Map<String, dynamic>? stats;
  final bool loading;
  final VoidCallback onRefresh;
  const _SystemLoadSection({required this.stats, required this.loading, required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.primary.withOpacity(0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row
          Row(
            children: [
              Icon(Icons.monitor_heart_rounded, color: AppColors.primary, size: 18),
              const SizedBox(width: 8),
              Text('Server-Auslastung',
                style: GoogleFonts.inter(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              const Spacer(),
              if (loading)
                const SizedBox(
                  width: 14, height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
                )
              else if (stats != null)
                GestureDetector(
                  onTap: onRefresh,
                  child: Icon(Icons.refresh_rounded, color: AppColors.textSecondary, size: 18),
                ),
            ],
          ),
          const SizedBox(height: 12),

          if (stats == null && !loading)
            _buildUnavailable()
          else if (stats == null && loading)
            _buildLoading()
          else
            _buildContent(),
        ],
      ),
    );
  }

  Widget _buildUnavailable() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: GestureDetector(
          onTap: onRefresh,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.cloud_off_rounded, size: 16, color: AppColors.textSecondary),
              const SizedBox(width: 6),
              Text('Nicht verfügbar – tippen zum Laden',
                style: GoogleFonts.inter(fontSize: 12, color: AppColors.textSecondary),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLoading() {
    return const Center(
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: SizedBox(
          width: 20, height: 20,
          child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
        ),
      ),
    );
  }

  Widget _buildContent() {
    final cpu = stats!['cpu'] as Map<String, dynamic>? ?? {};
    final mem = stats!['memory'] as Map<String, dynamic>? ?? {};
    final disks = stats!['disk'] as List<dynamic>? ?? [];
    final hostname = stats!['hostname'] as String? ?? '-';
    final procCount = stats!['process_count'] as int? ?? 0;
    final uptimeSec = stats!['uptime_seconds'] as int? ?? 0;

    final cpuPct = (cpu['percent'] as num?)?.toDouble() ?? 0.0;
    final loadAvg1 = (cpu['load_average_1m'] as num?)?.toDouble() ?? 0.0;
    final loadAvg5 = (cpu['load_average_5m'] as num?)?.toDouble() ?? 0.0;
    final coreCount = cpu['core_count'] as int? ?? 1;
    final memPct = (mem['percent'] as num?)?.toDouble() ?? 0.0;
    final memUsed = mem['used'] as int? ?? 0;
    final memTotal = mem['total'] as int? ?? 1;

    // Find root disk (or first one)
    double diskPct = 0.0;
    String diskStr = '-';
    if (disks.isNotEmpty) {
      final disk = disks.firstWhere(
        (d) => d['mount_point'] == '/',
        orElse: () => disks.first,
      ) as Map<String, dynamic>;
      diskPct = (disk['percent'] as num?)?.toDouble() ?? 0.0;
      final diskUsed = _formatBytes(disk['used'] as int? ?? 0);
      final diskTotal = _formatBytes(disk['total'] as int? ?? 0);
      diskStr = '$diskUsed / $diskTotal';
    }

    final hostUptime = _formatDuration(uptimeSec);

    return Column(
      children: [
        // Host info
        Row(
          children: [
            Icon(Icons.dns_rounded, size: 13, color: AppColors.textSecondary),
            const SizedBox(width: 6),
            Expanded(child: Text(hostname,
              style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textSecondary),
              overflow: TextOverflow.ellipsis,
            )),
            const SizedBox(width: 8),
            Icon(Icons.speed_rounded, size: 13, color: AppColors.textSecondary),
            const SizedBox(width: 4),
            Text('$procCount Prozesse',
              style: GoogleFonts.inter(fontSize: 12, color: AppColors.textSecondary),
            ),
          ],
        ),
        const SizedBox(height: 10),
        // Load bars
        _LoadBar(
          label: 'CPU',
          percent: cpuPct,
          value: '${cpuPct.toStringAsFixed(1)}%',
          color: _loadColor(cpuPct),
        ),
        if (loadAvg1 > 0 || loadAvg5 > 0)
          Padding(
            padding: const EdgeInsets.only(top: 4, left: 48),
            child: Text(
              'Load: ${loadAvg1.toStringAsFixed(2)} / ${loadAvg5.toStringAsFixed(2)} ($coreCount Kerne)',
              style: GoogleFonts.inter(fontSize: 10, color: AppColors.textSecondary),
            ),
          ),
        const SizedBox(height: 8),
        _LoadBar(
          label: 'RAM',
          percent: memPct,
          value: '${_formatBytes(memUsed)} / ${_formatBytes(memTotal)}',
          color: _loadColor(memPct),
        ),
        const SizedBox(height: 8),
        _LoadBar(
          label: 'Disk',
          percent: diskPct,
          value: diskStr,
          color: _loadColor(diskPct),
        ),
        const SizedBox(height: 8),
        // Uptime footer
        Row(
          children: [
            Icon(Icons.timer_outlined, size: 13, color: AppColors.textSecondary),
            const SizedBox(width: 4),
            Text('Uptime: $hostUptime',
              style: GoogleFonts.inter(fontSize: 11, color: AppColors.textSecondary),
            ),
          ],
        ),
      ],
    );
  }

  Color _loadColor(double pct) {
    if (pct < 60) return AppColors.success;
    if (pct < 80) return AppColors.warning;
    return AppColors.danger;
  }

  static String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  static String _formatDuration(int seconds) {
    final d = seconds ~/ 86400;
    final h = (seconds % 86400) ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    if (d > 0) return '${d}d ${h}h ${m}m';
    if (h > 0) return '${h}h ${m}m';
    return '${m}m';
  }
}

// ─── Load Bar ───

class _LoadBar extends StatelessWidget {
  final String label;
  final double percent;
  final String value;
  final Color color;
  const _LoadBar({required this.label, required this.percent, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 40,
          child: Text(label,
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: percent / 100,
              backgroundColor: color.withOpacity(0.15),
              color: color,
              minHeight: 8,
            ),
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 120,
          child: Text(value,
            textAlign: TextAlign.right,
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
        ),
      ],
    );
  }
}
