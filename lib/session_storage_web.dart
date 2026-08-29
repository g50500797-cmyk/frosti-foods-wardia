import 'dart:html' as html;

class SessionStorage {
  static const _key = 'wardia_access_token';

  static Future<String?> readToken() async => html.window.localStorage[_key];

  static Future<void> writeToken(String token) async {
    html.window.localStorage[_key] = token;
  }

  static Future<void> clear() async {
    html.window.localStorage.remove(_key);
  }
}
