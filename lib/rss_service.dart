import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:dart_rss/dart_rss.dart';

class RssService {
  static Future<RssFeed> fetchFeed(String url) async {
    try {
      final response = await http
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 10));
      
      if (response.statusCode == 200) {
        // utf8.decode ensures special characters parse correctly
        return RssFeed.parse(utf8.decode(response.bodyBytes));
      } else {
        throw Exception('Failed to load RSS feed (Status: ${response.statusCode})');
      }
    } catch (e) {
      throw Exception('Failed to fetch RSS feed: $e');
    }
  }
}