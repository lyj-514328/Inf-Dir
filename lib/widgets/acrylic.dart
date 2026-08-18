import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

/// Win11 Acrylic 毛玻璃材质（复刻 fluent_ui 的 Acrylic 实现，不引入
/// fluent_ui 依赖）。
///
/// 视觉管线与 fluent_ui 当前实现保持一致：
/// 1. 高斯模糊 [blurAmount]（默认 30）处理背景；
/// 2. luminosity 层 + 红/绿/蓝三色 saturation 增强（Win11 官方算法）；
/// 3. tint 叠色，其最终透明度由 HSV 亮度修正（`tintAlpha` 仅作声明参数，
///    与参考实现一致——有效透明度由 [AcrylicHelper] 计算）；
/// 4. 外层按 Figma 规范绘制双层投影。
///
/// 与参考实现的差异：噪点纹理（2% 透明度的 AcrylicNoise）暂以留白代替，
/// 不影响整体观感；材质层用 [MaterialType.transparency] 承载子组件，
/// 保证 InkWell 等 material 交互正常。
class Acrylic extends StatelessWidget {
  const Acrylic({
    super.key,
    required this.tint,
    this.tintAlpha = 0.8,
    this.luminosityAlpha = 0.8,
    this.blurAmount = 30,
    this.shape,
    this.shadowColor,
    this.elevation = 0,
    this.child,
  });

  /// 叠色主色调；无 FluentTheme 可回退，必须显式传入。
  final Color tint;

  /// tint 透明度声明值（与参考实现一致，最终透明度由 HSV 修正计算）。
  final double tintAlpha;

  /// luminosity 层透明度，默认 0.8。
  final double luminosityAlpha;

  /// 背景高斯模糊强度，默认 30。
  final double blurAmount;

  /// 形状（含圆角与描边），默认直角矩形。
  final ShapeBorder? shape;

  /// 投影颜色，默认黑色半透明由 [elevation] 决定。
  final Color? shadowColor;

  /// 投影高度（z 坐标），默认 0。
  final double elevation;

  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final shape = this.shape ?? const RoundedRectangleBorder();
    final shadowColor = this.shadowColor ?? Colors.black;
    // Figma 官方双层阴影：外层大而淡（0.13），内层小而深（0.11）。
    final shadows = [
      BoxShadow(
        color: shadowColor.withValues(alpha: 0.13),
        blurRadius: 0.9 * elevation,
        offset: Offset(0, 0.4 * elevation),
      ),
      BoxShadow(
        color: shadowColor.withValues(alpha: 0.11),
        blurRadius: 0.225 * elevation,
        offset: Offset(0, 0.085 * elevation),
      ),
    ];

    return DecoratedBox(
      decoration: ShapeDecoration(shape: shape, shadows: shadows),
      child: ClipPath(
        clipper: ShapeBorderClipper(shape: shape),
        child: CustomPaint(
          isComplex: true,
          painter: _AcrylicPainter(
            tintColor: AcrylicHelper.getEffectiveTintColor(
              tint,
              AcrylicHelper.getTintOpacityModifier(tint),
            ),
            luminosityColor: AcrylicHelper.getLuminosityColor(
              tint,
              luminosityAlpha,
            ),
          ),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: blurAmount, sigmaY: blurAmount),
            child: Material(
              type: MaterialType.transparency,
              shape: shape,
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

class _AcrylicPainter extends CustomPainter {
  // Win11 acrylic 算法固定的混色输入（饱和度增强三基色），非主题色。
  static final Color red = const Color(0xFFFF0000).withValues(alpha: 0.12);
  static final Color blue = const Color(0xFF00FF00).withValues(alpha: 0.12);
  static final Color green = const Color(0xFF0000FF).withValues(alpha: 0.12);

  final Color luminosityColor;
  final Color tintColor;

  const _AcrylicPainter({
    required this.luminosityColor,
    required this.tintColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    canvas
      ..drawColor(luminosityColor, BlendMode.luminosity)
      ..drawColor(red, BlendMode.saturation)
      ..drawColor(blue, BlendMode.saturation)
      ..drawColor(green, BlendMode.saturation)
      ..drawColor(
        tintColor,
        tintColor.a == 1 ? BlendMode.srcIn : BlendMode.color,
      );
  }

  @override
  bool shouldRepaint(covariant _AcrylicPainter old) {
    return luminosityColor != old.luminosityColor ||
        tintColor != old.tintColor;
  }
}

/// 微软官方算法（自 fluent_ui 移植）：根据 tint 的 HSV 亮度计算
/// 有效透明度与 luminosity 层颜色。
abstract final class AcrylicHelper {
  /// tint 有效透明度：HSV 值越亮越透明（0.45），越暗越不透明（0.85）。
  static double getTintOpacityModifier(Color color) {
    // Mid point of HsvV range that these calculations are based on.
    const midPoint = 0.50;

    const whiteMaxOpacity = 0.45; // 100% luminosity
    const midPointMaxOpacity = 0.90; // 50% luminosity
    const blackMaxOpacity = 0.85; // 0% luminosity

    final hsv = HSVColor.fromColor(color);

    var opacityModifier = midPointMaxOpacity;

    if (hsv.value != midPoint) {
      var lowestMaxOpacity = midPointMaxOpacity;
      var maxDeviation = midPoint;

      if (hsv.value > midPoint) {
        lowestMaxOpacity = whiteMaxOpacity; // At white (100% hsvV)
        maxDeviation = 1 - maxDeviation;
      } else if (hsv.value < midPoint) {
        lowestMaxOpacity = blackMaxOpacity; // At black (0% hsvV)
      }

      var maxOpacitySuppression = midPointMaxOpacity - lowestMaxOpacity;

      final deviation = hsv.value - midPoint;
      final normalizedDeviation = deviation / maxDeviation;

      // Saturation damps the suppression so color can come through more.
      if (hsv.saturation > 0) {
        maxOpacitySuppression *= math.max(1 - (hsv.saturation * 2), 0.0);
      }

      final opacitySuppression = maxOpacitySuppression * normalizedDeviation;
      opacityModifier = midPointMaxOpacity - opacitySuppression;
    }

    return opacityModifier;
  }

  static Color getEffectiveTintColor(Color color, double opacity) {
    return color.withValues(alpha: opacity);
  }

  static Color getLuminosityColor(Color tintColor, double luminosityOpacity) {
    return tintColor.withValues(alpha: luminosityOpacity.clamp(0.0, 1.0));
  }
}
