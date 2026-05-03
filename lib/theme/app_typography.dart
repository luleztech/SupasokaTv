import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

TextStyle _noUnderline(TextStyle style) => style.copyWith(
      decoration: TextDecoration.none,
      decorationColor: Colors.transparent,
      decorationThickness: 0,
    );

/// Display / headings (Supastream uses Inter black / tight tracking).
TextStyle orbitron(double size, {FontWeight weight = FontWeight.w800}) => _noUnderline(
      GoogleFonts.inter(fontSize: size, fontWeight: weight, letterSpacing: -0.5),
    );

/// Body UI (Inter — matches Supastream web template).
TextStyle rajdhani(double size, {FontWeight weight = FontWeight.w500}) =>
    _noUnderline(GoogleFonts.inter(fontSize: size, fontWeight: weight));

TextStyle inter(double size, {FontWeight weight = FontWeight.w500}) =>
    _noUnderline(GoogleFonts.inter(fontSize: size, fontWeight: weight));
