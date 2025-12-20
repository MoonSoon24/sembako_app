import 'package:flutter/material.dart';

class SettingsService extends ChangeNotifier {
  ThemeMode _themeMode = ThemeMode.light;
  int _defaultAdminFee = 2000;

  ThemeMode get themeMode => _themeMode;
  int get defaultAdminFee => _defaultAdminFee;

  void toggleTheme(bool isDark) {
    _themeMode = isDark ? ThemeMode.dark : ThemeMode.light;
    notifyListeners();
  }
}
