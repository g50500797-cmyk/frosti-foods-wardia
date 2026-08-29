import 'dart:convert';
import 'dart:html' as html;

Future<void> downloadText(String filename, String content, String mimeType) async {
  final blob = html.Blob([utf8.encode(content)], mimeType);
  final url = html.Url.createObjectUrlFromBlob(blob);
  html.AnchorElement(href: url)
    ..setAttribute('download', filename)
    ..click();
  html.Url.revokeObjectUrl(url);
}
