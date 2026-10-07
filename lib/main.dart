import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;

// ─────────────────────────── Cores ───────────────────────────
const kRed = Color(0xFFB5162D);
const kDarkRed = Color(0xFF8F1025);
const kBg = Color(0xFFF6E9E7);
const kCream = Color(0xFFFFF8EF);
const kDark = Color(0xFF2B1014);
const kBorder = Color(0xFFCDA9A4);
const kPink = Color(0xFFF8D9D5);
const kTeal = Color(0xFFE4F2ED);
const kYellow = Color(0xFFE4C93D);

const kBase = 'https://pokeapi.co/api/v2';

// ─────────────────────────── Cache SQLite ───────────────────────────
class ApiCache {
  static Database? _db;
  static final _client = http.Client();

  static Future<void> init() async {
    if (_db != null) return;
    final path = p.join(await getDatabasesPath(), 'pokedex.db');
    _db = await openDatabase(
      path,
      version: 1,
      onCreate: (db, _) => db.execute(
        'CREATE TABLE cache (url TEXT PRIMARY KEY, body TEXT NOT NULL)',
      ),
    );
  }

  static Future<dynamic> get(String path) async {
    final url = path.startsWith('http') ? path : '$kBase/$path';
    final db = _db!;

    final rows = await db.query(
      'cache',
      columns: ['body'],
      where: 'url = ?',
      whereArgs: [url],
      limit: 1,
    );
    if (rows.isNotEmpty) return jsonDecode(rows.first['body'] as String);

    final res = await _client.get(Uri.parse(url));
    if (res.statusCode != 200) throw Exception('Erro $url (${res.statusCode})');
    await db.insert('cache', {
      'url': url,
      'body': res.body,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    return jsonDecode(res.body);
  }

  static Future<void> clear() async => _db?.delete('cache');
}

// ─────────────────────────── Helpers ───────────────────────────
String pad3(int n) => n.toString().padLeft(3, '0');
String cap(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

// ─────────────────────────── Modelos ───────────────────────────
class Pokemon {
  final int id;
  final String name;
  final String sprite;
  final String shinySprite;
  final List<String> types;
  final List<String> abilities;
  final List<MapEntry<String, bool>> rawAbilities; // nome + is_hidden
  final int height;
  final int weight;
  final List<MapEntry<String, int>> stats;

  Pokemon({
    required this.id,
    required this.name,
    required this.sprite,
    required this.shinySprite,
    required this.types,
    required this.abilities,
    required this.rawAbilities,
    required this.height,
    required this.weight,
    required this.stats,
  });

  factory Pokemon.fromJson(Map<String, dynamic> json) {
    final id = json['id'] as int;
    final art =
        json['sprites']?['other']?['official-artwork']?['front_default']
            as String? ??
        'https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites/pokemon/other/official-artwork/$id.png';
    final shiny =
        json['sprites']?['other']?['official-artwork']?['front_shiny']
            as String? ??
        art;
    final types = (json['types'] as List)
        .map((t) => t['type']['name'] as String)
        .toList();
    final rawAbilities = (json['abilities'] as List)
        .map(
          (a) =>
              MapEntry(a['ability']['name'] as String, a['is_hidden'] == true),
        )
        .toList();
    final abilities = rawAbilities
        .map((a) => '${cap(a.key)}${a.value ? " (oculta)" : ""}')
        .toList();
    final stats = (json['stats'] as List)
        .map(
          (s) => MapEntry(s['stat']['name'] as String, s['base_stat'] as int),
        )
        .toList();
    return Pokemon(
      id: id,
      name: json['name'] as String,
      sprite: art,
      shinySprite: shiny,
      types: types,
      abilities: abilities,
      rawAbilities: rawAbilities,
      height: json['height'] as int,
      weight: json['weight'] as int,
      stats: stats,
    );
  }
}

// ─────────────────────────── App ───────────────────────────
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await ApiCache.init();
  runApp(const PokedexApp());
}

class PokedexApp extends StatelessWidget {
  const PokedexApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Pokédex',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        fontFamily: 'Manrope',
        scaffoldBackgroundColor: kBg,
        colorScheme: ColorScheme.fromSeed(seedColor: kRed),
        useMaterial3: true,
      ),
      home: const HomeShell(),
    );
  }
}

// ─────────────────────────── Shell com 3 abas ───────────────────────────
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
        bottom: TabBar(
          controller: _tab,
          indicatorColor: Colors.white,
          indicatorWeight: 3,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          labelStyle: const TextStyle(
            fontWeight: FontWeight.w900,
            fontSize: 12,
          ),
          tabs: const [
            Tab(text: 'POKÉMON'),
            Tab(text: 'GOLPES'),
            Tab(text: 'HABILIDADES'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tab,
        children: const [
          PokemonListPage(),
          ResourceCatalogPage(kind: 'move'),
          ResourceCatalogPage(kind: 'ability'),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// SEÇÃO 1 — LISTA DE POKÉMON
// ═══════════════════════════════════════════════════════════════
class PokemonListPage extends StatefulWidget {
  const PokemonListPage({super.key});
  @override
  State<PokemonListPage> createState() => _PokemonListPageState();
}

class _PokemonListPageState extends State<PokemonListPage>
    with AutomaticKeepAliveClientMixin {
  final _scroll = ScrollController();
  final _searchCtrl = TextEditingController();

  final List<Pokemon> _all = [];
  List<Pokemon> _filtered = [];
  String _query = '';

  bool _loading = false;
  bool _hasMore = true;
  int _offset = 0;
  static const _limit = 20;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _loadMore();
    _scroll.addListener(() {
      if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 300)
        _loadMore();
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadMore() async {
    if (_loading || !_hasMore) return;
    setState(() => _loading = true);

    try {
      final list = await ApiCache.get(
        'pokemon?limit=$_limit&offset=$_offset',
      ) as Map<String, dynamic>;
      final results = list['results'] as List;

      final futures = results.map((r) async {
        final detail =
            await ApiCache.get(r['url'] as String) as Map<String, dynamic>;
        return Pokemon.fromJson(detail);
      });
      final batch = await Future.wait(futures);

      if (!mounted) return;
      setState(() {
        _all.addAll(batch);
        _offset += _limit;
        _hasMore = results.length == _limit;
        _applyFilter();
        _loading = false;
      });
    } catch (e) {
      debugPrint('Erro no loadMore de Pokémon: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  void _applyFilter() {
    final q = _query.trim().toLowerCase();
    _filtered = q.isEmpty
        ? List.from(_all)
        : _all
              .where((p) => p.name.contains(q) || pad3(p.id).contains(q))
              .toList();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Column(
      children: [
        Container(
          margin: const EdgeInsets.all(16),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: kCream,
            border: Border.all(color: kDark, width: 2),
            boxShadow: const [BoxShadow(color: kDarkRed, offset: Offset(4, 4))],
          ),
          child: TextField(
            controller: _searchCtrl,
            onChanged: (v) {
              setState(() => _query = v);
              _applyFilter();
            },
            decoration: const InputDecoration(
              hintText: 'Buscar por nome ou número...',
              border: InputBorder.none,
              icon: Icon(Icons.search),
            ),
          ),
        ),
        Expanded(
          child: _filtered.isEmpty && _loading
              ? const Center(child: CircularProgressIndicator())
              : _filtered.isEmpty
              ? const Center(child: Text('Nenhum Pokémon encontrado'))
              : GridView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 280,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 0.72,
                  ),
                  itemCount: _filtered.length + (_loading ? 1 : 0),
                  itemBuilder: (ctx, i) {
                    if (i >= _filtered.length) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final p = _filtered[i];
                    return _PokemonCard(
                      pokemon: p,
                      onTap: () => Navigator.push(
                        ctx,
                        MaterialPageRoute(
                          builder: (_) => PokemonDetailPage(pokemon: p),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _PokemonCard extends StatelessWidget {
  final Pokemon pokemon;
  final VoidCallback onTap;
  const _PokemonCard({required this.pokemon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: kCream,
          border: Border.all(color: kBorder, width: 2),
          boxShadow: const [BoxShadow(color: kDarkRed, offset: Offset(4, 4))],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(height: 5, width: 42, color: kRed),
            Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '#${pad3(pokemon.id)}',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Expanded(
                    child: Center(
                      child: Image.network(
                        pokemon.sprite,
                        height: 100,
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) =>
                            const Icon(Icons.broken_image, size: 50),
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    cap(pokemon.name),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 4,
                    children: pokemon.types
                        .map(
                          (t) => Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: kPink,
                              border: Border.all(color: kDarkRed),
                            ),
                            child: Text(
                              cap(t),
                              style: const TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                                color: kDarkRed,
                              ),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────── Detalhes do Pokémon ───────────────────────────
class PokemonDetailPage extends StatefulWidget {
  final Pokemon pokemon;
  const PokemonDetailPage({super.key, required this.pokemon});
  @override
  State<PokemonDetailPage> createState() => _PokemonDetailPageState();
}

class _PokemonDetailPageState extends State<PokemonDetailPage> {
  bool _shiny = false;
  int _tab = 0;
  bool _loading = false;

  List<Map<String, dynamic>> _weaknessData = [];
  List<Map<String, dynamic>> _movesData = [];
  List<Map<String, dynamic>> _abilitiesData = [];

  Map<String, dynamic>? _species;

  Pokemon get p => widget.pokemon;

  @override
  void initState() {
    super.initState();
    _loadSpecies();
    _loadWeaknesses();
  }

  Future<void> _loadSpecies() async {
    try {
      final s =
          await ApiCache.get('pokemon-species/${p.id}') as Map<String, dynamic>;
      if (mounted) setState(() => _species = s);
    } catch (_) {}
  }

  Future<void> _loadWeaknesses() async {
    setState(() => _loading = true);
    try {
      final results = <Map<String, dynamic>>[];
      for (final t in p.types) {
        final data = await ApiCache.get('type/$t') as Map<String, dynamic>;
        results.add(data);
      }
      if (mounted) {
        setState(() {
          _weaknessData = results;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadMoves() async {
    if (_movesData.isNotEmpty) return;
    setState(() => _loading = true);
    try {
      final list =
          await ApiCache.get('pokemon/${p.id}') as Map<String, dynamic>;
      final moves = (list['moves'] as List).take(15).map((m) async {
        return await ApiCache.get(m['move']['url'] as String)
            as Map<String, dynamic>;
      });
      final data = await Future.wait(moves);
      if (mounted) {
        setState(() {
          _movesData = data;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadAbilities() async {
    if (_abilitiesData.isNotEmpty) return;
    setState(() => _loading = true);
    try {
      final data = await Future.wait(
        p.rawAbilities.map((a) async {
          return await ApiCache.get('ability/${a.key}') as Map<String, dynamic>;
        }),
      );
      if (mounted) {
        setState(() {
          _abilitiesData = data;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _changeTab(int i) {
    setState(() => _tab = i);
    if (i == 0) _loadWeaknesses();
    if (i == 1) _loadMoves();
    if (i == 2) _loadAbilities();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: kRed,
        foregroundColor: Colors.white,
        title: Text(cap(p.name)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Container(
          decoration: BoxDecoration(
            color: kCream,
            border: Border.all(color: kDark, width: 2),
            boxShadow: const [BoxShadow(color: kDarkRed, offset: Offset(6, 6))],
          ),
          child: Column(
            children: [
              // ── Imagem / arte ──
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
                    Container(
                      height: 260,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: kTeal,
                        border: Border.all(color: kDark, width: 4),
                      ),
                      child: Image.network(
                        _shiny ? p.shinySprite : p.sprite,
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) =>
                            const Icon(Icons.broken_image, size: 64),
                      ),
                    ),
                  ],
                ),
              ),

              // ── Info ──
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'NO. ${pad3(p.id)}',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: kDarkRed,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      cap(p.name),
                      style: const TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -1,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      children: p.types
                          .map(
                            (t) => Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: kPink,
                                border: Border.all(color: kDarkRed, width: 2),
                              ),
                              child: Text(
                                cap(t).toUpperCase(),
                                style: const TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w900,
                                  color: kDarkRed,
                                ),
                              ),
                            ),
                          )
                          .toList(),
                    ),
                    const SizedBox(height: 16),

                    Row(
                      children: [
                        _InfoBox(label: 'ALTURA', value: '${p.height / 10} m'),
                        const SizedBox(width: 8),
                        _InfoBox(label: 'PESO', value: '${p.weight / 10} kg'),
                        const SizedBox(width: 8),
                        _InfoBox(
                          label: 'GÊNERO',
                          value: _species == null
                              ? '—'
                              : (_species!['gender_rate'] as int) == -1
                              ? '—'
                              : '${((8 - (_species!['gender_rate'] as int)) / 8 * 100).round()}% ♂',
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    const Text(
                      'ESTATÍSTICAS BASE',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 2,
                      ),
                    ),
                    const SizedBox(height: 12),
                    ...p.stats.map(
                      (s) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 70,
                              child: Text(
                                s.key.toUpperCase(),
                                style: const TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.grey,
                                ),
                              ),
                            ),
                            Expanded(
                              child: LinearProgressIndicator(
                                value: s.value / 150,
                                backgroundColor: Colors.grey[300],
                                color: kRed,
                                minHeight: 8,
                              ),
                            ),
                            const SizedBox(width: 8),
                            SizedBox(
                              width: 30,
                              child: Text(
                                '${s.value}',
                                textAlign: TextAlign.right,
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 20),
                    const Divider(height: 1),
                    const SizedBox(height: 16),

                    const Text(
                      'INFORMAÇÕES ADICIONAIS',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 2,
                        color: kDarkRed,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Extras',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      decoration: BoxDecoration(
                        border: Border.all(color: kDark, width: 2),
                      ),
                      child: Row(
                        children: [
                          _TabBtn(
                            label: 'FRAQUEZAS',
                            selected: _tab == 0,
                            onTap: () => _changeTab(0),
                          ),
                          _TabBtn(
                            label: 'GOLPES',
                            selected: _tab == 1,
                            onTap: () => _changeTab(1),
                          ),
                          _TabBtn(
                            label: 'HABILIDADES',
                            selected: _tab == 2,
                            onTap: () => _changeTab(2),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (_loading)
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: CircularProgressIndicator(),
                        ),
                      ),
                    if (!_loading && _tab == 0) _buildWeaknesses(),
                    if (!_loading && _tab == 1) _buildMoves(),
                    if (!_loading && _tab == 2) _buildAbilities(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWeaknesses() {
    if (_weaknessData.isEmpty) return const Text('Sem dados.');
    final double_ = <String>{};
    final half = <String>{};
    final none = <String>{};
    for (final d in _weaknessData) {
      final rel = d['damage_relations'] as Map<String, dynamic>;
      for (final t in rel['double_damage_from'] as List) {
        double_.add(t['name'] as String);
      }
      for (final t in rel['half_damage_from'] as List) {
        half.add(t['name'] as String);
      }
      for (final t in rel['no_damage_from'] as List) {
        none.add(t['name'] as String);
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Section('Fraquezas · 2×', double_.toList()),
        _Section('Resistências · ½×', half.toList()),
        _Section('Imunidades · 0×', none.isEmpty ? ['Nenhuma'] : none.toList()),
      ],
    );
  }

  Widget _buildMoves() {
    if (_movesData.isEmpty) return const Text('Sem golpes.');
    return Column(
      children: _movesData.map((m) {
        final name = m['name'] as String;
        final power = m['power'];
        final pp = m['pp'];
        final acc = m['accuracy'];
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(border: Border.all(color: kDark, width: 2)),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      cap(name),
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                    Text(
                      'Poder: ${power ?? "—"} · PP: ${pp ?? "—"} · Prec: ${acc ?? "—"}%',
                      style: const TextStyle(fontSize: 10, color: Colors.grey),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildAbilities() {
    if (_abilitiesData.isEmpty) return const Text('Sem habilidades.');
    return Column(
      children: _abilitiesData.map((a) {
        final name = a['name'] as String;
        final effect =
            (a['effect_entries'] as List).firstWhere(
                  (e) => e['language']['name'] == 'en',
                  orElse: () => {'effect': 'Sem descrição.'},
                )['effect']
                as String;
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(border: Border.all(color: kDark, width: 2)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                cap(name),
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 6),
              Text(effect, style: const TextStyle(fontSize: 12, height: 1.5)),
            ],
          ),
        );
      }).toList(),
    );
  }
}

class _InfoBox extends StatelessWidget {
  final String label, value;
  const _InfoBox({required this.label, required this.value});
  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(border: Border.all(color: kDark, width: 2)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w900,
                color: Colors.grey,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900),
            ),
          ],
        ),
      ),
    );
  }
}

class _TabBtn extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _TabBtn({
    required this.label,
    required this.selected,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          color: selected ? kDarkRed : Colors.transparent,
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w900,
              color: selected ? Colors.white : kDark,
            ),
          ),
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final List<String> items;
  const _Section(this.title, this.items);
  @override
  Widget build(BuildContext context) {
    return Column(
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
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: items
              .map(
                (t) => Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: kPink,
                    border: Border.all(color: kDarkRed, width: 2),
                  ),
                  child: Text(
                    cap(t),
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: kDarkRed,
                    ),
                  ),
                ),
              )
              .toList(),
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// SEÇÃO 2 & 3 — CATÁLOGO DE GOLPES / HABILIDADES
// ═══════════════════════════════════════════════════════════════
class ResourceCatalogPage extends StatefulWidget {
  final String kind; // 'move' ou 'ability'
  const ResourceCatalogPage({super.key, required this.kind});
  @override
  State<ResourceCatalogPage> createState() => _ResourceCatalogPageState();
}

class _ResourceCatalogPageState extends State<ResourceCatalogPage>
    with AutomaticKeepAliveClientMixin {
  final _scroll = ScrollController();
  final _searchCtrl = TextEditingController();

  final List<Map<String, dynamic>> _all = [];
  List<Map<String, dynamic>> _filtered = [];
  String _query = '';

  bool _loading = false;
  bool _hasMore = true;
  int _offset = 0;
  static const _limit = 30;

  bool get isMove => widget.kind == 'move';

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _loadMore();
    _scroll.addListener(() {
      if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 300)
        _loadMore();
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadMore() async {
    if (_loading || !_hasMore) return;
    setState(() => _loading = true);

    try {
      final list = await ApiCache.get(
        '${widget.kind}?limit=$_limit&offset=$_offset',
      ) as Map<String, dynamic>;
      final results = list['results'] as List;

      final futures = results.map((r) async {
        return await ApiCache.get(r['url'] as String) as Map<String, dynamic>;
      });
      final batch = await Future.wait(futures);

      if (!mounted) return;
      setState(() {
        _all.addAll(batch);
        _offset += _limit;
        _hasMore = results.length == _limit;
        _applyFilter();
        _loading = false;
      });
    } catch (e) {
      debugPrint('Erro no loadMore de ${widget.kind}: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  void _applyFilter() {
    final q = _query.trim().toLowerCase();
    _filtered = q.isEmpty
        ? List.from(_all)
        : _all.where((i) => (i['name'] as String).contains(q)).toList();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Column(
      children: [
        Container(
          margin: const EdgeInsets.all(16),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: kCream,
            border: Border.all(color: kDark, width: 2),
            boxShadow: const [BoxShadow(color: kDarkRed, offset: Offset(4, 4))],
          ),
          child: TextField(
            controller: _searchCtrl,
            onChanged: (v) {
              setState(() => _query = v);
              _applyFilter();
            },
            decoration: InputDecoration(
              hintText: 'Buscar ${isMove ? "golpe" : "habilidade"}...',
              border: InputBorder.none,
              icon: const Icon(Icons.search),
            ),
          ),
        ),
        Expanded(
          child: _filtered.isEmpty && _loading
              ? const Center(child: CircularProgressIndicator())
              : _filtered.isEmpty
              ? Center(
                  child: Text(
                    'Nenhum ${isMove ? "golpe" : "habilidade"} encontrado',
                  ),
                )
              : ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: _filtered.length + (_loading ? 1 : 0),
                  itemBuilder: (ctx, i) {
                    if (i >= _filtered.length) {
                      return const Padding(
                        padding: EdgeInsets.all(16),
                        child: Center(child: CircularProgressIndicator()),
                      );
                    }
                    final item = _filtered[i];
                    return _ResourceCard(
                      data: item,
                      isMove: isMove,
                      onTap: () => Navigator.push(
                        ctx,
                        MaterialPageRoute(
                          builder: (_) =>
                              ResourceDetailPage(data: item, isMove: isMove),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _ResourceCard extends StatelessWidget {
  final Map<String, dynamic> data;
  final bool isMove;
  final VoidCallback onTap;
  const _ResourceCard({
    required this.data,
    required this.isMove,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final name = data['name'] as String;
    final id = data['id'] as int;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: kCream,
          border: Border.all(color: kBorder, width: 2),
          boxShadow: const [BoxShadow(color: kDarkRed, offset: Offset(3, 3))],
        ),
        child: Row(
          children: [
            Text(
              '#${pad3(id)}',
              style: const TextStyle(
                fontFamily: 'monospace',
                fontWeight: FontWeight.bold,
                color: kDarkRed,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    cap(name),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 4),
                  if (isMove)
                    Wrap(
                      spacing: 6,
                      children: [
                        _Chip(label: cap(data['type']['name'] as String)),
                        _Chip(
                          label: cap(data['damage_class']['name'] as String),
                        ),
                        if (data['power'] != null)
                          _Chip(label: 'PWR ${data['power']}'),
                      ],
                    )
                  else
                    Text(
                      'Geração ${data['generation']['name'] ?? "?"}',
                      style: const TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward, size: 18, color: kDarkRed),
          ],
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  const _Chip({required this.label});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: kPink,
        border: Border.all(color: kDarkRed),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.bold,
          color: kDarkRed,
        ),
      ),
    );
  }
}

// ─────────────────────────── Detalhes de Golpe / Habilidade ───────────────────────────
class ResourceDetailPage extends StatelessWidget {
  final Map<String, dynamic> data;
  final bool isMove;
  const ResourceDetailPage({
    super.key,
    required this.data,
    required this.isMove,
  });

  @override
  Widget build(BuildContext context) {
    final name = data['name'] as String;
    final id = data['id'] as int;
    final effect =
        (data['effect_entries'] as List).firstWhere(
              (e) => e['language']['name'] == 'en',
              orElse: () => {'effect': 'Sem descrição.'},
            )['effect']
            as String;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: kRed,
        foregroundColor: Colors.white,
        title: Text(cap(name)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Container(
          decoration: BoxDecoration(
            color: kCream,
            border: Border.all(color: kDark, width: 2),
            boxShadow: const [BoxShadow(color: kDarkRed, offset: Offset(6, 6))],
          ),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '#${pad3(id)}',
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.bold,
                  color: kDarkRed,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                isMove ? 'REGISTRO DE GOLPE' : 'REGISTRO DE HABILIDADE',
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2,
                  color: kDarkRed,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                cap(name),
                style: const TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -1,
                ),
              ),
              const SizedBox(height: 16),
              if (isMove) ...[
                Row(
                  children: [
                    _InfoBox(
                      label: 'TIPO',
                      value: cap(data['type']['name'] as String),
                    ),
                    const SizedBox(width: 8),
                    _InfoBox(
                      label: 'CLASSE',
                      value: cap(data['damage_class']['name'] as String),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _InfoBox(label: 'PODER', value: '${data['power'] ?? "—"}'),
                    const SizedBox(width: 8),
                    _InfoBox(label: 'PP', value: '${data['pp'] ?? "—"}'),
                    const SizedBox(width: 8),
                    _InfoBox(
                      label: 'PRECISÃO',
                      value: '${data['accuracy'] ?? "—"}%',
                    ),
                  ],
                ),
              ] else ...[
                Row(
                  children: [
                    _InfoBox(
                      label: 'GERAÇÃO',
                      value: cap(data['generation']['name'] as String),
                    ),
                    const SizedBox(width: 8),
                    _InfoBox(label: 'NOME', value: cap(data['name'] as String)),
                  ],
                ),
              ],
              const SizedBox(height: 20),
              const Text(
                'EFEITO EM BATALHA',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2,
                  color: kDarkRed,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: const BoxDecoration(
                  border: Border(left: BorderSide(color: kRed, width: 4)),
                ),
                child: Text(
                  effect,
                  style: const TextStyle(
                    fontSize: 14,
                    height: 1.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
