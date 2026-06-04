import 'package:app_core/app_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Slice 11 — suggest a feature (layer 4); text in Postgres only.
class SuggestFeatureScreen extends ConsumerStatefulWidget {
  const SuggestFeatureScreen({super.key});

  @override
  ConsumerState<SuggestFeatureScreen> createState() =>
      _SuggestFeatureScreenState();
}

class _SuggestFeatureScreenState extends ConsumerState<SuggestFeatureScreen> {
  final _bodyController = TextEditingController();
  String _category = 'other';
  bool _submitting = false;
  bool _submitted = false;

  @override
  void dispose() {
    _bodyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_submitted) {
      return Scaffold(
        appBar: AppBar(title: const Text('Suggest a feature')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.favorite_outline,
                    size: 56, color: AppColors.teal),
                const SizedBox(height: 16),
                Text(
                  'Thank you — we read every one',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: AppColors.tealDark,
                      ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Really. Your idea is in our queue; we triage from the '
                  'database, not from analytics.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: AppColors.muted),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Suggest a feature')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            'What should Vamo do next?',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: AppColors.tealDark,
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            'One idea per submission. We keep the full text private — only the '
            'category is logged to analytics.',
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: AppColors.muted),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _bodyController,
            maxLines: 6,
            maxLength: 500,
            decoration: const InputDecoration(
              labelText: 'Your idea',
              hintText: 'I wish I could…',
              alignLabelWithHint: true,
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 16),
          Text(
            'Category (optional)',
            style: Theme.of(context).textTheme.labelLarge,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              for (final c in kSuggestionCategories)
                ChoiceChip(
                  label: Text(c),
                  selected: _category == c,
                  onSelected: (_) => setState(() => _category = c),
                ),
            ],
          ),
          const SizedBox(height: 28),
          FilledButton(
            onPressed: _bodyController.text.trim().isEmpty || _submitting
                ? null
                : _submit,
            child: _submitting
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Send suggestion'),
          ),
        ],
      ),
    );
  }

  Future<void> _submit() async {
    setState(() => _submitting = true);
    try {
      await ref.read(suggestionsRepositoryProvider).submit(
            body: _bodyController.text,
            category: _category,
          );
      ref.read(analyticsProvider).capture(
            VamoEvent.suggestionSubmitted,
            properties: {'category': _category},
          );
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _submitted = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      showActionError(
        context,
        ref,
        screen: 'suggest_feature',
        action: 'submit_suggestion',
        error: e,
      );
    }
  }
}
