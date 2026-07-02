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
            _StandsPicker(
              clients: _clients,
              loading: _loadingClients,
              selectedIds: _selectedClientIds,
              onChanged: (ids) => setState(() {
                _selectedClientIds
                  ..clear()
                  ..addAll(ids);
              }),
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

// ─── Stands picker ────────────────────────────────────────────────────────────

class _StandsPicker extends StatefulWidget {
  final List<Client> clients;
  final bool loading;
  final Set<String> selectedIds;
  final ValueChanged<Set<String>> onChanged;

  const _StandsPicker({
    required this.clients,
    required this.loading,
    required this.selectedIds,
    required this.onChanged,
  });

  @override
  State<_StandsPicker> createState() => _StandsPickerState();
}

class _StandsPickerState extends State<_StandsPicker> {
  void _openSheet() async {
    final result = await showModalBottomSheet<Set<String>>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => _StandsSheet(
        clients: widget.clients,
        initial: Set<String>.from(widget.selectedIds),
      ),
    );
    if (result != null) widget.onChanged(result);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.loading) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
        ),
      );
    }
    if (widget.clients.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(12),
          child: Text('Nenhum stand disponível.',
              style: TextStyle(color: Colors.grey)),
        ),
      );
    }

    final count = widget.selectedIds.length;
    final label = count == 0
        ? 'Toda a feira'
        : count == 1
            ? '1 stand selecionado'
            : '$count stands selecionados';

    return InkWell(
      onTap: _openSheet,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.grey.shade400),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: count == 0 ? Colors.grey : const Color(0xFF1E3A5F),
                  fontStyle: count == 0 ? FontStyle.italic : FontStyle.normal,
                  fontWeight:
                      count > 0 ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ),
            Icon(Icons.arrow_drop_down,
                color: Colors.grey.shade600),
          ],
        ),
      ),
    );
  }
}

class _StandsSheet extends StatefulWidget {
  final List<Client> clients;
  final Set<String> initial;

  const _StandsSheet({required this.clients, required this.initial});

  @override
  State<_StandsSheet> createState() => _StandsSheetState();
}

class _StandsSheetState extends State<_StandsSheet> {
  late final Set<String> _selected;
  final _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _selected = Set<String>.from(widget.initial);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<Client> get _filtered {
    if (_query.isEmpty) return widget.clients;
    final q = _query.toLowerCase();
    return widget.clients
        .where((c) =>
            c.nome.toLowerCase().contains(q) ||
            c.local.toLowerCase().contains(q))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;
    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (_, scrollCtrl) => Column(
        children: [
          // Handle
          Container(
            margin: const EdgeInsets.symmetric(vertical: 10),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2)),
          ),
          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                const Expanded(
                  child: Text('Selecionar Stands',
                      style: TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold)),
                ),
                if (_selected.isNotEmpty)
                  TextButton(
                    onPressed: () => setState(() => _selected.clear()),
                    child: const Text('Limpar',
                        style: TextStyle(color: Colors.red)),
                  ),
                TextButton(
                  onPressed: () => Navigator.pop(context, _selected),
                  child: const Text('Confirmar',
                      style: TextStyle(
                          color: Color(0xFF1E3A5F),
                          fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
          // Search
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: TextField(
              controller: _searchCtrl,
              onChanged: (v) => setState(() => _query = v),
              decoration: InputDecoration(
                hintText: 'Buscar stand...',
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: _query.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: () {
                          _searchCtrl.clear();
                          setState(() => _query = '');
                        })
                    : null,
                filled: true,
                fillColor: Colors.grey.shade100,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none),
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
              ),
            ),
          ),
          const Divider(height: 1),
          // List
          Expanded(
            child: filtered.isEmpty
                ? const Center(
                    child: Text('Nenhum stand encontrado.',
                        style: TextStyle(color: Colors.grey)))
                : ListView.builder(
                    controller: scrollCtrl,
                    itemCount: filtered.length,
                    itemBuilder: (_, i) {
                      final c = filtered[i];
                      final sel = _selected.contains(c.firestoreId);
                      return CheckboxListTile(
                        value: sel,
                        activeColor: const Color(0xFF1E3A5F),
                        title: Text(c.displayName,
                            style: const TextStyle(
                                fontWeight: FontWeight.w500)),
                        subtitle: c.local.isNotEmpty
                            ? Text('Local: ${c.local}',
                                style: const TextStyle(fontSize: 12))
                            : null,
                        onChanged: (v) => setState(() {
                          if (v == true) {
                            _selected.add(c.firestoreId);
                          } else {
                            _selected.remove(c.firestoreId);
                          }
                        }),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
