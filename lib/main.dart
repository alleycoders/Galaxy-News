import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:dart_rss/dart_rss.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'rss_service.dart';

void main() {
  runApp(const GalaxyNewsApp());
}

ValueNotifier<ThemeMode> themeNotifier = ValueNotifier(ThemeMode.dark);

class GalaxyNewsApp extends StatelessWidget {
  const GalaxyNewsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeNotifier,
      builder: (context, currentThemeMode, child) {
        return MaterialApp(
          title: 'Galaxy News',
          theme: ThemeData.light(useMaterial3: true),
          darkTheme: ThemeData.dark(useMaterial3: true),
          themeMode: currentThemeMode,
          home: const MainNavigationScreen(),
        );
      },
    );
  }
}

class SavedArticle {
  final String title;
  final String description;
  final String link;
  final String pubDate;
  final String content;
  final String? imageUrl;

  SavedArticle({
    required this.title,
    required this.description,
    required this.link,
    required this.pubDate,
    required this.content,
    this.imageUrl,
  });

  Map<String, dynamic> toJson() => {
        'title': title,
        'description': description,
        'link': link,
        'pubDate': pubDate,
        'content': content,
        'imageUrl': imageUrl,
      };

  factory SavedArticle.fromJson(Map<String, dynamic> json) => SavedArticle(
        title: json['title'] ?? '',
        description: json['description'] ?? '',
        link: json['link'] ?? '',
        pubDate: json['pubDate'] ?? '',
        content: json['content'] ?? '',
        imageUrl: json['imageUrl'],
      );
}

// Master Sidebar Widget with Folder Deletion and Feed Management
Widget buildMasterSidebar(
  BuildContext context,
  Map<String, List<String>> folders,
  String? selectedFeedUrl,
  bool isSavedView,
  bool isSettingsView,
  Function(String?) onSelectFeed,
  Function(bool, bool) onViewChange,
  Function(BuildContext) onShowAddFolder,
  Function(BuildContext, String) onShowAddFeed,
  Function(String, int) onRemoveFeed,
  Function(BuildContext, String) onRemoveFolder,
) {
  return Drawer(
    child: SafeArea(
      child: Column(
        children: [
          const SizedBox(height: 12),
          ListTile(
            leading: const Icon(Icons.bookmark, color: Colors.amber),
            title: const Text('Saved Articles'),
            onTap: () {
              onViewChange(true, false);
              Navigator.of(context).pop();
              Navigator.of(context).popUntil((route) => route.isFirst);
            },
          ),
          ListTile(
            leading: const Icon(Icons.settings),
            title: const Text('Settings'),
            onTap: () {
              onViewChange(false, true);
              Navigator.of(context).pop();
              Navigator.of(context).popUntil((route) => route.isFirst);
            },
          ),
          const Divider(),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Folders & Feeds', style: TextStyle(fontWeight: FontWeight.bold)),
                IconButton(
                  icon: const Icon(Icons.create_new_folder, size: 20),
                  onPressed: () => onShowAddFolder(context),
                  tooltip: 'Add Folder',
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              children: folders.entries.map((entry) {
                final folderName = entry.key;
                final feeds = entry.value;
                return ExpansionTile(
                  leading: const Icon(Icons.folder, color: Colors.orangeAccent),
                  title: Text(folderName),
                  trailing: PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert, size: 18),
                    onSelected: (value) {
                      if (value == 'add') {
                        onShowAddFeed(context, folderName);
                      } else if (value == 'delete') {
                        onRemoveFolder(context, folderName);
                      }
                    },
                    itemBuilder: (context) => [
                      const PopupMenuItem(value: 'add', child: Text('Add Feed')),
                      if (folders.length > 1) // Prevent deleting the last remaining folder if desired
                        const PopupMenuItem(
                          value: 'delete',
                          child: Text('Delete Folder', style: TextStyle(color: Colors.redAccent)),
                        ),
                    ],
                  ),
                  children: feeds.asMap().entries.map((feedEntry) {
                    final feedIdx = feedEntry.key;
                    final feedUrl = feedEntry.value;
                    return ListTile(
                      contentPadding: const EdgeInsets.only(left: 32, right: 16),
                      title: Text(feedUrl, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13)),
                      selected: selectedFeedUrl == feedUrl && !isSavedView && !isSettingsView,
                      onTap: () {
                        onSelectFeed(feedUrl);
                        Navigator.of(context).pop();
                        Navigator.of(context).popUntil((route) => route.isFirst);
                      },
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline, size: 16, color: Colors.red),
                        onPressed: () => onRemoveFeed(folderName, feedIdx),
                      ),
                    );
                  }).toList(),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    ),
  );
}

class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({super.key});

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  Map<String, List<String>> _folders = {'General': []};
  List<SavedArticle> _savedArticles = [];
  
  String? _selectedFeedUrl;
  bool _isSavedView = false;
  bool _isSettingsView = false;
  bool _isLoading = true;
  
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    
    final isDark = prefs.getBool('is_dark_mode') ?? true;
    themeNotifier.value = isDark ? ThemeMode.dark : ThemeMode.light;

    final foldersString = prefs.getString('saved_folders');
    if (foldersString != null) {
      final Map<String, dynamic> decoded = jsonDecode(foldersString);
      _folders = decoded.map((k, v) => MapEntry(k, List<String>.from(v)));
    } else {
      final oldFeeds = prefs.getStringList('saved_feeds');
      if (oldFeeds != null && oldFeeds.isNotEmpty) {
        _folders = {'General': oldFeeds};
      } else {
        _folders = {'General': []};
      }
    }

    final savedStringList = prefs.getStringList('saved_articles_list') ?? [];
    _savedArticles = savedStringList
        .map((item) => SavedArticle.fromJson(jsonDecode(item)))
        .toList();

    setState(() {
      _isLoading = false;
    });
  }

  Future<void> _saveData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('saved_folders', jsonEncode(_folders));
  }

  Future<void> _saveBookmarks() async {
    final prefs = await SharedPreferences.getInstance();
    final list = _savedArticles.map((article) => jsonEncode(article.toJson())).toList();
    await prefs.setStringList('saved_articles_list', list);
  }

  void _addFolder(String folderName) {
    if (folderName.isNotEmpty && !_folders.containsKey(folderName)) {
      setState(() {
        _folders[folderName] = [];
      });
      _saveData();
    }
  }

  void _removeFolder(BuildContext context, String folderName) {
    if (_folders.length <= 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You must keep at least one folder.')),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete Folder "$folderName"?'),
        content: const Text('This will remove the folder and all feeds contained within it.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white),
            onPressed: () {
              setState(() {
                _folders.remove(folderName);
                if (_selectedFeedUrl != null) {
                  // Reset feed selection if it belonged to deleted folder
                  bool stillExists = _folders.values.any((feeds) => feeds.contains(_selectedFeedUrl));
                  if (!stillExists) _selectedFeedUrl = null;
                }
              });
              _saveData();
              Navigator.pop(context);
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _addFeedToFolder(String folderName, String url) {
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme || (!uri.isScheme('http') && !uri.isScheme('https'))) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid HTTP/HTTPS URL.')),
      );
      return;
    }

    if (_folders.containsKey(folderName) && !_folders[folderName]!.contains(url)) {
      setState(() {
        _folders[folderName]!.add(url);
      });
      _saveData();
    }
  }

  void _removeFeed(String folderName, int index) {
    setState(() {
      _folders[folderName]?.removeAt(index);
    });
    _saveData();
  }

  String? _extractImageUrl(String? htmlContent) {
    if (htmlContent == null) return null;
    final document = html_parser.parse(htmlContent);
    final img = document.querySelector('img');
    return img?.attributes['src'];
  }

  void _toggleBookmark(RssItem item) {
    final rawContent = item.content?.value ?? item.description ?? '';
    final article = SavedArticle(
      title: item.title ?? 'Untitled',
      description: item.description ?? '',
      link: item.link ?? '',
      pubDate: item.pubDate ?? '',
      content: rawContent,
      imageUrl: _extractImageUrl(rawContent),
    );

    setState(() {
      final exists = _savedArticles.any((a) => a.link == article.link && a.title == article.title);
      if (exists) {
        _savedArticles.removeWhere((a) => a.link == article.link && a.title == article.title);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Removed from Saved Articles')));
      } else {
        _savedArticles.add(article);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Article Saved!')));
      }
    });
    _saveBookmarks();
  }

  bool _isBookmarked(RssItem item) {
    return _savedArticles.any((a) => a.link == item.link && a.title == item.title);
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    Widget mainContent;
    if (_isSettingsView) {
      mainContent = SettingsScreen(
        onOpenDrawer: () => _scaffoldKey.currentState?.openDrawer(),
      );
    } else if (_isSavedView) {
      mainContent = SavedArticlesScreen(
        articles: _savedArticles,
        onRemove: (article) {
          setState(() {
            _savedArticles.remove(article);
          });
          _saveBookmarks();
        },
        onToggleBookmark: _toggleBookmark,
        isBookmarked: _isBookmarked,
        onOpenDrawer: () => _scaffoldKey.currentState?.openDrawer(),
        folders: _folders,
        selectedFeedUrl: _selectedFeedUrl,
        onSelectFeed: (url) {
          setState(() {
            _selectedFeedUrl = url;
            _isSavedView = false;
            _isSettingsView = false;
          });
        },
        onViewChange: (saved, settings) {
          setState(() {
            _selectedFeedUrl = null;
            _isSavedView = saved;
            _isSettingsView = settings;
          });
        },
        onShowAddFolder: _showAddFolderDialog,
        onShowAddFeed: _showAddFeedDialog,
        onRemoveFeed: _removeFeed,
        onRemoveFolder: _removeFolder,
      );
    } else if (_selectedFeedUrl != null) {
      mainContent = NewsFeedScreen(
        key: PageStorageKey<String>(_selectedFeedUrl!),
        feedUrl: _selectedFeedUrl!,
        onToggleBookmark: _toggleBookmark,
        isBookmarked: _isBookmarked,
        onOpenDrawer: () => _scaffoldKey.currentState?.openDrawer(),
        folders: _folders,
        selectedFeedUrl: _selectedFeedUrl,
        onSelectFeed: (url) {
          setState(() {
            _selectedFeedUrl = url;
            _isSavedView = false;
            _isSettingsView = false;
          });
        },
        onViewChange: (saved, settings) {
          setState(() {
            _selectedFeedUrl = null;
            _isSavedView = saved;
            _isSettingsView = settings;
          });
        },
        onShowAddFolder: _showAddFolderDialog,
        onShowAddFeed: _showAddFeedDialog,
        onRemoveFeed: _removeFeed,
        onRemoveFolder: _removeFolder,
      );
    } else {
      mainContent = Scaffold(
        appBar: AppBar(
          title: const Text('Galaxy News'),
          leading: IconButton(
            icon: const Icon(Icons.menu),
            onPressed: () => _scaffoldKey.currentState?.openDrawer(),
          ),
        ),
        body: const Center(
          child: Text(
            'Select a feed from the sidebar or add a folder/feed to start reading.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey, fontSize: 16),
          ),
        ),
      );
    }

    return Scaffold(
      key: _scaffoldKey,
      drawer: buildMasterSidebar(
        context,
        _folders,
        _selectedFeedUrl,
        _isSavedView,
        _isSettingsView,
        (feedUrl) {
          setState(() {
            _selectedFeedUrl = feedUrl;
            _isSavedView = false;
            _isSettingsView = false;
          });
        },
        (isSaved, isSettings) {
          setState(() {
            _selectedFeedUrl = null;
            _isSavedView = isSaved;
            _isSettingsView = isSettings;
          });
        },
        _showAddFolderDialog,
        _showAddFeedDialog,
        _removeFeed,
        _removeFolder,
      ),
      body: mainContent,
    );
  }

  void _showAddFolderDialog(BuildContext context) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Create New Folder'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: 'Folder Name'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              _addFolder(controller.text.trim());
              Navigator.pop(context);
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  void _showAddFeedDialog(BuildContext context, String folderName) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Add Feed to $folderName'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: 'RSS Feed URL (https://...)'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              _addFeedToFolder(folderName, controller.text.trim());
              Navigator.pop(context);
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }
}

class NewsFeedScreen extends StatefulWidget {
  final String feedUrl;
  final Function(RssItem) onToggleBookmark;
  final bool Function(RssItem) isBookmarked;
  final VoidCallback onOpenDrawer;
  final Map<String, List<String>> folders;
  final String? selectedFeedUrl;
  final Function(String?) onSelectFeed;
  final Function(bool, bool) onViewChange;
  final Function(BuildContext) onShowAddFolder;
  final Function(BuildContext, String) onShowAddFeed;
  final Function(String, int) onRemoveFeed;
  final Function(BuildContext, String) onRemoveFolder;

  const NewsFeedScreen({
    super.key,
    required this.feedUrl,
    required this.onToggleBookmark,
    required this.isBookmarked,
    required this.onOpenDrawer,
    required this.folders,
    required this.selectedFeedUrl,
    required this.onSelectFeed,
    required this.onViewChange,
    required this.onShowAddFolder,
    required this.onShowAddFeed,
    required this.onRemoveFeed,
    required this.onRemoveFolder,
  });

  @override
  State<NewsFeedScreen> createState() => _NewsFeedScreenState();
}

class _NewsFeedScreenState extends State<NewsFeedScreen> {
  late Future<RssFeed> _futureFeed;
  final GlobalKey<ScaffoldState> _feedScaffoldKey = GlobalKey<ScaffoldState>();

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
      key: _feedScaffoldKey,
      drawer: buildMasterSidebar(
        context,
        widget.folders,
        widget.selectedFeedUrl,
        false,
        false,
        widget.onSelectFeed,
        widget.onViewChange,
        widget.onShowAddFolder,
        widget.onShowAddFeed,
        widget.onRemoveFeed,
        widget.onRemoveFolder,
      ),
      appBar: AppBar(
        title: Text(widget.feedUrl, overflow: TextOverflow.ellipsis),
        leading: IconButton(
          icon: const Icon(Icons.menu),
          onPressed: () => _feedScaffoldKey.currentState?.openDrawer(),
        ),
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
            key: PageStorageKey<String>('grid_${widget.feedUrl}'),
            padding: const EdgeInsets.all(12.0),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 320,
              childAspectRatio: 1.05,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
            ),
            itemCount: items.length,
            itemBuilder: (context, index) {
              final item = items[index];
              final bookmarked = widget.isBookmarked(item);

              return InkWell(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => ArticleDetailScreen(
                        item: item,
                        onToggleBookmark: widget.onToggleBookmark,
                        isBookmarked: bookmarked,
                        folders: widget.folders,
                        selectedFeedUrl: widget.selectedFeedUrl,
                        onSelectFeed: widget.onSelectFeed,
                        onViewChange: widget.onViewChange,
                        onShowAddFolder: widget.onShowAddFolder,
                        onShowAddFeed: widget.onShowAddFeed,
                        onRemoveFeed: widget.onRemoveFeed,
                        onRemoveFolder: widget.onRemoveFolder,
                      ),
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
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                item.title ?? 'Untitled',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                ),
                              ),
                            ),
                            IconButton(
                              icon: Icon(
                                bookmarked ? Icons.star : Icons.star_border,
                                color: Colors.amber,
                              ),
                              onPressed: () {
                                widget.onToggleBookmark(item);
                                setState(() {});
                              },
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Expanded(
                          child: Text(
                            _cleanSnippet(item.description),
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.grey[600],
                              fontSize: 13,
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          item.pubDate ?? '',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey[500],
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

class ArticleDetailScreen extends StatefulWidget {
  final RssItem item;
  final Function(RssItem) onToggleBookmark;
  final bool isBookmarked;
  final Map<String, List<String>> folders;
  final String? selectedFeedUrl;
  final Function(String?) onSelectFeed;
  final Function(bool, bool) onViewChange;
  final Function(BuildContext) onShowAddFolder;
  final Function(BuildContext, String) onShowAddFeed;
  final Function(String, int) onRemoveFeed;
  final Function(BuildContext, String) onRemoveFolder;

  const ArticleDetailScreen({
    super.key,
    required this.item,
    required this.onToggleBookmark,
    required this.isBookmarked,
    required this.folders,
    required this.selectedFeedUrl,
    required this.onSelectFeed,
    required this.onViewChange,
    required this.onShowAddFolder,
    required this.onShowAddFeed,
    required this.onRemoveFeed,
    required this.onRemoveFolder,
  });

  @override
  State<ArticleDetailScreen> createState() => _ArticleDetailScreenState();
}

class _ArticleDetailScreenState extends State<ArticleDetailScreen> {
  late bool _bookmarkedState;
  final GlobalKey<ScaffoldState> _articleScaffoldKey = GlobalKey<ScaffoldState>();

  @override
  void initState() {
    super.initState();
    _bookmarkedState = widget.isBookmarked;
  }

  Widget _buildCachedImage(String src) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12.0),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8.0),
        child: CachedNetworkImage(
          imageUrl: src,
          placeholder: (context, url) => Container(
            height: 150,
            color: Colors.grey[300],
            child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
          ),
          errorWidget: (context, url, error) => const SizedBox.shrink(),
          fit: BoxFit.cover,
        ),
      ),
    );
  }

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

      if (tag == 'h1' || tag == 'h2' || tag == 'h3') {
        if (text.isNotEmpty) {
          widgets.add(Padding(
            padding: const EdgeInsets.only(top: 20.0, bottom: 10.0),
            child: Text(text, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          ));
        }
      } else if (tag == 'figure' || tag == 'img') {
        final img = tag == 'img' ? node : node.querySelector('img');
        final src = img?.attributes['src'];
        if (src != null) widgets.add(_buildCachedImage(src));
      } else if (tag == 'p') {
        final img = node.querySelector('img');
        if (img != null) {
          final src = img.attributes['src'];
          if (src != null) widgets.add(_buildCachedImage(src));
        }
        if (text.isNotEmpty) {
          widgets.add(Padding(
            padding: const EdgeInsets.only(bottom: 14.0),
            child: Text(text, style: const TextStyle(fontSize: 16, height: 1.6)),
          ));
        }
      }
    }

    if (widgets.isEmpty && body.text.trim().isNotEmpty) {
      widgets.add(Text(body.text.trim(), style: const TextStyle(fontSize: 16, height: 1.6)));
    }

    return widgets;
  }

  @override
  Widget build(BuildContext context) {
    final rawContent = widget.item.content?.value ?? widget.item.description;

    return Scaffold(
      key: _articleScaffoldKey,
      drawer: buildMasterSidebar(
        context,
        widget.folders,
        widget.selectedFeedUrl,
        false,
        false,
        widget.onSelectFeed,
        widget.onViewChange,
        widget.onShowAddFolder,
        widget.onShowAddFeed,
        widget.onRemoveFeed,
        widget.onRemoveFolder,
      ),
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.menu),
          onPressed: () => _articleScaffoldKey.currentState?.openDrawer(),
        ),
        title: Text(widget.item.source?.value ?? 'Article', overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            icon: Icon(_bookmarkedState ? Icons.star : Icons.star_border, color: Colors.amber),
            onPressed: () {
              widget.onToggleBookmark(widget.item);
              setState(() {
                _bookmarkedState = !_bookmarkedState;
              });
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        key: PageStorageKey<String>('detail_${widget.item.link ?? widget.item.title}'),
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.item.title ?? 'Untitled', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            Text(widget.item.pubDate ?? '', style: TextStyle(fontSize: 13, color: Colors.grey[600])),
            const Divider(height: 30),
            ..._buildRichContent(rawContent),
          ],
        ),
      ),
    );
  }
}

class SettingsScreen extends StatelessWidget {
  final VoidCallback onOpenDrawer;

  const SettingsScreen({super.key, required this.onOpenDrawer});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        leading: IconButton(icon: const Icon(Icons.menu), onPressed: onOpenDrawer),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          const Text('Appearance', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          ValueListenableBuilder<ThemeMode>(
            valueListenable: themeNotifier,
            builder: (context, themeMode, child) {
              return SwitchListTile(
                title: const Text('Dark Mode'),
                subtitle: Text(themeMode == ThemeMode.dark ? 'Currently Dark' : 'Currently Light'),
                value: themeMode == ThemeMode.dark,
                onChanged: (bool value) async {
                  themeNotifier.value = value ? ThemeMode.dark : ThemeMode.light;
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.setBool('is_dark_mode', value);
                },
              );
            },
          ),
        ],
      ),
    );
  }
}

class SavedArticlesScreen extends StatelessWidget {
  final List<SavedArticle> articles;
  final Function(SavedArticle) onRemove;
  final Function(RssItem) onToggleBookmark;
  final bool Function(RssItem) isBookmarked;
  final VoidCallback onOpenDrawer;
  final Map<String, List<String>> folders;
  final String? selectedFeedUrl;
  final Function(String?) onSelectFeed;
  final Function(bool, bool) onViewChange;
  final Function(BuildContext) onShowAddFolder;
  final Function(BuildContext, String) onShowAddFeed;
  final Function(String, int) onRemoveFeed;
  final Function(BuildContext, String) onRemoveFolder;

  const SavedArticlesScreen({
    super.key,
    required this.articles,
    required this.onRemove,
    required this.onToggleBookmark,
    required this.isBookmarked,
    required this.onOpenDrawer,
    required this.folders,
    required this.selectedFeedUrl,
    required this.onSelectFeed,
    required this.onViewChange,
    required this.onShowAddFolder,
    required this.onShowAddFeed,
    required this.onRemoveFeed,
    required this.onRemoveFolder,
  });

  String _cleanSnippet(String? htmlString) {
    if (htmlString == null) return 'No description available.';
    final document = html_parser.parse(htmlString);
    return document.body?.text ?? 'No description available.';
  }

  @override
  Widget build(BuildContext context) {
    final GlobalKey<ScaffoldState> savedScaffoldKey = GlobalKey<ScaffoldState>();

    return Scaffold(
      key: savedScaffoldKey,
      drawer: buildMasterSidebar(
        context,
        folders,
        selectedFeedUrl,
        true,
        false,
        onSelectFeed,
        onViewChange,
        onShowAddFolder,
        onShowAddFeed,
        onRemoveFeed,
        onRemoveFolder,
      ),
      appBar: AppBar(
        title: const Text('Saved Articles'),
        leading: IconButton(
          icon: const Icon(Icons.menu),
          onPressed: () => savedScaffoldKey.currentState?.openDrawer(),
        ),
      ),
      body: articles.isEmpty
          ? const Center(
              child: Text(
                'No saved articles yet. Click the star icon on any article to save it!',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey, fontSize: 16),
              ),
            )
          : GridView.builder(
              padding: const EdgeInsets.all(12.0),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 320,
                childAspectRatio: 1.05,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
              ),
              itemCount: articles.length,
              itemBuilder: (context, index) {
                final article = articles[index];
                final item = RssItem(
                  title: article.title,
                  description: article.content,
                  link: article.link,
                  pubDate: article.pubDate,
                );
                final bookmarked = isBookmarked(item);

                return InkWell(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => ArticleDetailScreen(
                          item: item,
                          onToggleBookmark: onToggleBookmark,
                          isBookmarked: bookmarked,
                          folders: folders,
                          selectedFeedUrl: selectedFeedUrl,
                          onSelectFeed: onSelectFeed,
                        onViewChange: onViewChange,
                        onShowAddFolder: onShowAddFolder,
                        onShowAddFeed: onShowAddFeed,
                        onRemoveFeed: onRemoveFeed,
                        onRemoveFolder: onRemoveFolder,
                      ),
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
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                article.title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                ),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.star, color: Colors.amber),
                              onPressed: () => onRemove(article),
                              tooltip: 'Remove from Saved',
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Expanded(
                          child: Text(
                            _cleanSnippet(article.description),
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.grey[600],
                              fontSize: 13,
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          article.pubDate,
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey[500],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
    );
  }
}
