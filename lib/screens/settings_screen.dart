import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/sheets_service.dart';
import '../providers/app_provider.dart';
import 'hangar_list_screen.dart';

class SettingsScreen extends StatefulWidget {
  final bool isInitial;
  const SettingsScreen({super.key, this.isInitial = false});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _apiKeyCtrl = TextEditingController();
  final _sheetNameCtrl = TextEditingController();
  bool _isBusy = false;
  bool _obscure = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    _apiKeyCtrl.text = await SheetsService.getApiKey();
    _sheetNameCtrl.text = await SheetsService.getSheetName();
    setState(() {});
  }

  Future<void> _save() async {
    if (_apiKeyCtrl.text.trim().isEmpty) {
      _snack('Informe a chave de API do Google.', isError: true);
      return;
    }
    setState(() => _isBusy = true);
    await SheetsService.saveSettings(
        _apiKeyCtrl.text, _sheetNameCtrl.text);

    if (!mounted) return;

    final provider = context.read<AppProvider>();
    await provider.syncFromSheets();

    if (!mounted) return;
    setState(() => _isBusy = false);

    if (provider.error != null) {
      _snack('Erro: ${provider.error}', isError: true);
    } else {
      if (widget.isInitial) {
        Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const HangarListScreen()));
      } else {
        Navigator.of(context).pop();
        _snack('Configurações salvas e dados sincronizados!');
      }
    }
  }

  void _snack(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: isError ? Colors.red : Colors.green,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1E3A5F),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!widget.isInitial)
                IconButton(
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                    onPressed: () => Navigator.pop(context)),
              const SizedBox(height: 16),
              const Icon(Icons.settings, color: Colors.white, size: 48),
              const SizedBox(height: 12),
              const Text('Configuração',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 26,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              const Text(
                  'Cole sua Google API Key abaixo.\n'
                  'A planilha deve estar compartilhada publicamente (somente visualização) '
                  'ou com a conta que gerou a chave.',
                  style: TextStyle(color: Colors.white70, fontSize: 13)),
              const SizedBox(height: 28),
              _field(
                controller: _apiKeyCtrl,
                label: 'Google API Key',
                hint: 'AIzaSy...',
                icon: Icons.key,
                obscure: _obscure,
                suffix: IconButton(
                  icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off,
                      color: Colors.white54),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
              const SizedBox(height: 16),
              _field(
                controller: _sheetNameCtrl,
                label: 'Nome da aba (padrão: Sheet1)',
                hint: 'Sheet1',
                icon: Icons.table_chart,
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.amber.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.amber.withOpacity(0.4)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.amber, size: 16),
                    SizedBox(width: 8),
                    Expanded(
                        child: Text(
                      'ID da planilha já está configurado no app.\n'
                      'Acesse console.cloud.google.com → Habilite Sheets API → Crie uma API Key.',
                      style: TextStyle(color: Colors.amber, fontSize: 11),
                    )),
                  ],
                ),
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _isBusy ? null : _save,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: _isBusy
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text('Salvar e Sincronizar',
                          style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.white)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _field({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    bool obscure = false,
    Widget? suffix,
  }) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white70),
        hintText: hint,
        hintStyle: const TextStyle(color: Colors.white30),
        prefixIcon: Icon(icon, color: Colors.white54),
        suffixIcon: suffix,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Colors.white30)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Colors.white)),
        filled: true,
        fillColor: Colors.white.withOpacity(0.07),
      ),
    );
  }
}
