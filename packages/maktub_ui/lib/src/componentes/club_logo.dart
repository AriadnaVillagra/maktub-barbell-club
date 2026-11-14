import 'package:flutter/widgets.dart';

/// The Maktub Barbell Club crest. It reserves its [size] before the image loads, so the layout
/// doesn't jump, and it needs no network: the image is bundled with this package.
class ClubLogo extends StatelessWidget {
  const ClubLogo({super.key, this.size = ClubLogo.large});

  /// For the head of a screen, such as sign-in.
  static const large = 160.0;

  static const _asset = 'assets/logo-club.png';

  final double size;

  @override
  Widget build(BuildContext context) => Image.asset(
        _asset,
        package: 'maktub_ui',
        width: size,
        height: size,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.medium,
        semanticLabel: 'Logo de Maktub Barbell Club',
      );
}
