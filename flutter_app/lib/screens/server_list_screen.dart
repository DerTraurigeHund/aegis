import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';
import '../services/database_service.dart';
import '../services/api_service.dart';
import '../models/server.dart';
import 'add_server_screen.dart';
import 'project_dashboard_screen.dart';

class ServerListScreen extends StatefulWidget {
  const ServerListScreen({super.key});

  @override
  State<ServerListScreen> createState() => _ServerListScreenState();
}

class _ServerListScreenState extends State<ServerListScreen> {
  List<Server> _servers = [];
  Map<int, bool> _healthStatus = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadServers();
  }

  Future<void> _loadServers() async {
    final db = context.read<DatabaseService>();
    final servers = await db.getServers();
    if (mounted) {
      setState(() { _servers = servers; _loading = false; });
      _checkHealth();
    }
  }

  Future<void> _checkHealth() async {
    final api = context.read<ApiService>();
    final results = <int, bool>{};
    for (final server in _servers) {
      results[server.id!] = await api.healthCheck(server.baseUrl);
    }
    if (mounted) setState(() => _healthStatus = results);
  }

  void _navigateToAddServer() async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const AddServerScreen()),
    );
    if (result == true) _loadServers();
  }

  void _editServer(Server server) async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => AddServerScreen(server: server)),
    );
    if (result == true) _loadServers();
  }

  void _deleteServer(Server server) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Server entfernen?', style: GoogleFonts.inter(fontWeight: FontWeight.w700)),
        content: Text('${server.name} wird nur aus der App entfernt.', style: GoogleFonts.inter()),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Abbrechen'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Entfernen', style: GoogleFonts.inter(color: AppColors.danger, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
    if (confirm == true) {
      final db = context.read<DatabaseService>();
      await db.deleteServer(server.id!);
      _loadServers();
    }
  }

  @override
  Widget build(BuildContext context) {
    final onlineCount = _healthStatus.values.where((v) => v).length;
    final offlineCount = _healthStatus.values.where((v) => !v).length;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          // Custom header
          SliverToBoxAdapter(
            child: Container(
              padding: const EdgeInsets.fromLTRB(20, 60, 20, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Aegis',
                            style: GoogleFonts.inter(
                              fontSize: 28,
                              fontWeight: FontWeight.w800,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${_servers.length} Server · $onlineCount online · $offlineCount offline',
                            style: GoogleFonts.inter(
                              fontSize: 14,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                      Row(
                        children: [
                          _HeaderButton(
                            icon: Icons.refresh_rounded,
                            onTap: _loadServers,
                          ),
                          const SizedBox(width: 8),
                          _HeaderButton(
                            icon: Icons.add_rounded,
                            onTap: _navigateToAddServer,
                            highlight: true,
                          ),
                        ],
                      ),
                    ],
                  ),
                  if (_servers.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    _OverviewBar(
                      total: _servers.length,
                      online: onlineCount,
                      offline: offlineCount,
                    ),
                  ],
                ],
              ),
            ),
          ),

          // Server list
          if (_loading)
            const SliverFillRemaining(
              child: Center(child: CircularProgressIndicator(color: AppColors.primary)),
            )
          else if (_servers.isEmpty)
            SliverFillRemaining(
              child: _EmptyState(onAdd: _navigateToAddServer),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (ctx, i) => _ServerCard(
                    server: _servers[i],
                    online: _healthStatus[_servers[i].id],
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ProjectDashboardScreen(server: _servers[i]),
                      ),
                    ),
                    onEdit: () => _editServer(_servers[i]),
                    onDelete: () => _deleteServer(_servers[i]),
                  ),
                  childCount: _servers.length,
                ),
              ),
            ),

          const SliverToBoxAdapter(child: SizedBox(height: 100)),
        ],
      ),
    );
  }
}

// ─── Header Button ───

class _HeaderButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final bool highlight;

  const _HeaderButton({required this.icon, required this.onTap, this.highlight = false});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: highlight ? AppColors.primary : AppColors.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: highlight ? null : Border.all(color: AppColors.surfaceLighter),
          ),
          child: Icon(icon, color: highlight ? Colors.white : AppColors.textSecondary, size: 24),
        ),
      ),
    );
  }
}

// ─── Overview Bar ───

class _OverviewBar extends StatelessWidget {
  final int total, online, offline;
  const _OverviewBar({required this.total, required this.online, required this.offline});

  @override
  Widget build(BuildContext context) {
    final onlinePct = total > 0 ? online / total : 0.0;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Row(
            children: [
              _StatChip(label: 'Online', value: online, color: AppColors.success),
              const SizedBox(width: 12),
              _StatChip(label: 'Offline', value: offline, color: AppColors.danger),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: onlinePct,
              backgroundColor: AppColors.danger.withOpacity(0.3),
              color: AppColors.success,
              minHeight: 6,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final String label;
  final int value;
  final Color color;
  const _StatChip({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Container(
              width: 8, height: 8,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 8),
            Text('$value', style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 18, color: color)),
            const SizedBox(width: 6),
            Text(label, style: GoogleFonts.inter(fontSize: 13, color: AppColors.textSecondary)),
          ],
        ),
      ),
    );
  }
}

// ─── Server Card ───

class _ServerCard extends StatelessWidget {
  final Server server;
  final bool? online;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _ServerCard({
    required this.server,
    required this.online,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: online == true
            ? Border.all(color: AppColors.success.withOpacity(0.2))
            : online == false
                ? Border.all(color: AppColors.danger.withOpacity(0.15))
                : null,
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
                // Status indicator
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: (online == true ? AppColors.success : online == false ? AppColors.danger : AppColors.textSecondary).withOpacity(0.15),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    online == true ? Icons.cloud_done_rounded : (online == false ? Icons.cloud_off_rounded : Icons.cloud_rounded),
                    color: online == true ? AppColors.success : (online == false ? AppColors.danger : AppColors.textSecondary),
                    size: 24,
                  ),
                ),
                const SizedBox(width: 14),
                // Info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        server.name,
                        style: GoogleFonts.inter(
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        server.baseUrl.replaceAll(RegExp(r'^https?://'), ''),
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                // Status badge
                if (online == true)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: AppColors.success.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text('Online', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.success)),
                  )
                else if (online == false)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: AppColors.danger.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text('Offline', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.danger)),
                  ),
                const SizedBox(width: 8),
                // Actions
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert_rounded, color: AppColors.textSecondary),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  color: AppColors.surfaceLight,
                  onSelected: (v) {
                    if (v == 'edit') onEdit();
                    if (v == 'delete') onDelete();
                    if (v == 'copy_key') {
                      Clipboard.setData(ClipboardData(text: server.apiKey));
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('API-Key kopiert'), backgroundColor: AppColors.surfaceLighter),
                      );
                    }
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(value: 'edit', child: Row(children: [Icon(Icons.edit_rounded, size: 18), SizedBox(width: 10), Text('Bearbeiten')])),
                    const PopupMenuItem(value: 'copy_key', child: Row(children: [Icon(Icons.key_rounded, size: 18), SizedBox(width: 10), Text('API-Key kopieren')])),
                    const PopupMenuItem(value: 'delete', child: Row(children: [Icon(Icons.delete_outline_rounded, size: 18, color: AppColors.danger), SizedBox(width: 10), Text('Entfernen', style: TextStyle(color: AppColors.danger))])),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Empty State ───

class _EmptyState extends StatelessWidget {
  final VoidCallback onAdd;
  const _EmptyState({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 100, height: 100,
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(28),
              ),
              child: const Icon(Icons.dns_rounded, size: 48, color: AppColors.primary),
            ),
            const SizedBox(height: 24),
            Text(
              'Keine Server',
              style: GoogleFonts.inter(fontSize: 22, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
            ),
            const SizedBox(height: 8),
            Text(
              'Füge deinen ersten Server hinzu, um Projekte zu überwachen.',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(fontSize: 15, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 28),
            FilledButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Server hinzufügen'),
            ),
          ],
        ),
      ),
    );
  }
}
