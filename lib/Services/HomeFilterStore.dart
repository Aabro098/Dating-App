import 'package:viora/components/HomeFilterSheet.dart';

/// Persists home screen filters and Top Picks state while the app is open.
/// Resets only on app restart or logout.
class HomeFilterStore {
  static HomeFilterState _filters = const HomeFilterState();
  static bool _isTopPicksActive = false;

  static HomeFilterState get filters => _filters;

  static set filters(HomeFilterState value) {
    _filters = value;
  }

  static bool get isTopPicksActive => _isTopPicksActive;

  static set isTopPicksActive(bool value) {
    _isTopPicksActive = value;
  }

  static void reset() {
    _filters = const HomeFilterState();
    _isTopPicksActive = false;
  }
}
