import 'package:app_core/app_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'capture_repository.dart';

/// Slice 8 — add a titled note to a solo trip.
class AddCaptureNoteScreen extends ConsumerStatefulWidget {
  const AddCaptureNoteScreen({super.key, required this.tripId});

  final String tripId;

  @override
  ConsumerState<AddCaptureNoteScreen> createState() =>
      _AddCaptureNoteScreenState();
}

class _AddCaptureNoteScreenState extends ConsumerState<AddCaptureNoteScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _bodyController = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _titleController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await ref.read(captureRepositoryProvider).addNote(
            tripId: widget.tripId,
            title: _titleController.text,
            body: _bodyController.text,
          );
      if (!mounted) return;
      context.pop();
    } catch (e) {
      if (!mounted) return;
      showActionError(
        context,
        ref,
        screen: 'capture_note',
        action: 'save_capture_note',
        error: e,
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Add note'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: _saving ? null : () => context.pop(),
        ),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            TextFormField(
              controller: _titleController,
              decoration: const InputDecoration(
                labelText: 'Title',
                hintText: 'Sunset at the beach',
              ),
              textCapitalization: TextCapitalization.sentences,
              validator: (v) {
                if (v == null || v.trim().isEmpty) return 'Add a title';
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _bodyController,
              decoration: const InputDecoration(
                labelText: 'Notes',
                hintText: 'What made this moment special?',
                alignLabelWithHint: true,
              ),
              maxLines: 6,
              textCapitalization: TextCapitalization.sentences,
            ),
            const SizedBox(height: 32),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      height: 22,
                      width: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text('Save note'),
            ),
          ],
        ),
      ),
    );
  }
}
