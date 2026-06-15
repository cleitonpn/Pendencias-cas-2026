import 'package:flutter/material.dart';
import '../services/firestore_service.dart';

class SpecEditRequestsScreen extends StatefulWidget {
  const SpecEditRequestsScreen({super.key});

  @override
  State<SpecEditRequestsScreen> createState() => _SpecEditRequestsScreenState();
}

class _SpecEditRequestsScreenState extends State<SpecEditRequestsScreen> {
  List<Map<String, dynamic>> _requests = [];
  bool _loading = true;
  final Set<String> _approving = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final list = await FirestoreService.getPendingSpecEditRequests();
    if (mounted) setState(() { _requests = list; _loading = false; });
  }

  Future<void> _approve(Map<String, dynamic> req) async {
    final clientId = req['id'] as String;
    setState(() => _approving.add(clientId));
    try {
      await FirestoreService.approveSpecEditRequest(clientId);
      if (mounted) {
        setState(() {
          _requests.removeWhere((r) => r['id'] == clientId);
          _approving.remove(clientId);
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Edição liberada para o consultor.'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        setState(() => _approving.remove(clientId));
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Erro ao aprovar. Tente novamente.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  String _fmtDate(String? iso) {
    if (iso == null || iso.isEmpty) return '';
    try {
      final dt = DateTime.parse(iso).toLocal();
      final d = dt.day.toString().padLeft(2, '0');
      final mo = dt.month.toString().padLeft(2, '0');
      final h = dt.hour.toString().padLeft(2, '0');
      final mi = dt.minute.toString().padLeft(2, '0');
      return '$d/$mo ${h}h${mi}';
    } catch (_) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F2F5),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E3A5F),
        foregroundColor: Colors.white,
        title: const Text('Solicitações de Edição',
            style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _load,
            tooltip: 'Atualizar',
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _requests.isEmpty
              ? const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.check_circle_outline,
                          size: 72, color: Colors.green),
                      SizedBox(height: 16),
                      Text('Nenhuma solicitação pendente',
                          style: TextStyle(
                              color: Colors.grey,
                              fontSize: 16,
                              fontWeight: FontWeight.w500)),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _requests.length,
                  itemBuilder: (context, i) {
                    final req = _requests[i];
                    final clientId = req['id'] as String;
                    final clientName = (req['clientName'] as String?) ?? clientId;
                    final fairName = (req['fairName'] as String?) ?? '';
                    final requestedBy = (req['requestedBy'] as String?) ?? '';
                    final requestedAt = _fmtDate(req['requestedAt'] as String?);
                    final isApproving = _approving.contains(clientId);

                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      elevation: 2,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: const BorderSide(
                            color: Color(0xFFFFB74D), width: 1.5),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: Colors.orange.shade50,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Icon(Icons.edit_note,
                                      color: Colors.orange.shade700, size: 22),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(clientName,
                                          style: const TextStyle(
                                              fontSize: 15,
                                              fontWeight: FontWeight.bold)),
                                      if (fairName.isNotEmpty)
                                        Text(fairName,
                                            style: const TextStyle(
                                                fontSize: 12,
                                                color: Colors.grey)),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            if (requestedBy.isNotEmpty)
                              _InfoRow(
                                  Icons.person_outline,
                                  'Solicitado por',
                                  requestedBy),
                            if (requestedAt.isNotEmpty)
                              _InfoRow(
                                  Icons.access_time,
                                  'Data',
                                  requestedAt),
                            const SizedBox(height: 12),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton.icon(
                                onPressed: isApproving ? null : () => _approve(req),
                                icon: isApproving
                                    ? const SizedBox(
                                        width: 14,
                                        height: 14,
                                        child: CircularProgressIndicator(
                                            color: Colors.white,
                                            strokeWidth: 2))
                                    : const Icon(Icons.lock_open_outlined,
                                        size: 16),
                                label: Text(isApproving
                                    ? 'Aprovando...'
                                    : 'Liberar edição'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF1E3A5F),
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                      vertical: 12),
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8)),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _InfoRow(this.icon, this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Icon(icon, size: 14, color: Colors.grey),
          const SizedBox(width: 6),
          Text('$label: ',
              style: const TextStyle(fontSize: 12, color: Colors.grey)),
          Flexible(
            child: Text(value,
                style: const TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}
