import 'package:flutter/material.dart';

class ThemeService extends ChangeNotifier {
  // Use ThemeMode to allow system, light, or dark options
  ThemeMode _themeMode = ThemeMode.light;

  ThemeMode get themeMode => _themeMode;

  bool get isDarkMode => _themeMode == ThemeMode.dark;

  void toggleTheme() {
    _themeMode = isDarkMode ? ThemeMode.light : ThemeMode.dark;
    notifyListeners(); // Rebuilds the app when theme changes
  }
}