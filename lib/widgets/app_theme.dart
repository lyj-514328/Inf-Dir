/// Inf-Dir 设计 token 层 —— 全局唯一的视觉决策来源。
///
/// 约定：widget 中禁止出现 `Color(0x...)` / `Colors.xxx` 字面量，
/// 一律通过 `context.colors`（[AppColors]）与 [AppMetrics] 取值。
import 'package:flutter/material.dart';

// ── 颜色 token ───────────────────────────────────────────────────────

/// 随明暗主题变化的一套语义色。
class AppColors extends ThemeExtension<AppColors> {
  /// 应用窗口底色（Scaffold）
  final Color windowBg;

  /// 面板 / 列表 / 输入框底
  final Color surface;

  /// 菜单栏、列头、状态栏、标签栏、侧栏底
  final Color surfaceSubtle;

  /// 行 hover 遮罩
  final Color surfaceHover;

  /// 常规边框 / 分隔线
  final Color border;

  /// 输入框边框、激活标签边框
  final Color borderStrong;

  /// 正文 / 文件名
  final Color textPrimary;

  /// 状态栏、次级文字
  final Color textSecondary;

  /// 占位、禁用、提示
  final Color textTertiary;

  /// 主题强调色（焦点边框、选中行、splitter）
  final Color accent;

  /// 侧栏选中底
  final Color accentSubtle;

  /// 失焦面板选中行底
  final Color selectedInactive;

  /// 删除确认、关闭 hover
  final Color danger;

  /// fallback 文件夹图标
  final Color iconFolder;

  /// fallback 文件图标
  final Color iconFile;

  /// Alt 遮罩层压暗色
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
    required this.accentSubtle,
    required this.selectedInactive,
    required this.danger,
    required this.iconFolder,
    required this.iconFile,
    required this.scrim,
  });

  /// 亮色 —— 现代 Fluent 精炼
  static const light = AppColors(
    windowBg: Color(0xFFF3F3F3),
    surface: Color(0xFFFFFFFF),
    surfaceSubtle: Color(0xFFF7F7F7),
    surfaceHover: Color(0x0A000000),
    border: Color(0xFFE0E0E0),
    borderStrong: Color(0xFFC8C8C8),
    textPrimary: Color(0xFF1B1B1B),
    textSecondary: Color(0xFF5F5F5F),
    textTertiary: Color(0xFF8A8A8A),
    accent: Color(0xFF0078D4),
    accentSubtle: Color(0xFFE5F1FB),
    selectedInactive: Color(0xFFE3E3E3),
    danger: Color(0xFFC42B1C),
    iconFolder: Color(0xFFE8A33D),
    iconFile: Color(0xFF8A8A8A),
    scrim: Color(0x0F000000),
  );

  /// 深色 —— VS Code 式编辑器风
  static const dark = AppColors(
    windowBg: Color(0xFF1E1E1E),
    surface: Color(0xFF252526),
    surfaceSubtle: Color(0xFF2D2D30),
    surfaceHover: Color(0x14FFFFFF),
    border: Color(0xFF3E3E42),
    borderStrong: Color(0xFF505050),
    textPrimary: Color(0xFFE8E8E8),
    textSecondary: Color(0xFF9D9D9D),
    textTertiary: Color(0xFF6E6E6E),
    accent: Color(0xFF4CA9E8),
    accentSubtle: Color(0xFF094771),
    selectedInactive: Color(0xFF3A3A3A),
    danger: Color(0xFFF1707B),
    iconFolder: Color(0xFFE8A33D),
    iconFile: Color(0xFF9D9D9D),
    scrim: Color(0x4D000000),
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
    Color? accentSubtle,
    Color? selectedInactive,
    Color? danger,
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
      accentSubtle: accentSubtle ?? this.accentSubtle,
      selectedInactive: selectedInactive ?? this.selectedInactive,
      danger: danger ?? this.danger,
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
      accentSubtle: Color.lerp(accentSubtle, other.accentSubtle, t)!,
      selectedInactive:
          Color.lerp(selectedInactive, other.selectedInactive, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
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
  static const double rowHeight = 22;
  static const double sidebarRowHeight = 22;
  static const double quickAccessHeaderHeight = 20;

  // 栏高
  static const double menuBarHeight = 24;
  static const double workspaceBarHeight = 30;
  static const double paneTabBarHeight = 26;
  static const double addressBarHeight = 26;
  static const double navToolbarHeight = 28;
  static const double statusBarHeight = 20;

  // 圆角
  static const double paneRadius = 6;
  static const double cardRadius = 4;
  static const double controlRadius = 3;
  static const double tabRadius = 4;

  // 间距
  static const double paneGap = 2;
  static const double pagePadding = 4;

  // 图标
  static const double iconSm = 14;
  static const double iconMd = 16;

  // 字号
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
      surface: c.surface,
      outline: c.borderStrong,
      outlineVariant: c.border,
      error: c.danger,
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
        thickness: WidgetStateProperty.all(8),
        radius: const Radius.circular(4),
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
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        textStyle: TextStyle(fontSize: AppMetrics.fontSmall, color: c.textPrimary),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: c.accent),
    );
  }
}
