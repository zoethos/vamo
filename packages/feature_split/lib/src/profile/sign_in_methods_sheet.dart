import 'package:app_core/app_core.dart';
import 'package:flutter/material.dart';

/// Account-owned OAuth linking. The user must already be authenticated; this
/// starts Supabase's reauthentication flow and never creates an app account.
class SignInMethodsSheet extends StatefulWidget {
  const SignInMethodsSheet({
    super.key,
    required this.linkedProviders,
    required this.onLink,
  });

  final Set<AuthIdentityProvider> linkedProviders;
  final Future<bool> Function(AuthIdentityProvider provider) onLink;

  @override
  State<SignInMethodsSheet> createState() => _SignInMethodsSheetState();
}

class _SignInMethodsSheetState extends State<SignInMethodsSheet> {
  AuthIdentityProvider? _linking;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(20, 20, 20, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Sign-in methods',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            _MethodRow(
              icon: Icons.email_outlined,
              label: AuthIdentityProvider.email.label,
              linked: widget.linkedProviders.contains(
                AuthIdentityProvider.email,
              ),
            ),
            _MethodRow(
              icon: Icons.g_mobiledata,
              label: AuthIdentityProvider.google.label,
              linked: widget.linkedProviders.contains(
                AuthIdentityProvider.google,
              ),
              busy: _linking == AuthIdentityProvider.google,
              onLink: () => _link(AuthIdentityProvider.google),
            ),
            _MethodRow(
              icon: Icons.apple,
              label: AuthIdentityProvider.apple.label,
              linked: widget.linkedProviders.contains(
                AuthIdentityProvider.apple,
              ),
              busy: _linking == AuthIdentityProvider.apple,
              onLink: () => _link(AuthIdentityProvider.apple),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _link(AuthIdentityProvider provider) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Link ${provider.label}?'),
        content: const Text(
          'Continue to confirm this sign-in method for your existing Vamo account.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _linking = provider);
    try {
      await widget.onLink(provider);
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) return;
      final message = error is IdentityLinkUnavailableException
          ? 'Adding a sign-in method is not enabled yet. Try again later.'
          : actionFailureUserMessage(error);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    } finally {
      if (mounted) setState(() => _linking = null);
    }
  }
}

class _MethodRow extends StatelessWidget {
  const _MethodRow({
    required this.icon,
    required this.label,
    required this.linked,
    this.busy = false,
    this.onLink,
  });

  final IconData icon;
  final String label;
  final bool linked;
  final bool busy;
  final VoidCallback? onLink;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon),
      title: Text(label),
      trailing: linked
          ? const Icon(Icons.check_circle_outline, color: AppColors.jadeTeal)
          : TextButton(
              onPressed: busy ? null : onLink,
              child: busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Link'),
            ),
    );
  }
}
