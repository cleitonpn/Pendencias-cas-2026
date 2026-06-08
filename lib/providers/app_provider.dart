import 'package:flutter/material.dart';
import '../models/client.dart';
import '../models/fair.dart';
import '../models/pending_item.dart';
import '../services/sheets_service.dart';
import '../services/database_service.dart';

class AppProvider extends ChangeNotifier {
  List<Fair> _fairs = [];
  Fair? _currentFair;
  List<Client> _clients = [];
  List<String> _hangars = [];
  bool _isLoading = false;
  String? _error;
  DateTime? _lastSync;

  List<Fair> get fairs => _fairs;
  Fair? get currentFair => _currentFair;
  String get currentFairName => _currentFair?.name ?? 'Pendências';
  List<Client> get clients => _clients;
  List<String> get hangars => _hangars;
  bool get isLoading => _isLoading;
  String? get error => _error;
  DateTime? get lastSync => _lastSync;

  Future<void> init() async {
    _fairs = await DatabaseService.getFairs();
    notifyListeners();
  }

  Future<void> selectFair(Fair fair) async {
    _currentFair = fair;
    _lastSync = null;
    _error = null;
    _setLoading(true);
    await _loadLocal();
    _setLoading(false);
  }

  Future<void> loadFromLocal() async {
    if (_currentFair == null) return;
    _setLoading(true);
    await _loadLocal();
    _setLoading(false);
  }

  Future<void> syncFromSheets() async {
    if (_currentFair == null) return;
    _error = null;
    _setLoading(true);
    try {
      final sheetClients = await SheetsService.fetchClients(
        spreadsheetId: _currentFair!.spreadsheetId,
        sheetName: _currentFair!.sheetName,
        fairId: _currentFair!.id!,
      );

      // Preserve local completion status
      final localMap = {for (final c in _clients) c.rowId: c};
      for (final c in sheetClients) {
        final local = localMap[c.rowId];
        if (local != null) {
          c.isCompleted = local.isCompleted;
          c.completedAt = local.completedAt;
        }
      }

      await DatabaseService.upsertClients(sheetClients);
      await _loadLocal();
      _lastSync = DateTime.now();
    } catch (e) {
      _error = e.toString().replaceFirst('Exception: ', '');
    } finally {
      _setLoading(false);
    }
  }

  Future<void> _loadLocal() async {
    if (_currentFair == null) return;
    _clients = await DatabaseService.getClients(fairId: _currentFair!.id!);
    _hangars = await DatabaseService.getHangars(fairId: _currentFair!.id!);
    notifyListeners();
  }

  void _setLoading(bool v) {
    _isLoading = v;
    notifyListeners();
  }

  List<Client> getClientsByHangar(String hangar) {
    final list =
        (hangar == 'Externos' || hangar == 'Todos os Stands')
            ? _clients.where((c) => c.hangar.isEmpty).toList()
            : _clients.where((c) => c.hangar == hangar).toList();
    return list..sort((a, b) => a.local.compareTo(b.local));
  }

  Future<void> markClientCompleted(Client client, bool completed) async {
    await DatabaseService.updateClientStatus(client.rowId, completed);
    client.isCompleted = completed;
    client.completedAt = completed ? DateTime.now() : null;
    notifyListeners();
  }

  Future<PendingItem> addPendingItem(PendingItem item) async {
    final id = await DatabaseService.insertPendingItem(item);
    return PendingItem(
      id: id,
      clientId: item.clientId,
      clientName: item.clientName,
      local: item.local,
      hangar: item.hangar,
      team: item.team,
      responsible: item.responsible,
      description: item.description,
      createdAt: item.createdAt,
    );
  }

  Future<void> resolveItem(int id) async {
    await DatabaseService.resolvePendingItem(id);
    notifyListeners();
  }

  Future<Fair> addFair(
      String name, String spreadsheetId, String sheetName) async {
    final fair = Fair(
      name: name,
      spreadsheetId: spreadsheetId,
      sheetName: sheetName,
      createdAt: DateTime.now(),
    );
    final id = await DatabaseService.insertFair(fair);
    _fairs = await DatabaseService.getFairs();
    notifyListeners();
    return Fair(
        id: id,
        name: fair.name,
        spreadsheetId: fair.spreadsheetId,
        sheetName: fair.sheetName,
        createdAt: fair.createdAt);
  }

  Future<void> deleteFair(int id) async {
    await DatabaseService.deleteFair(id);
    if (_currentFair?.id == id) {
      _currentFair = null;
      _clients = [];
      _hangars = [];
    }
    _fairs = await DatabaseService.getFairs();
    notifyListeners();
  }
}
