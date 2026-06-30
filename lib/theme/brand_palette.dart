import 'package:flutter/material.dart';

/// Shared brand colors — splash, home, and key UI surfaces.
abstract final class BrandPalette {
  static const bgDeep = Color(0xFF05080F);
  static const bgMid = Color(0xFF0C1424);
  static const accent = Color(0xFF38BDF8);
  static const accentWarm = Color(0xFFF59E0B);
  static const white = Color(0xFFF8FAFC);

  static const activeGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [accent, accentWarm],
  );

  static const surfaceGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [bgMid, bgDeep],
  );
}

/// Per-category styling for home channel sections.
class HomeSectionStyle {
  const HomeSectionStyle({
    required this.primary,
    required this.secondary,
    required this.emoji,
    required this.label,
  });

  final Color primary;
  final Color secondary;
  final String emoji;
  final String label;

  LinearGradient get accentGradient => LinearGradient(
        colors: [primary, secondary],
      );

  static HomeSectionStyle forTitle(String title) {
    final lower = title.toLowerCase();
    if (lower.contains('bure') || lower.contains('free')) {
      return const HomeSectionStyle(
        primary: BrandPalette.accent,
        secondary: BrandPalette.accentWarm,
        emoji: '🆓',
        label: 'Free',
      );
    }
    if (lower.contains('mpira') || lower.contains('sport') || lower.contains('football')) {
      return const HomeSectionStyle(
        primary: BrandPalette.accent,
        secondary: Color(0xFF0EA5E9),
        emoji: '⚽',
        label: 'Sports',
      );
    }
    if (lower.contains('tamthilia') || lower.contains('movie')) {
      return const HomeSectionStyle(
        primary: BrandPalette.accentWarm,
        secondary: Color(0xFFFBBF24),
        emoji: '🎬',
        label: 'Movies',
      );
    }
    if (lower.contains('habari') || lower.contains('news')) {
      return const HomeSectionStyle(
        primary: BrandPalette.white,
        secondary: BrandPalette.accent,
        emoji: '📰',
        label: 'News',
      );
    }
    if (lower.contains('stream')) {
      return const HomeSectionStyle(
        primary: BrandPalette.accentWarm,
        secondary: BrandPalette.accent,
        emoji: '⚡',
        label: 'Streams',
      );
    }
    return const HomeSectionStyle(
      primary: BrandPalette.accent,
      secondary: BrandPalette.accentWarm,
      emoji: '📺',
      label: 'TV',
    );
  }

  static HomeSectionStyle forCategoryKey(String key) {
    switch (key) {
      case 'all':
        return const HomeSectionStyle(
          primary: BrandPalette.accent,
          secondary: BrandPalette.accentWarm,
          emoji: '✦',
          label: 'All',
        );
      case 'football':
      case 'mpira':
      case 'sports':
        return forTitle('mpira');
      case 'movies':
      case 'tamthilia':
        return forTitle('tamthilia');
      case 'news':
      case 'habari':
        return forTitle('habari');
      case 'entertainment':
        return const HomeSectionStyle(
          primary: BrandPalette.accentWarm,
          secondary: BrandPalette.accent,
          emoji: '🎵',
          label: 'Shows',
        );
      default:
        return HomeSectionStyle(
          primary: BrandPalette.accent,
          secondary: BrandPalette.accentWarm,
          emoji: '📺',
          label: key,
        );
    }
  }
}
