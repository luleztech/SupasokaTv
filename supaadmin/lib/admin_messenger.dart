import 'package:flutter/material.dart';

/// For [SnackBar]s from [AdminStore] (no BuildContext).
final GlobalKey<ScaffoldMessengerState> adminScaffoldMessengerKey =
    GlobalKey<ScaffoldMessengerState>();

/// Cleans `Exception:` prefixes so snackbars stay readable.
String adminFormatError(Object e) {
  var s = e.toString().trim();
  const p = 'Exception: ';
  if (s.startsWith(p)) {
    s = s.substring(p.length).trim();
  }
  return s;
}
