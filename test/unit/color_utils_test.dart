import 'package:flutter_test/flutter_test.dart';
import 'package:typesync/core/utils/color_utils.dart';

void main() {
  double contrastRatio(double foreground, double background) {
    final lighter = foreground > background ? foreground : background;
    final darker = foreground > background ? background : foreground;
    return (lighter + 0.05) / (darker + 0.05);
  }

  test('note surfaces have readable automatic foregrounds', () {
    for (final colorOption in AppColorPalette.noteBackgroundColors) {
      final surface = AppColorPalette.resolveBackgroundColor(colorOption.hex);
      final foreground = AppColorPalette.getContrastingTextColor(surface);
      expect(
        contrastRatio(
          foreground.computeLuminance(),
          surface.computeLuminance(),
        ),
        greaterThanOrEqualTo(4.5),
        reason: '${colorOption.name} must support normal-sized text',
      );
    }
  });

  test('legacy note backgrounds resolve to the updated palette', () {
    expect(
      AppColorPalette.resolveBackgroundColor('#6BCB77'),
      AppColorPalette.parseHexColor('#DCE9DE'),
    );
    expect(
      AppColorPalette.matchesBackgroundColor('#FFB88C', '#FFB88C'),
      isTrue,
    );
  });
}
