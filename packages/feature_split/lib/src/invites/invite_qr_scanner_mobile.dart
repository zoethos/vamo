import 'package:app_core/app_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'invite_channel.dart';
import 'invite_labels.dart';
import 'invite_route.dart';

bool get isInviteQrScanSupported => true;

Future<void> showInviteQrScannerSheet({
  required BuildContext context,
  required WidgetRef ref,
  required InviteLabels labels,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (ctx) => _InviteQrScannerSheet(
      ref: ref,
      labels: labels,
    ),
  );
}

class _InviteQrScannerSheet extends ConsumerStatefulWidget {
  const _InviteQrScannerSheet({
    required this.ref,
    required this.labels,
  });

  final WidgetRef ref;
  final InviteLabels labels;

  @override
  ConsumerState<_InviteQrScannerSheet> createState() =>
      _InviteQrScannerSheetState();
}

class _InviteQrScannerSheetState extends ConsumerState<_InviteQrScannerSheet> {
  final _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
  );
  final _pasteController = TextEditingController();
  bool _handled = false;
  String? _error;
  bool _cameraDenied = false;

  @override
  void dispose() {
    _controller.dispose();
    _pasteController.dispose();
    super.dispose();
  }

  void _acceptToken(String token) {
    if (_handled) return;
    _handled = true;
    Navigator.of(context).pop();
    routeInviteToken(
      context: context,
      ref: widget.ref,
      token: token,
      channel: InviteChannel.qr,
    );
  }

  void _onDetect(BarcodeCapture capture) {
    if (_handled) return;
    for (final barcode in capture.barcodes) {
      final raw = barcode.rawValue;
      if (raw == null) continue;
      final token = InviteUrls.parseTokenFromString(raw);
      if (token != null) {
        _acceptToken(token);
        return;
      }
    }
  }

  void _onPasteJoin() {
    final token = InviteUrls.parseTokenFromString(_pasteController.text);
    if (token == null) {
      setState(() => _error = widget.labels.notVamoInvite);
      return;
    }
    _acceptToken(token);
  }

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.sizeOf(context).height * 0.88;

    return SizedBox(
      height: height,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(20, 8, 20, 0),
            child: Text(
              widget.labels.scannerTitle,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: AppColors.ink,
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ),
          const SizedBox(height: 12),
          if (!_cameraDenied)
            Expanded(
              flex: 3,
              child: Padding(
                padding: const EdgeInsetsDirectional.symmetric(horizontal: 16),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: MobileScanner(
                    controller: _controller,
                    onDetect: _onDetect,
                    errorBuilder: (context, error, child) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted) setState(() => _cameraDenied = true);
                      });
                      return Center(
                        child: Text(
                          widget.labels.cameraDenied,
                          textAlign: TextAlign.center,
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(color: AppColors.graphite),
                        ),
                      );
                    },
                  ),
                ),
              ),
            )
          else
            Padding(
              padding: const EdgeInsetsDirectional.all(20),
              child: Text(
                widget.labels.cameraDenied,
                textAlign: TextAlign.center,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: AppColors.graphite),
              ),
            ),
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(20, 16, 20, 8),
            child: Text(
              widget.labels.pasteLink,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
          Padding(
            padding: const EdgeInsetsDirectional.symmetric(horizontal: 20),
            child: TextField(
              controller: _pasteController,
              decoration: InputDecoration(
                hintText: widget.labels.pasteHint,
                errorText: _error,
              ),
              keyboardType: TextInputType.url,
              autocorrect: false,
            ),
          ),
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(20, 12, 20, 20),
            child: FilledButton(
              onPressed: _onPasteJoin,
              child: Text(widget.labels.pasteJoin),
            ),
          ),
        ],
      ),
    );
  }
}
