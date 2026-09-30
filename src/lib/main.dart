import 'package:flutter/material.dart';
import 'package:dart_rss/dart_rss.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:shared_preferences/shared_preferences.dart';
import 'rss_service.dart';

void main() {
  runApp(const GalaxyNewsApp());
}

class GalaxyNewsApp extends StatelessWidget {
  const GalaxyNewsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Galaxy News',
      theme: ThemeData.dark(useMaterial3: true),
      home: const FeedSelectionScreen(),
    );
  }
}

class FeedSelectionScreen extends StatefulWidget {
  const FeedSelectionScreen({super.key});

  @override
  State<FeedSelectionScreen> createState() => _FeedSelectionScreenState();
}

class _FeedSelectionScreenState extends State<FeedSelectionScreen> {
  List<String> _userFeeds = [];
  final TextEditingController _urlController = TextEditingController();
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadFeeds();
  }

  // Load saved feeds from local storage
  Future<void> _loadFeeds() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _userFeeds = prefs.getStringList('saved_feeds') ?? [];
      _isLoading = false;
    });
  }

  // Save feeds to local storage
  Future<void> _saveFeeds() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('saved_feeds', _userFeeds);
  }

  void _addFeed() {
    final url = _urlController.text.trim();
    if (url.isNotEmpty && !_userFeeds.contains(url)) {
      setState(() {
        _userFeeds.add(url);
        _urlController.clear();
      });
      _saveFeeds();
    }
  }

  void _removeFeed(int index) {
    setState(() {
      _userFeeds.removeAt(index);
    });
    _saveFeeds();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Galaxy News - Your Feeds'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _urlController,
                          decoration: const InputDecoration(
                            labelText: 'Enter RSS Feed URL',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      ElevatedButton(
                        onPressed: _addFeed,
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                        ),
                        child: const Text('Add Feed'),
                      ),
                    ],
                  ),
                ),
                const Divider(),
                Expanded(
                  child: _userFeeds.isEmpty
                      ? const Center(
                          child: Text(
                            'No feeds added yet.\nPaste an RSS link above to choose your own sources!',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.grey),
                          ),
                        )
                      : ListView.builder(
                          itemCount: _userFeeds.length,
                          itemBuilder: (context, index) {
                            final feedUrl = _userFeeds[index];
                            return ListTile(
                              leading: const Icon(Icons.rss_feed, color: Colors.orangeAccent),
                              title: Text(feedUrl, overflow: TextOverflow.ellipsis),
                              trailing: IconButton(
                                icon: const Icon(Icons.delete, color: Colors.redAccent),
                                onPressed: () => _removeFeed(index),
                              ),
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => NewsFeedScreen(feedUrl: feedUrl),
                                  ),
                                );
                              },
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }
}

class NewsFeedScreen extends StatefulWidget {
  final String feedUrl;

  const NewsFeedScreen({super.key, required this.feedUrl});

  @override
  State<NewsFeedScreen> createState() => _NewsFeedScreenState();
}

class _NewsFeedScreenState extends State<NewsFeedScreen> {
  late Future<RssFeed> _futureFeed;

  @override
  void initState() {
    super.initState();
    _futureFeed = RssService.fetchFeed(widget.feedUrl);
  }

  String _cleanSnippet(String? htmlString) {
    if (htmlString == null) return 'No description available.';
    final document = html_parser.parse(htmlString);
    return document.body?.text ?? 'No description available.';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.feedUrl),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              setState(() {
                _futureFeed = RssService.fetchFeed(widget.feedUrl);
              });
            },
          ),
        ],
      ),
      body: FutureBuilder<RssFeed>(
        future: _futureFeed,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          } else if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text(
                  'Error loading feed:\n${snapshot.error}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.redAccent),
                ),
              ),
            );
          } else if (!snapshot.hasData || snapshot.data!.items.isEmpty) {
            return const Center(child: Text('No articles found in this feed.'));
          }

          final items = snapshot.data!.items;

          return GridView.builder(
            padding: const EdgeInsets.all(12.0),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 320,
              childAspectRatio: 1.1,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
            ),
            itemCount: items.length,
            itemBuilder: (context, index) {
              final item = items[index];
              return InkWell(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => ArticleDetailScreen(item: item),
                    ),
                  );
                },
                borderRadius: BorderRadius.circular(12),
                child: Card(
                  elevation: 2,
                  child: Padding(
                    padding: const EdgeInsets.all(14.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.title ?? 'Untitled',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Expanded(
                          child: Text(
                            _cleanSnippet(item.description),
                            maxLines: 4,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.grey[400],
                              fontSize: 13,
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          item.pubDate ?? '',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class ArticleDetailScreen extends StatelessWidget {
  final RssItem item;

  const ArticleDetailScreen({super.key, required this.item});

  List<Widget> _buildRichContent(String? htmlString) {
    if (htmlString == null || htmlString.isEmpty) {
      return [const Text('No content available.')];
    }

    final document = html_parser.parse(htmlString);
    final body = document.body;
    if (body == null) return [const Text('No content available.')];

    List<Widget> widgets = [];

    for (final node in body.children) {
      final tag = node.localName?.toLowerCase();
      final text = node.text.trim();

      if (tag == 'h1' || tag == 'h2') {
        if (text.isNotEmpty) {
          widgets.add(Padding(
            padding: const EdgeInsets.only(top: 20.0, bottom: 10.0),
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ));
        }
      } else if (tag == 'h3' || tag == 'h4' || tag == 'h5') {
        if (text.isNotEmpty) {
          widgets.add(Padding(
            padding: const EdgeInsets.only(top: 16.0, bottom: 8.0),
            child: Text(
              text,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
                color: Colors.grey[300],
              ),
            ),
          ));
        }
      } else if (tag == 'figure' || tag == 'img') {
        final img = tag == 'img' ? node : node.querySelector('img');
        final src = img?.attributes['src'];
        if (src != null) {
          widgets.add(Padding(
            padding: const EdgeInsets.symmetric(vertical: 12.0),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8.0),
              child: Image.network(
                src,
                errorBuilder: (context, error, stackTrace) => const SizedBox.shrink(),
              ),
            ),
          ));
        }
      } else if (tag == 'p') {
        final img = node.querySelector('img');
        if (img != null) {
          final src = img.attributes['src'];
          if (src != null) {
            widgets.add(Padding(
              padding: const EdgeInsets.symmetric(vertical: 12.0),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8.0),
                child: Image.network(
                  src,
                  errorBuilder: (context, error, stackTrace) => const SizedBox.shrink(),
                ),
              ),
            ));
          }
        }
        if (text.isNotEmpty) {
          widgets.add(Padding(
            padding: const EdgeInsets.only(bottom: 14.0),
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 16,
                height: 1.6,
                color: Colors.white70,
              ),
            ),
          ));
        }
      }
    }

    if (widgets.isEmpty && body.text.trim().isNotEmpty) {
      widgets.add(Text(
        body.text.trim(),
        style: const TextStyle(fontSize: 16, height: 1.6),
      ));
    }

    return widgets;
  }

  @override
  Widget build(BuildContext context) {
    final rawContent = item.content?.value ?? item.description;

    return Scaffold(
      appBar: AppBar(
        title: Text(item.source?.value ?? 'Article'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              item.title ?? 'Untitled',
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              item.pubDate ?? '',
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey[500],
              ),
            ),
            const Divider(height: 30),
            ..._buildRichContent(rawContent),
          ],
        ),
      ),
    );
  }
}
