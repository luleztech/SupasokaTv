import 'package:flutter/widgets.dart';

/// Global keys / scroll handle used by the first-launch coach tour.
abstract final class CoachTargets {
  static final homeTopBar = GlobalKey(debugLabel: 'coach_home_top');
  static final mpiraSection = GlobalKey(debugLabel: 'coach_mpira');
  static final unlockTab = GlobalKey(debugLabel: 'coach_unlock_tab');
  static final profileTab = GlobalKey(debugLabel: 'coach_profile_tab');

  /// Owned by [HomeScreen]; coach tour uses it to scroll to Mpira.
  static ScrollController? homeScroll;
}
