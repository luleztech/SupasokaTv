import 'package:flutter_test/flutter_test.dart';
import 'package:supasoka/services/content_store.dart';
import 'package:supasoka/theme/app_theme.dart';
import 'package:supatv/models/tv_playback_settings.dart';
import 'package:supatv/main.dart';

void main() {
  testWidgets('SupaTV app builds', (WidgetTester tester) async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final store = ContentStore();
    final theme = await ThemeController.load();
    final playback = TvPlaybackSettings();
    await tester.pumpWidget(SupaTvApp(
      contentStore: store,
      themeController: theme,
      playbackSettings: playback,
    ));
    expect(find.text('SupaTV'), findsOneWidget);
  });
}
