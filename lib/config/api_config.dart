import 'package:supasoka/config/deployment.dart';

/// Backend base URL (no trailing slash).
/// Defaults to [kRailwayApiBaseUrl]. Override: `--dart-define=API_BASE_URL=https://…`
const String kApiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: kRailwayApiBaseUrl,
);

String get apiConfigUrl => kApiBaseUrl.trim();
