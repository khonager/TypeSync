/// Login Screen
///
/// User authentication screen with email/password login.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../core/services/auth_service.dart';
import '../../../core/services/auth_persistence_diagnostics.dart';
import '../../../core/routes/app_router.dart';
import '../../../core/utils/email_validation.dart';
import '../../../core/widgets/desktop_window_frame.dart';
import 'magic_link_dialog.dart';
import '../widgets/auth_text_field.dart';
import '../widgets/expandable_error.dart';

/// Login screen with email/password authentication
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) return;

    final authService = context.read<AuthService>();
    final success = await authService.signIn(
      email: _emailController.text,
      password: _passwordController.text,
    );

    if (success && mounted) {
      AppRouter.navigateAndClearStack(context, AppRouter.home);
    }
  }

  Future<void> _handleGuestMode() async {
    final authService = context.read<AuthService>();
    await authService.signInAsGuest();

    if (mounted) {
      AppRouter.navigateAndClearStack(context, AppRouter.home);
    }
  }

  @override
  Widget build(BuildContext context) {
    final authService = context.watch<AuthService>();
    final authDiagnostics = context.watch<AuthPersistenceDiagnostics>();

    return Scaffold(
      body: Column(
        children: [
          if (supportsCustomDesktopWindowFrame)
            const DesktopWindowHeader(
              title: Text('typesync'),
            ),
          Expanded(
            child: SafeArea(
              top: !supportsCustomDesktopWindowFrame,
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Logo/Icon (Enter key icon as per requirements)
                        Container(
                          width: 80,
                          height: 80,
                          margin: const EdgeInsets.only(bottom: 32),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.surface,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Center(
                            child: Icon(
                              Icons.keyboard_return,
                              size: 40,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ),
                        ),

                        // Title
                        Text(
                          'Welcome back',
                          style: Theme.of(context).textTheme.headlineMedium,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Sign in to continue',
                          style:
                              Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    color: Colors.grey,
                                  ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 32),

                        if (authDiagnostics.suspectedUnexpectedSignOut)
                          Container(
                            margin: const EdgeInsets.only(bottom: 16),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color:
                                  Theme.of(context).colorScheme.errorContainer,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Column(
                              children: [
                                Text(
                                  'Firebase did not restore the previous '
                                  'session even though app storage survived.',
                                  style: TextStyle(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onErrorContainer,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                                TextButton(
                                  onPressed: _showAuthDiagnostics,
                                  child: const Text('View startup report'),
                                ),
                              ],
                            ),
                          ),

                        // Error message (expandable)
                        if (authService.hasError)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 16),
                            child: ExpandableError(
                              message: authService.errorMessage ??
                                  'An error occurred',
                              onDismiss: authService.clearError,
                            ),
                          ),

                        // Email field
                        AuthTextField(
                          controller: _emailController,
                          label: 'Email',
                          hint: 'Enter your email',
                          keyboardType: TextInputType.emailAddress,
                          textInputAction: TextInputAction.next,
                          prefixIcon: Icons.email_outlined,
                          validator: validateEmailAddress,
                        ),
                        const SizedBox(height: 16),

                        // Password field
                        AuthTextField(
                          controller: _passwordController,
                          label: 'Password',
                          hint: 'Enter your password',
                          obscureText: _obscurePassword,
                          textInputAction: TextInputAction.done,
                          onFieldSubmitted: (_) => _handleLogin(),
                          prefixIcon: Icons.lock_outline,
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscurePassword
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                            ),
                            onPressed: () {
                              setState(
                                () => _obscurePassword = !_obscurePassword,
                              );
                            },
                          ),
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return 'Password is required';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 8),

                        // Forgot password
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            onPressed: _showForgotPassword,
                            child: const Text('Forgot password?'),
                          ),
                        ),
                        const SizedBox(height: 24),

                        // Login button
                        ElevatedButton(
                          onPressed:
                              authService.isLoading ? null : _handleLogin,
                          child: authService.isLoading
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Text('Sign In'),
                        ),
                        const SizedBox(height: 12),
                        TextButton(
                          onPressed: authService.isLoading
                              ? null
                              : () {
                                  showDialog(
                                    context: context,
                                    builder: (context) =>
                                        const MagicLinkDialog(),
                                  );
                                },
                          child: const Text('Email me a sign-in link'),
                        ),
                        const SizedBox(height: 16),

                        // Register link
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              "Don't have an account? ",
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                            TextButton(
                              onPressed: () {
                                AppRouter.navigateTo(
                                  context,
                                  AppRouter.register,
                                );
                              },
                              child: const Text('Sign Up'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),

                        // Guest mode button
                        OutlinedButton(
                          onPressed:
                              authService.isLoading ? null : _handleGuestMode,
                          child: const Text('Continue as Guest'),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Use the app locally without an account',
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: Colors.grey,
                                  ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        TextButton.icon(
                          onPressed: _showAuthDiagnostics,
                          icon: const Icon(Icons.bug_report_outlined, size: 18),
                          label: const Text('Authentication diagnostics'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showForgotPassword() {
    showDialog(
      context: context,
      builder: (context) => _ForgotPasswordDialog(),
    );
  }

  void _showAuthDiagnostics() {
    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Authentication diagnostics'),
          content: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: 640,
              maxHeight: 440,
            ),
            child: Consumer<AuthPersistenceDiagnostics>(
              builder: (context, diagnostics, child) {
                return SingleChildScrollView(
                  child: SelectableText(
                    diagnostics.exportText(),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontFamily: 'monospace',
                        ),
                  ),
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () async {
                final report =
                    context.read<AuthPersistenceDiagnostics>().exportText();
                await Clipboard.setData(ClipboardData(text: report));
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Authentication report copied'),
                  ),
                );
              },
              child: const Text('Copy'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }
}

/// Forgot password dialog
class _ForgotPasswordDialog extends StatefulWidget {
  @override
  State<_ForgotPasswordDialog> createState() => _ForgotPasswordDialogState();
}

class _ForgotPasswordDialogState extends State<_ForgotPasswordDialog> {
  final _emailController = TextEditingController();
  bool _sent = false;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _sendResetEmail() async {
    if (_emailController.text.isEmpty) return;

    final authService = context.read<AuthService>();
    final success = await authService.resetPassword(_emailController.text);

    if (success) {
      setState(() => _sent = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final authService = context.watch<AuthService>();

    return AlertDialog(
      title: Text(_sent ? 'Email Sent' : 'Reset Password'),
      content: _sent
          ? const Text(
              'Check your email for a link to reset your password.',
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Enter your email address and we\'ll send you a link to reset your password.',
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _emailController,
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    hintText: 'Enter your email',
                  ),
                  keyboardType: TextInputType.emailAddress,
                ),
                if (authService.hasError)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      authService.errorMessage ?? '',
                      style: const TextStyle(color: Colors.red, fontSize: 12),
                    ),
                  ),
              ],
            ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(_sent ? 'Close' : 'Cancel'),
        ),
        if (!_sent)
          ElevatedButton(
            onPressed: authService.isLoading ? null : _sendResetEmail,
            child: authService.isLoading
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Send'),
          ),
      ],
    );
  }
}
