// =====================================================================
// FlashLearn - a flashcard study app (Flutter + Dart, Material 3)
// Single file, no external packages: paste into DartPad (Flutter mode).
// Data is kept in memory (MemoryStorage). To persist across reloads,
// swap MemoryStorage for a StorageService that uses shared_preferences.
// =====================================================================
import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// ======================= SECTION 1: MODELS ===========================

const List<Color> kColors = [
  Color(0xFF3F51B5),
  Color(0xFF00796B),
  Color(0xFFC62828),
  Color(0xFFEF6C00),
  Color(0xFF6A1B9A),
  Color(0xFF37474F),
];
const List<IconData> kIcons = [
  Icons.code,
  Icons.science,
  Icons.calculate,
  Icons.language,
  Icons.history_edu,
  Icons.public,
];

int _seq = 0;
String _id() => '${DateTime.now().microsecondsSinceEpoch}_${_seq++}';

/// One flashcard: a question (front) and an answer (back).
class Flashcard {
  Flashcard({
    required this.id,
    required this.front,
    required this.back,
    this.favorite = false,
    this.known = false,
  });
  final String id;
  String front;
  String back;
  bool favorite;
  bool known;

  Map<String, dynamic> toJson() =>
      {'id': id, 'front': front, 'back': back, 'fav': favorite, 'known': known};

  factory Flashcard.fromJson(Map<String, dynamic> j) => Flashcard(
        id: j['id'] as String,
        front: j['front'] as String,
        back: j['back'] as String,
        favorite: j['fav'] as bool? ?? false,
        known: j['known'] as bool? ?? false,
      );
}

/// A deck groups flashcards under one subject.
class Deck {
  Deck({
    required this.id,
    required this.name,
    this.color = 0,
    this.icon = 0,
    this.best = -1,
    List<Flashcard>? cards,
  }) : cards = cards ?? [];
  final String id;
  String name;
  int color;
  int icon;
  int best; // best quiz score in percent, -1 = no quiz taken yet
  final List<Flashcard> cards;

  Color get colorValue => kColors[color % kColors.length];
  IconData get iconValue => kIcons[icon % kIcons.length];
  double get mastery =>
      cards.isEmpty ? 0 : cards.where((c) => c.known).length / cards.length;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'color': color,
        'icon': icon,
        'best': best,
        'cards': cards.map((c) => c.toJson()).toList(),
      };

  factory Deck.fromJson(Map<String, dynamic> j) => Deck(
        id: j['id'] as String,
        name: j['name'] as String,
        color: j['color'] as int? ?? 0,
        icon: j['icon'] as int? ?? 0,
        best: j['best'] as int? ?? -1,
        cards: (j['cards'] as List)
            .map((e) => Flashcard.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
      );
}

// ======================= SECTION 2: STORAGE ==========================

abstract class StorageService {
  Future<String?> load();
  Future<void> save(String json);
}

/// In-memory storage (used in DartPad). Replace for real persistence.
class MemoryStorage implements StorageService {
  String? _data;
  @override
  Future<String?> load() async => _data;
  @override
  Future<void> save(String json) async => _data = json;
}

// ======================= SECTION 3: STORE ============================

List<Deck> _sample() {
  Deck d(String n, int c, int i, List<List<String>> q) => Deck(
        id: _id(),
        name: n,
        color: c,
        icon: i,
        cards: q.map((p) => Flashcard(id: _id(), front: p[0], back: p[1])).toList(),
      );
  return [
    d('Flutter Basics', 0, 0, [
      ['What is a Widget in Flutter?', 'The basic building block of a Flutter UI; everything on screen is a widget.'],
      ['Stateless vs Stateful widget?', 'Stateless never changes; Stateful holds mutable state and rebuilds via setState().'],
      ['What does setState() do?', 'Marks the widget dirty so build() runs again with the new state.'],
      ['Which language does Flutter use?', 'Dart'],
      ['What is hot reload?', 'Injects updated code into the running app without losing its state.'],
      ['What is pubspec.yaml for?', "Declares the project's dependencies, assets and metadata."],
    ]),
    d('Data Structures', 1, 1, [
      ['Stack ordering?', 'LIFO (last in, first out)'],
      ['Queue ordering?', 'FIFO (first in, first out)'],
      ['Time complexity of binary search?', 'O(log n)'],
      ['Average lookup in a hash table?', 'O(1)'],
      ['In-order traversal of a BST gives?', 'Elements in sorted order'],
      ['Which structure has O(1) insert at the head?', 'Linked list'],
    ]),
    d('World Capitals', 3, 5, [
      ['Capital of Japan?', 'Tokyo'],
      ['Capital of Australia?', 'Canberra'],
      ['Capital of Canada?', 'Ottawa'],
      ['Capital of Brazil?', 'Brasilia'],
      ['Capital of Egypt?', 'Cairo'],
      ['Capital of India?', 'New Delhi'],
    ]),
  ];
}

/// Holds all app data and business logic. UI listens to it (ChangeNotifier).
class FlashStore extends ChangeNotifier {
  FlashStore(this.storage);
  final StorageService storage;
  List<Deck> decks = [];
  ThemeMode themeMode = ThemeMode.system;
  final Set<String> studyDays = {};

  Future<void> init() async {
    final raw = await storage.load();
    if (raw == null) {
      decks = _sample();
      return;
    }
    try {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      decks = (m['decks'] as List)
          .map((e) => Deck.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
      themeMode = ThemeMode.values[(m['theme'] as int?) ?? 0];
      studyDays
        ..clear()
        ..addAll(((m['days'] as List?) ?? []).cast<String>());
    } catch (_) {
      decks = _sample();
    }
  }

  void _commit() {
    notifyListeners();
    storage.save(jsonEncode({
      'decks': decks.map((d) => d.toJson()).toList(),
      'theme': themeMode.index,
      'days': studyDays.toList(),
    }));
  }

  // ---- decks ----
  bool nameTaken(String n, {String? exceptId}) => decks.any(
      (d) => d.id != exceptId && d.name.trim().toLowerCase() == n.trim().toLowerCase());
  void addDeck(String name, int color, int icon) {
    decks.add(Deck(id: _id(), name: name, color: color, icon: icon));
    _commit();
  }

  void editDeck(Deck d, String name, int color, int icon) {
    d.name = name;
    d.color = color;
    d.icon = icon;
    _commit();
  }

  int removeDeck(Deck d) {
    final i = decks.indexOf(d);
    decks.remove(d);
    _commit();
    return i;
  }

  void restoreDeck(int i, Deck d) {
    decks.insert(math.min(i, decks.length), d);
    _commit();
  }

  // ---- cards ----
  void addCard(Deck d, String f, String b) {
    d.cards.add(Flashcard(id: _id(), front: f, back: b));
    _commit();
  }

  /// Adds many [front, back] pairs with a single save/notify.
  void addCards(Deck d, List<List<String>> pairs) {
    for (final p in pairs) {
      d.cards.add(Flashcard(id: _id(), front: p[0], back: p[1]));
    }
    _commit();
  }

  void editCard(Flashcard c, String f, String b) {
    c.front = f;
    c.back = b;
    _commit();
  }

  int removeCard(Deck d, Flashcard c) {
    final i = d.cards.indexOf(c);
    d.cards.remove(c);
    _commit();
    return i;
  }

  void restoreCard(Deck d, int i, Flashcard c) {
    d.cards.insert(math.min(i, d.cards.length), c);
    _commit();
  }

  void toggleFav(Flashcard c) {
    c.favorite = !c.favorite;
    _commit();
  }

  void setKnown(Flashcard c, bool k) {
    c.known = k;
    _commit();
  }

  void setBest(Deck d, int pct) {
    if (pct > d.best) {
      d.best = pct;
      _commit();
    }
  }

  // ---- stats ----
  static String _day(DateTime t) => '${t.year}-${t.month}-${t.day}';
  void markStudied() {
    studyDays.add(_day(DateTime.now()));
    _commit();
  }

  int get streak {
    var d = DateTime.now();
    if (!studyDays.contains(_day(d))) d = DateTime(d.year, d.month, d.day - 1);
    var n = 0;
    while (studyDays.contains(_day(d))) {
      n++;
      d = DateTime(d.year, d.month, d.day - 1);
    }
    return n;
  }

  int get totalCards => decks.fold(0, (a, d) => a + d.cards.length);
  int get knownCards =>
      decks.fold(0, (a, d) => a + d.cards.where((c) => c.known).length);

  // ---- settings ----
  void setTheme(ThemeMode m) {
    themeMode = m;
    _commit();
  }

  void resetSample() {
    decks = _sample();
    _commit();
  }

  void clearAll() {
    decks = [];
    studyDays.clear();
    _commit();
  }
}

late FlashStore store;

// ======================= SECTION 4: APP ROOT =========================

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  store = FlashStore(MemoryStorage()); // <- swap here for persistent storage
  await store.init();
  runApp(const FlashLearnApp());
}

ThemeData _theme(Brightness b) => ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF3F51B5), brightness: b),
    );

class FlashLearnApp extends StatelessWidget {
  const FlashLearnApp({super.key});
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) => MaterialApp(
        title: 'FlashLearn',
        debugShowCheckedModeBanner: false,
        themeMode: store.themeMode,
        theme: _theme(Brightness.light),
        darkTheme: _theme(Brightness.dark),
        themeAnimationDuration: const Duration(milliseconds: 400),
        home: const HomeScreen(),
      ),
    );
  }
}

// ======================= SECTION 5: HELPERS ==========================

/// Animation duration that collapses to zero when reduced motion is on.
Duration dur(BuildContext c, int ms) =>
    MediaQuery.of(c).disableAnimations ? Duration.zero : Duration(milliseconds: ms);

String fmt(Duration d) =>
    '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

RoundedRectangleBorder cardShape(BuildContext c, {double r = 20}) =>
    RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(r),
      side: BorderSide(color: Theme.of(c).colorScheme.outline, width: 1.5),
    );

/// Fade + slide page transition.
Route<T> fadeRoute<T>(Widget page) => PageRouteBuilder<T>(
      transitionDuration: const Duration(milliseconds: 350),
      reverseTransitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (_, __, ___) => page,
      transitionsBuilder: (_, a, __, child) {
        final c = CurvedAnimation(parent: a, curve: Curves.easeOutCubic);
        return FadeTransition(
          opacity: c,
          child: SlideTransition(
            position: Tween<Offset>(begin: const Offset(0.06, 0), end: Offset.zero).animate(c),
            child: child,
          ),
        );
      },
    );

Future<bool> confirm(BuildContext c, String title, String msg, {String ok = 'Confirm'}) async {
  final r = await showDialog<bool>(
    context: c,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(msg),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(ok)),
      ],
    ),
  );
  return r ?? false;
}

void deleteDeck(ScaffoldMessengerState m, Deck d) {
  final i = store.removeDeck(d);
  m
    ..clearSnackBars()
    ..showSnackBar(SnackBar(
      behavior: SnackBarBehavior.floating,
      content: Text('Deleted "${d.name}"'),
      action: SnackBarAction(label: 'UNDO', onPressed: () => store.restoreDeck(i, d)),
    ));
}

void deleteCard(ScaffoldMessengerState m, Deck d, Flashcard c) {
  final i = store.removeCard(d, c);
  m
    ..clearSnackBars()
    ..showSnackBar(SnackBar(
      behavior: SnackBarBehavior.floating,
      content: const Text('Card deleted'),
      action: SnackBarAction(label: 'UNDO', onPressed: () => store.restoreCard(d, i, c)),
    ));
}

void toast(BuildContext c, String msg) => ScaffoldMessenger.of(c)
  ..clearSnackBars()
  ..showSnackBar(SnackBar(behavior: SnackBarBehavior.floating, content: Text(msg)));

/// Text with search matches highlighted (bold + underline + background).
Widget highlight(BuildContext c, String text, String q, {TextStyle? style, int? maxLines}) {
  final base = style ?? Theme.of(c).textTheme.bodyMedium!;
  final overflow = maxLines == null ? null : TextOverflow.ellipsis;
  if (q.isEmpty) return Text(text, style: base, maxLines: maxLines, overflow: overflow);
  final lt = text.toLowerCase(), lq = q.toLowerCase();
  final spans = <TextSpan>[];
  var s = 0;
  while (true) {
    final i = lt.indexOf(lq, s);
    if (i < 0) {
      spans.add(TextSpan(text: text.substring(s)));
      break;
    }
    if (i > s) spans.add(TextSpan(text: text.substring(s, i)));
    spans.add(TextSpan(
      text: text.substring(i, i + lq.length),
      style: TextStyle(
        fontWeight: FontWeight.w900,
        decoration: TextDecoration.underline,
        backgroundColor: Colors.amber.withValues(alpha: 0.5),
      ),
    ));
    s = i + lq.length;
  }
  return Text.rich(TextSpan(style: base, children: spans), maxLines: maxLines, overflow: overflow);
}

// ======================= SECTION 6: REUSABLE WIDGETS =================

/// Fades and slides its child in, delayed by index (staggered entrance).
class StaggeredItem extends StatefulWidget {
  const StaggeredItem({super.key, required this.index, required this.child});
  final int index;
  final Widget child;
  @override
  State<StaggeredItem> createState() => _StaggeredItemState();
}

class _StaggeredItemState extends State<StaggeredItem> {
  bool _show = false;
  Timer? _t;
  @override
  void initState() {
    super.initState();
    _t = Timer(Duration(milliseconds: 40 * math.min(widget.index, 12)), () {
      if (mounted) setState(() => _show = true);
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedOpacity(
        opacity: _show ? 1 : 0,
        duration: dur(context, 350),
        child: AnimatedSlide(
          offset: _show ? Offset.zero : const Offset(0, 0.12),
          duration: dur(context, 350),
          curve: Curves.easeOutCubic,
          child: widget.child,
        ),
      );
}

/// Shrinks slightly while pressed (micro-interaction).
class PressScale extends StatefulWidget {
  const PressScale({super.key, required this.child});
  final Widget child;
  @override
  State<PressScale> createState() => _PressScaleState();
}

class _PressScaleState extends State<PressScale> {
  bool _down = false;
  void _set(bool v) => setState(() => _down = v);
  @override
  Widget build(BuildContext context) => Listener(
        onPointerDown: (_) => _set(true),
        onPointerUp: (_) => _set(false),
        onPointerCancel: (_) => _set(false),
        child: AnimatedScale(
          scale: _down ? 0.96 : 1,
          duration: const Duration(milliseconds: 100),
          child: widget.child,
        ),
      );
}

/// Shakes horizontally whenever [trigger] changes to a non-zero value.
class ShakeWidget extends StatefulWidget {
  const ShakeWidget({super.key, required this.trigger, required this.child});
  final int trigger;
  final Widget child;
  @override
  State<ShakeWidget> createState() => _ShakeWidgetState();
}

class _ShakeWidgetState extends State<ShakeWidget> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 450));
  @override
  void didUpdateWidget(ShakeWidget old) {
    super.didUpdateWidget(old);
    if (widget.trigger != old.trigger &&
        widget.trigger != 0 &&
        !MediaQuery.of(context).disableAnimations) {
      _c.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _c,
        child: widget.child,
        builder: (_, child) => Transform.translate(
          offset: Offset(math.sin(_c.value * math.pi * 6) * 9 * (1 - _c.value), 0),
          child: child,
        ),
      );
}

/// Circular progress ring that animates to its value.
class ProgressRing extends StatelessWidget {
  const ProgressRing({
    super.key,
    required this.value,
    required this.color,
    this.size = 56,
    this.stroke = 7,
  });
  final double value, size, stroke;
  final Color color;
  @override
  Widget build(BuildContext context) {
    final track = Theme.of(context).colorScheme.outlineVariant;
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: value),
      duration: dur(context, 800),
      curve: Curves.easeOutCubic,
      builder: (_, v, __) => SizedBox(
        width: size,
        height: size,
        child: CustomPaint(
          painter: _RingPainter(v, color, track, stroke),
          child: Center(
            child: Text('${(v * 100).round()}%',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: size / 4.2)),
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.v, this.color, this.track, this.stroke);
  final double v, stroke;
  final Color color, track;
  @override
  void paint(Canvas canvas, Size size) {
    final r = Rect.fromLTWH(stroke / 2, stroke / 2, size.width - stroke, size.height - stroke);
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(r, 0, 2 * math.pi, false, p..color = track);
    canvas.drawArc(r, -math.pi / 2, 2 * math.pi * v, false, p..color = color);
  }

  @override
  bool shouldRepaint(_RingPainter o) => o.v != v || o.color != color || o.track != track;
}

/// Number that counts up from 0.
class CountUp extends StatelessWidget {
  const CountUp(this.n, {super.key, this.style});
  final int n;
  final TextStyle? style;
  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<int>(
        tween: IntTween(begin: 0, end: n),
        duration: dur(context, 700),
        curve: Curves.easeOut,
        builder: (_, v, __) => Text('$v', style: style),
      );
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, required this.message, this.action});
  final IconData icon;
  final String title, message;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 72, color: Theme.of(context).colorScheme.outline),
              const SizedBox(height: 12),
              Text(title, style: Theme.of(context).textTheme.titleLarge, textAlign: TextAlign.center),
              const SizedBox(height: 6),
              Text(message, textAlign: TextAlign.center),
              if (action != null) ...[const SizedBox(height: 16), action!],
            ],
          ),
        ),
      );
}

class DeckBadge extends StatelessWidget {
  const DeckBadge(this.deck, {super.key, this.size = 52});
  final Deck deck;
  final double size;
  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: deck.colorValue, borderRadius: BorderRadius.circular(size / 3)),
        child: Icon(deck.iconValue, color: Colors.white, size: size / 2),
      );
}

/// Card that flips in 3D. Front/back swap at the 90 degree midpoint so the
/// back text is never mirrored. Tapping mid-flip reverses smoothly.
class FlipCard extends StatefulWidget {
  const FlipCard({super.key, required this.front, required this.back, required this.showBack, required this.onTap});
  final String front, back;
  final bool showBack;
  final VoidCallback onTap;
  @override
  State<FlipCard> createState() => _FlipCardState();
}

class _FlipCardState extends State<FlipCard> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 500),
    value: widget.showBack ? 1 : 0,
  );

  @override
  void didUpdateWidget(FlipCard old) {
    super.didUpdateWidget(old);
    if (old.showBack != widget.showBack) {
      _c.duration = dur(context, 500);
      widget.showBack ? _c.forward() : _c.reverse();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Widget _face(BuildContext context, bool back) {
    final s = Theme.of(context).colorScheme;
    final fg = back ? s.onSecondaryContainer : s.onPrimaryContainer;
    return Container(
      width: double.infinity,
      height: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: back ? s.secondaryContainer : s.primaryContainer,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: s.outline, width: 2),
        boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 14, offset: Offset(0, 6))],
      ),
      child: Column(
        children: [
          Row(children: [
            Icon(back ? Icons.lightbulb_outline : Icons.help_outline, color: fg),
            const SizedBox(width: 8),
            Text(back ? 'ANSWER' : 'QUESTION',
                style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 1.2, color: fg)),
          ]),
          Expanded(
            child: Center(
              child: SingleChildScrollView(
                child: Text(back ? widget.back : widget.front,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(color: fg)),
              ),
            ),
          ),
          Text('Tap to flip', style: TextStyle(color: fg)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => RepaintBoundary(
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedBuilder(
            animation: _c,
            builder: (context, _) {
              final angle = Curves.easeInOutCubic.transform(_c.value) * math.pi;
              final showBackFace = angle > math.pi / 2;
              return Transform(
                alignment: Alignment.center,
                transform: Matrix4.identity()
                  ..setEntry(3, 2, 0.001)
                  ..rotateY(angle),
                child: showBackFace
                    ? Transform(
                        alignment: Alignment.center,
                        transform: Matrix4.identity()..rotateY(math.pi),
                        child: _face(context, true),
                      )
                    : _face(context, false),
              );
            },
          ),
        ),
      );
}

// ======================= SECTION 7: DIALOGS ==========================

void showDeckDialog(BuildContext context, {Deck? deck}) =>
    showDialog<void>(context: context, builder: (_) => _DeckDialog(deck: deck));

class _DeckDialog extends StatefulWidget {
  const _DeckDialog({this.deck});
  final Deck? deck;
  @override
  State<_DeckDialog> createState() => _DeckDialogState();
}

class _DeckDialogState extends State<_DeckDialog> {
  final _key = GlobalKey<FormState>();
  late final TextEditingController _name = TextEditingController(text: widget.deck?.name ?? '');
  late int _color = widget.deck?.color ?? 0;
  late int _icon = widget.deck?.icon ?? 0;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_key.currentState!.validate()) return;
    final n = _name.text.trim();
    if (widget.deck == null) {
      store.addDeck(n, _color, _icon);
    } else {
      store.editDeck(widget.deck!, n, _color, _icon);
    }
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    return AlertDialog(
      title: Text(widget.deck == null ? 'New deck' : 'Edit deck'),
      content: SingleChildScrollView(
        child: Form(
          key: _key,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextFormField(
                controller: _name,
                autofocus: true,
                maxLength: 30,
                decoration: const InputDecoration(labelText: 'Deck name', border: OutlineInputBorder()),
                validator: (v) {
                  final t = (v ?? '').trim();
                  if (t.isEmpty) return 'Please enter a name';
                  if (store.nameTaken(t, exceptId: widget.deck?.id)) {
                    return 'A deck with this name already exists';
                  }
                  return null;
                },
                onFieldSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: 8),
              const Text('Color', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Wrap(spacing: 10, runSpacing: 10, children: [
                for (var i = 0; i < kColors.length; i++)
                  GestureDetector(
                    onTap: () => setState(() => _color = i),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: kColors[i],
                        shape: BoxShape.circle,
                        border: Border.all(color: s.onSurface, width: _color == i ? 4 : 1),
                      ),
                      child: _color == i ? const Icon(Icons.check, color: Colors.white, size: 20) : null,
                    ),
                  ),
              ]),
              const SizedBox(height: 16),
              const Text('Icon', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Wrap(spacing: 10, runSpacing: 10, children: [
                for (var i = 0; i < kIcons.length; i++)
                  GestureDetector(
                    onTap: () => setState(() => _icon = i),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: _icon == i ? s.primary : null,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: s.outline, width: _icon == i ? 3 : 1),
                      ),
                      child: Icon(kIcons[i], color: _icon == i ? s.onPrimary : s.onSurface),
                    ),
                  ),
              ]),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: _submit, child: const Text('Save')),
      ],
    );
  }
}

void showCardDialog(BuildContext context, Deck deck, {Flashcard? card}) =>
    showDialog<void>(context: context, builder: (_) => _CardDialog(deck: deck, card: card));

class _CardDialog extends StatefulWidget {
  const _CardDialog({required this.deck, this.card});
  final Deck deck;
  final Flashcard? card;
  @override
  State<_CardDialog> createState() => _CardDialogState();
}

class _CardDialogState extends State<_CardDialog> {
  final _key = GlobalKey<FormState>();
  late final TextEditingController _front = TextEditingController(text: widget.card?.front ?? '');
  late final TextEditingController _back = TextEditingController(text: widget.card?.back ?? '');

  @override
  void dispose() {
    _front.dispose();
    _back.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_key.currentState!.validate()) return;
    if (widget.card == null) {
      store.addCard(widget.deck, _front.text.trim(), _back.text.trim());
    } else {
      store.editCard(widget.card!, _front.text.trim(), _back.text.trim());
    }
    Navigator.pop(context);
  }

  String? _required(String? v) => (v ?? '').trim().isEmpty ? 'This field cannot be empty' : null;

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.card == null ? 'New card' : 'Edit card'),
        content: SingleChildScrollView(
          child: Form(
            key: _key,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextFormField(
                controller: _front,
                autofocus: true,
                minLines: 2,
                maxLines: 4,
                maxLength: 300,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(labelText: 'Question (front)', border: OutlineInputBorder()),
                validator: _required,
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _back,
                minLines: 2,
                maxLines: 4,
                maxLength: 300,
                decoration: const InputDecoration(labelText: 'Answer (back)', border: OutlineInputBorder()),
                validator: _required,
              ),
            ]),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: _submit, child: const Text('Save')),
        ],
      );
}

// ======================= SECTION 7B: NOTES -> CARDS ==================

/// Offline generator: scores every sentence in the notes, keeps the most
/// informative ones and turns each into a question/answer card.
/// No AI service or internet is needed; it is pure Dart text processing.
class NoteCardGenerator {
  static const _stop = {
    'the', 'and', 'but', 'for', 'with', 'from', 'this', 'that', 'these', 'those',
    'which', 'who', 'whom', 'can', 'will', 'would', 'should', 'could', 'may',
    'might', 'has', 'have', 'had', 'not', 'also', 'than', 'then', 'such', 'their',
    'there', 'they', 'you', 'our', 'your', 'into', 'about', 'over', 'more', 'most',
    'some', 'any', 'each', 'other', 'when', 'where', 'while', 'how', 'what', 'why',
    'are', 'was', 'were', 'been', 'its', 'it',
  };
  static const _pronouns = {'it', 'this', 'that', 'they', 'these', 'those', 'which', 'there', 'he', 'she', 'we'};
  static final _colon = RegExp(r'^([^:]{2,50}):\s+(.{8,})$');
  static final _def = RegExp(
      r'^(.{2,60}?)\s+(?:is defined as|is called|refers to|means|is|are)\s+(.{8,})$',
      caseSensitive: false);

  static List<String> _words(String s) =>
      RegExp(r"[A-Za-z0-9][A-Za-z0-9'\-]*").allMatches(s).map((m) => m.group(0)!).toList();

  static bool _keyword(String l) => l.length > 3 && !_stop.contains(l);

  /// Splits notes into clean sentences of 5-45 words.
  static List<String> _sentences(String text) => text
      .split(RegExp(r'[\r\n]+|(?<=[.!?])\s+'))
      .map((s) => s.replaceAll(RegExp(r'^[\s\-\*\u2022]+'), '').replaceAll(RegExp(r'^\d+[\.\)]\s+'), '').trim())
      .where((s) {
        final n = s.split(RegExp(r'\s+')).length;
        return n >= 5 && n <= 45;
      })
      .toList();

  static String _clean(String s) {
    var t = s.trim().replaceAll(RegExp(r'[.\s]+$'), '');
    if (t.isEmpty) return t;
    t = t[0].toUpperCase() + t.substring(1);
    return t.length > 300 ? '${t.substring(0, 297)}...' : t;
  }

  /// Turns one sentence into [front, back], or null if it is not usable.
  static List<String>? _make(String s, Map<String, int> freq) {
    final c = _colon.firstMatch(s);
    if (c != null) return ['What is ${c[1]!.trim()}?', _clean(c[2]!)];

    final d = _def.firstMatch(s);
    if (d != null) {
      final subj = d[1]!.trim();
      final first = subj.split(RegExp(r'\s+')).first.toLowerCase();
      if (subj.split(RegExp(r'\s+')).length <= 6 && !_pronouns.contains(first)) {
        return ['What is $subj?', _clean(d[2]!)];
      }
    }

    // Fallback: fill-in-the-blank on the most important word.
    final words = _words(s);
    String? best;
    var bestScore = -1;
    for (var i = 0; i < words.length; i++) {
      final w = words[i], l = w.toLowerCase();
      if (!_keyword(l)) continue;
      var sc = (freq[l] ?? 1) * 2 + l.length;
      if (i > 0 && RegExp(r'^[A-Z]').hasMatch(w)) sc += 3;
      if (RegExp(r'\d').hasMatch(w)) sc += 3;
      if (sc > bestScore) {
        bestScore = sc;
        best = w;
      }
    }
    if (best == null) return null;
    final blanked = s.replaceFirst(RegExp('\\b${RegExp.escape(best)}\\b'), '_____');
    final front = 'Fill in the blank:\n${blanked.length > 280 ? '${blanked.substring(0, 277)}...' : blanked}';
    return [front, best];
  }

  static List<List<String>> generate(String text, {int count = 5}) {
    final sents = _sentences(text);
    if (sents.isEmpty) return [];
    final freq = <String, int>{};
    for (final w in _words(text)) {
      final l = w.toLowerCase();
      if (_keyword(l)) freq[l] = (freq[l] ?? 0) + 1;
    }
    // Score = how many frequent keywords the sentence carries (+ bonus for definitions).
    final scored = <MapEntry<int, double>>[];
    for (var i = 0; i < sents.length; i++) {
      final ws = _words(sents[i]).map((w) => w.toLowerCase()).where(_keyword).toSet();
      var sc = ws.fold<double>(0, (a, l) => a + (freq[l] ?? 0)) / math.sqrt(ws.length + 1);
      if (_colon.hasMatch(sents[i]) || _def.hasMatch(sents[i])) sc += 3;
      scored.add(MapEntry(i, sc));
    }
    scored.sort((a, b) => b.value.compareTo(a.value));
    final out = <int, List<String>>{};
    final fronts = <String>{};
    for (final e in scored) {
      if (out.length >= count) break;
      final card = _make(sents[e.key], freq);
      if (card == null || card[1].trim().isEmpty || !fronts.add(card[0])) continue;
      out[e.key] = card;
    }
    final keys = out.keys.toList()..sort(); // keep the original order of the notes
    return [for (final k in keys) out[k]!];
  }
}

void showNotesDialog(BuildContext context, Deck deck) =>
    showDialog<void>(context: context, builder: (_) => _NotesDialog(deck: deck));

/// Step 1: paste notes. Step 2: review the generated cards and pick which to add.
class _NotesDialog extends StatefulWidget {
  const _NotesDialog({required this.deck});
  final Deck deck;
  @override
  State<_NotesDialog> createState() => _NotesDialogState();
}

class _NotesDialogState extends State<_NotesDialog> {
  final _notes = TextEditingController();
  List<List<String>>? _cards;
  List<bool> _sel = [];
  String? _err;

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  void _generate() {
    final t = _notes.text.trim();
    if (t.split(RegExp(r'\s+')).length < 20) {
      setState(() => _err = 'Paste at least a few sentences (20+ words).');
      return;
    }
    final r = NoteCardGenerator.generate(t);
    if (r.isEmpty) {
      setState(() => _err = 'No usable sentences found. Use complete sentences.');
      return;
    }
    setState(() {
      _cards = r;
      _sel = List.filled(r.length, true);
      _err = null;
    });
  }

  void _add() {
    final chosen = [
      for (var i = 0; i < _cards!.length; i++)
        if (_sel[i]) _cards![i]
    ];
    if (chosen.isEmpty) return;
    final m = ScaffoldMessenger.of(context);
    store.addCards(widget.deck, chosen);
    Navigator.pop(context);
    m
      ..clearSnackBars()
      ..showSnackBar(SnackBar(
          behavior: SnackBarBehavior.floating, content: Text('Added ${chosen.length} cards')));
  }

  @override
  Widget build(BuildContext context) {
    final review = _cards != null;
    return AlertDialog(
      title: Text(review ? 'Review generated cards' : 'Generate cards from notes'),
      content: SizedBox(
        width: double.maxFinite,
        child: review
            ? ListView(shrinkWrap: true, children: [
                for (var i = 0; i < _cards!.length; i++)
                  CheckboxListTile(
                    value: _sel[i],
                    controlAffinity: ListTileControlAffinity.leading,
                    onChanged: (v) => setState(() => _sel[i] = v ?? false),
                    title: Text(_cards![i][0], style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text(_cards![i][1]),
                  ),
              ])
            : SingleChildScrollView(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  TextField(
                    controller: _notes,
                    autofocus: true,
                    minLines: 8,
                    maxLines: 12,
                    decoration: InputDecoration(
                      hintText: 'Paste your notes here...',
                      border: const OutlineInputBorder(),
                      errorText: _err,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text('Creates up to 5 cards from the most important sentences.'),
                ]),
              ),
      ),
      actions: review
          ? [
              TextButton(onPressed: () => setState(() => _cards = null), child: const Text('Back')),
              FilledButton(
                  onPressed: _sel.contains(true) ? _add : null,
                  child: Text('Add ${_sel.where((s) => s).length} cards')),
            ]
          : [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
              FilledButton.icon(
                  onPressed: _generate,
                  icon: const Icon(Icons.auto_awesome),
                  label: const Text('Generate')),
            ],
    );
  }
}

// ======================= SECTION 8: HOME =============================

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) => Scaffold(
        appBar: AppBar(
          title: const Text('FlashLearn', style: TextStyle(fontWeight: FontWeight.w800)),
          actions: [
            IconButton(
                tooltip: 'Search',
                icon: const Icon(Icons.search),
                onPressed: () => Navigator.push(context, fadeRoute(const SearchScreen()))),
            IconButton(
                tooltip: 'Statistics',
                icon: const Icon(Icons.bar_chart),
                onPressed: () => Navigator.push(context, fadeRoute(const StatsScreen()))),
            IconButton(
                tooltip: 'Settings',
                icon: const Icon(Icons.settings),
                onPressed: () => Navigator.push(context, fadeRoute(const SettingsScreen()))),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => showDeckDialog(context),
          icon: const Icon(Icons.add),
          label: const Text('New deck'),
        ),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: store.decks.isEmpty
                ? EmptyState(
                    icon: Icons.style,
                    title: 'No decks yet',
                    message: 'Create your first deck to start learning.',
                    action: FilledButton.icon(
                        onPressed: () => showDeckDialog(context),
                        icon: const Icon(Icons.add),
                        label: const Text('Create deck')),
                  )
                : Column(children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text('Learn smarter, one card at a time',
                            style: Theme.of(context).textTheme.titleMedium),
                      ),
                    ),
                    Expanded(
                      child: LayoutBuilder(builder: (context, box) {
                        final cols = box.maxWidth >= 700 ? 2 : 1;
                        return GridView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
                          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: cols,
                            mainAxisExtent: 112,
                            crossAxisSpacing: 12,
                            mainAxisSpacing: 12,
                          ),
                          itemCount: store.decks.length,
                          itemBuilder: (context, i) {
                            final d = store.decks[i];
                            return StaggeredItem(key: ValueKey(d.id), index: i, child: DeckTile(deck: d));
                          },
                        );
                      }),
                    ),
                  ]),
          ),
        ),
      ),
    );
  }
}

class DeckTile extends StatelessWidget {
  const DeckTile({super.key, required this.deck});
  final Deck deck;
  @override
  Widget build(BuildContext context) {
    return PressScale(
      child: Card(
        margin: EdgeInsets.zero,
        shape: cardShape(context),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => Navigator.push(context, fadeRoute(DeckScreen(deckId: deck.id))),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 4, 12),
            child: Row(children: [
              Hero(tag: 'deck-${deck.id}', child: DeckBadge(deck)),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(deck.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                    Text('${deck.cards.length} cards', style: Theme.of(context).textTheme.bodySmall),
                    if (deck.best >= 0)
                      Row(children: [
                        const Icon(Icons.emoji_events, size: 14),
                        const SizedBox(width: 4),
                        Text('Best quiz ${deck.best}%', style: Theme.of(context).textTheme.bodySmall),
                      ]),
                  ],
                ),
              ),
              ProgressRing(value: deck.mastery, color: deck.colorValue, size: 52, stroke: 6),
              PopupMenuButton<String>(
                tooltip: 'More',
                onSelected: (v) {
                  if (v == 'edit') {
                    showDeckDialog(context, deck: deck);
                  } else {
                    deleteDeck(ScaffoldMessenger.of(context), deck);
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'edit', child: Text('Edit deck')),
                  PopupMenuItem(value: 'delete', child: Text('Delete deck')),
                ],
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

// ======================= SECTION 9: DECK DETAIL ======================

class DeckScreen extends StatelessWidget {
  const DeckScreen({super.key, required this.deckId});
  final String deckId;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        Deck? found;
        for (final d in store.decks) {
          if (d.id == deckId) found = d;
        }
        if (found == null) return const Scaffold(body: SizedBox());
        final d = found;
        final s = Theme.of(context).colorScheme;
        return Scaffold(
          appBar: AppBar(
            title: Text(d.name),
            actions: [
              PopupMenuButton<String>(
                onSelected: (v) async {
                  if (v == 'edit') {
                    showDeckDialog(context, deck: d);
                    return;
                  }
                  final ok = await confirm(context, 'Delete deck?',
                      '"${d.name}" and its ${d.cards.length} cards will be deleted.',
                      ok: 'Delete');
                  if (ok && context.mounted) {
                    final m = ScaffoldMessenger.of(context);
                    Navigator.pop(context);
                    await Future<void>.delayed(const Duration(milliseconds: 400));
                    deleteDeck(m, d);
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'edit', child: Text('Edit deck')),
                  PopupMenuItem(value: 'delete', child: Text('Delete deck')),
                ],
              ),
            ],
          ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => showCardDialog(context, d),
            icon: const Icon(Icons.add),
            label: const Text('Add card'),
          ),
          body: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 900),
              child: Column(children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(children: [
                    Hero(tag: 'deck-${d.id}', child: DeckBadge(d, size: 64)),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('${d.cards.length} cards',
                            style: Theme.of(context).textTheme.titleLarge),
                        Text('${d.cards.where((c) => c.known).length} mastered'),
                      ]),
                    ),
                    ProgressRing(value: d.mastery, color: d.colorValue, size: 64),
                  ]),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(children: [
                    Expanded(
                      child: FilledButton.icon(
                        icon: const Icon(Icons.school),
                        label: const Text('Study'),
                        onPressed: () {
                          if (d.cards.isEmpty) {
                            toast(context, 'Add a card first.');
                          } else {
                            Navigator.push(context, fadeRoute(StudyScreen(deck: d)));
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.quiz),
                        label: const Text('Quiz'),
                        onPressed: () {
                          if (d.cards.length < 2) {
                            toast(context, 'Add at least 2 cards to start a quiz.');
                          } else {
                            Navigator.push(context, fadeRoute(QuizScreen(deck: d)));
                          }
                        },
                      ),
                    ),
                  ]),
                ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                  child: SizedBox(
                    width: double.infinity,
                    child: TextButton.icon(
                      onPressed: () => showNotesDialog(context, d),
                      icon: const Icon(Icons.auto_awesome),
                      label: const Text('Generate 5 cards from notes'),
                    ),
                  ),
                ),
                Expanded(
                  child: d.cards.isEmpty
                      ? EmptyState(
                          icon: Icons.layers,
                          title: 'This deck is empty',
                          message: 'Add your first flashcard.',
                          action: FilledButton.icon(
                              onPressed: () => showCardDialog(context, d),
                              icon: const Icon(Icons.add),
                              label: const Text('Add card')))
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
                          itemCount: d.cards.length,
                          itemBuilder: (context, i) => _row(context, d, d.cards[i], i, s),
                        ),
                ),
              ]),
            ),
          ),
        );
      },
    );
  }

  Widget _row(BuildContext context, Deck d, Flashcard c, int i, ColorScheme s) {
    return StaggeredItem(
      key: ValueKey('row-${c.id}'),
      index: i,
      child: Dismissible(
        key: ValueKey(c.id),
        direction: DismissDirection.endToStart,
        background: Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.only(right: 20),
          alignment: Alignment.centerRight,
          decoration: BoxDecoration(color: s.errorContainer, borderRadius: BorderRadius.circular(16)),
          child: const Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.delete),
            SizedBox(width: 6),
            Text('Delete'),
          ]),
        ),
        onDismissed: (_) => deleteCard(ScaffoldMessenger.of(context), d, c),
        child: Card(
          margin: const EdgeInsets.symmetric(vertical: 4),
          shape: cardShape(context, r: 16),
          child: ListTile(
            onTap: () => showCardDialog(context, d, card: c),
            leading: Tooltip(
              message: c.known ? 'Mastered' : 'Still learning',
              child: Icon(c.known ? Icons.check_circle : Icons.radio_button_unchecked),
            ),
            title: Text(c.front, maxLines: 2, overflow: TextOverflow.ellipsis),
            subtitle: Text(c.back, maxLines: 2, overflow: TextOverflow.ellipsis),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              IconButton(
                tooltip: c.favorite ? 'Remove favorite' : 'Add favorite',
                onPressed: () => store.toggleFav(c),
                icon: starIcon(c.favorite),
              ),
              PopupMenuButton<String>(
                onSelected: (v) {
                  if (v == 'edit') {
                    showCardDialog(context, d, card: c);
                  } else {
                    deleteCard(ScaffoldMessenger.of(context), d, c);
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'edit', child: Text('Edit card')),
                  PopupMenuItem(value: 'delete', child: Text('Delete card')),
                ],
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Star icon that bounces in when toggled on.
Widget starIcon(bool fav) => AnimatedSwitcher(
      duration: const Duration(milliseconds: 400),
      switchInCurve: Curves.elasticOut,
      transitionBuilder: (child, a) => ScaleTransition(scale: a, child: child),
      child: Icon(fav ? Icons.star : Icons.star_border, key: ValueKey(fav)),
    );

// ======================= SECTION 10: STUDY ===========================

class StudyScreen extends StatefulWidget {
  const StudyScreen({super.key, required this.deck});
  final Deck deck;
  @override
  State<StudyScreen> createState() => _StudyScreenState();
}

class _StudyScreenState extends State<StudyScreen> {
  List<Flashcard> _cards = [];
  int _i = 0, _dir = 1;
  bool _back = false, _shuffle = false, _favOnly = false;
  bool _done = false, _busy = false, _dragging = false;
  double _dx = 0;
  final Set<String> _knew = {}, _missed = {};
  final Stopwatch _clock = Stopwatch();
  Timer? _flyTimer;

  @override
  void initState() {
    super.initState();
    _rebuild();
  }

  @override
  void dispose() {
    _flyTimer?.cancel();
    super.dispose();
  }

  void _rebuild() =>
      _begin(widget.deck.cards.where((c) => !_favOnly || c.favorite).toList());

  void _begin(List<Flashcard> list) {
    if (_shuffle) list.shuffle();
    _cards = list;
    _i = 0;
    _dir = 1;
    _back = false;
    _done = false;
    _busy = false;
    _dragging = false;
    _dx = 0;
    _knew.clear();
    _missed.clear();
    _clock
      ..reset()
      ..start();
  }

  void _goto(int delta) {
    if (_busy || _cards.isEmpty) return;
    final n = _i + delta;
    if (n < 0) return;
    if (n >= _cards.length) {
      _finish();
      return;
    }
    setState(() {
      _dir = delta;
      _i = n;
      _back = false;
    });
  }

  void _finish() {
    _clock.stop();
    setState(() => _done = true);
    store.markStudied();
  }

  /// Flies the card off-screen, records the result, then shows the next one.
  void _mark(bool known) {
    if (_busy || _cards.isEmpty) return;
    final c = _cards[_i];
    final w = MediaQuery.of(context).size.width;
    store.setKnown(c, known);
    if (known) {
      _knew.add(c.id);
      _missed.remove(c.id);
    } else {
      _missed.add(c.id);
      _knew.remove(c.id);
    }
    setState(() {
      _busy = true;
      _dragging = false;
      _dx = known ? w : -w;
    });
    _flyTimer = Timer(const Duration(milliseconds: 230), () {
      if (!mounted) return;
      final last = _i + 1 >= _cards.length;
      setState(() {
        _busy = false;
        _dragging = true;
        _dx = 0;
        _dir = 1;
        _back = false;
        if (!last) _i++;
      });
      if (last) _finish();
    });
  }

  KeyEventResult _onKey(FocusNode n, KeyEvent e) {
    if (e is! KeyDownEvent || _done || _cards.isEmpty) return KeyEventResult.ignored;
    if (e.logicalKey == LogicalKeyboardKey.space) {
      setState(() => _back = !_back);
    } else if (e.logicalKey == LogicalKeyboardKey.arrowRight) {
      _goto(1);
    } else if (e.logicalKey == LogicalKeyboardKey.arrowLeft) {
      _goto(-1);
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final started = _knew.isNotEmpty || _missed.isNotEmpty || _i > 0;
    return PopScope(
      canPop: _done || _cards.isEmpty || !started,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final ok = await confirm(context, 'Leave session?', 'Your progress in this session will be lost.',
            ok: 'Leave');
        if (ok && context.mounted) Navigator.pop(context);
      },
      child: Focus(
        autofocus: true,
        onKeyEvent: _onKey,
        child: Scaffold(
          appBar: AppBar(
            title: Text(widget.deck.name),
            actions: [
              IconButton(
                tooltip: 'Shuffle',
                isSelected: _shuffle,
                icon: const Icon(Icons.shuffle),
                selectedIcon: const Icon(Icons.shuffle_on),
                onPressed: () => setState(() {
                  _shuffle = !_shuffle;
                  _rebuild();
                }),
              ),
              IconButton(
                tooltip: 'Favorites only',
                isSelected: _favOnly,
                icon: const Icon(Icons.star_border),
                selectedIcon: const Icon(Icons.star),
                onPressed: () => setState(() {
                  _favOnly = !_favOnly;
                  _rebuild();
                }),
              ),
            ],
          ),
          body: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 700),
                child: _done
                    ? _summary(context)
                    : _cards.isEmpty
                        ? EmptyState(
                            icon: Icons.star_border,
                            title: 'No cards to show',
                            message: 'There are no favorite cards in this deck yet.',
                            action: FilledButton(
                                onPressed: () => setState(() {
                                      _favOnly = false;
                                      _rebuild();
                                    }),
                                child: const Text('Show all cards')))
                        : _studyBody(context),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _studyBody(BuildContext context) {
    final c = _cards[_i];
    final s = Theme.of(context).colorScheme;
    final id = ValueKey(c.id);
    Widget hint(bool right) {
      final o = ((right ? _dx : -_dx) / 120).clamp(0.0, 1.0);
      return Positioned(
        top: 16,
        left: right ? null : 16,
        right: right ? 16 : null,
        child: Opacity(
          opacity: o,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: s.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: s.outline, width: 3),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(right ? Icons.check : Icons.replay),
              const SizedBox(width: 6),
              Text(right ? 'KNEW IT' : 'STILL LEARNING',
                  style: const TextStyle(fontWeight: FontWeight.w900)),
            ]),
          ),
        ),
      );
    }

    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 8, 8),
        child: Column(children: [
          Row(children: [
            Text('Card ${_i + 1} of ${_cards.length}', style: Theme.of(context).textTheme.titleMedium),
            const Spacer(),
            IconButton(
              tooltip: c.favorite ? 'Remove favorite' : 'Add favorite',
              onPressed: () {
                store.toggleFav(c);
                setState(() {});
              },
              icon: starIcon(c.favorite),
            ),
          ]),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: TweenAnimationBuilder<double>(
              tween: Tween<double>(end: (_i + 1) / _cards.length),
              duration: dur(context, 400),
              builder: (_, v, __) => LinearProgressIndicator(
                  value: v, minHeight: 10, borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ]),
      ),
      Expanded(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: GestureDetector(
            onHorizontalDragStart: (_) {
              if (!_busy) setState(() => _dragging = true);
            },
            onHorizontalDragUpdate: (d) {
              if (!_busy) setState(() => _dx += d.delta.dx);
            },
            onHorizontalDragEnd: (_) {
              if (_busy) return;
              if (_dx > 110) {
                _mark(true);
              } else if (_dx < -110) {
                _mark(false);
              } else {
                setState(() {
                  _dragging = false;
                  _dx = 0;
                });
              }
            },
            child: Stack(children: [
              Positioned.fill(
                child: AnimatedContainer(
                  duration: _dragging ? Duration.zero : dur(context, 230),
                  curve: Curves.easeOut,
                  transformAlignment: Alignment.bottomCenter,
                  transform: Matrix4.translationValues(_dx, 0, 0)..rotateZ(_dx / 1200),
                  child: AnimatedSwitcher(
                    duration: dur(context, 350),
                    transitionBuilder: (child, anim) {
                      final incoming = child.key == id;
                      final begin = Offset((incoming ? 0.25 : -0.25) * _dir, 0);
                      return FadeTransition(
                        opacity: anim,
                        child: SlideTransition(
                          position: Tween<Offset>(begin: begin, end: Offset.zero).animate(anim),
                          child: ScaleTransition(
                              scale: Tween<double>(begin: 0.92, end: 1).animate(anim), child: child),
                        ),
                      );
                    },
                    child: FlipCard(
                      key: id,
                      front: c.front,
                      back: c.back,
                      showBack: _back,
                      onTap: () => setState(() => _back = !_back),
                    ),
                  ),
                ),
              ),
              IgnorePointer(child: Stack(children: [hint(true), hint(false)])),
            ]),
          ),
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Row(children: [
          Expanded(
              child: OutlinedButton.icon(
                  onPressed: () => _mark(false),
                  icon: const Icon(Icons.replay),
                  label: const Text('Still learning'))),
          const SizedBox(width: 12),
          Expanded(
              child: FilledButton.icon(
                  onPressed: () => _mark(true),
                  icon: const Icon(Icons.check),
                  label: const Text('I knew it'))),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          IconButton.outlined(
              tooltip: 'Previous',
              onPressed: _i > 0 ? () => _goto(-1) : null,
              icon: const Icon(Icons.arrow_back)),
          Flexible(
              child: Text('Tap card to flip  |  swipe to mark',
                  textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall)),
          IconButton.outlined(
              tooltip: 'Next', onPressed: () => _goto(1), icon: const Icon(Icons.arrow_forward)),
        ]),
      ),
    ]);
  }

  Widget _summary(BuildContext context) {
    final big = Theme.of(context).textTheme.displayMedium?.copyWith(fontWeight: FontWeight.w800);
    Widget stat(IconData i, int n, String label) => Column(children: [
          Icon(i, size: 32),
          CountUp(n, style: big),
          Text(label),
        ]);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(children: [
        const Icon(Icons.emoji_events, size: 72),
        Text('Session complete', style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 24),
        Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
          stat(Icons.check_circle, _knew.length, 'Knew it'),
          stat(Icons.replay, _missed.length, 'Still learning'),
        ]),
        const SizedBox(height: 16),
        Text('Time taken: ${fmt(_clock.elapsed)}', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 24),
        Wrap(spacing: 12, runSpacing: 12, alignment: WrapAlignment.center, children: [
          FilledButton.icon(
              onPressed: () => setState(_rebuild),
              icon: const Icon(Icons.refresh),
              label: const Text('Study again')),
          if (_missed.isNotEmpty)
            OutlinedButton.icon(
                onPressed: () => setState(() {
                      final missed = _cards.where((c) => _missed.contains(c.id)).toList();
                      _begin(missed);
                    }),
                icon: const Icon(Icons.replay),
                label: const Text('Review missed')),
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Done')),
        ]),
      ]),
    );
  }
}

// ======================= SECTION 11: QUIZ ============================

class _Q {
  _Q(this.card, this.options);
  final Flashcard card;
  final List<String> options;
  int? chosen;
  bool get correct => chosen != null && options[chosen!] == card.back;
}

class QuizScreen extends StatefulWidget {
  const QuizScreen({super.key, required this.deck});
  final Deck deck;
  @override
  State<QuizScreen> createState() => _QuizScreenState();
}

class _QuizScreenState extends State<QuizScreen> {
  late List<_Q> _qs;
  int _i = 0;
  bool _done = false;
  final Stopwatch _clock = Stopwatch()..start();
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _qs = _generate();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && !_done) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  /// One correct answer + up to 3 distractors taken from the other cards.
  List<_Q> _generate() {
    final rnd = math.Random();
    final backs = widget.deck.cards.map((c) => c.back).toSet();
    final cards = [...widget.deck.cards]..shuffle(rnd);
    return cards
        .map((c) {
          final others = backs.where((b) => b != c.back).toList()..shuffle(rnd);
          final opts = [c.back, ...others.take(3)]..shuffle(rnd);
          return _Q(c, opts);
        })
        .where((q) => q.options.length > 1)
        .toList();
  }

  void _choose(int i) {
    if (_qs[_i].chosen != null) return;
    setState(() => _qs[_i].chosen = i);
  }

  void _next() {
    if (_i + 1 >= _qs.length) {
      _clock.stop();
      final score = _qs.where((q) => q.correct).length;
      store.setBest(widget.deck, (score * 100 / _qs.length).round());
      store.markStudied();
      setState(() => _done = true);
    } else {
      setState(() => _i++);
    }
  }

  void _retry() => setState(() {
        _qs = _generate();
        _i = 0;
        _done = false;
        _clock
          ..reset()
          ..start();
      });

  @override
  Widget build(BuildContext context) {
    final inProgress = !_done && _qs.isNotEmpty && (_i > 0 || _qs[0].chosen != null);
    return PopScope(
      canPop: !inProgress,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final ok = await confirm(context, 'Quit quiz?', 'Your answers so far will be lost.', ok: 'Quit');
        if (ok && context.mounted) Navigator.pop(context);
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text('Quiz: ${widget.deck.name}'),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Chip(
                  avatar: const Icon(Icons.timer_outlined, size: 18), label: Text(fmt(_clock.elapsed))),
            ),
          ],
        ),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 700),
              child: _qs.isEmpty
                  ? const EmptyState(
                      icon: Icons.quiz,
                      title: 'Not enough variety',
                      message: 'Add cards with different answers to generate a quiz.')
                  : _done
                      ? _result(context)
                      : _question(context),
            ),
          ),
        ),
      ),
    );
  }

  Widget _question(BuildContext context) {
    final q = _qs[_i];
    final s = Theme.of(context).colorScheme;
    final answered = q.chosen != null;
    final last = _i + 1 >= _qs.length;
    return ListView(padding: const EdgeInsets.all(16), children: [
      Text('Question ${_i + 1} of ${_qs.length}', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 8),
      TweenAnimationBuilder<double>(
        tween: Tween<double>(end: (_i + (answered ? 1 : 0)) / _qs.length),
        duration: dur(context, 400),
        builder: (_, v, __) =>
            LinearProgressIndicator(value: v, minHeight: 10, borderRadius: BorderRadius.circular(8)),
      ),
      const SizedBox(height: 16),
      AnimatedSwitcher(
        duration: dur(context, 300),
        child: Container(
          key: ValueKey(_i),
          width: double.infinity,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: s.primaryContainer,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: s.outline, width: 2),
          ),
          child: Column(children: [
            Row(children: [
              Icon(Icons.help_outline, color: s.onPrimaryContainer),
              const SizedBox(width: 8),
              Text('QUESTION',
                  style: TextStyle(fontWeight: FontWeight.w800, color: s.onPrimaryContainer)),
            ]),
            const SizedBox(height: 12),
            Text(q.card.front,
                textAlign: TextAlign.center,
                style: Theme.of(context)
                    .textTheme
                    .headlineSmall
                    ?.copyWith(color: s.onPrimaryContainer)),
          ]),
        ),
      ),
      const SizedBox(height: 16),
      for (var i = 0; i < q.options.length; i++) _option(context, q, i),
      if (answered)
        FilledButton.icon(
          onPressed: _next,
          icon: Icon(last ? Icons.flag : Icons.arrow_forward),
          label: Text(last ? 'Finish' : 'Next question'),
        ),
    ]);
  }

  Widget _option(BuildContext context, _Q q, int i) {
    final s = Theme.of(context).colorScheme;
    final answered = q.chosen != null;
    final isCorrect = q.options[i] == q.card.back;
    final isChosen = q.chosen == i;
    Color? bg;
    IconData? icon;
    if (answered) {
      if (isCorrect) {
        bg = Colors.green.withValues(alpha: 0.3);
        icon = Icons.check_circle;
      } else if (isChosen) {
        bg = Colors.red.withValues(alpha: 0.3);
        icon = Icons.cancel;
      }
    }
    final marked = icon != null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: ShakeWidget(
        trigger: isChosen && !isCorrect ? _i + 1 : 0,
        child: PressScale(
          child: GestureDetector(
            onTap: () => _choose(i),
            child: AnimatedContainer(
              duration: dur(context, 300),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: bg ?? s.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: s.outline, width: marked ? 3 : 1.5),
              ),
              child: Row(children: [
                CircleAvatar(radius: 14, child: Text('ABCD'[i])),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(q.options[i],
                      style: TextStyle(
                          fontSize: 16, fontWeight: marked ? FontWeight.w800 : FontWeight.w500)),
                ),
                if (icon != null) Icon(icon),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  Widget _result(BuildContext context) {
    final score = _qs.where((q) => q.correct).length;
    final wrong = _qs.where((q) => !q.correct).toList();
    return ListView(padding: const EdgeInsets.all(16), children: [
      const SizedBox(height: 8),
      Center(
          child: ProgressRing(
              value: score / _qs.length, color: widget.deck.colorValue, size: 160, stroke: 14)),
      const SizedBox(height: 12),
      Center(
          child: Text('$score / ${_qs.length} correct',
              style: Theme.of(context).textTheme.headlineSmall)),
      Center(child: Text('Time ${fmt(_clock.elapsed)}  |  Best score ${widget.deck.best}%')),
      const SizedBox(height: 16),
      if (wrong.isEmpty)
        const Center(child: Text('Perfect score! Nothing to review.'))
      else ...[
        Text('Review your mistakes', style: Theme.of(context).textTheme.titleMedium),
        for (final q in wrong)
          Card(
            shape: cardShape(context, r: 16),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(q.card.front, style: const TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                Row(children: [
                  const Icon(Icons.cancel, size: 18),
                  const SizedBox(width: 6),
                  Expanded(
                      child: Text('Your answer: ${q.chosen == null ? "-" : q.options[q.chosen!]}')),
                ]),
                Row(children: [
                  const Icon(Icons.check_circle, size: 18),
                  const SizedBox(width: 6),
                  Expanded(child: Text('Correct: ${q.card.back}')),
                ]),
              ]),
            ),
          ),
      ],
      const SizedBox(height: 16),
      Wrap(spacing: 12, runSpacing: 12, alignment: WrapAlignment.center, children: [
        FilledButton.icon(onPressed: _retry, icon: const Icon(Icons.refresh), label: const Text('Retry')),
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Done')),
      ]),
    ]);
  }
}

// ======================= SECTION 12: SEARCH ==========================

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});
  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _c = TextEditingController();
  String _q = '';

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lq = _q.toLowerCase();
    final decks = _q.isEmpty
        ? <Deck>[]
        : store.decks.where((d) => d.name.toLowerCase().contains(lq)).toList();
    final hits = <(Deck, Flashcard)>[];
    if (_q.isNotEmpty) {
      for (final d in store.decks) {
        for (final c in d.cards) {
          if (c.front.toLowerCase().contains(lq) || c.back.toLowerCase().contains(lq)) {
            hits.add((d, c));
          }
        }
      }
    }
    final bold = Theme.of(context).textTheme.titleMedium!.copyWith(fontWeight: FontWeight.w700);
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _c,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Search decks and cards', border: InputBorder.none),
          onChanged: (v) => setState(() => _q = v.trim()),
        ),
        actions: [
          if (_q.isNotEmpty)
            IconButton(
                tooltip: 'Clear',
                icon: const Icon(Icons.close),
                onPressed: () => setState(() {
                      _c.clear();
                      _q = '';
                    })),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: _q.isEmpty
              ? const EmptyState(
                  icon: Icons.search, title: 'Search', message: 'Type to find decks and cards.')
              : (decks.isEmpty && hits.isEmpty)
                  ? const EmptyState(
                      icon: Icons.search_off, title: 'No results', message: 'Try a different word.')
                  : ListView(padding: const EdgeInsets.all(16), children: [
                      if (decks.isNotEmpty) Text('Decks', style: Theme.of(context).textTheme.titleSmall),
                      for (final d in decks)
                        Card(
                          shape: cardShape(context, r: 16),
                          child: ListTile(
                            leading: DeckBadge(d, size: 40),
                            title: highlight(context, d.name, _q, style: bold),
                            subtitle: Text('${d.cards.length} cards'),
                            onTap: () => Navigator.push(context, fadeRoute(DeckScreen(deckId: d.id))),
                          ),
                        ),
                      if (hits.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text('Cards', style: Theme.of(context).textTheme.titleSmall),
                      ],
                      for (final h in hits)
                        Card(
                          shape: cardShape(context, r: 16),
                          child: ListTile(
                            leading: Icon(h.$1.iconValue),
                            title: highlight(context, h.$2.front, _q, style: bold, maxLines: 2),
                            subtitle: highlight(context, h.$2.back, _q, maxLines: 2),
                            trailing: Text(h.$1.name, style: Theme.of(context).textTheme.bodySmall),
                            onTap: () => Navigator.push(context, fadeRoute(DeckScreen(deckId: h.$1.id))),
                          ),
                        ),
                    ]),
        ),
      ),
    );
  }
}

// ======================= SECTION 13: STATS ===========================

class StatsScreen extends StatelessWidget {
  const StatsScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final big = Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800);
        Widget tile(double w, IconData i, int n, String label) => SizedBox(
              width: w,
              child: Card(
                margin: EdgeInsets.zero,
                shape: cardShape(context),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(children: [
                    Icon(i, size: 30),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        CountUp(n, style: big),
                        Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
                      ]),
                    ),
                  ]),
                ),
              ),
            );
        final total = store.totalCards;
        final overall = total == 0 ? 0.0 : store.knownCards / total;
        return Scaffold(
          appBar: AppBar(title: const Text('Statistics')),
          body: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 900),
              child: LayoutBuilder(builder: (context, box) {
                final w = (math.min(box.maxWidth, 900) - 32 - 12) / 2;
                return ListView(padding: const EdgeInsets.all(16), children: [
                  Wrap(spacing: 12, runSpacing: 12, children: [
                    tile(w, Icons.style, store.decks.length, 'Decks'),
                    tile(w, Icons.layers, total, 'Cards'),
                    tile(w, Icons.check_circle, store.knownCards, 'Mastered'),
                    tile(w, Icons.local_fire_department, store.streak, 'Day streak'),
                  ]),
                  const SizedBox(height: 20),
                  Center(
                      child: ProgressRing(
                          value: overall, color: Theme.of(context).colorScheme.primary, size: 150, stroke: 14)),
                  const Center(child: Padding(padding: EdgeInsets.all(8), child: Text('Overall mastery'))),
                  const SizedBox(height: 12),
                  Text('Decks', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  if (store.decks.isEmpty) const Text('No decks yet.'),
                  for (final d in store.decks)
                    Card(
                      shape: cardShape(context, r: 16),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Row(children: [
                            Icon(d.iconValue),
                            const SizedBox(width: 8),
                            Expanded(
                                child: Text(d.name,
                                    style: const TextStyle(fontWeight: FontWeight.bold),
                                    overflow: TextOverflow.ellipsis)),
                            Text(d.best >= 0 ? 'Best quiz ${d.best}%' : 'No quiz yet'),
                          ]),
                          const SizedBox(height: 8),
                          TweenAnimationBuilder<double>(
                            tween: Tween<double>(begin: 0, end: d.mastery),
                            duration: dur(context, 800),
                            curve: Curves.easeOutCubic,
                            builder: (_, v, __) => LinearProgressIndicator(
                                value: v, minHeight: 12, borderRadius: BorderRadius.circular(8)),
                          ),
                          const SizedBox(height: 4),
                          Text('${(d.mastery * 100).round()}% mastered'),
                        ]),
                      ),
                    ),
                ]);
              }),
            ),
          ),
        );
      },
    );
  }
}

// ======================= SECTION 14: SETTINGS ========================

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) => Scaffold(
        appBar: AppBar(title: const Text('Settings')),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 700),
            child: ListView(padding: const EdgeInsets.all(16), children: [
              Text('Theme', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              SegmentedButton<ThemeMode>(
                segments: const [
                  ButtonSegment(value: ThemeMode.light, icon: Icon(Icons.light_mode), label: Text('Light')),
                  ButtonSegment(value: ThemeMode.dark, icon: Icon(Icons.dark_mode), label: Text('Dark')),
                  ButtonSegment(value: ThemeMode.system, icon: Icon(Icons.brightness_auto), label: Text('System')),
                ],
                selected: {store.themeMode},
                onSelectionChanged: (s) => store.setTheme(s.first),
              ),
              const SizedBox(height: 24),
              Card(
                shape: cardShape(context, r: 16),
                child: ListTile(
                  leading: const Icon(Icons.restart_alt),
                  title: const Text('Reset to sample data'),
                  subtitle: const Text('Replaces all decks with the 3 sample decks'),
                  onTap: () async {
                    if (await confirm(context, 'Reset data?', 'All your decks and cards will be replaced.',
                            ok: 'Reset') &&
                        context.mounted) {
                      store.resetSample();
                      toast(context, 'Sample data restored');
                    }
                  },
                ),
              ),
              Card(
                shape: cardShape(context, r: 16),
                child: ListTile(
                  leading: const Icon(Icons.delete_forever),
                  title: const Text('Clear all data'),
                  subtitle: const Text('Deletes every deck, card and statistic'),
                  onTap: () async {
                    if (await confirm(context, 'Clear everything?', 'This cannot be undone.', ok: 'Clear') &&
                        context.mounted) {
                      store.clearAll();
                      toast(context, 'All data cleared');
                    }
                  },
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}