/// Expandable Error Widget
///
/// Error message that expands on tap to show more details.
/// Simple view by default for users, detailed view on tap.

import 'package:flutter/material.dart';

/// Error display with expandable details
///
/// Shows a simplified error message by default.
/// Tap to expand and see full error details.
class ExpandableError extends StatefulWidget {
  final String message;
  final String? details;
  final VoidCallback? onDismiss;

  const ExpandableError({
    super.key,
    required this.message,
    this.details,
    this.onDismiss,
  });

  @override
  State<ExpandableError> createState() => _ExpandableErrorState();
}

class _ExpandableErrorState extends State<ExpandableError> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      decoration: BoxDecoration(
        color: Colors.red.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.red.withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => setState(() => _isExpanded = !_isExpanded),
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.error_outline,
                      color: Colors.red,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        widget.message,
                        style: const TextStyle(
                          color: Colors.red,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    // Expand indicator
                    Icon(
                      _isExpanded ? Icons.expand_less : Icons.expand_more,
                      color: Colors.red.withOpacity(0.7),
                    ),
                    if (widget.onDismiss != null)
                      IconButton(
                        icon: const Icon(Icons.close, size: 16),
                        onPressed: widget.onDismiss,
                        color: Colors.red.withOpacity(0.7),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                  ],
                ),
                // Expanded details
                if (_isExpanded) ...[
                  const SizedBox(height: 8),
                  const Divider(color: Colors.red, height: 1),
                  const SizedBox(height: 8),
                  Text(
                    widget.details ?? _getDetailedMessage(),
                    style: TextStyle(
                      color: Colors.red.withOpacity(0.8),
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Tap to collapse',
                    style: TextStyle(
                      color: Colors.red.withOpacity(0.5),
                      fontSize: 10,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _getDetailedMessage() {
    // Provide more context based on the error message
    if (widget.message.contains('password')) {
      return 'Password errors usually occur when:\n'
          '• The password is incorrect\n'
          '• The password doesn\'t meet requirements (min 6 characters)\n'
          '• Caps lock might be on';
    }
    if (widget.message.contains('email')) {
      return 'Email errors usually occur when:\n'
          '• The email format is invalid\n'
          '• The email is already registered\n'
          '• The email doesn\'t exist in our system';
    }
    if (widget.message.contains('network') ||
        widget.message.contains('connection')) {
      return 'Network errors usually occur when:\n'
          '• You have no internet connection\n'
          '• The server is temporarily unavailable\n'
          '• Your firewall might be blocking the connection';
    }
    return 'If this error persists, try:\n'
        '• Checking your internet connection\n'
        '• Refreshing the page\n'
        '• Contacting support';
  }
}
