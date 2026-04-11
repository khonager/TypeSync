// ignore_for_file: deprecated_member_use

library;

final RegExp _basicEmailPattern = RegExp(
  r'^[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}$',
  caseSensitive: false,
);

String? validateEmailAddress(String? value) {
  final email = value?.trim() ?? '';
  if (email.isEmpty) {
    return 'Email is required';
  }

  if (!_basicEmailPattern.hasMatch(email)) {
    if (email.endsWith('.con')) {
      return 'Enter a valid email. Did you mean .com?';
    }
    return 'Enter a valid email';
  }

  return null;
}
