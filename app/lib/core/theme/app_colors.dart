import 'package:flutter/material.dart';

class AppColors {
  AppColors._();

  // Primary
  static const primary = Color(0xFF2563EB);
  static const primaryLight = Color(0xFF60A5FA);
  static const primaryDark = Color(0xFF1D4ED8);

  // Secondary
  static const secondary = Color(0xFF7C3AED);
  static const secondaryLight = Color(0xFFA78BFA);

  // Accent
  static const accent = Color(0xFF06B6D4);
  static const accentLight = Color(0xFF67E8F9);

  // Success / Error / Warning
  static const success = Color(0xFF10B981);
  static const error = Color(0xFFEF4444);
  static const warning = Color(0xFFF59E0B);
  static const info = Color(0xFF3B82F6);

  // Neutrals
  static const white = Color(0xFFFFFFFF);
  static const black = Color(0xFF000000);
  static const background = Color(0xFFF8FAFC);
  static const surface = Color(0xFFFFFFFF);
  static const surfaceVariant = Color(0xFFF1F5F9);
  static const border = Color(0xFFE2E8F0);
  static const divider = Color(0xFFF1F5F9);

  // Text
  static const textPrimary = Color(0xFF0F172A);
  static const textSecondary = Color(0xFF475569);
  static const textTertiary = Color(0xFF94A3B8);
  static const textOnPrimary = Color(0xFFFFFFFF);

  // Gradient
  static const gradientStart = Color(0xFF2563EB);
  static const gradientEnd = Color(0xFF7C3AED);

  static const LinearGradient primaryGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [gradientStart, gradientEnd],
  );

  // Status colors
  static const statusBooked = Color(0xFF3B82F6);
  static const statusInProgress = Color(0xFFF59E0B);
  static const statusCompleted = Color(0xFF10B981);
  static const statusCancelled = Color(0xFFEF4444);
  static const statusPaymentPending = Color(0xFFF97316);
}
