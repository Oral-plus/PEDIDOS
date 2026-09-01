import 'package:flutter/material.dart';

class AppTheme {
  static const Color primaryColor = Color(0xFF000000);
  static const Color secondaryColor = Color(0xFF333333);
  static const Color accentColor = Color(0xFFFF9500);
  static const Color errorColor = Color(0xFFFF3B30);
  static const Color successColor = Color(0xFF34C759);
  
  static const Color primaryBlue = Color(0xFF1A56DB);
  static const Color secondaryBlue = Color(0xFF3B82F6);
  static const Color darkBlue = Color(0xFF111827);
  static const Color lightBlue = Color(0xFFEFF6FF);
  static const Color elegantGray = Color(0xFFF9FAFB);
  
  static const Color textPrimary = Color(0xFF1A1A2E);
  static const Color textSecondary = Color(0xFF6B7280);
  
  static const Color backgroundColor = Color(0xFFF2F2F7);
  static const Color secondaryBackgroundColor = Color(0xFFFFFFFF);
  static const Color groupedBackgroundColor = Color(0xFFF2F2F7);
  
  static const Color surfaceColor = Color(0xFFFFFFFF);
  static const Color cardColor = Color(0xFFFFFFFF);
  
  static const Color textPrimaryColor = Color(0xFF000000);
  static const Color textSecondaryColor = Color(0xFF3C3C43);
  static const Color textTertiaryColor = Color(0xFF8E8E93);
  static const Color labelColor = Color(0xFF8E8E93);
  
  static const Color separatorColor = Color(0x3C3C4329);
  static const Color borderColor = Color(0xFFE5E5EA);

  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      primarySwatch: Colors.blue,
      primaryColor: primaryColor,
      scaffoldBackgroundColor: backgroundColor,
      fontFamily: 'SF Pro Display',
      
      colorScheme: const ColorScheme.light(
        primary: primaryColor,
        secondary: secondaryColor,
        surface: surfaceColor,
        error: errorColor,
        onPrimary: Colors.white,
        onSecondary: Colors.white,
        onSurface: textPrimaryColor,
        onError: Colors.white,
      ),
      
      
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryColor,
          foregroundColor: Colors.white,
          elevation: 0,
          shadowColor: Colors.transparent,
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
          minimumSize: const Size(0, 50),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(25),
          ),
          textStyle: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.41,
          ),
        ),
      ),
      
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: primaryColor,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          textStyle: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w400,
            letterSpacing: -0.41,
          ),
        ),
      ),
      
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceColor,
        hintStyle: const TextStyle(
          color: textTertiaryColor,
          fontSize: 17,
          fontWeight: FontWeight.w400,
          letterSpacing: -0.41,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(
            color: borderColor,
            width: 0.5,
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(
            color: borderColor,
            width: 0.5,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(
            color: primaryColor,
            width: 2,
          ),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(
            color: errorColor,
            width: 1,
          ),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(
            color: errorColor,
            width: 2,
          ),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
      ),
      

      
      dividerTheme: const DividerThemeData(
        color: separatorColor,
        thickness: 0.5,
        space: 1,
      ),
      
      listTileTheme: const ListTileThemeData(
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        minLeadingWidth: 32,
        iconColor: textSecondaryColor,
        textColor: textPrimaryColor,
        titleTextStyle: TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w400,
          color: textPrimaryColor,
          letterSpacing: -0.41,
        ),
        subtitleTextStyle: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w400,
          color: textSecondaryColor,
          letterSpacing: -0.24,
        ),
      ),
      
      textTheme: const TextTheme(
        headlineLarge: TextStyle(
          fontSize: 34,
          fontWeight: FontWeight.bold,
          color: textPrimaryColor,
          letterSpacing: 0.37,
          height: 1.12,
        ),
        headlineMedium: TextStyle(
          fontSize: 28,
          fontWeight: FontWeight.w400,
          color: textPrimaryColor,
          letterSpacing: 0.36,
          height: 1.14,
        ),
        headlineSmall: TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.bold,
          color: textPrimaryColor,
          letterSpacing: 0.35,
          height: 1.16,
        ),
        titleLarge: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: textPrimaryColor,
          letterSpacing: 0.38,
          height: 1.20,
        ),
        titleMedium: TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w600,
          color: textPrimaryColor,
          letterSpacing: -0.41,
          height: 1.29,
        ),
        titleSmall: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w400,
          color: textPrimaryColor,
          letterSpacing: -0.32,
          height: 1.31,
        ),
        bodyLarge: TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w400,
          color: textPrimaryColor,
          letterSpacing: -0.41,
          height: 1.29,
        ),
        bodyMedium: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w400,
          color: textPrimaryColor,
          letterSpacing: -0.32,
          height: 1.31,
        ),
        bodySmall: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w400,
          color: textSecondaryColor,
          letterSpacing: -0.24,
          height: 1.33,
        ),
        labelLarge: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w400,
          color: textSecondaryColor,
          letterSpacing: -0.08,
          height: 1.38,
        ),
        labelMedium: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w400,
          color: textSecondaryColor,
          letterSpacing: 0,
          height: 1.33,
        ),
        labelSmall: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w400,
          color: textTertiaryColor,
          letterSpacing: 0.07,
          height: 1.36,
        ),
      ),
      
      iconTheme: const IconThemeData(
        color: textSecondaryColor,
        size: 24,
      ),
      
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return Colors.white;
          }
          return Colors.white;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return accentColor;
          }
          return const Color(0xFFE9E9EA);
        }),
      ),
      
      sliderTheme: const SliderThemeData(
        activeTrackColor: primaryColor,
        inactiveTrackColor: Color(0xFFE9E9EA),
        thumbColor: Colors.white,
        overlayColor: Color(0x1F007AFF),
        trackHeight: 4,
      ),
    );
  }
  
  static ThemeData get darkTheme {
    const Color darkBackgroundColor = Color(0xFF000000);
    const Color darkSurfaceColor = Color(0xFF1C1C1E);
    const Color darkPrimaryColor = Color(0xFFFFFFFF);
    const Color darkTextPrimary = Color(0xFFFFFFFF);
    const Color darkTextSecondary = Color(0xFFEBEBF5);
    const Color darkTextTertiary = Color(0x99EBEBF5);
    const Color darkSeparator = Color(0x545458A6);
    const Color darkBorder = Color(0xFF38383A);

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      primaryColor: darkPrimaryColor,
      scaffoldBackgroundColor: darkBackgroundColor,
      fontFamily: 'SF Pro Display',
      
      colorScheme: const ColorScheme.dark(
        primary: darkPrimaryColor,
        secondary: Color(0xFF64D2FF),
        surface: darkSurfaceColor,
        error: Color(0xFFFF453A),
        onPrimary: Colors.white,
        onSecondary: Colors.black,
        onSurface: darkTextPrimary,
        onError: Colors.white,
      ),
      
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: Colors.black,
          elevation: 0,
          shadowColor: Colors.transparent,
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
          minimumSize: const Size(0, 50),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(25),
          ),
          textStyle: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.41,
          ),
        ),
      ),
      
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: darkPrimaryColor,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          textStyle: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w400,
            letterSpacing: -0.41,
          ),
        ),
      ),
      
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: darkSurfaceColor,
        hintStyle: const TextStyle(
          color: darkTextTertiary,
          fontSize: 17,
          fontWeight: FontWeight.w400,
          letterSpacing: -0.41,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(
            color: darkBorder,
            width: 0.5,
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(
            color: darkBorder,
            width: 0.5,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(
            color: darkPrimaryColor,
            width: 2,
          ),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(
            color: errorColor,
            width: 1,
          ),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(
            color: errorColor,
            width: 2,
          ),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
      ),
      
      dividerTheme: const DividerThemeData(
        color: darkSeparator,
        thickness: 0.5,
        space: 1,
      ),
      
      listTileTheme: const ListTileThemeData(
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        minLeadingWidth: 32,
        iconColor: darkTextSecondary,
        textColor: darkTextPrimary,
        titleTextStyle: TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w400,
          color: darkTextPrimary,
          letterSpacing: -0.41,
        ),
        subtitleTextStyle: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w400,
          color: darkTextSecondary,
          letterSpacing: -0.24,
        ),
      ),
      
      textTheme: const TextTheme(
        headlineLarge: TextStyle(fontSize: 34, fontWeight: FontWeight.bold, color: darkTextPrimary, letterSpacing: 0.37, height: 1.12),
        headlineMedium: TextStyle(fontSize: 28, fontWeight: FontWeight.w400, color: darkTextPrimary, letterSpacing: 0.36, height: 1.14),
        headlineSmall: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: darkTextPrimary, letterSpacing: 0.35, height: 1.16),
        titleLarge: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: darkTextPrimary, letterSpacing: 0.38, height: 1.20),
        titleMedium: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: darkTextPrimary, letterSpacing: -0.41, height: 1.29),
        titleSmall: TextStyle(fontSize: 16, fontWeight: FontWeight.w400, color: darkTextPrimary, letterSpacing: -0.32, height: 1.31),
        bodyLarge: TextStyle(fontSize: 17, fontWeight: FontWeight.w400, color: darkTextPrimary, letterSpacing: -0.41, height: 1.29),
        bodyMedium: TextStyle(fontSize: 16, fontWeight: FontWeight.w400, color: darkTextPrimary, letterSpacing: -0.32, height: 1.31),
        bodySmall: TextStyle(fontSize: 15, fontWeight: FontWeight.w400, color: darkTextSecondary, letterSpacing: -0.24, height: 1.33),
        labelLarge: TextStyle(fontSize: 13, fontWeight: FontWeight.w400, color: darkTextSecondary, letterSpacing: -0.08, height: 1.38),
        labelMedium: TextStyle(fontSize: 12, fontWeight: FontWeight.w400, color: darkTextSecondary, letterSpacing: 0, height: 1.33),
        labelSmall: TextStyle(fontSize: 11, fontWeight: FontWeight.w400, color: darkTextTertiary, letterSpacing: 0.07, height: 1.36),
      ),
      
      iconTheme: const IconThemeData(
        color: darkTextSecondary,
        size: 24,
      ),
      
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) => Colors.white),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return accentColor;
          return const Color(0xFF39393D);
        }),
      ),
      
      sliderTheme: const SliderThemeData(
        activeTrackColor: darkPrimaryColor,
        inactiveTrackColor: Color(0xFF39393D),
        thumbColor: Colors.white,
        overlayColor: Color(0x33FFFFFF),
        trackHeight: 4,
      ),
    );
  }
}