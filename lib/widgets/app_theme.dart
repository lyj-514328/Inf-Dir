/// Inf-Dir 设计 token 层 —— 全局唯一的视觉决策来源。
///
/// 约定：widget 中禁止出现 `Color(0x...)` / `Colors.xxx` 字面量，
/// 一律通过 `context.colors`（[AppColors]）与 [AppMetrics] 取值。
library;

import 'package:flutter/material.dart';

// ── 颜色 token ───────────────────────────────────────────────────────

/// 随明暗主题变化的一套语义色。
class AppColors extends ThemeExtension<AppColors> {
  /// 应用窗口底色（Scaffold）
  final Color windowBg;

  /// 面板 / 列表 / 输入框底
  final Color surface;

  /// 列头、状态栏、标签栏、侧栏底
  final Color surfaceSubtle;

  /// 行 / 控件 hover 遮罩
  final Color surfaceHover;

  /// 常规边框 / 分隔线
  final Color border;

  /// 输入框边框、激活控件边框
  final Color borderStrong;

  /// 正文 / 文件名
  final Color textPrimary;

  /// 状态栏、次级文字
  final Color textSecondary;

  /// 占位、禁用、提示
  final Color textTertiary;

  /// 主题强调色（焦点边框、选中行、splitter）
  final Color accent;

  /// accent 的 hover / 按下加深态
  final Color accentHover;

  /// accent 实底上的前景色（选中行文字、主按钮文字）
  final Color onAccent;

  /// 侧栏选中底
  final Color accentSubtle;

  /// 失焦面板选中行底
  final Color selectedInactive;

  /// 删除确认、关闭 hover
  final Color danger;

  /// 成功 / 已同步（云状态绿勾）
  final Color success;

  /// fallback 文件夹图标
  final Color iconFolder;

  /// fallback 文件图标
  final Color iconFile;

  /// Alt 遮罩层压暗色 / 浮层阴影色
  final Color scrim;

  const AppColors({
    required this.windowBg,
    required this.surface,
    required this.surfaceSubtle,
    required this.surfaceHover,
    required this.border,
    required this.borderStrong,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.accent,
    required this.accentHover,
    required this.onAccent,
    required this.accentSubtle,
    required this.selectedInactive,
    required this.danger,
    required this.success,
    required this.iconFolder,
    required this.iconFile,
    required this.scrim,
  });

  /// 亮色 —— 现代极简：中性灰基底 + 靛蓝强调色
  static const light = AppColors(
    windowBg: Color(0xFFF7F7F5),
    surface: Color(0xFFFFFFFF),
    surfaceSubtle: Color(0xFFF1F1EE),
    surfaceHover: Color(0xFFE9E9E5),
    border: Color(0xFFE4E4E0),
    borderStrong: Color(0xFFCFCFC9),
    textPrimary: Color(0xFF1B1B1E),
    textSecondary: Color(0xFF5D5D63),
    textTertiary: Color(0xFF9A9AA0),
    accent: Color(0xFF4F52E0),
    accentHover: Color(0xFF3F42C4),
    onAccent: Color(0xFFFFFFFF),
    accentSubtle: Color(0xFFEDEDFB),
    selectedInactive: Color(0xFFE7E7E3),
    danger: Color(0xFFD13438),
    success: Color(0xFF2E7D32),
    iconFolder: Color(0xFFE8A33D),
    iconFile: Color(0xFF9A9AA0),
    scrim: Color(0x14000000),
  );

  /// 深色 —— 低对比中性灰 + 提亮靛蓝
  static const dark = AppColors(
    windowBg: Color(0xFF1B1B1E),
    surface: Color(0xFF232327),
    surfaceSubtle: Color(0xFF26262B),
    surfaceHover: Color(0xFF2E2E34),
    border: Color(0xFF333338),
    borderStrong: Color(0xFF46464D),
    textPrimary: Color(0xFFE9E9EB),
    textSecondary: Color(0xFFA6A6AC),
    textTertiary: Color(0xFF6E6E75),
    accent: Color(0xFF8A8DF0),
    accentHover: Color(0xFF9C9EF4),
    onAccent: Color(0xFF1B1B1E),
    accentSubtle: Color(0xFF2E2E4A),
    selectedInactive: Color(0xFF333339),
    danger: Color(0xFFF1707B),
    success: Color(0xFF66BB6A),
    iconFolder: Color(0xFFE8A33D),
    iconFile: Color(0xFFA6A6AC),
    scrim: Color(0x66000000),
  );

  @override
  AppColors copyWith({
    Color? windowBg,
    Color? surface,
    Color? surfaceSubtle,
    Color? surfaceHover,
    Color? border,
    Color? borderStrong,
    Color? textPrimary,
    Color? textSecondary,
    Color? textTertiary,
    Color? accent,
    Color? accentHover,
    Color? onAccent,
    Color? accentSubtle,
    Color? selectedInactive,
    Color? danger,
    Color? success,
    Color? iconFolder,
    Color? iconFile,
    Color? scrim,
  }) {
    return AppColors(
      windowBg: windowBg ?? this.windowBg,
      surface: surface ?? this.surface,
      surfaceSubtle: surfaceSubtle ?? this.surfaceSubtle,
      surfaceHover: surfaceHover ?? this.surfaceHover,
      border: border ?? this.border,
      borderStrong: borderStrong ?? this.borderStrong,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textTertiary: textTertiary ?? this.textTertiary,
      accent: accent ?? this.accent,
      accentHover: accentHover ?? this.accentHover,
      onAccent: onAccent ?? this.onAccent,
      accentSubtle: accentSubtle ?? this.accentSubtle,
      selectedInactive:
          selectedInactive ?? this.selectedInactive,
      danger: danger ?? this.danger,
      success: success ?? this.success,
      iconFolder: iconFolder ?? this.iconFolder,
      iconFile: iconFile ?? this.iconFile,
      scrim: scrim ?? this.scrim,
    );
  }

  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) {
    if (other is! AppColors) return this;
    return AppColors(
      windowBg: Color.lerp(windowBg, other.windowBg, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceSubtle: Color.lerp(surfaceSubtle, other.surfaceSubtle, t)!,
      surfaceHover: Color.lerp(surfaceHover, other.surfaceHover, t)!,
      border: Color.lerp(border, other.border, t)!,
      borderStrong: Color.lerp(borderStrong, other.borderStrong, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textTertiary: Color.lerp(textTertiary, other.textTertiary, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      accentHover: Color.lerp(accentHover, other.accentHover, t)!,
      onAccent: Color.lerp(onAccent, other.onAccent, t)!,
      accentSubtle: Color.lerp(accentSubtle, other.accentSubtle, t)!,
      selectedInactive:
          Color.lerp(selectedInactive, other.selectedInactive, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      success: Color.lerp(success, other.success, t)!,
      iconFolder: Color.lerp(iconFolder, other.iconFolder, t)!,
      iconFile: Color.lerp(iconFile, other.iconFile, t)!,
      scrim: Color.lerp(scrim, other.scrim, t)!,
    );
  }
}

/// BuildContext 快捷访问：`context.colors`
extension AppThemeX on BuildContext {
  AppColors get colors => Theme.of(this).extension<AppColors>()!;
}

// ── 尺寸 token ───────────────────────────────────────────────────────

/// 不随主题变化的尺寸 / 字号 / 圆角常量。
abstract final class AppMetrics {
  // 行高
  static const double rowHeight = 26;
  static const double sidebarRowHeight = 24;
  static const double quickAccessHeaderHeight = 24;

  // 栏高
  static const double topBarHeight = 40;
  static const double paneTabBarHeight = 30;
  static const double addressBarHeight = 34;
  static const double commandBarHeight = 34;
  static const double statusBarHeight = 22;

  // 圆角
  static const double paneRadius = 10;
  static const double cardRadius = 8;
  static const double controlRadius = 6;
  static const double tabRadius = 6;

  // 间距
  static const double paneGap = 6;
  static const double pagePadding = 8;

  // 图标
  static const double iconSm = 14;
  static const double iconMd = 16;

  // 字号
  static const double fontTitle = 13;
  static const double fontBody = 12;
  static const double fontSmall = 11;
  static const double fontCaption = 10.5;
}

// ── ThemeData 工厂 ───────────────────────────────────────────────────

abstract final class AppTheme {
  static ThemeData light() => _build(AppColors.light, Brightness.light);

  static ThemeData dark() => _build(AppColors.dark, Brightness.dark);

  static ThemeData _build(AppColors c, Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: c.accent,
      brightness: brightness,
    ).copyWith(
      primary: c.accent,
      onPrimary: c.onAccent,
      surface: c.surface,
      outline: c.borderStrong,
      outlineVariant: c.border,
      error: c.danger,
      surfaceTint: Colors.transparent,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      brightness: brightness,
      scaffoldBackgroundColor: c.windowBg,
      dividerColor: c.border,
      fontFamily: 'Segoe UI',
      visualDensity: VisualDensity.compact,
      splashFactory: NoSplash.splashFactory,
      highlightColor: Colors.transparent,
      hoverColor: c.surfaceHover,
      extensions: [c],
      textTheme: (brightness == Brightness.light
              ? Typography.material2021().black
              : Typography.material2021().white)
          .apply(bodyColor: c.textPrimary, displayColor: c.textPrimary),
      scrollbarTheme: ScrollbarThemeData(
        // 细滑块、常驻显示，hover/拖拽时略增粗
        thickness: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.hovered) ||
              states.contains(WidgetState.dragged)) {
            return 6.0;
          }
          return 4.0;
        }),
        radius: const Radius.circular(3),
        thumbVisibility: WidgetStateProperty.all(true),
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.hovered) ||
              states.contains(WidgetState.dragged)) {
            return c.textTertiary;
          }
          return c.borderStrong;
        }),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(AppMetrics.cardRadius),
          border: Border.all(color: c.border),
          boxShadow: [
            BoxShadow(
              color: c.scrim,
              blurRadius: 12,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        textStyle: TextStyle(fontSize: AppMetrics.fontSmall, color: c.textPrimary),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: c.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 8,
        shadowColor: c.scrim,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppMetrics.cardRadius),
          side: BorderSide(color: c.border),
        ),
        menuPadding: const EdgeInsets.symmetric(vertical: 4),
        textStyle: TextStyle(
          fontSize: AppMetrics.fontBody,
          color: c.textPrimary,
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: c.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 12,
        shadowColor: c.scrim,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        titleTextStyle: TextStyle(
          fontSize: AppMetrics.fontTitle,
          fontWeight: FontWeight.w600,
          color: c.textPrimary,
        ),
        contentTextStyle: TextStyle(
          fontSize: AppMetrics.fontBody,
          color: c.textPrimary,
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: c.accent),
    );
  }
}
