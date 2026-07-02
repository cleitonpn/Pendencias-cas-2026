import 'package:flutter/material.dart';
import '../models/client.dart';
import '../models/freight_request.dart';
import '../services/database_service.dart';
import '../services/firestore_service.dart';
import '../utils/fcm_topics.dart';

class FreightRequestFormScreen extends StatefulWidget {
  final int fairId;
  final String fairName;
  final String requestedBy;
  final String requestedByRole;

  const FreightRequestFormScreen({
    super.key,
    required this.fairId,
    required this.fairName,
    required this.requestedBy,
    required this.requestedByRole,
  });

  @override
  State<FreightRequestFormScreen> createState() =>
      _FreightRequestFormScreenState();
}

class _FreightRequestFormScreenState extends State<FreightRequestFormScreen> {
  List<Client> _clients = [];
  final Set<String> _selectedClientIds = {};
  bool _loadingClients = true;

  final _portaoCtrl = TextEditingController();
  final _itemsCtrl = TextEditingController();
  DateTime? _scheduledDate;
  TimeOfDay? _scheduledTime;
  String _priority = 'normal';

  final Map<String, bool> _motivos = {
    'montagem': false,
    'desmontagem': false,
    'sobra': false,
    'extra': false,
    'itens_faltantes': false,
    'outros': false,
  };

  static const _motivoLabels = {
    'montagem': 'Montagem',
    'desmontagem': 'Desmontagem',
    'sobra': 'Sobra',
    'extra': 'Extra',
    'itens_faltantes': 'Itens Faltantes',
    'outros': 'Outros',
  };

  final Map<String, bool> _equipes = {
    'marcenaria': false,
    'tapecaria': false,
    'eletrica': false,
    'comunicacao_visual': false,
    'vidracaria': false,
    'outros': false,
  };

  static const _equipeLabels = {
    'marcenaria': 'Marcenaria',
    'tapecaria': 'Tapeçaria',
    'eletrica': 'Elétrica',
    'comunicacao_visual': 'Comunicação Visual',
    'vidracaria': 'Vidraçaria',
    'outros': 'Outros',
  };

  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _loadClients();
  }

  @override
  void dispose() {
    _portaoCtrl.dispose();
    _itemsCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadClients() async {
    try {
      final list = await DatabaseService.getClients(fairId: widget.fairId);
      if (mounted) setState(() { _clients = list; _loadingClients = false; });
    } catch (_) {
      if (mounted) setState(() => _loadingClients = false);
    }
  }

  String get _scheduledForString {
    if (_scheduledDate == null || _scheduledTime == null) return '';
    final dt = DateTime(
      _scheduledDate!.year, _scheduledDate!.month, _scheduledDate!.day,
      _scheduledTime!.hour, _scheduledTime!.minute,
    );
    return dt.toIso8601String();
  }

  String _requesterTopic() {
    final role = widget.requestedByRole;
    final name = widget.requestedBy;
    if (role == 'producer') return fcmTopic('producer', name);
    if (role == 'consultant') return fcmTopic('consultant', name);
    return 'admins';
  }

  Future<void> _submit() async {
    final scheduledFor = _scheduledForString;
    if (scheduledFor.isEmpty) {
      _snack('Selecione a data e hora da solicitação.', isError: true);
      return;
    }
    if (_itemsCtrl.text.trim().isEmpty) {
      _snack('Descreva os itens necessários.', isError: true);
      return;
    }
    final selectedMotivos =
        _motivos.entries.where((e) => e.value).map((e) => e.key).toList();
    if (selectedMotivos.isEmpty) {
      _snack('Selecione ao menos um motivo.', isError: true);
      return;
    }

    final selectedClients =
        _clients.where((c) => _selectedClientIds.contains(c.firestoreId)).toList();
    final clientIds = selectedClients.map((c) => c.firestoreId).toList();
    final clientNames = selectedClients.map((c) => c.displayName).toList();
    final selectedEquipes =
        _equipes.entries.where((e) => e.value).map((e) => e.key).toList();

    setState(() => _submitting = true);
    try {
      final req = FreightRequest(
        number: 0,
        fairId: widget.fairId,
        fairName: widget.fairName,
        clientIds: clientIds,
        clientNames: clientNames,
        portao: _portaoCtrl.text.trim(),
        scheduledFor: scheduledFor,
        items: _itemsCtrl.text.trim(),
        motivos: selectedMotivos,
        equipes: selectedEquipes,
        priority: _priority,
        status: 'em_aberto',
        requestedBy: widget.requestedBy,
        requestedByRole: widget.requestedByRole,
        requesterTopic: _requesterTopic(),
        requestedAt: DateTime.now().toIso8601String(),
        handledBy: '',
        statusNote: '',
        receiptPhotoUrl: '',
      );
      await FirestoreService.createFreightRequest(req);
      if (mounted) {
        _snack('Solicitação enviada com sucesso!');
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) _snack('Erro ao enviar: $e', isError: true);
    } finally {
      if (mounted) setState(() => _submitting = false);
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
      backgroundColor: const Color(0xFFF0F2F5),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E3A5F),
        title: const Text('Solicitar Logística',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Fair chip
            Chip(
              avatar: const Icon(Icons.event, size: 16, color: Color(0xFF1E3A5F)),
              label: Text(widget.fairName,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              backgroundColor: const Color(0xFF1E3A5F).withOpacity(0.08),
            ),
            const SizedBox(height: 16),

            // Stands
            _label('STANDS (opcional)'),
            const SizedBox(height: 4),
            const Text(
                'Selecione stands específicos ou deixe em branco para toda a feira.',
                style: TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 8),
            Card(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: _loadingClients
                    ? const Center(
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : _clients.isEmpty
                        ? const Text('Nenhum stand disponível.',
                            style: TextStyle(color: Colors.grey))
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (_selectedClientIds.isEmpty)
                                const Padding(
                                  padding: EdgeInsets.only(bottom: 8),
                                  child: Text('Toda a feira',
                                      style: TextStyle(
                                          color: Colors.grey,
                                          fontStyle: FontStyle.italic)),
                                ),
                              Wrap(
                                spacing: 6,
                                runSpacing: 4,
                                children: _clients.map((c) {
                                  final sel = _selectedClientIds
                                      .contains(c.firestoreId);
                                  return FilterChip(
                                    label: Text(
                                      '${c.displayName} (${c.local})',
                                      style: TextStyle(
                                          fontSize: 12,
                                          color: sel
                                              ? Colors.white
                                              : Colors.black87),
                                    ),
                                    selected: sel,
                                    selectedColor: const Color(0xFF1E3A5F),
                                    checkmarkColor: Colors.white,
                                    onSelected: (v) {
                                      setState(() {
                                        if (v) {
                                          _selectedClientIds
                                              .add(c.firestoreId);
                                        } else {
                                          _selectedClientIds
                                              .remove(c.firestoreId);
                                        }
                                      });
                                    },
                                  );
                                }).toList(),
                              ),
                            ],
                          ),
              ),
            ),
            const SizedBox(height: 16),

            // Portão
            _label('PORTÃO DE DESCARGA'),
            const SizedBox(height: 8),
            TextField(
              controller: _portaoCtrl,
              decoration: InputDecoration(
                hintText: 'ex: Portão 3',
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10)),
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 12),
              ),
            ),
            const SizedBox(height: 16),

            // Data e hora
            _label('DATA E HORA *'),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.calendar_today, size: 18),
                    label: Text(_scheduledDate == null
                        ? 'Selecionar Data'
                        : '${_scheduledDate!.day.toString().padLeft(2, '0')}/${_scheduledDate!.month.toString().padLeft(2, '0')}/${_scheduledDate!.year}'),
                    onPressed: () async {
                      final d = await showDatePicker(
                        context: context,
                        initialDate: _scheduledDate ?? DateTime.now(),
                        firstDate: DateTime.now()
                            .subtract(const Duration(days: 1)),
                        lastDate:
                            DateTime.now().add(const Duration(days: 365)),
                      );
                      if (d != null) setState(() => _scheduledDate = d);
                    },
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF1E3A5F),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.access_time, size: 18),
                    label: Text(_scheduledTime == null
                        ? 'Selecionar Hora'
                        : '${_scheduledTime!.hour.toString().padLeft(2, '0')}:${_scheduledTime!.minute.toString().padLeft(2, '0')}'),
                    onPressed: () async {
                      final t = await showTimePicker(
                        context: context,
                        initialTime: _scheduledTime ?? TimeOfDay.now(),
                      );
                      if (t != null) setState(() => _scheduledTime = t);
                    },
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF1E3A5F),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Itens
            _label('ITENS NECESSÁRIOS *'),
            const SizedBox(height: 8),
            TextField(
              controller: _itemsCtrl,
              maxLines: 4,
              decoration: InputDecoration(
                hintText: 'Descreva os itens a serem transportados...',
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10)),
                contentPadding: const EdgeInsets.all(14),
              ),
            ),
            const SizedBox(height: 16),

            // Prioridade
            _label('PRIORIDADE'),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: ChoiceChip(
                    label: const Center(child: Text('Normal')),
                    selected: _priority == 'normal',
                    selectedColor: Colors.grey.shade700,
                    labelStyle: TextStyle(
                        color: _priority == 'normal'
                            ? Colors.white
                            : Colors.black87,
                        fontWeight: FontWeight.w600),
                    onSelected: (_) => setState(() => _priority = 'normal'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ChoiceChip(
                    label: const Center(child: Text('Urgente')),
                    selected: _priority == 'urgente',
                    selectedColor: Colors.red,
                    labelStyle: TextStyle(
                        color: _priority == 'urgente'
                            ? Colors.white
                            : Colors.black87,
                        fontWeight: FontWeight.w600),
                    onSelected: (_) => setState(() => _priority = 'urgente'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Motivo
            _label('MOTIVO *'),
            const SizedBox(height: 8),
            Card(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
              child: Column(
                children: _motivos.keys.toList().asMap().entries.map((entry) {
                  final key = entry.value;
                  return CheckboxListTile(
                    title: Text(_motivoLabels[key]!),
                    value: _motivos[key],
                    activeColor: const Color(0xFF1E3A5F),
                    onChanged: (v) => setState(() => _motivos[key] = v!),
                    dense: true,
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 16),

            // Equipe
            _label('EQUIPE'),
            const SizedBox(height: 8),
            Card(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
              child: Column(
                children: _equipes.keys.toList().asMap().entries.map((entry) {
                  final key = entry.value;
                  return CheckboxListTile(
                    title: Text(_equipeLabels[key]!),
                    value: _equipes[key],
                    activeColor: const Color(0xFF1E3A5F),
                    onChanged: (v) => setState(() => _equipes[key] = v!),
                    dense: true,
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 24),

            // Submit
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton.icon(
                onPressed: _submitting ? null : _submit,
                icon: _submitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2))
                    : const Icon(Icons.local_shipping),
                label: Text(_submitting ? 'Enviando...' : 'Enviar Solicitação',
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1E3A5F),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _label(String text) => Text(
        text,
        style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: Colors.grey,
            letterSpacing: 1),
      );
}
