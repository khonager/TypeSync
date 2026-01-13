/// Editor Stats Widget
/// 
/// Displays line and character count in the editor header.

import 'package:flutter/material.dart';

/// Stats display for the editor
/// 
/// Shows "Lines/Char" count matching the design mockup.
class EditorStats extends StatelessWidget {
  final int lineCount;
  final int characterCount;

  const EditorStats({
    super.key,
    required this.lineCount,
    required this.characterCount,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            'Lines/Char',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Colors.grey,
              fontSize: 10,
            ),
          ),
          Text(
            '$lineCount/$characterCount',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              fontFamily: 'JetBrainsMono',
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

