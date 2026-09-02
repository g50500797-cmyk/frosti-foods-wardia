import 'dart:html' as html;

class SessionStorage {
  static const _key = 'wardia_access_token';
  static const _emailKey = 'wardia_last_email';

  static Future<String?> readToken() async => html.window.localStorage[_key];

  static Future<void> writeToken(String token) async {
    html.window.localStorage[_key] = token;
  }

  static Future<String?> readEmail() async =>
      html.window.localStorage[_emailKey];

  static Future<void> writeEmail(String email) async {
    html.window.localStorage[_emailKey] = email;
  }

  static Future<void> clear() async {
    html.window.localStorage.remove(_key);
  }
}
