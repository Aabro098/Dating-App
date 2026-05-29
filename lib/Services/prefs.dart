import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:viora/models/UserDetails.dart';
import 'package:shared_preferences/shared_preferences.dart';

class Prefs {
  // You can add additional fields like environment, version, etc.
  Prefs(SharedPreferences prefs) : prefs = ListenablePrefs(prefs);
  final ListenablePrefs prefs;

  PrefsValue<UserDetails?> get userDetails =>
      prefs.get<UserDetails?>(_prefsKeyuserDetails, null);

  PrefsValue<bool> get notificationPermissionGranted =>
      prefs.get<bool>(_prefsKeyNotificationPermission, false);

  PrefsValue<bool> get isFirstLaunch =>
      prefs.get<bool>(_prefsKeyIsFirstLaunch, true);

  PrefsValue<int> get notificationDenialCount =>
      prefs.get<int>(_prefsKeyNotificationDenialCount, 0);

  PrefsValue<int> get otpStartTime =>
      prefs.get<int>(_prefsKeyOtpStartTime, 0);

  PrefsValue<String> get lastVerificationDialogShownDate =>
      prefs.get<String>(_prefsKeyLastVerificationDialogShownDate, '');

  PrefsValue<bool> get locationPermissionDenied =>
      prefs.get<bool>(_prefsKeyLocationPermissionDenied, false);

  PrefsValue<int> get currentSessionId =>
      prefs.get<int>(_prefsKeyCurrentSessionId, 0);

  PrefsValue<int> get safetyTipsVersion =>
      prefs.get<int>(_prefsKeySafetyTipsVersion, 0);

  static const _prefsKeyuserDetails = 'userDetails';
  static const _prefsKeyNotificationPermission = 'notification_permission_granted';
  static const _prefsKeyIsFirstLaunch = 'is_first_launch';
  static const _prefsKeyNotificationDenialCount = 'notification_denial_count';
  static const _prefsKeyOtpStartTime = 'otp_start_time';
  static const _prefsKeyLastVerificationDialogShownDate = 'last_verification_dialog_shown_date';
  static const _prefsKeyLocationPermissionDenied = 'location_permission_denied';
  static const _prefsKeyCurrentSessionId = 'current_session_id';
  static const _prefsKeySafetyTipsVersion = 'safety_tips_version';
  Future<void> clear() => prefs.clear();

  // ...
}

class ListenablePrefs {
  ListenablePrefs(this._prefs) {
    _notifyKeys();
  }

  final SharedPreferences _prefs;

  PrefsValue<T> get<T>(String key, T defaultValue) =>
      PrefsValue(this, key, defaultValue);

  ValueListenable<Set<String>?> get keys => _keys;

  Future<void> clear() async {
    await _prefs.clear();
    final keys = _notifiers.keys.toList(); // create a stable copy
    _notifyKeys();
    keys.forEach(_notifyKey);
  }

  void _addKeyListener(String key, VoidCallback callback) {
    (_notifiers[key] ??= _ChangeNotifier()).addListener(callback);
  }

  void _removeKeyListener(String key, VoidCallback callback) {
    final notifier = _notifiers[key];
    if (notifier == null) {
      return;
    }
    notifier.removeListener(callback);
    if (!notifier._hasListeners) {
      _notifiers.remove(key);
    }
  }

  void _notifyKey(String key) => _notifiers[key]?._notifyListeners();

  void _notifyKeys() => _keys.value = _prefs.getKeys();

  // this map only contains notifiers for keys that have a listener currently attached
  // notifiers are added/removed when the first/last listener is added/removed
  final _notifiers = <String, _ChangeNotifier>{};

  final _keys = ValueNotifier<Set<String>?>(null);
}

class _ChangeNotifier extends ChangeNotifier {
  bool get _hasListeners => super.hasListeners;

  void _notifyListeners() => super.notifyListeners();
}

class PrefsValue<T> extends ValueListenable<T> {
  PrefsValue(this.prefs, this.key, this.defaultValue);

  final ListenablePrefs prefs;
  final String key;
  final T defaultValue;

  @override
  void addListener(VoidCallback listener) =>
      prefs._addKeyListener(key, listener);

  @override
  void removeListener(VoidCallback listener) =>
      prefs._removeKeyListener(key, listener);

  Future<void> remove() async {
    await prefs._prefs.remove(key);
    prefs._notifyKeys();
    prefs._notifyKey(key);
  }

  bool get exists => prefs._prefs.containsKey(key);

  Future<void> set(T value) async {
    if (value == null) {
      await remove();
      return;
    }

    final didExist = exists;

    var typeName = T.toString();
    if (typeName.endsWith('?')) {
      typeName = typeName.substring(0, typeName.length - 1);
    }

    switch (typeName) {
      case 'bool':
        await prefs._prefs.setBool(key, value as bool);
        break;
      case 'int':
        await prefs._prefs.setInt(key, value as int);
        break;
      case 'double':
        await prefs._prefs.setDouble(key, value as double);
        break;
      case 'String':
        await prefs._prefs.setString(key, value as String);
        break;
      case 'List<String>':
        await prefs._prefs.setStringList(key, value as List<String>);
        break;

      case 'UserDetails':
        await _setUserDetails(value as UserDetails?);
        print("vinay in prefs set the $value is set ");
        break;
      default:
        throw ArgumentError('Unsupported $T');
    }
    if (!didExist) {
      prefs._notifyKeys();
    }
    prefs._notifyKey(key);
  }

  // FOR USERDETAILS - Use new SharedPreferences methods
  Future<bool> _setUserDetails(UserDetails? userDetails) {
    if (userDetails == null) {
      return prefs._prefs.remove(key);
    }

    try {
      // Use the new toPrefsString() method instead of toJson()
      final userDetailsString = userDetails.toPrefsString();
      return prefs._prefs.setString(key, userDetailsString);
    } catch (e) {
      print("vinay Error saving UserDetails: $e");
      return Future.value(false);
    }
  }

  UserDetails? _getUserDetails(String key) {
    final userDetailsString = prefs._prefs.getString(key);
    if (userDetailsString == null || userDetailsString.isEmpty) {
      return null;
    }

    try {
      // Use the new fromPrefsString() method instead of fromJson()
      return UserDetails.fromPrefsString(userDetailsString);
    } catch (exc) {
      print(
        'vinay PREFS Unable to load userDetails value for key "$key": $exc',
      );
      return null;
    }
  }

  @override
  T get value {
    if (!exists) {
      return defaultValue;
    }
    var typeName = T.toString();
    if (typeName.endsWith('?')) {
      typeName = typeName.substring(0, typeName.length - 1);
    }
    switch (typeName) {
      case 'bool':
        return prefs._prefs.getBool(key) as T;
      case 'int':
        return prefs._prefs.getInt(key) as T;
      case 'double':
        return prefs._prefs.getDouble(key) as T;
      case 'String':
        return prefs._prefs.getString(key) as T;
      case 'List<String>':
        return prefs._prefs.getStringList(key) as T;
      case 'UserDetails':
        return _getUserDetails(key) as T;

      default:
        throw ArgumentError('Unsupported $T');
    }
  }
}
