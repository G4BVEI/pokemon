// main.dart — Pokédex (Flutter) baseado no exemplo React (App.tsx)
// Sem busca · rolagem infinita · árvore de evolução com imagens
//
// pubspec.yaml -> dependencies:
//   http: ^1.2.0
//   sqflite: ^2.3.0
//   path: ^1.9.0
//   google_fonts: ^6.2.0
//
// Android: adicione <uses-permission android:name="android.permission.INTERNET"/>
// no AndroidManifest.xml principal (builds release).

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as pth;
import 'package:sqflite/sqflite.dart';

// ─────────────────────────── Cores ───────────────────────────
const kRed = Color(0xFFB5162D);
const kDarkRed = Color(0xFF8F1025);
const kShadowRed = Color(0xFF7D1022);
const kBg = Color(0xFFF6E9E7);
const kCream = Color(0xFFFFF8EF);
const kDark = Color(0xFF2B1014);
const kBorder = Color(0xFFCDA9A4);
const kPink = Color(0xFFF8D9D5);
const kTeal = Color(0xFFDCEDEA);
const kYellow = Color(0xFFE4C93D);
const kMuted = Color(0xFF6E4B4E);
const kBarBg = Color(0xFFEAD3D0);
const kLabel = Color(0xFF9D6D72);

// ─────────────────────────── Helpers ───────────────────────────
String pad3(int n) => n.toString().padLeft(3, '0');
String cap(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
String humanize(String s) => s.split('-').map(cap).join(' ');

int idFromUrl(String url) =>
    int.parse(url.split('/').where((s) => s.isNotEmpty).last);

const _spriteBase =
    'https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites/pokemon';

String artworkUrl(int id, {bool shiny = false}) =>
    '$_spriteBase/other/official-artwork/${shiny ? "shiny/" : ""}$id.png';
String spriteUrl(int id) => '$_spriteBase/$id.png';

TextStyle mono({double size = 12, Color color = kDarkRed}) =>
    GoogleFonts.dmMono(
      fontSize: size,
      fontWeight: FontWeight.w500,
      color: color,
    );

String fmtNum(double v) =>
    (v == v.roundToDouble() ? v.toInt().toString() : v.toString()).replaceAll(
      '.',
      ',',
    );

/// Texto de efeito em inglês, sem marcações da API.
String effectText(Map<String, dynamic> d, {bool short = false}) {
  final entries = (d['effect_entries'] as List?) ?? const [];
  for (final e in entries) {
    if (e['language']['name'] == 'en') {
      final raw = (short ? e['short_effect'] : e['effect']) as String;
      return raw
          .replaceAll(r'$effect_chance', '${d['effect_chance'] ?? ''}')
          .replaceAllMapped(RegExp(r'\[([^\]]*)\]\{[^}]*\}'), (m) => m[1] ?? '')
          .replaceAll(RegExp(r'\s*\n\s*'), ' ')
          .trim();
    }
  }
  return 'Sem descrição.';
}

/// Última descrição em inglês (a mais recente entre os jogos).
String? latestFlavor(List? entries) {
  if (entries == null) return null;
  for (var i = entries.length - 1; i >= 0; i--) {
    final e = entries[i];
    if (e['language']['name'] == 'en') {
      return (e['flavor_text'] as String)
          .replaceAll(RegExp('\u00ad\\n?'), '')
          .replaceAll(RegExp(r'[\n\f]'), ' ')
          .trim();
    }
  }
  return null;
}

// ─────────────────────────── API + cache ───────────────────────────
/// Cache em 3 níveis: memória (LRU simples) → SQLite → rede.
/// Se o SQLite não estiver disponível (web/desktop sem ffi), usa só memória.
class Api {
  static const base = 'https://pokeapi.co/api/v2';
  static Database? _db;
  static final http.Client _client = http.Client();
  static final Map<String, dynamic> _mem = <String, dynamic>{};
  static final Map<String, Future<dynamic>> _inflight =
      <String, Future<dynamic>>{};

  static Future<void> init() async {
    try {
      final path = pth.join(await getDatabasesPath(), 'pokedex.db');
      _db = await openDatabase(
        path,
        version: 1,
        onCreate: (db, _) => db.execute(
          'CREATE TABLE cache (url TEXT PRIMARY KEY, body TEXT NOT NULL)',
        ),
      );
    } catch (e) {
      debugPrint('SQLite indisponível, usando apenas memória: $e');
    }
  }

  static void _remember(String url, dynamic data) {
    _mem[url] = data;
    if (_mem.length > 200) _mem.remove(_mem.keys.first);
  }

  /// [path] pode ser relativo ("pokemon/25") ou uma URL completa.
  static Future<dynamic> get(String path) {
    final url = path.startsWith('http') ? path : '$base/$path';
    if (_mem.containsKey(url)) return Future<dynamic>.value(_mem[url]);
    return _inflight[url] ??= _fetch(url).whenComplete(() {
      _inflight.remove(url);
    });
  }

  static Future<dynamic> _fetch(String url) async {
    final db = _db;
    if (db != null) {
      final rows = await db.query(
        'cache',
        columns: ['body'],
        where: 'url = ?',
        whereArgs: [url],
        limit: 1,
      );
      if (rows.isNotEmpty) {
        final data = jsonDecode(rows.first['body'] as String);
        _remember(url, data);
        return data;
      }
    }
    final res = await _client.get(Uri.parse(url));
    if (res.statusCode != 200) {
      throw Exception('Erro ${res.statusCode} em $url');
    }
    final body = utf8.decode(res.bodyBytes);
    final data = jsonDecode(body);
    _remember(url, data);
    if (db != null) {
      await db.insert('cache', {
        'url': url,
        'body': body,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    return data;
  }
}

/// Índice id → tipos, montado a partir dos 18 endpoints /type/{n}.
/// Evita baixar o JSON completo de cada Pokémon só para mostrar os tipos nos cards.
class TypeIndex {
  static final Map<int, List<String>> _byId = <int, List<String>>{};
  static Future<void>? _loading;

  static Future<void> ensure() => _loading ??= _load().catchError((Object e) {
    _loading = null;
    throw e;
  });

  static Future<void> _load() async {
    final all = await Future.wait(
      List.generate(18, (i) => Api.get('type/${i + 1}')),
    );
    final tmp = <int, List<MapEntry<int, String>>>{};
    for (final t in all) {
      final name = t['name'] as String;
      for (final e in (t['pokemon'] as List)) {
        final id = idFromUrl(e['pokemon']['url'] as String);
        (tmp[id] ??= <MapEntry<int, String>>[]).add(
          MapEntry(e['slot'] as int, name),
        );
      }
    }
    tmp.forEach((id, list) {
      list.sort((a, b) => a.key.compareTo(b.key));
      _byId[id] = list.map((e) => e.value).toList();
    });
  }

  static List<String> of(int id) => _byId[id] ?? const <String>[];
}

// ─────────────────────────── Widgets básicos ───────────────────────────
class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = const Color(0x1A154D45)
      ..strokeWidth = 1;
    for (double x = 0; x <= size.width; x += 16) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), p);
    }
    for (double y = 0; y <= size.height; y += 16) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), p);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Moldura "tela do scanner" (fundo quadriculado) para as imagens.
class SpriteFrame extends StatelessWidget {
  const SpriteFrame({
    super.key,
    required this.child,
    this.height,
    this.border = 0,
  });
  final Widget child;
  final double? height;
  final double border;

  @override
  Widget build(BuildContext context) => Container(
    height: height,
    width: double.infinity,
    decoration: BoxDecoration(
      color: kTeal,
      border: border > 0 ? Border.all(color: kDark, width: border) : null,
    ),
    child: Stack(
      fit: StackFit.expand,
      children: [
        Positioned.fill(child: CustomPaint(painter: _GridPainter())),
        Padding(
          padding: const EdgeInsets.all(8),
          child: Center(child: child),
        ),
      ],
    ),
  );
}

/// Arte oficial do Pokémon, com loading e fallback para o sprite pequeno.
class PokeImage extends StatelessWidget {
  const PokeImage(
    this.id, {
    super.key,
    this.shiny = false,
    this.cacheWidth = 320,
  });
  final int id;
  final bool shiny;
  final int cacheWidth;

  @override
  Widget build(BuildContext context) => Image.network(
    artworkUrl(id, shiny: shiny),
    fit: BoxFit.contain,
    cacheWidth: cacheWidth,
    gaplessPlayback: true,
    loadingBuilder: (c, child, progress) => progress == null
        ? child
        : const Center(
            child: SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2, color: kRed),
            ),
          ),
    errorBuilder: (c, e, s) => Image.network(
      spriteUrl(id),
      fit: BoxFit.contain,
      filterQuality: FilterQuality.none,
      errorBuilder: (c, e, s) =>
          const Icon(Icons.catching_pokemon, color: kBorder, size: 40),
    ),
  );
}

class Pill extends StatelessWidget {
  const Pill(
    this.label, {
    super.key,
    this.big = false,
    this.bg = kPink,
    this.fg = kDarkRed,
    this.border = kDarkRed,
    this.onTap,
  });
  final String label;
  final bool big;
  final Color bg, fg, border;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: EdgeInsets.symmetric(
        horizontal: big ? 12 : 6,
        vertical: big ? 6 : 2,
      ),
      decoration: BoxDecoration(
        color: bg,
        border: Border.all(color: border, width: big ? 2 : 1),
      ),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          fontSize: big ? 10 : 9,
          fontWeight: FontWeight.w900,
          color: fg,
          letterSpacing: 0.6,
        ),
      ),
    ),
  );
}

class InfoBox extends StatelessWidget {
  const InfoBox({super.key, required this.label, required this.value});
  final String label, value;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(border: Border.all(color: kDark, width: 2)),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w900,
            color: kLabel,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900),
        ),
      ],
    ),
  );
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, this.color = kDark});
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w900,
      letterSpacing: 2,
      color: color,
    ),
  );
}

class HeroPanel extends StatelessWidget {
  const HeroPanel({
    super.key,
    required this.kicker,
    required this.title,
    this.subtitle,
  });
  final String kicker, title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.fromLTRB(16, 16, 16, 20),
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: kCream,
      border: Border.all(color: kDark, width: 2),
      boxShadow: const [BoxShadow(color: kShadowRed, offset: Offset(5, 5))],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          kicker,
          style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w800,
            letterSpacing: 2,
            color: Color(0xFF9D1830),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          title,
          style: const TextStyle(
            fontSize: 30,
            fontWeight: FontWeight.w900,
            letterSpacing: -1.2,
            height: 1.05,
          ),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 10),
          Text(
            subtitle!,
            style: const TextStyle(fontSize: 13, color: kMuted, height: 1.4),
          ),
        ],
      ],
    ),
  );
}

void openPokemon(BuildContext context, int id) => Navigator.push(
  context,
  MaterialPageRoute(builder: (_) => PokemonDetailPage(id: id)),
);

void openResource(BuildContext context, String kind, String name) =>
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ResourceDetailPage(kind: kind, name: name),
      ),
    );

// ─────────────────────────── Grade com rolagem infinita ───────────────────────────
/// Lista paginada genérica (limit/offset) com rolagem infinita.
/// Usada para Pokémon, golpes e habilidades.
class PagedGrid extends StatefulWidget {
  const PagedGrid({
    super.key,
    required this.endpoint,
    required this.limit,
    required this.header,
    required this.gridDelegate,
    required this.loadItem,
    required this.itemBuilder,
  });

  final String endpoint;
  final int limit;
  final Widget header;
  final SliverGridDelegate gridDelegate;

  /// Transforma um item bruto da lista ({name, url}) nos dados exibidos no card.
  final Future<Map<String, dynamic>> Function(Map<String, dynamic> raw)
  loadItem;
  final Widget Function(BuildContext context, Map<String, dynamic> item)
  itemBuilder;

  @override
  State<PagedGrid> createState() => _PagedGridState();
}

class _PagedGridState extends State<PagedGrid>
    with AutomaticKeepAliveClientMixin<PagedGrid> {
  final ScrollController _scroll = ScrollController();
  final List<Map<String, dynamic>> _items = <Map<String, dynamic>>[];
  bool _loading = false;
  bool _hasMore = true;
  Object? _error;
  int _offset = 0;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _loadMore();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_error != null) return;
    if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 400) {
      _loadMore();
    }
  }

  Future<void> _loadMore() async {
    if (_loading || !_hasMore) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await Api.get(
        '${widget.endpoint}?limit=${widget.limit}&offset=$_offset',
      ) as Map<String, dynamic>;
      final raw = (page['results'] as List).cast<Map<String, dynamic>>();
      // ids >= 10000 são formas alternativas: encerramos a lista aqui.
      final valid = raw
          .where((r) => idFromUrl(r['url'] as String) < 10000)
          .toList();
      final batch = await Future.wait(valid.map(widget.loadItem));
      if (!mounted) return;
      setState(() {
        _items.addAll(batch);
        _offset += widget.limit;
        _hasMore = valid.length == raw.length && page['next'] != null;
        _loading = false;
      });
      // Se a tela ainda não rola (tablet/desktop), carrega a próxima página.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted &&
            _hasMore &&
            _scroll.hasClients &&
            _scroll.position.maxScrollExtent < 400) {
          _loadMore();
        }
      });
    } catch (e) {
      debugPrint('Erro ao carregar ${widget.endpoint}: $e');
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e;
        });
      }
    }
  }

  Widget _footer() {
    final Widget child;
    if (_error != null) {
      child = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Não foi possível carregar mais itens.',
            style: TextStyle(fontSize: 12, color: kMuted),
          ),
          TextButton(
            onPressed: _loadMore,
            child: const Text(
              'TENTAR DE NOVO',
              style: TextStyle(fontWeight: FontWeight.w900, color: kDarkRed),
            ),
          ),
        ],
      );
    } else if (_loading) {
      child = const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2, color: kRed),
          ),
          SizedBox(width: 12),
          Text(
            'CARREGANDO MAIS...',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.5,
              color: kDarkRed,
            ),
          ),
        ],
      );
    } else if (!_hasMore) {
      child = const Text(
        'TODOS OS RESULTADOS FORAM CARREGADOS',
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.5,
          color: kMuted,
        ),
      );
    } else {
      child = const SizedBox.shrink();
    }
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 24, 16, 32),
      padding: const EdgeInsets.only(top: 16),
      constraints: const BoxConstraints(minHeight: 64),
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: kBorder)),
      ),
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return CustomScrollView(
      controller: _scroll,
      slivers: [
        SliverToBoxAdapter(child: widget.header),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          sliver: SliverGrid(
            gridDelegate: widget.gridDelegate,
            delegate: SliverChildBuilderDelegate(
              (ctx, i) => widget.itemBuilder(ctx, _items[i]),
              childCount: _items.length,
            ),
          ),
        ),
        SliverToBoxAdapter(child: _footer()),
      ],
    );
  }
}

// ─────────────────────────── App ───────────────────────────
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Api.init();
  runApp(const PokedexApp());
}

class PokedexApp extends StatelessWidget {
  const PokedexApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Pokédex',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: kBg,
      colorScheme: ColorScheme.fromSeed(seedColor: kRed),
      textTheme: GoogleFonts.manropeTextTheme(),
    ),
    home: const HomeShell(),
  );
}

class HomeShell extends StatelessWidget {
  const HomeShell({super.key});

  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 3,
    child: Scaffold(
      appBar: AppBar(
        backgroundColor: kRed,
        foregroundColor: Colors.white,
        title: Row(
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: kCream, width: 3),
                gradient: const RadialGradient(
                  colors: [
                    Color(0xFFDFFCFF),
                    Color(0xFF55D9ED),
                    Color(0xFF147F9B),
                    Color(0xFF0B3C51),
                  ],
                  stops: [0.0, 0.3, 0.6, 1.0],
                ),
              ),
            ),
            const SizedBox(width: 10),
            const Text(
              'Pokédex',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
          ],
        ),
        bottom: const TabBar(
          indicatorColor: Colors.white,
          indicatorWeight: 3,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          labelStyle: TextStyle(fontWeight: FontWeight.w900, fontSize: 12),
          tabs: [
            Tab(text: 'POKÉMON'),
            Tab(text: 'GOLPES'),
            Tab(text: 'HABILIDADES'),
          ],
        ),
      ),
      body: const TabBarView(
        children: [
          PokemonListPage(),
          CatalogPage(kind: 'move'),
          CatalogPage(kind: 'ability'),
        ],
      ),
    ),
  );
}

// ═══════════════════════════════════════════════════════════════
// LISTA DE POKÉMON (sem busca · rolagem infinita)
// ═══════════════════════════════════════════════════════════════
class PokemonListPage extends StatelessWidget {
  const PokemonListPage({super.key});

  @override
  Widget build(BuildContext context) => PagedGrid(
    endpoint: 'pokemon',
    limit: 20,
    header: const HeroPanel(
      kicker: 'POKÉDEX NACIONAL',
      title: 'Lista de Pokémon',
    ),
    gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
      maxCrossAxisExtent: 260,
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      mainAxisExtent: 250,
    ),
    loadItem: (r) async {
      await TypeIndex.ensure();
      final id = idFromUrl(r['url'] as String);
      return <String, dynamic>{
        'id': id,
        'name': r['name'],
        'types': TypeIndex.of(id),
      };
    },
    itemBuilder: (ctx, p) =>
        PokemonCard(data: p, onTap: () => openPokemon(ctx, p['id'] as int)),
  );
}

class PokemonCard extends StatelessWidget {
  const PokemonCard({super.key, required this.data, required this.onTap});
  final Map<String, dynamic> data;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final id = data['id'] as int;
    final types = (data['types'] as List).cast<String>();

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: kCream,
          border: Border.all(color: kBorder, width: 2),
          boxShadow: const [BoxShadow(color: kShadowRed, offset: Offset(4, 4))],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(height: 5, width: 42, color: kRed),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '#${pad3(id)}',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Colors.black45,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Expanded(child: SpriteFrame(child: PokeImage(id))),
                    const SizedBox(height: 8),
                    Text(
                      humanize(data['name'] as String),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      children: types.map((t) => Pill(humanize(t))).toList(),
                    ),
                    const SizedBox(height: 8),
                    Container(height: 1, color: kBorder),
                    const SizedBox(height: 6),
                    const Text(
                      'VER DETALHES →',
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.6,
                        color: kDarkRed,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// CATÁLOGO DE GOLPES / HABILIDADES (rolagem infinita)
// ═══════════════════════════════════════════════════════════════
class CatalogPage extends StatelessWidget {
  const CatalogPage({super.key, required this.kind});
  final String kind; // 'move' ou 'ability'
  bool get isMove => kind == 'move';

  @override
  Widget build(BuildContext context) => PagedGrid(
    endpoint: kind,
    limit: 30,
    header: HeroPanel(
      kicker: 'BIBLIOTECA DE DADOS / POKÉAPI',
      title: isMove ? 'Catálogo de golpes' : 'Catálogo de habilidades',
      subtitle: isMove
          ? 'Consulte poder, PP, precisão e quais Pokémon podem aprender cada golpe.'
          : 'Descubra efeitos em batalha, gerações e quais Pokémon possuem cada habilidade.',
    ),
    gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
      maxCrossAxisExtent: 420,
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      mainAxisExtent: 112,
    ),
    loadItem: (r) async =>
        (await Api.get(r['url'] as String)) as Map<String, dynamic>,
    itemBuilder: (ctx, item) => ResourceCard(
      data: item,
      isMove: isMove,
      onTap: () => openResource(ctx, kind, item['name'] as String),
    ),
  );
}

class ResourceCard extends StatelessWidget {
  const ResourceCard({
    super.key,
    required this.data,
    required this.isMove,
    required this.onTap,
  });
  final Map<String, dynamic> data;
  final bool isMove;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final id = data['id'] as int;
    final type = data['type'] as Map<String, dynamic>?;
    final cls = data['damage_class'] as Map<String, dynamic>?;
    final gen =
        (data['generation'] as Map<String, dynamic>?)?['name'] as String?;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: kCream,
          border: Border.all(color: kBorder, width: 2),
          boxShadow: const [BoxShadow(color: kShadowRed, offset: Offset(3, 3))],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('#${pad3(id)}', style: mono(size: 11)),
                const Text(
                  '→',
                  style: TextStyle(fontSize: 16, color: kDarkRed),
                ),
              ],
            ),
            Text(
              humanize(data['name'] as String),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
            ),
            if (isMove)
              Wrap(
                spacing: 6,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (type != null) Pill(humanize(type['name'] as String)),
                  if (cls != null)
                    Pill(
                      humanize(cls['name'] as String),
                      bg: kCream,
                      border: kBorder,
                      fg: kDark,
                    ),
                  if (data['power'] != null)
                    Text(
                      'PWR ${data['power']}',
                      style: mono(size: 10, color: kDark),
                    ),
                ],
              )
            else
              Text(
                'GERAÇÃO ${(gen ?? '?').replaceFirst('generation-', '').toUpperCase()}',
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.2,
                  color: kLabel,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// DETALHES DO POKÉMON
// ═══════════════════════════════════════════════════════════════
const kStatLabels = <String, String>{
  'hp': 'HP',
  'attack': 'Attack',
  'defense': 'Defense',
  'special-attack': 'Sp. Atk',
  'special-defense': 'Sp. Def',
  'speed': 'Speed',
};

class PokemonDetailPage extends StatefulWidget {
  const PokemonDetailPage({super.key, required this.id});
  final int id;

  @override
  State<PokemonDetailPage> createState() => _PokemonDetailPageState();
}

class _PokemonDetailPageState extends State<PokemonDetailPage> {
  Map<String, dynamic>? _d;
  Map<String, dynamic>? _species;
  Map<String, dynamic>? _chain;
  Map<String, List<String>> _weak = const {
    'weak': [],
    'resist': [],
    'immune': [],
  };
  Object? _error;
  bool _shiny = false;
  int _tab = 0;
  Future<List<Map<String, dynamic>>>? _movesF;
  Future<List<Map<String, dynamic>>>? _abilitiesF;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final d = await Api.get('pokemon/${widget.id}') as Map<String, dynamic>;
      // A espécie vem da URL do próprio Pokémon (formas têm id diferente da espécie).
      final speciesF = Api.get(d['species']['url'] as String);
      final typesF = Future.wait(
        (d['types'] as List).map((t) => Api.get(t['type']['url'] as String)),
      );
      final both = await Future.wait<dynamic>(<Future<dynamic>>[
        speciesF,
        typesF,
      ]);
      final species = both[0] as Map<String, dynamic>;
      final typeData = (both[1] as List).cast<Map<String, dynamic>>();

      final evoUrl =
          (species['evolution_chain'] as Map<String, dynamic>?)?['url']
              as String?;
      final chain = evoUrl == null
          ? null
          : await Api.get(evoUrl) as Map<String, dynamic>;

      if (!mounted) return;
      setState(() {
        _d = d;
        _species = species;
        _chain = chain;
        _weak = _computeWeaknesses(typeData);
      });
    } catch (e) {
      debugPrint('Erro ao carregar Pokémon ${widget.id}: $e');
      if (mounted) setState(() => _error = e);
    }
  }

  void _retry() {
    setState(() => _error = null);
    _load();
  }

  Map<String, List<String>> _computeWeaknesses(
    List<Map<String, dynamic>> typeData,
  ) {
    final mult = <String, double>{};
    for (final t in typeData) {
      final r = t['damage_relations'] as Map<String, dynamic>;
      void apply(String key, double f) {
        for (final x in (r[key] as List)) {
          final n = x['name'] as String;
          mult[n] = f == 0 ? 0.0 : (mult[n] ?? 1.0) * f;
        }
      }

      apply('double_damage_from', 2);
      apply('half_damage_from', 0.5);
      apply('no_damage_from', 0);
    }
    final entries = mult.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    String label(String t, double v) {
      final base = humanize(t);
      if (v == 4) return '$base ×4';
      if (v == 0.25) return '$base ×¼';
      return base;
    }

    final weak = <String>[], resist = <String>[], immune = <String>[];
    for (final e in entries) {
      if (e.value > 1) {
        weak.add(label(e.key, e.value));
      } else if (e.value == 0) {
        immune.add(label(e.key, e.value));
      } else if (e.value < 1) {
        resist.add(label(e.key, e.value));
      }
    }
    return {'weak': weak, 'resist': resist, 'immune': immune};
  }

  Future<List<Map<String, dynamic>>> _loadMoves() async {
    final moves = (_d!['moves'] as List).take(20).toList();
    final res = await Future.wait(
      moves.map((m) => Api.get(m['move']['url'] as String)),
    );
    return res.cast<Map<String, dynamic>>();
  }

  Future<List<Map<String, dynamic>>> _loadAbilities() async {
    final list = (_d!['abilities'] as List).cast<Map<String, dynamic>>();
    return Future.wait(
      list.map((a) async {
        final detail = await Api.get(
          a['ability']['url'] as String,
        ) as Map<String, dynamic>;
        return <String, dynamic>{
          'detail': detail,
          'hidden': a['is_hidden'] == true,
        };
      }),
    );
  }

  void _selectTab(int i) => setState(() {
    _tab = i;
    if (i == 1) _movesF ??= _loadMoves();
    if (i == 2) _abilitiesF ??= _loadAbilities();
  });

  AppBar _bar(String title) => AppBar(
    backgroundColor: kRed,
    foregroundColor: Colors.white,
    title: Text(title),
  );

  @override
  Widget build(BuildContext context) {
    if (_d == null) {
      return Scaffold(
        appBar: _bar(''),
        body: Center(
          child: _error == null
              ? const CircularProgressIndicator(color: kRed)
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Não foi possível carregar este Pokémon.'),
                    TextButton(
                      onPressed: _retry,
                      child: const Text(
                        'TENTAR DE NOVO',
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          color: kDarkRed,
                        ),
                      ),
                    ),
                  ],
                ),
        ),
      );
    }

    final d = _d!;
    final sp = _species!;
    final id = d['id'] as int;
    final name = humanize(d['name'] as String);
    final types = (d['types'] as List)
        .map((t) => t['type']['name'] as String)
        .toList();
    final gen =
        ((sp['generation'] as Map<String, dynamic>?)?['name'] as String? ?? '')
            .replaceFirst('generation-', '')
            .toUpperCase();

    String? genus;
    for (final g in (sp['genera'] as List)) {
      if (g['language']['name'] == 'en') {
        genus = g['genus'] as String;
        break;
      }
    }
    final description = latestFlavor(sp['flavor_text_entries'] as List?);
    final genderRate = sp['gender_rate'] as int;
    final gender = genderRate == -1
        ? 'Sem gênero'
        : '${fmtNum(100 - genderRate * 12.5)}% ♂ · ${fmtNum(genderRate * 12.5)}% ♀';

    return Scaffold(
      appBar: _bar(name),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Container(
              decoration: BoxDecoration(
                color: kCream,
                border: Border.all(color: kDark, width: 2),
                boxShadow: const [
                  BoxShadow(color: kDarkRed, offset: Offset(6, 6)),
                ],
              ),
              child: Column(
                children: [
                  // ── Arte oficial ──
                  Container(
                    color: kRed,
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'ARTE OFICIAL',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 2,
                              ),
                            ),
                            GestureDetector(
                              onTap: () => setState(() => _shiny = !_shiny),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: _shiny ? kYellow : kCream,
                                  border: Border.all(color: kDark, width: 2),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  _shiny ? 'SHINY' : 'NORMAL',
                                  style: const TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        SpriteFrame(
                          height: 280,
                          border: 4,
                          child: PokeImage(id, shiny: _shiny, cacheWidth: 640),
                        ),
                        const SizedBox(height: 12),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: kDarkRed,
                              border: Border.all(color: kDark, width: 2),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              'GEN $gen',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // ── Informações ──
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('NO. ${pad3(id)}', style: mono(size: 12)),
                        const SizedBox(height: 4),
                        Text(
                          name,
                          style: const TextStyle(
                            fontSize: 32,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -1,
                          ),
                        ),
                        if (genus != null)
                          Text(
                            genus,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: kMuted,
                            ),
                          ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: types
                              .map(
                                (t) => Pill(
                                  humanize(t),
                                  big: true,
                                  onTap: () => Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => TypePage(typeName: t),
                                    ),
                                  ),
                                ),
                              )
                              .toList(),
                        ),
                        if (description != null) ...[
                          const SizedBox(height: 16),
                          Text(
                            description,
                            style: const TextStyle(
                              fontSize: 14,
                              height: 1.6,
                              color: kMuted,
                            ),
                          ),
                        ],
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: InfoBox(
                                label: 'ALTURA',
                                value: '${fmtNum((d['height'] as int) / 10)} m',
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: InfoBox(
                                label: 'PESO',
                                value:
                                    '${fmtNum((d['weight'] as int) / 10)} kg',
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: InfoBox(label: 'GÊNERO', value: gender),
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),

                        // ── Stats ──
                        const SectionTitle('ESTATÍSTICAS BASE'),
                        const SizedBox(height: 12),
                        ...(d['stats'] as List).map((s) {
                          final key = s['stat']['name'] as String;
                          final val = s['base_stat'] as int;
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Row(
                              children: [
                                SizedBox(
                                  width: 64,
                                  child: Text(
                                    (kStatLabels[key] ?? humanize(key))
                                        .toUpperCase(),
                                    style: const TextStyle(
                                      fontSize: 9,
                                      fontWeight: FontWeight.w800,
                                      color: kLabel,
                                    ),
                                  ),
                                ),
                                Expanded(
                                  child: Container(
                                    height: 8,
                                    color: kBarBg,
                                    alignment: Alignment.centerLeft,
                                    child: FractionallySizedBox(
                                      widthFactor: (val / 150)
                                          .clamp(0.0, 1.0)
                                          .toDouble(),
                                      child: Container(color: kRed),
                                    ),
                                  ),
                                ),
                                SizedBox(
                                  width: 34,
                                  child: Text(
                                    '$val',
                                    textAlign: TextAlign.right,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        }),

                        // ── Evolução ──
                        if (_chain != null) ...[
                          const SizedBox(height: 24),
                          Container(height: 2, color: kDark),
                          const SizedBox(height: 20),
                          const SectionTitle('CADEIA DE EVOLUÇÃO'),
                          const SizedBox(height: 16),
                          Center(
                            child: EvolutionTree(
                              node: _chain!['chain'] as Map<String, dynamic>,
                              currentId: sp['id'] as int,
                            ),
                          ),
                        ],

                        // ── Extras ──
                        const SizedBox(height: 28),
                        Container(height: 2, color: kDark),
                        const SizedBox(height: 20),
                        const SectionTitle(
                          'INFORMAÇÕES ADICIONAIS',
                          color: Color(0xFF9D1830),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Extras',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 16),
                        _extrasNav(),
                        const SizedBox(height: 20),
                        if (_tab == 0) _weaknessTab(),
                        if (_tab == 1) _movesTab(),
                        if (_tab == 2) _abilitiesTab(),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── Abas de extras ──
  Widget _extrasNav() {
    const labels = ['Fraquezas', 'Golpes', 'Habilidades'];
    return Container(
      decoration: BoxDecoration(border: Border.all(color: kDark, width: 2)),
      child: Row(
        children: List.generate(
          3,
          (i) => Expanded(
            child: GestureDetector(
              onTap: () => _selectTab(i),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: _tab == i ? kDarkRed : null,
                  border: i < 2
                      ? const Border(right: BorderSide(color: kDark))
                      : null,
                ),
                child: Text(
                  labels[i].toUpperCase(),
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    color: _tab == i ? Colors.white : kDark,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _weaknessTab() {
    Widget group(String title, List<String> items) => Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 10),
          if (items.isEmpty)
            const Text('Nenhuma', style: TextStyle(fontSize: 12, color: kMuted))
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: items.map((t) => Pill(t, big: true)).toList(),
            ),
        ],
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        group('FRAQUEZAS · 2×', _weak['weak']!),
        group('RESISTÊNCIAS · ½×', _weak['resist']!),
        group('IMUNIDADES · 0×', _weak['immune']!),
      ],
    );
  }

  Widget _loadingBox() => const Padding(
    padding: EdgeInsets.all(24),
    child: Center(child: CircularProgressIndicator(color: kRed)),
  );

  Widget _movesTab() => FutureBuilder<List<Map<String, dynamic>>>(
    future: _movesF,
    builder: (ctx, snap) {
      if (snap.hasError)
        return const Text('Não foi possível carregar os golpes.');
      if (!snap.hasData) return _loadingBox();
      const head = TextStyle(
        color: Colors.white,
        fontSize: 9,
        fontWeight: FontWeight.w900,
        letterSpacing: 1,
      );
      return Container(
        decoration: BoxDecoration(border: Border.all(color: kDark, width: 2)),
        child: Column(
          children: [
            Container(
              color: kDark,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: const Row(
                children: [
                  Expanded(child: Text('GOLPE', style: head)),
                  SizedBox(width: 52, child: Text('PODER', style: head)),
                  SizedBox(width: 36, child: Text('PP', style: head)),
                  SizedBox(width: 56, child: Text('PREC.', style: head)),
                ],
              ),
            ),
            ...snap.data!.map((m) {
              final type =
                  (m['type'] as Map<String, dynamic>?)?['name'] as String?;
              String v(Object? x, [String suffix = '']) =>
                  x == null ? '—' : '$x$suffix';
              return GestureDetector(
                onTap: () => openResource(context, 'move', m['name'] as String),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                  decoration: const BoxDecoration(
                    border: Border(bottom: BorderSide(color: kBorder)),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              humanize(m['name'] as String),
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            if (type != null)
                              Text(
                                humanize(type),
                                style: const TextStyle(
                                  fontSize: 9,
                                  color: kLabel,
                                ),
                              ),
                          ],
                        ),
                      ),
                      SizedBox(
                        width: 52,
                        child: Text(
                          v(m['power']),
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                      SizedBox(
                        width: 36,
                        child: Text(
                          v(m['pp']),
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                      SizedBox(
                        width: 56,
                        child: Text(
                          v(m['accuracy'], '%'),
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ],
        ),
      );
    },
  );

  Widget _abilitiesTab() => FutureBuilder<List<Map<String, dynamic>>>(
    future: _abilitiesF,
    builder: (ctx, snap) {
      if (snap.hasError)
        return const Text('Não foi possível carregar as habilidades.');
      if (!snap.hasData) return _loadingBox();
      return Column(
        children: snap.data!.map((a) {
          final detail = a['detail'] as Map<String, dynamic>;
          final hidden = a['hidden'] as bool;
          return GestureDetector(
            onTap: () =>
                openResource(context, 'ability', detail['name'] as String),
            child: Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                border: Border.all(color: kDark, width: 2),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Flexible(
                        child: Text(
                          humanize(detail['name'] as String),
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      if (hidden)
                        const Pill(
                          'Oculta',
                          bg: kYellow,
                          border: kDark,
                          fg: kDark,
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    effectText(detail, short: true),
                    style: const TextStyle(
                      fontSize: 13,
                      height: 1.5,
                      color: kMuted,
                    ),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      );
    },
  );
}

// ═══════════════════════════════════════════════════════════════
// ÁRVORE DE EVOLUÇÃO (com imagens e condição de cada evolução)
// ═══════════════════════════════════════════════════════════════
const _kTimes = <String, String>{
  'day': 'Dia',
  'night': 'Noite',
  'dusk': 'Entardecer',
  'full-moon': 'Lua cheia',
};

String _oneCondition(Map<String, dynamic> d) {
  String nameOf(String k) =>
      humanize((d[k] as Map<String, dynamic>)['name'] as String);
  final parts = <String>[];
  if (d['min_level'] != null) parts.add('Nível ${d['min_level']}');
  if (d['item'] != null) parts.add(nameOf('item'));
  if (d['held_item'] != null) parts.add('Segurando ${nameOf('held_item')}');
  if (d['min_happiness'] != null)
    parts.add('Felicidade ≥ ${d['min_happiness']}');
  if (d['min_affection'] != null) parts.add('Afeto ≥ ${d['min_affection']}');
  if (d['known_move'] != null) parts.add('Golpe ${nameOf('known_move')}');
  if (d['known_move_type'] != null)
    parts.add('Golpe tipo ${nameOf('known_move_type')}');
  if (d['location'] != null) parts.add('Em ${nameOf('location')}');
  final tod = d['time_of_day'] as String? ?? '';
  if (tod.isNotEmpty) parts.add(_kTimes[tod] ?? tod);
  final trigger = (d['trigger'] as Map<String, dynamic>?)?['name'] as String?;
  if (trigger == 'trade') parts.add('Troca');
  if (parts.isEmpty) return trigger == null ? '' : humanize(trigger);
  return parts.join(' · ');
}

/// Resume as condições de evolução (até 2 alternativas distintas).
String evoCondition(List details) {
  final set = <String>{};
  for (final e in details) {
    set.add(_oneCondition(e as Map<String, dynamic>));
  }
  set.remove('');
  return set.take(2).join('  /  ');
}

class EvolutionTree extends StatelessWidget {
  const EvolutionTree({
    super.key,
    required this.node,
    required this.currentId,
    this.condition,
  });
  final Map<String, dynamic> node;
  final int currentId;
  final String? condition;

  @override
  Widget build(BuildContext context) {
    final species = node['species'] as Map<String, dynamic>;
    // O id da espécie vem da URL da própria espécie: a imagem sempre bate com o nome.
    final id = idFromUrl(species['url'] as String);
    final children = (node['evolves_to'] as List).cast<Map<String, dynamic>>();

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (condition != null) _EvoArrow(condition!),
        _EvoCard(
          id: id,
          name: species['name'] as String,
          current: id == currentId,
          onTap: () {
            if (id != currentId) {
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (_) => PokemonDetailPage(id: id)),
              );
            }
          },
        ),
        if (children.isNotEmpty)
          Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.start,
            spacing: 12,
            runSpacing: 4,
            children: children
                .map(
                  (c) => EvolutionTree(
                    node: c,
                    currentId: currentId,
                    condition: evoCondition(c['evolution_details'] as List),
                  ),
                )
                .toList(),
          ),
      ],
    );
  }
}

class _EvoArrow extends StatelessWidget {
  const _EvoArrow(this.label);
  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 140),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            '↓',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w900,
              color: kDarkRed,
            ),
          ),
          if (label.isNotEmpty)
            Text(
              label.toUpperCase(),
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w900,
                color: kDarkRed,
                height: 1.3,
              ),
            ),
        ],
      ),
    ),
  );
}

class _EvoCard extends StatelessWidget {
  const _EvoCard({
    required this.id,
    required this.name,
    required this.current,
    required this.onTap,
  });
  final int id;
  final String name;
  final bool current;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: 112,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: current ? kPink : kCream,
        border: Border.all(color: current ? kDarkRed : kBorder, width: 2),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SpriteFrame(height: 92, child: PokeImage(id, cacheWidth: 240)),
          const SizedBox(height: 6),
          Text(
            humanize(name),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900),
          ),
          Text('#${pad3(id)}', style: mono(size: 9, color: kLabel)),
        ],
      ),
    ),
  );
}

// ═══════════════════════════════════════════════════════════════
// DETALHES DE GOLPE / HABILIDADE
// ═══════════════════════════════════════════════════════════════
class MiniPokemon extends StatelessWidget {
  const MiniPokemon({
    super.key,
    required this.id,
    required this.name,
    required this.onTap,
  });
  final int id;
  final String name;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: kCream,
        border: Border.all(color: kBorder, width: 2),
      ),
      child: Column(
        children: [
          Expanded(child: SpriteFrame(child: PokeImage(id, cacheWidth: 200))),
          const SizedBox(height: 4),
          Text(
            humanize(name),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w900),
          ),
        ],
      ),
    ),
  );
}

class ResourceDetailPage extends StatefulWidget {
  const ResourceDetailPage({super.key, required this.kind, required this.name});
  final String kind; // 'move' ou 'ability'
  final String name;

  @override
  State<ResourceDetailPage> createState() => _ResourceDetailPageState();
}

class _ResourceDetailPageState extends State<ResourceDetailPage> {
  late final Future<dynamic> _f = Api.get('${widget.kind}/${widget.name}');
  bool get isMove => widget.kind == 'move';

  String _nm(Object? x) =>
      x == null ? '—' : humanize((x as Map)['name'] as String);

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      backgroundColor: kRed,
      foregroundColor: Colors.white,
      title: Text(humanize(widget.name)),
    ),
    body: FutureBuilder<dynamic>(
      future: _f,
      builder: (ctx, snap) {
        if (snap.hasError) {
          return const Center(child: Text('Não foi possível carregar.'));
        }
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator(color: kRed));
        }
        return _content(snap.data as Map<String, dynamic>);
      },
    ),
  );

  Widget _content(Map<String, dynamic> d) {
    final id = d['id'] as int;
    final flavor = latestFlavor(d['flavor_text_entries'] as List?);
    final gen =
        ((d['generation'] as Map<String, dynamic>?)?['name'] as String? ?? '?')
            .replaceFirst('generation-', '')
            .toUpperCase();

    final related = <Map<String, dynamic>>[];
    final src = isMove
        ? (d['learned_by_pokemon'] as List? ?? [])
        : (d['pokemon'] as List? ?? []);
    for (final e in src) {
      final p = (isMove ? e : e['pokemon']) as Map<String, dynamic>;
      final pid = idFromUrl(p['url'] as String);
      if (pid < 10000) related.add({'id': pid, 'name': p['name']});
      if (related.length >= 60) break;
    }

    final info = isMove
        ? <List<String>>[
            ['TIPO', _nm(d['type'])],
            ['CATEGORIA', _nm(d['damage_class'])],
            ['PODER', '${d['power'] ?? '—'}'],
            ['PP', '${d['pp'] ?? '—'}'],
            ['PRECISÃO', d['accuracy'] == null ? '—' : '${d['accuracy']}%'],
          ]
        : <List<String>>[
            ['GERAÇÃO', gen],
            ['SÉRIE PRINCIPAL', d['is_main_series'] == true ? 'Sim' : 'Não'],
          ];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: kCream,
              border: Border.all(color: kDark, width: 2),
              boxShadow: const [
                BoxShadow(color: kDarkRed, offset: Offset(6, 6)),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('#${pad3(id)}', style: mono(size: 12)),
                const SizedBox(height: 4),
                SectionTitle(
                  isMove ? 'REGISTRO DE GOLPE' : 'REGISTRO DE HABILIDADE',
                  color: kDarkRed,
                ),
                const SizedBox(height: 8),
                Text(
                  humanize(d['name'] as String),
                  style: const TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -1,
                  ),
                ),
                if (flavor != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    flavor,
                    style: const TextStyle(
                      fontSize: 14,
                      height: 1.5,
                      color: kMuted,
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: info
                      .map(
                        (e) => ConstrainedBox(
                          constraints: const BoxConstraints(minWidth: 96),
                          child: InfoBox(label: e[0], value: e[1]),
                        ),
                      )
                      .toList(),
                ),
                const SizedBox(height: 20),
                const SectionTitle('EFEITO EM BATALHA', color: kDarkRed),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: const BoxDecoration(
                    border: Border(left: BorderSide(color: kRed, width: 4)),
                  ),
                  child: Text(
                    effectText(d),
                    style: const TextStyle(
                      fontSize: 14,
                      height: 1.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (related.isNotEmpty) ...[
                  const SizedBox(height: 24),
                  SectionTitle(
                    isMove
                        ? 'POKÉMON QUE APRENDEM'
                        : 'POKÉMON COM ESTA HABILIDADE',
                    color: kDarkRed,
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: related
                        .map(
                          (p) => SizedBox(
                            width: 100,
                            height: 112,
                            child: MiniPokemon(
                              id: p['id'] as int,
                              name: p['name'] as String,
                              onTap: () => openPokemon(context, p['id'] as int),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// PÁGINA DE TIPO — Pokémon daquele tipo (sem chamadas extras)
// ═══════════════════════════════════════════════════════════════
class TypePage extends StatefulWidget {
  const TypePage({super.key, required this.typeName});
  final String typeName;

  @override
  State<TypePage> createState() => _TypePageState();
}

class _TypePageState extends State<TypePage> {
  late final Future<dynamic> _f = Api.get('type/${widget.typeName}');

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      backgroundColor: kRed,
      foregroundColor: Colors.white,
      title: Text('Tipo: ${humanize(widget.typeName)}'),
    ),
    body: FutureBuilder<dynamic>(
      future: _f,
      builder: (ctx, snap) {
        if (snap.hasError) {
          return const Center(child: Text('Não foi possível carregar.'));
        }
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator(color: kRed));
        }
        final data = snap.data as Map<String, dynamic>;
        final items = <Map<String, dynamic>>[];
        for (final e in (data['pokemon'] as List)) {
          final p = e['pokemon'] as Map<String, dynamic>;
          final id = idFromUrl(p['url'] as String);
          if (id < 10000) items.add({'id': id, 'name': p['name']});
        }
        items.sort((a, b) => (a['id'] as int).compareTo(b['id'] as int));
        return GridView.builder(
          padding: const EdgeInsets.all(16),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 150,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            mainAxisExtent: 140,
          ),
          itemCount: items.length,
          itemBuilder: (_, i) => MiniPokemon(
            id: items[i]['id'] as int,
            name: items[i]['name'] as String,
            onTap: () => openPokemon(context, items[i]['id'] as int),
          ),
        );
      },
    ),
  );
}
