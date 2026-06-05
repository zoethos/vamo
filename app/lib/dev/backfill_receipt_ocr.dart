import 'package:app_core/app_core.dart';
import 'package:feature_split/feature_split.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Dev entry: `melos run backfill_receipt_ocr` — OCR backfill for place_label.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Env.load();
  await Supabase.initialize(
    url: Env.supabaseUrl,
    publishableKey: Env.supabaseAnonKey,
  );

  runApp(
    const ProviderScope(
      child: MaterialApp(home: _BackfillReceiptOcrScreen()),
    ),
  );
}

class _BackfillReceiptOcrScreen extends ConsumerStatefulWidget {
  const _BackfillReceiptOcrScreen();

  @override
  ConsumerState<_BackfillReceiptOcrScreen> createState() =>
      _BackfillReceiptOcrScreenState();
}

class _BackfillReceiptOcrScreenState
    extends ConsumerState<_BackfillReceiptOcrScreen> {
  ReceiptOcrBackfillResult? _result;
  bool _running = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _run());
  }

  Future<void> _run() async {
    setState(() => _running = true);
    final result = await ref.read(receiptOcrBackfillProvider).run();
    if (!mounted) return;
    setState(() {
      _result = result;
      _running = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Receipt OCR backfill')),
      body: Center(
        child: _running
            ? const CircularProgressIndicator()
            : Text(_result == null
                ? 'Starting…'
                : 'scanned=${_result!.scanned} updated=${_result!.updated} '
                    'places=${_result!.placesResolved} '
                    'skipped=${_result!.skipped} failed=${_result!.failed}'),
      ),
    );
  }
}
