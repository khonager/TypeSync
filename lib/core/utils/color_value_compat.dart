library;

import 'package:flutter/material.dart';

/// Serializes a [Color] to a 32-bit ARGB int across Flutter SDK versions.
int colorToArgb32(Color color) {
  final dynamic dynamicColor = color;

  try {
    return dynamicColor.toARGB32() as int;
  } on NoSuchMethodError {
    final alpha = dynamicColor.alpha as int;
    final red = dynamicColor.red as int;
    final green = dynamicColor.green as int;
    final blue = dynamicColor.blue as int;

    return (alpha << 24) | (red << 16) | (green << 8) | blue;
  }
}
