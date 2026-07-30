import 'package:flutter/material.dart';
import '../services/directory_service.dart';

/// Lista de pessoas com busca e seleção múltipla, agrupada por papel.
///
/// A lista vem do cadastro, não da presença. Antes as telas mostravam só quem
/// estava online, então mandar um aviso para alguém dependia da pessoa estar
/// com o app aberto — exatamente o contrário do que um aviso serve.
class UserPicker extends StatefulWidget {
  final List<AppUser> users;
  final Set<String> selectedKeys;
  final ValueChanged<Set<String>> onChanged;

  /// Papéis que não podem ser desmarcados, com o motivo mostrado na tela.
  final Set<String> lockedRoles;
  final String? lockedReason;

  const UserPicker({
    super.key,
    required this.users,
    required this.selectedKeys,
    required this.onChanged,
    this.lockedRoles = const {},
    this.lockedReason,
  });

  @override
  State<UserPicker> createState() => _UserPickerState();
}

class _UserPickerState extends State<UserPicker> {
  static const _navy = Color(0xFF1E3A5F);
  final _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<AppUser> get _filtered {
    final q = _query.toLowerCase().trim();
    if (q.isEmpty) return widget.users;
    return widget.users
        .where((u) =>
            u.name.toLowerCase().contains(q) ||
            u.roleLabel.toLowerCase().contains(q) ||
            u.team.toLowerCase().contains(q))
        .toList();
  }

  void _toggle(AppUser u) {
    if (widget.lockedRoles.contains(u.role)) return;
    final next = {...widget.selectedKeys};
    if (!next.remove(u.key)) next.add(u.key);
    widget.onChanged(next);
  }

  void _toggleRole(String role, bool select) {
    if (widget.lockedRoles.contains(role)) return;
    final next = {...widget.selectedKeys};
    for (final u in _filtered.where((u) => u.role == role)) {
      if (select) {
        next.add(u.key);
      } else {
        next.remove(u.key);
      }
    }
    widget.onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final byRole = <String, List<AppUser>>{};
    for (final u in _filtered) {
      byRole.putIfAbsent(u.role, () => []).add(u);
    }
    final roles =
        DirectoryService.roles.where((r) => byRole.containsKey(r)).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _searchCtrl,
          onChanged: (v) => setState(() => _query = v),
          decoration: InputDecoration(
            hintText: 'Buscar por nome, papel ou equipe…',
            prefixIcon: const Icon(Icons.search),
            isDense: true,
            border:
                OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
        const SizedBox(height: 8),
        Text('${widget.selectedKeys.length} selecionado(s)',
            style: const TextStyle(
                fontSize: 12, color: Colors.grey, fontWeight: FontWeight.w600)),
        if (widget.lockedReason != null) ...[
          const SizedBox(height: 4),
          Text(widget.lockedReason!,
              style: const TextStyle(fontSize: 11, color: Colors.orange)),
        ],
        const SizedBox(height: 8),
        if (roles.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: Text('Ninguém encontrado.',
                  style: TextStyle(color: Colors.grey)),
            ),
          )
        else
          ...roles.map((role) {
            final list = byRole[role]!;
            final locked = widget.lockedRoles.contains(role);
            final allSelected =
                list.every((u) => widget.selectedKeys.contains(u.key));
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 8, bottom: 2),
                  child: Row(
                    children: [
                      Text(list.first.roleLabel.toUpperCase(),
                          style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: _navy,
                              letterSpacing: 0.5)),
                      const SizedBox(width: 6),
                      Text('(${list.length})',
                          style: const TextStyle(
                              fontSize: 11, color: Colors.grey)),
                      const Spacer(),
                      if (locked)
                        const Icon(Icons.lock, size: 14, color: Colors.orange)
                      else
                        TextButton(
                          style: TextButton.styleFrom(
                            padding: EdgeInsets.zero,
                            minimumSize: const Size(0, 0),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          onPressed: () => _toggleRole(role, !allSelected),
                          child: Text(
                              allSelected ? 'Limpar' : 'Todos',
                              style: const TextStyle(fontSize: 12)),
                        ),
                    ],
                  ),
                ),
                ...list.map((u) => CheckboxListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      value: widget.selectedKeys.contains(u.key),
                      onChanged: locked ? null : (_) => _toggle(u),
                      title: Text(u.name,
                          style: const TextStyle(fontSize: 14)),
                      subtitle: u.team.isEmpty
                          ? null
                          : Text(u.team,
                              style: const TextStyle(fontSize: 11)),
                    )),
              ],
            );
          }),
      ],
    );
  }
}
