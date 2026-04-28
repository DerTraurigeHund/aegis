import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';
import '../models/server.dart';
import '../services/database_service.dart';
import '../services/api_service.dart';

class AddServerScreen extends StatefulWidget {
  final Server? server;
  const AddServerScreen({super.key, this.server});

  @override
  State<AddServerScreen> createState() => _AddServerScreenState();
}

class _AddServerScreenState extends State<AddServerScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _urlController = TextEditingController(text: 'https://');
  final _apiKeyController = TextEditingController();
  bool _saving = false;
  bool _testing = false;
  bool? _testResult; // null=not tested, true=ok, false=failed

  bool get _isEditing => widget.server != null;

  @override
  void initState() {
    super.initState();
    if (_isEditing) {
      _nameController.text = widget.server!.name;
      _urlController.text = widget.server!.baseUrl;
      _apiKeyController.text = widget.server!.apiKey;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _urlController.dispose();
    _apiKeyController.dispose();
    super.dispose();
  }

  Future<void> _testConnection() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() { _testing = true; _testResult = null; });

    final api = context.read<ApiService>();
    final url = _urlController.text.trim().replaceAll(RegExp(r'/+$'), '');
    final ok = await api.healthCheck(url);

    if (mounted) setState(() { _testing = false; _testResult = ok; });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    final server = Server(
      id: widget.server?.id,
      name: _nameController.text.trim(),
      baseUrl: _urlController.text.trim().replaceAll(RegExp(r'/+$'), ''),
      apiKey: _apiKeyController.text.trim(),
      createdAt: widget.server?.createdAt,
    );

    final db = context.read<DatabaseService>();
    if (_isEditing) {
      await db.updateServer(server);
    } else {
      await db.addServer(server);
    }

    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Server bearbeiten' : 'Server hinzufügen'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Icon header
              Center(
                child: Container(
                  width: 80, height: 80,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(22),
                  ),
                  child: const Icon(Icons.dns_rounded, size: 40, color: AppColors.primary),
                ),
              ),
              const SizedBox(height: 32),

              // Name
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Name',
                  hintText: 'z.B. Produktion Alpha',
                  prefixIcon: Icon(Icons.label_rounded),
                ),
                validator: (v) => v == null || v.trim().isEmpty ? 'Name erforderlich' : null,
              ),
              const SizedBox(height: 16),

              // URL
              TextFormField(
                controller: _urlController,
                decoration: const InputDecoration(
                  labelText: 'URL',
                  hintText: 'https://192.168.1.10:8070',
                  prefixIcon: Icon(Icons.link_rounded),
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'URL erforderlich';
                  if (!v.startsWith('http')) return 'Muss mit http:// oder https:// beginnen';
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // API Key
              TextFormField(
                controller: _apiKeyController,
                decoration: const InputDecoration(
                  labelText: 'API-Key',
                  hintText: 'Wird beim ersten Backend-Start generiert',
                  prefixIcon: Icon(Icons.key_rounded),
                ),
                validator: (v) => v == null || v.trim().isEmpty ? 'API-Key erforderlich' : null,
              ),
              const SizedBox(height: 20),

              // Test connection button
              OutlinedButton.icon(
                onPressed: _testing ? null : _testConnection,
                icon: _testing
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary))
                    : Icon(_testResult == true ? Icons.check_circle_rounded : (_testResult == false ? Icons.cancel_rounded : Icons.wifi_tethering_rounded)),
                label: Text(
                  _testing ? 'Teste...' : (_testResult == true ? 'Verbindung OK!' : (_testResult == false ? 'Verbindung fehlgeschlagen' : 'Verbindung testen')),
                ),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(
                    color: _testResult == true ? AppColors.success : (_testResult == false ? AppColors.danger : AppColors.primaryLight),
                  ),
                  foregroundColor: _testResult == true ? AppColors.success : (_testResult == false ? AppColors.danger : AppColors.primary),
                ),
              ),
              const SizedBox(height: 28),

              // Save button
              FilledButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : Text(_isEditing ? 'Speichern' : 'Hinzufügen'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
