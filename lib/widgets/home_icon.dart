import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';

class HomeIcon extends StatelessWidget {
  final double size;

  const HomeIcon({super.key, required this.size});

  @override
  Widget build(BuildContext context) {
    return SvgPicture.asset(
      'assets/icons/home.svg',
      width: size,
      height: size,
      fit: BoxFit.contain,
      excludeFromSemantics: true,
    );
  }
}
