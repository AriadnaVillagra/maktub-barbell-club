import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:maktub_ui/maktub_ui.dart';

import '../../../core/red/api_providers.dart';
import '../../catalogo/presentation/catalog_admin_widgets.dart';
import '../../catalogo/presentation/providers.dart';
import '../data/http_members_repository.dart';
import '../domain/members_repository.dart';

final membersRepositoryProvider = Provider<MembersRepository>(
  (ref) => HttpMembersRepository(ref.watch(clienteApiProvider)),
);

final clubMembersProvider = FutureProvider<List<ClubMember>>((ref) async {
  final clubId = ref.watch(catalogClubIdProvider);
  if (clubId == null) return const [];
  return ref.watch(membersRepositoryProvider).members(clubId);
});

String _roleLabel(Rol r) => switch (r) {
  Rol.coach => 'Coach',
  Rol.atleta => 'Atleta',
  Rol.adminClub => 'Admin del club',
};

/// The club's members: a club admin registers people and changes their roles.
class MembersPage extends ConsumerWidget {
  const MembersPage({super.key});

  Future<void> _edit(BuildContext context, WidgetRef ref, ClubMember? member) async {
    final clubId = ref.read(catalogClubIdProvider);
    final repo = ref.read(membersRepositoryProvider);
    final result = await showDialog<_MemberForm>(
      context: context,
      builder: (_) => _MemberDialog(member: member),
    );
    if (result == null || clubId == null || !context.mounted) return;
    try {
      await repo.register(clubId, email: result.email, name: result.name, roles: result.roles);
      ref.invalidate(clubMembersProvider);
    } catch (e) {
      if (context.mounted) showApiError(context, e);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    appBar: AppBar(title: const Text('Miembros')),
    floatingActionButton: FloatingActionButton.extended(
      key: const Key('member-add'),
      onPressed: () => _edit(context, ref, null),
      icon: const Icon(Icons.person_add_outlined),
      label: const Text('Registrar miembro'),
    ),
    body: asyncView(
      ref.watch(clubMembersProvider),
      onRetry: () => ref.invalidate(clubMembersProvider),
      builder: (members) => ListView(
        padding: const EdgeInsets.only(bottom: Espacio.xxxl * 2),
        children: [
          for (final m in members)
            ListTile(
              key: Key('member-${m.userId}'),
              leading: const Icon(Icons.person_outline),
              title: Text(m.name),
              subtitle: Text('${m.email}\n${[for (final r in Rol.values) if (m.roles.contains(r)) _roleLabel(r)].join(' · ')}'),
              isThreeLine: true,
              onTap: () => _edit(context, ref, m),
            ),
        ],
      ),
    ),
  );
}

class _MemberForm {
  const _MemberForm(this.email, this.name, this.roles);

  final String email;
  final String name;
  final Set<Rol> roles;
}

class _MemberDialog extends StatefulWidget {
  const _MemberDialog({this.member});

  final ClubMember? member;

  @override
  State<_MemberDialog> createState() => _MemberDialogState();
}

class _MemberDialogState extends State<_MemberDialog> {
  late final _email = TextEditingController(text: widget.member?.email ?? '');
  late final _name = TextEditingController(text: widget.member?.name ?? '');
  late Set<Rol> _roles = {...?widget.member?.roles};

  @override
  void dispose() {
    _email.dispose();
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final existing = widget.member != null;
    final ready = _roles.isNotEmpty && _email.text.trim().isNotEmpty;
    return AlertDialog(
      title: Text(existing ? 'Roles de ${widget.member!.name}' : 'Registrar miembro'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: Espacio.m,
          children: [
            if (!existing) ...[
              TextField(
                key: const Key('member-email'),
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(labelText: 'Email de Google'),
                onChanged: (_) => setState(() {}),
              ),
              TextField(
                key: const Key('member-name'),
                controller: _name,
                decoration: const InputDecoration(labelText: 'Nombre'),
              ),
            ],
            Wrap(
              spacing: Espacio.s,
              children: [
                for (final r in Rol.values)
                  FilterChip(
                    key: Key('member-role-${r.cable}'),
                    label: Text(_roleLabel(r)),
                    selected: _roles.contains(r),
                    onSelected: (on) => setState(() {
                      _roles = on ? {..._roles, r} : ({..._roles}..remove(r));
                    }),
                  ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(
          key: const Key('member-save'),
          onPressed: ready
              ? () => Navigator.pop(context, _MemberForm(_email.text.trim(), _name.text.trim(), _roles))
              : null,
          child: const Text('Guardar'),
        ),
      ],
    );
  }
}
