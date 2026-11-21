import 'package:flutter/material.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:maktub_ui/maktub_ui.dart';

/// What someone without an account fills in to ask for a club for their team.
typedef ClubRequestFields = ({String clubName, String requesterName, String? note});

/// The club request form on the sign-in screen: the club's name, the requester's name and an optional note.
/// It keeps what was typed while a send is in flight or after it fails.
class ClubRequestForm extends StatefulWidget {
  const ClubRequestForm({super.key, required this.onSubmit, required this.onCancel, this.sending = false});

  final ValueChanged<ClubRequestFields> onSubmit;
  final VoidCallback onCancel;
  final bool sending;

  @override
  State<ClubRequestForm> createState() => _ClubRequestFormState();
}

class _ClubRequestFormState extends State<ClubRequestForm> {
  final _club = TextEditingController();
  final _name = TextEditingController();
  final _note = TextEditingController();

  @override
  void dispose() {
    _club.dispose();
    _name.dispose();
    _note.dispose();
    super.dispose();
  }

  List<String> get _problems =>
      ClubRequest.problems(clubName: _club.text.trim(), requesterName: _name.text.trim(), note: _note.text.trim());

  void _submit() {
    if (_problems.isNotEmpty || widget.sending) return;
    final note = _note.text.trim();
    widget.onSubmit((clubName: _club.text.trim(), requesterName: _name.text.trim(), note: note.isEmpty ? null : note));
  }

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    spacing: Espacio.m,
    children: [
      TextField(
        key: const Key('club-request-club'),
        controller: _club,
        enabled: !widget.sending,
        maxLength: ClubRequest.maxClubName,
        textCapitalization: TextCapitalization.words,
        decoration: const InputDecoration(labelText: 'Nombre del club'),
        onChanged: (_) => setState(() {}),
      ),
      TextField(
        key: const Key('club-request-name'),
        controller: _name,
        enabled: !widget.sending,
        maxLength: ClubRequest.maxRequesterName,
        textCapitalization: TextCapitalization.words,
        decoration: const InputDecoration(labelText: 'Tu nombre'),
        onChanged: (_) => setState(() {}),
      ),
      TextField(
        key: const Key('club-request-note'),
        controller: _note,
        enabled: !widget.sending,
        maxLength: ClubRequest.maxNote,
        minLines: 2,
        maxLines: 4,
        decoration: const InputDecoration(
          labelText: 'Nota (opcional)',
          hintText: 'Quiénes son, cuántos entrenan…',
        ),
        onChanged: (_) => setState(() {}),
      ),
      FilledButton(
        key: const Key('club-request-send'),
        onPressed: _problems.isEmpty && !widget.sending ? _submit : null,
        child: const Text('Enviar pedido'),
      ),
      TextButton(
        key: const Key('club-request-cancel'),
        onPressed: widget.sending ? null : widget.onCancel,
        child: const Text('Volver al ingreso'),
      ),
    ],
  );
}
