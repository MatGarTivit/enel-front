import 'package:flutter/foundation.dart';

/// Stores the currently selected user's information from GLPI
class UserSession extends ChangeNotifier {
  int? _userId;
  String? _userName;

  int? get userId => _userId;
  String? get userName => _userName;

  bool get hasUser => _userId != null && _userName != null;

  void setUser({required int id, required String name}) {
    _userId = id;
    _userName = name;
    notifyListeners();
  }

  void clearUser() {
    _userId = null;
    _userName = null;
    notifyListeners();
  }
}
