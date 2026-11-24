import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:sik3/core/models/apd_item.dart';
import 'package:sik3/core/theme/sik3_theme.dart';

/// Renders a crisp pure-SVG icon for one of the 6 workshop APD items.
class ApdSvgIcon extends StatelessWidget {
  const ApdSvgIcon({
    super.key,
    required this.item,
    this.size = 24.0,
    this.color,
    this.semanticLabel,
  });

  final ApdItem item;
  final double size;
  final Color? color;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final effectiveColor =
        color ?? IconTheme.of(context).color ?? Sik3Colors.navy;

    return SvgPicture.asset(
      item.svgAssetPath,
      width: size,
      height: size,
      colorFilter: ColorFilter.mode(effectiveColor, BlendMode.srcIn),
      semanticsLabel: semanticLabel ?? item.labelId,
    );
  }
}
