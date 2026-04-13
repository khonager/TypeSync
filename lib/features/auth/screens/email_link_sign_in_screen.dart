library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/routes/app_router.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/utils/email_validation.dart';

class EmailLinkSignInScreen extends StatefulWidget {
  const EmailLinkSignInScreen({super.key});

  @override
  State<EmailLinkSignInScreen> createState() => _EmailLinkSignInScreenState();
}

class _EmailLinkSignInScreenState extends State<EmailLinkSignInScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _emailController;
  bool _attemptedAutoComplete = false;

  @override
  void initState() {
    super.initState();
    final initialEmail = Uri.base.queryParameters['email'] ??
        context.read<AuthService>().pendingEmailLinkEmail ??
        '';
    _emailController = TextEditingController(text: initialEmail);
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeCompleteSignIn());
  }

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _maybeCompleteSignIn() async {
    if (!mounted || _attemptedAutoComplete) {
      return;
    }

    _attemptedAutoComplete = true;
    final authService = context.read<AuthService>();
    final emailLink = Uri.base.toString();

    if (!kIsWeb || !authService.isSignInLink(emailLink)) {
      return;
    }

    if (_emailController.text.trim().isEmpty) {
      return;
    }

    final success = await authService.completeSignInWithEmailLink(
      email: _emailController.text,
      emailLink: emailLink,
    );

    if (!mounted) {
      return;
    }

    if (success) {
      AppRouter.navigateAndClearStack(context, AppRouter.home);
    }
  }

  Future<void> _handleContinue() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final authService = context.read<AuthService>();
    final success = await authService.completeSignInWithEmailLink(
      email: _emailController.text,
      emailLink: Uri.base.toString(),
    );

    if (!mounted) {
      return;
    }

    if (success) {
      AppRouter.navigateAndClearStack(context, AppRouter.home);
    }
  }

  @override
  Widget build(BuildContext context) {
    final authService = context.watch<AuthService>();
    final isValidEmailLink =
        !kIsWeb || authService.isSignInLink(Uri.base.toString());

    return Scaffold(
      appBar: AppBar(
        title: const Text('Finish Sign In'),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(
                    isValidEmailLink ? Icons.mark_email_read : Icons.link_off,
                    size: 56,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(height: 24),
                  Text(
                    isValidEmailLink ? 'Finish signing in' : 'Link unavailable',
                    style: Theme.of(context).textTheme.headlineSmall,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    isValidEmailLink
                        ? 'Use the email address that requested the TypeSync sign-in link.'
                        : 'This email sign-in link is missing or no longer valid.',
                    style: Theme.of(context).textTheme.bodyMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  if (authService.hasError)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Text(
                        authService.errorMessage ?? '',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  TextFormField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      labelText: 'Email',
                      hintText: 'name@example.com',
                      prefixIcon: Icon(Icons.email_outlined),
                    ),
                    validator: validateEmailAddress,
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: authService.isLoading || !isValidEmailLink
                        ? null
                        : _handleContinue,
                    child: authService.isLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Continue'),
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: () {
                      AppRouter.navigateAndClearStack(context, AppRouter.login);
                    },
                    child: const Text('Back to Sign In'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
