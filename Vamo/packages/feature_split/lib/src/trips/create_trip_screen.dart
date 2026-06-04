import 'package:app_core/app_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'trips_models.dart';
import 'trips_repository.dart';

/// Slice 1 — create a solo trip (invite friends lands in Slice 5).
class CreateTripScreen extends ConsumerStatefulWidget {
  const CreateTripScreen({super.key});

  @override
  ConsumerState<CreateTripScreen> createState() => _CreateTripScreenState();
}

class _CreateTripScreenState extends ConsumerState<CreateTripScreen> {
  late final FlowTracker _flowTracker;

  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _destinationController = TextEditingController();

  String _baseCurrency = 'EUR';
  DateTime? _startDate;
  DateTime? _endDate;
  bool _saving = false;

  static const _currencies = kProfileCurrencies;

  @override
  void initState() {
    super.initState();
    _flowTracker = FlowTracker(
      flow: 'create_trip',
      analytics: ref.read(analyticsProvider),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadDefaultCurrency());
  }

  Future<void> _loadDefaultCurrency() async {
    try {
      final profile = await ref.read(userProfileProvider.future);
      if (mounted) setState(() => _baseCurrency = profile.baseCurrency);
    } catch (_) {
      // Profile unavailable before first sign-in edge case.
    }
  }

  @override
  void dispose() {
    _flowTracker.abandonIfIncomplete();
    _nameController.dispose();
    _destinationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('New trip'),
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
            Text(
              'Si va?',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: AppColors.tealDark,
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              'Start solo — you can invite Vamigos later.',
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: AppColors.muted),
            ),
            const SizedBox(height: 24),
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Trip name',
                hintText: 'Amalfi with the crew',
              ),
              textCapitalization: TextCapitalization.sentences,
              validator: (v) {
                if (v == null || v.trim().isEmpty) {
                  return 'Give your trip a name';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _destinationController,
              decoration: const InputDecoration(
                labelText: 'Destination (optional)',
                hintText: 'Positano, Italy',
              ),
              textCapitalization: TextCapitalization.words,
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: _baseCurrency,
              decoration: const InputDecoration(labelText: 'Base currency'),
              items: _currencies
                  .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                  .toList(),
              onChanged: _saving
                  ? null
                  : (v) => setState(() => _baseCurrency = v ?? 'EUR'),
            ),
            const SizedBox(height: 16),
            _DateRow(
              label: 'Start date',
              value: _startDate,
              onPick: _pickStart,
              onClear: () => setState(() => _startDate = null),
            ),
            const SizedBox(height: 12),
            _DateRow(
              label: 'End date',
              value: _endDate,
              onPick: _pickEnd,
              onClear: () => setState(() => _endDate = null),
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
                  : const Text('Create trip'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickStart() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _startDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
    );
    if (picked != null && mounted) setState(() => _startDate = picked);
  }

  Future<void> _pickEnd() async {
    final initial = _endDate ?? _startDate ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: _startDate ?? DateTime(2020),
      lastDate: DateTime(2035),
    );
    if (picked != null && mounted) setState(() => _endDate = picked);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_startDate != null &&
        _endDate != null &&
        _endDate!.isBefore(_startDate!)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('End date must be on or after start date.')),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      final id = await ref.read(tripsRepositoryProvider).createTrip(
            CreateTripInput(
              name: _nameController.text,
              destination: _destinationController.text.isEmpty
                  ? null
                  : _destinationController.text,
              startDate: _isoDate(_startDate),
              endDate: _isoDate(_endDate),
              baseCurrency: _baseCurrency,
            ),
          );
      if (!mounted) return;
      _flowTracker.complete();
      context.go(AppRoutes.trip(id));
    } catch (e) {
      if (!mounted) return;
      showActionError(
        context,
        ref,
        screen: 'create_trip',
        action: 'create_trip',
        error: e,
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String? _isoDate(DateTime? d) =>
      d == null ? null : DateFormat('yyyy-MM-dd').format(d);
}

class _DateRow extends StatelessWidget {
  const _DateRow({
    required this.label,
    required this.value,
    required this.onPick,
    required this.onClear,
  });

  final String label;
  final DateTime? value;
  final VoidCallback onPick;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final formatted =
        value == null ? null : DateFormat.yMMMd().format(value!);
    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: onPick,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(formatted ?? label),
            ),
          ),
        ),
        if (value != null) ...[
          const SizedBox(width: 8),
          IconButton(
            tooltip: 'Clear date',
            onPressed: onClear,
            icon: const Icon(Icons.clear),
          ),
        ],
      ],
    );
  }
}
