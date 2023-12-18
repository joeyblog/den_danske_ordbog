import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as htmlParser;
import 'package:html/dom.dart' as htmlDom;
import 'package:flutter_tts/flutter_tts.dart';
import 'package:adaptive_theme/adaptive_theme.dart';

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return AdaptiveTheme(
      light: ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        colorSchemeSeed: Colors.lightBlue[600],
      ),
      dark: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorSchemeSeed: Colors.lightBlue[600],
      ),
      initial: AdaptiveThemeMode.system,
      builder: (theme, darkTheme) => MaterialApp(
        title: 'Adaptive Theme Demo',
        theme: theme,
        darkTheme: darkTheme,
        home: MyHomePage(),
      ),
    );
  }
}

class MyHomePage extends StatefulWidget {
  @override
  _MyHomePageState createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  TextEditingController _controller = TextEditingController();
  FlutterTts _flutterTts = FlutterTts();
  bool loading = false;
  List<SearchResult> searchResultList = [];
  List<WordInfo> wordInfoList = [];
  Map<String, List<SearchResult>> searchResultsCache = {};
  Map<String, WordInfo> wordInfoCache = {};

  Future<void> fetchSearchResult() async {
    setState(() {
      loading = true;
      wordInfoList = [];
      searchResultList = [];
    });

    final searchTerm = _controller.text;

    // キャッシュがあればそれを利用
    if (searchResultsCache.containsKey(searchTerm)) {
      setState(() async {
        for (var r in searchResultsCache[searchTerm]!) {
          await fetchWordInformation(r.wordUrl, r.wordName, r.partOfSpeech);
        }
        loading = false;
      });
      return;
    }

    final url = 'https://ordnet.dk/ddo/ordbog?query=$searchTerm';

    try {
      final response = await http.get(Uri.parse(url));

      if (response.statusCode == 200) {
        // HTML をパース
        var document = htmlParser.parse(response.body);

        // 検索結果を取得
        var searchResultBox = document.querySelector('.searchResultBox');

        if (searchResultBox != null) {
          var searchResultItems = searchResultBox.querySelectorAll('div');
          setState(() {
            loading = false;
          });
          for (var item in searchResultItems) {
            var link = item.querySelector('a');
            if (link != null) {
              link.children.forEach((child) {
                child.remove();
              });
              var wordUrl = link.attributes['href'] ?? '';
              var wordName = link.text.trim();
              item.children.forEach((child) {
                child.remove();
              });
              var partOfSpeech = item.text.trim();
              searchResultList.add(SearchResult(
                wordName,
                partOfSpeech,
                wordUrl,
              ));
              await fetchWordInformation(wordUrl, wordName, partOfSpeech);
            }
          }
          searchResultsCache[searchTerm] = searchResultList;
        }
      } else {
        print(
            'Failed to load search result. Status code: ${response.statusCode}');
      }
    } catch (e) {
      print('Error: $e');
      setState(() {
        loading = false;
      });
    } finally {}
  }

  Future<void> fetchWordInformation(
      String wordUrl, String wordName, String partOfSpeech) async {
    setState(() {
      wordInfoList.add(WordInfo.skeleton());
    });

    String pronunciation = '';
    String inflections = '';
    List<Definition> definitions = [];

    // キャッシュがあればそれを利用
    if (wordInfoCache.containsKey(wordUrl)) {
      var cachedResult = wordInfoCache[wordUrl]!;
      pronunciation = cachedResult.pronunciation;
      inflections = cachedResult.inflections;
      definitions = cachedResult.definitions;
      wordInfoCache[wordUrl] = WordInfo(
        wordName,
        partOfSpeech,
        wordUrl,
        pronunciation,
        inflections,
        definitions,
      );
      setState(() {
        wordInfoList.removeWhere(
            (result) => result.wordName.isEmpty && result.partOfSpeech.isEmpty);
        wordInfoList.add(WordInfo(wordName, partOfSpeech, wordUrl,
            pronunciation, inflections, definitions));
      });
    } else {
      try {
        final response = await http.get(Uri.parse(wordUrl));

        if (response.statusCode == 200) {
          // HTML をパース
          final document = htmlParser.parse(response.body);

          // 必要な情報を取得
          final pronunciationElement = document.querySelector('.lydskrift');
          pronunciation = pronunciationElement?.text ?? 'Not found';
          pronunciation =
              pronunciation.replaceAll('[', '/').replaceAll(']', '/');

          final inflectionsElement = document.querySelector('#id-boj');
          inflections = inflectionsElement?.text ?? 'Not found';
          inflections = inflections.replaceAll(RegExp("Bøjning"), "").trim();
          inflections = inflections.replaceAll("-", wordName).trim();

          final definitionBox = document.querySelector('#content-betydninger');
          if (definitionBox != null) {
            definitions = _extractDefinitions(definitionBox);
          }
        } else {
          print(
              'Failed to load word information. Status code: ${response.statusCode}');
        }
      } catch (e) {
        print('Error: $e');
      } finally {
        // キャッシュに結果を保存
        wordInfoCache[wordUrl] = WordInfo(
          wordName,
          partOfSpeech,
          wordUrl,
          pronunciation,
          inflections,
          definitions,
        );
        setState(() {
          wordInfoList.removeWhere((result) =>
              result.wordName.isEmpty && result.partOfSpeech.isEmpty);
          wordInfoList.add(WordInfo(wordName, partOfSpeech, wordUrl,
              pronunciation, inflections, definitions));
        });
      }
    }
  }

  List<Definition> _extractDefinitions(htmlDom.Element definitionBox) {
    List<Definition> result = [];
    // Extracting definitions with numbers
    final definitionNumbers =
        definitionBox.querySelectorAll('.definitionNumber');
    final definitionIndents =
        definitionBox.querySelectorAll('.definitionIndent');

    for (int i = 0; i < definitionNumbers.length; i++) {
      var numberText = definitionNumbers[i].text.trim();
      final indentText =
          definitionIndents[i].querySelector('.definition')?.text ?? "";
      numberText = numberText.replaceAll(".", "");

      bool toIndent = numberText.contains(RegExp('[a-zA-Z]'));

      result.add(Definition(numberText, indentText.trim(), toIndent));
    }

    return result;
  }

  Future<void> _playTTS(String text) async {
    await _flutterTts.setLanguage('da-DK');
    await _flutterTts.speak(text);
  }

  @override
  void dispose() {
    _controller.dispose();
    _flutterTts.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Den Danske Ordbog'),
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              TextField(
                controller: _controller,
                onChanged: (value) {
                  setState(() {});
                },
                decoration: InputDecoration(
                  labelText: 'Indtast et ord her',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: () {
                      setState(() {
                        _controller.clear();
                        wordInfoList.clear();
                      });
                    },
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12.0),
                  ),
                ),
              ),
              const SizedBox(height: 16.0),
              ElevatedButton(
                onPressed: () async {
                  await fetchSearchResult();
                  setState(() {});
                },
                style: ElevatedButton.styleFrom(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12.0),
                  ),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.search),
                    SizedBox(width: 8.0),
                    Text('Søg'),
                  ],
                ),
              ),
              const SizedBox(height: 16.0),
              Column(
                children: wordInfoList
                    .map((result) => _buildWordInfoCard(result))
                    .toList(),
              ),
              loading
                  ? CircularProgressIndicator(
                      backgroundColor: Colors.grey[300], // Skeleton bar color
                      valueColor:
                          AlwaysStoppedAnimation<Color>(Colors.grey[500]!),
                    )
                  : const SizedBox.shrink(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWordInfoCard(WordInfo result) {
    // Check if it's a skeleton WordInfo
    if (result.wordName.isEmpty && result.partOfSpeech.isEmpty) {
      // Show a loading indicator for the skeleton card
      return Card(
        elevation: 4.0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16.0),
        ),
        child: SizedBox(
          width: double.infinity, // Set width to match the parent card
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Loading indicator (LinearProgressIndicator for a skeleton bar)
                const SizedBox(height: 8.0),
                CircularProgressIndicator(
                  backgroundColor: Colors.grey[300], // Skeleton bar color
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.grey[500]!),
                ),
                const SizedBox(height: 8.0),
              ],
            ),
          ),
        ),
      );
    }

    // It's an actual WordInfo, show the data
    return Card(
      elevation: 4.0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16.0),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${result.wordName} (${result.partOfSpeech})',
              style: const TextStyle(
                fontSize: 24.0,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8.0),
            Row(
              children: [
                Text(
                  result.pronunciation,
                  style: const TextStyle(
                    fontStyle: FontStyle.italic,
                  ),
                ),
                IconButton(
                  iconSize: 20.0,
                  icon: const Icon(Icons.volume_up),
                  onPressed: () {
                    _playTTS("${result.wordName}, ${result.inflections}");
                  },
                ),
              ],
            ),
            Text(
              result.inflections,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16.0),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: result.definitions
                  .map((definition) => _buildDefinitionCard(definition))
                  .toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDefinitionCard(Definition definition) {
    return Padding(
      padding: EdgeInsets.only(left: definition.toIndent ? 16.0 : 0.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${definition.numberText}. ${definition.indentText}',
            style: const TextStyle(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8.0),
        ],
      ),
    );
  }
}

class SearchResult {
  final String wordName;
  final String partOfSpeech;
  final String wordUrl;

  SearchResult(
    this.wordName,
    this.partOfSpeech,
    this.wordUrl,
  );
}

class WordInfo {
  final String wordName;
  final String partOfSpeech;
  final String wordUrl;
  final String pronunciation;
  final String inflections;
  final List<Definition> definitions;

  WordInfo(
    this.wordName,
    this.partOfSpeech,
    this.wordUrl,
    this.pronunciation,
    this.inflections,
    this.definitions,
  );

  // Factory constructor for creating a skeleton WordInfo
  factory WordInfo.skeleton() {
    return WordInfo('', '', '', '', '', []);
  }
}

class Definition {
  final String numberText;
  final String indentText;
  final bool toIndent;

  Definition(this.numberText, this.indentText, this.toIndent);
}
