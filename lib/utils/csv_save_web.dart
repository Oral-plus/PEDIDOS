import 'dart:convert';
import 'dart:html' as html;

Future<void> saveCsvBytes(String filename, String content) async {
  final bytes = utf8.encode(content);
  final blob = html.Blob([bytes]);
  final url = html.Url.createObjectUrlFromBlob(blob);
  final anchor = html.AnchorElement()
    ..href = url
    ..download = filename;
  anchor.click();
  html.Url.revokeObjectUrl(url);
}
