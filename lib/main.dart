import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:liquid_glass_easy/liquid_glass_easy.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:telegram_nav_bar/telegram_nav_bar.dart' as tg_nav;
import 'package:frost_nav_bar/frost_nav_bar.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:video_player/video_player.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:camera/camera.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' hide ThumbnailSize;
import 'package:file_selector/file_selector.dart';
import 'package:photo_manager/photo_manager.dart';

// ═══════════════════════════════════════════════════════════════
// Если видишь [permission-denied] — открой Firebase Console →
// Realtime Database → Rules и вставь правила из конца файла
// (или из сообщения ассистента).
// ═══════════════════════════════════════════════════════════════

class SLineColors {
  // dark — более глубокий, «премиум»
  static const dBg = Color(0xFF0B0F14);
  static const dPanel = Color(0xFF12181F);
  static const dHover = Color(0xFF1A222D);
  static const dText = Color(0xFFF5F7FA);
  static const dMuted = Color(0xFF8A96A8);
  static const dInput = Color(0xFF171E28);
  static const dBubble = Color(0xFF1C2430);
  // light
  static const lBg = Color(0xFFF2F4F8);
  static const lPanel = Color(0xFFFFFFFF);
  static const lHover = Color(0xFFEBEEF3);
  static const lText = Color(0xFF111827);
  static const lMuted = Color(0xFF6B7280);
  static const lInput = Color(0xFFF3F5F8);
  static const lBubble = Color(0xFFE9EDF4);

  static const accentA = Color(0xFF4F8CFF);
  static const accentB = Color(0xFF7B6CFF);
  static const mint = Color(0xFF2DD4BF);
  static const danger = Color(0xFFFF5C7A);
}

/// Стекло на всех платформах (Telegram-like)
bool get slineGlass => true;

/// Заголовки для CDN (catbox/B2 часто режут клиент без UA)
const Map<String, String> kMediaHeaders = {
  'User-Agent':
      'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/121.0.0.0 Mobile Safari/537.36',
  'Accept': '*/*',
  'Accept-Language': 'en-US,en;q=0.9,ru;q=0.8',
  'Referer': 'https://catbox.moe/',
};

Future<File> downloadMediaToTemp(String url, {String? extHint}) async {
  // tmpfiles.org: https://tmpfiles.org/123/name → https://tmpfiles.org/dl/123/name
  var fixed = url.trim();
  // Private B2 (с веба) — нужен signed URL
  try {
    if (B2Storage.isB2Url(fixed)) {
      fixed = await B2Storage.resolveDownloadUrl(fixed);
    }
  } catch (_) {}
  if (fixed.contains('tmpfiles.org/') && !fixed.contains('tmpfiles.org/dl/')) {
    fixed = fixed.replaceFirst('tmpfiles.org/', 'tmpfiles.org/dl/');
  }
  // litterbox иногда отдаёт litter.catbox.moe / litterbox.catbox.moe
  final candidates = <String>{fixed};
  if (fixed.contains('litter.catbox.moe')) {
    candidates.add(fixed.replaceFirst('litter.catbox.moe', 'litterbox.catbox.moe'));
  }
  if (fixed.contains('litterbox.catbox.moe')) {
    candidates.add(fixed.replaceFirst('litterbox.catbox.moe', 'litter.catbox.moe'));
  }
  // files.catbox.moe ↔ catbox.moe
  if (fixed.contains('files.catbox.moe')) {
    candidates.add(fixed.replaceFirst('files.catbox.moe', 'catbox.moe'));
  }

  Object? lastErr;
  http.Response? res;

  // Несколько попыток: catbox/CDN часто рвут соединение (errno 104)
  final attempts = <Map<String, String>>[
    {
      'User-Agent':
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/121.0.0.0 Safari/537.36',
      'Accept': 'image/avif,image/webp,image/apng,image/*,*/*;q=0.8',
    },
    Map<String, String>.from(kMediaHeaders),
    {
      'User-Agent': 'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36',
      'Accept': '*/*',
      'Referer': 'https://litterbox.catbox.moe/',
    },
    {
      'User-Agent': 'Mozilla/5.0',
      'Accept': '*/*',
      'Referer': 'https://catbox.moe/',
    },
    {}, // без заголовков
  ];

  outer:
  for (final cand in candidates) {
    final uri = Uri.parse(cand);
    for (var i = 0; i < attempts.length; i++) {
      try {
        res = await http
            .get(uri, headers: attempts[i].isEmpty ? null : attempts[i])
            .timeout(const Duration(seconds: 25));
        if (res.statusCode >= 200 &&
            res.statusCode < 300 &&
            res.bodyBytes.isNotEmpty) {
          break outer;
        }
        lastErr = 'HTTP ${res.statusCode}';
        res = null;
      } catch (e) {
        lastErr = e;
        res = null;
        await Future<void>.delayed(Duration(milliseconds: 150 * (i + 1)));
      }
    }
  }

  if (res == null ||
      res.statusCode < 200 ||
      res.statusCode >= 300 ||
      res.bodyBytes.isEmpty) {
    throw Exception('Скачивание: $lastErr');
  }

  var ext = extHint ?? 'bin';
  final path = url.toLowerCase();
  if (path.contains('.jpg') || path.contains('.jpeg')) {
    ext = 'jpg';
  } else if (path.contains('.png')) {
    ext = 'png';
  } else if (path.contains('.webp')) {
    ext = 'webp';
  } else if (path.contains('.gif')) {
    ext = 'gif';
  } else if (path.contains('.mp4')) {
    ext = 'mp4';
  } else if (path.contains('.webm')) {
    ext = 'webm';
  } else if (path.contains('.m4a')) {
    ext = 'm4a';
  } else if (path.contains('.mp3')) {
    ext = 'mp3';
  } else if (path.contains('.ogg')) {
    ext = 'ogg';
  } else {
    final ct = (res.headers['content-type'] ?? '').toLowerCase();
    if (ct.contains('jpeg')) {
      ext = 'jpg';
    } else if (ct.contains('png')) {
      ext = 'png';
    } else if (ct.contains('gif')) {
      ext = 'gif';
    } else if (ct.contains('mp4')) {
      ext = 'mp4';
    } else if (ct.contains('webm')) {
      ext = 'webm';
    } else if (ct.contains('audio')) {
      ext = 'm4a';
    }
  }
  final dir = await getTemporaryDirectory();
  final f =
      File('${dir.path}/sl_${DateTime.now().millisecondsSinceEpoch}.$ext');
  await f.writeAsBytes(res.bodyBytes, flush: true);
  return f;
}

/// Картинка с headers (catbox и др.)
class SLineNetImage extends StatelessWidget {
  final String url;
  final double? width;
  final double? height;
  final BoxFit fit;
  final Widget Function(BuildContext, Object, StackTrace?)? errorBuilder;
  const SLineNetImage({
    super.key,
    required this.url,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.errorBuilder,
  });

  @override
  Widget build(BuildContext context) {
    final u = normalizeMediaUrl(url);
    // SVG data URI — Flutter Image.memory не рендерит SVG
    if (u.startsWith('data:image/svg') ||
        u.contains('data:image/svg+xml')) {
      return SizedBox(
        width: width ?? 120,
        height: height ?? 120,
        child: errorBuilder?.call(context, 'svg', null) ??
            const Icon(Icons.image_not_supported_outlined),
      );
    }
    if (u.startsWith('data:image')) {
      try {
        final comma = u.indexOf(',');
        if (comma < 0) throw Exception('bad data uri');
        final payload = u.substring(comma + 1);
        final meta = u.substring(0, comma).toLowerCase();
        final bytes = meta.contains(';base64')
            ? base64Decode(payload)
            : Uint8List.fromList(payload.codeUnits);
        return Image.memory(bytes,
            width: width, height: height, fit: fit,
            errorBuilder: errorBuilder);
      } catch (e) {
        return errorBuilder?.call(context, e, null) ??
            const Icon(Icons.broken_image);
      }
    }
    final headers = <String, String>{
      'User-Agent':
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/121.0.0.0 Safari/537.36',
      'Accept': 'image/avif,image/webp,image/apng,image/*,*/*;q=0.8',
    };
    final low = u.toLowerCase();
    if (low.contains('catbox')) {
      headers['Referer'] = 'https://catbox.moe/';
    } else if (low.contains('giphy.com') || low.contains('tenor.com')) {
      headers['Referer'] = 'https://giphy.com/';
    }
    return Image.network(
      u,
      width: width,
      height: height,
      fit: fit,
      headers: headers,
      gaplessPlayback: true,
      filterQuality: FilterQuality.medium,
      errorBuilder: errorBuilder ??
          (_, __, ___) => const Icon(Icons.broken_image),
      loadingBuilder: (c, child, p) {
        if (p == null) return child;
        return SizedBox(
          width: width ?? 120,
          height: height ?? 120,
          child: const Center(
              child: CircularProgressIndicator(strokeWidth: 2)),
        );
      },
    );
  }
}

/// Скачивает медиа на диск (tmpfiles/catbox/B2), потом показывает — надёжнее Image.network
class _DlImage extends StatefulWidget {
  final String url;
  final double? width;
  final double? height;
  final BoxFit fit;
  final Widget Function(BuildContext, Object, StackTrace?)? errorBuilder;
  const _DlImage({
    required this.url,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.errorBuilder,
  });
  @override
  State<_DlImage> createState() => _DlImageState();
}

class _DlImageState extends State<_DlImage> {
  File? _file;
  Object? _err;
  bool _loading = true;
  String? _resolvedUrl;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant _DlImage old) {
    super.didUpdateWidget(old);
    if (old.url != widget.url) _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _err = null;
      _file = null;
    });
    final u = normalizeMediaUrl(widget.url);
    if (u.startsWith('data:image/svg') ||
        u.contains('data:image/svg+xml')) {
      if (mounted) {
        setState(() {
          _loading = false;
          _err = 'svg';
        });
      }
      return;
    }
    if (u.startsWith('data:image')) {
      try {
        final comma = u.indexOf(',');
        if (comma < 0) throw Exception('bad data uri');
        final bytes = base64Decode(u.substring(comma + 1));
        final dir = await getTemporaryDirectory();
        final f = File(
            '${dir.path}/img_${DateTime.now().millisecondsSinceEpoch}.jpg');
        await f.writeAsBytes(bytes, flush: true);
        if (mounted) {
          setState(() {
            _file = f;
            _loading = false;
          });
        }
      } catch (e) {
        if (mounted) {
          setState(() {
            _err = e;
            _loading = false;
          });
        }
      }
      return;
    }
    if (!u.startsWith('http')) {
      final f = File(u);
      if (await f.exists()) {
        if (mounted) {
          setState(() {
            _file = f;
            _loading = false;
          });
        }
        return;
      }
    }
    try {
      var fetchUrl = u;
      if (B2Storage.isB2Url(u)) {
        fetchUrl = await B2Storage.resolveDownloadUrl(u);
      }
      if (mounted) setState(() => _resolvedUrl = fetchUrl);
      final f = await downloadMediaToTemp(fetchUrl, extHint: 'jpg');
      if (mounted) {
        setState(() {
          _file = f;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _err = e;
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return SizedBox(
        width: widget.width ?? 120,
        height: widget.height ?? 120,
        child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    if (_err != null || _file == null) {
      // Fallback: прямая загрузка через Image.network (B2 — signed URL)
      final u = (_resolvedUrl ?? widget.url).trim();
      if (u.startsWith('http')) {
        return Image.network(
          u,
          width: widget.width,
          height: widget.height,
          fit: widget.fit,
          headers: {
            'User-Agent':
                'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/121.0.0.0 Safari/537.36',
            'Accept': 'image/*,*/*;q=0.8',
            'Referer': u.contains('litter')
                ? 'https://litterbox.catbox.moe/'
                : 'https://catbox.moe/',
          },
          errorBuilder: widget.errorBuilder ??
              (_, __, ___) => const Icon(Icons.broken_image),
          loadingBuilder: (c, child, p) {
            if (p == null) return child;
            return SizedBox(
              width: widget.width ?? 120,
              height: widget.height ?? 120,
              child: const Center(
                  child: CircularProgressIndicator(strokeWidth: 2)),
            );
          },
        );
      }
      return widget.errorBuilder?.call(context, _err ?? 'err', null) ??
          const Icon(Icons.broken_image);
    }
    return Image.file(
      _file!,
      width: widget.width,
      height: widget.height,
      fit: widget.fit,
      errorBuilder: widget.errorBuilder ??
          (_, __, ___) => const Icon(Icons.broken_image),
    );
  }
}

class SLineGlass extends StatelessWidget {
  final Widget child;
  final double blur;
  final BorderRadius? radius;
  final Color? tint;
  final Border? border;
  /// true = liquid_glass_easy (рефракция / frost как TG iOS)
  final bool liquid;
  const SLineGlass({
    super.key,
    required this.child,
    this.blur = 22,
    this.radius,
    this.tint,
    this.border,
    this.liquid = true,
  });

  @override
  Widget build(BuildContext context) {
    final r = radius ?? BorderRadius.circular(16);
    final isLight = themeCtrl.light;
    final base = tint ??
        (isLight
            ? Colors.white.withValues(alpha: 0.18)
            : const Color(0xFF1C1C1E).withValues(alpha: 0.22));
    final corner = r.topLeft.x > 0 ? r.topLeft.x : 16.0;
    final rim = isLight
        ? Colors.white.withValues(alpha: 0.55)
        : Colors.white.withValues(alpha: 0.16);

    if (liquid) {
      return ClipRRect(
        borderRadius: r,
        child: LiquidGlassLens(
          style: LiquidGlassStyle(
            shape: LiquidGlassShape.continuousRoundedRectangle(
              cornerRadius: corner,
            ),
            appearance: LiquidGlassAppearance(
              color: base,
              saturation: isLight ? 1.1 : 1.15,
              blur: LiquidGlassBlur(sigmaX: 2.2, sigmaY: 2.2),
            ),
            refraction: LiquidGlassRefraction(
              refractionType: OpticalRefraction(
                refraction: 1.5,
                refractionWidth: 24,
                depth: 0.7,
              ),
            ),
          ),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: r,
              border: border ?? Border.all(color: rim, width: 0.65),
            ),
            child: child,
          ),
        ),
      );
    }

    // fallback без пакета
    return ClipRRect(
      borderRadius: r,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: Container(
          decoration: BoxDecoration(
            color: base,
            borderRadius: r,
            border: border ?? Border.all(color: rim, width: 0.6),
          ),
          child: child,
        ),
      ),
    );
  }
}


/// Нижняя панель 1в1 Telegram iOS:
/// - настоящее размытие (BackdropFilter)
/// - капсула едет за пальцем (drag)
/// - при ведении капсула уже и выше
/// - spring + haptic
/// Нижняя панель: liquid_glass_widgets — узкая овальная капсула, без поиска
class _TgIosBottomBar extends StatelessWidget {
  final int index;
  final ValueChanged<int> onChanged;
  final Map<int, int> badges;
  const _TgIosBottomBar({
    required this.index,
    required this.onChanged,
    this.badges = const {},
  });

  static const _items = <(IconData, String)>[
    (Icons.person_rounded, 'Контакты'),
    (Icons.phone_rounded, 'Звонки'),
    (Icons.chat_bubble_rounded, 'Чаты'),
    (Icons.settings_rounded, 'Настройки'),
  ];

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final mq = MediaQuery.of(context);
    final isTablet = mq.size.shortestSide >= 600;
    final barH = isTablet ? 46.0 : 50.0;
    final bottomInset = mq.padding.bottom;
    // Уже по ширине: не на весь экран, по центру
    final maxW = isTablet ? 420.0 : mq.size.width * 0.92;
    final sidePad = ((mq.size.width - maxW) / 2).clamp(8.0, 40.0);

    return Padding(
      padding: EdgeInsets.fromLTRB(sidePad, 0, sidePad, 4),
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxW, maxHeight: barH + 6),
          child: SizedBox(
            height: barH + 4,
            width: maxW,
            child: GlassTabBar.bottom(
              selectedIndex: index.clamp(0, _items.length - 1),
              onTabSelected: (i) {
                HapticFeedback.selectionClick();
                onChanged(i);
              },
              tabs: [
                for (var i = 0; i < _items.length; i++)
                  GlassTab(
                    icon: Icon(_items[i].$1, size: isTablet ? 18 : 20),
                    label: _items[i].$2,
                  ),
              ],
              barHeight: barH,
              horizontalPadding: isTablet ? 12 : 4,
              verticalPadding: 2,
              showIndicator: true,
              indicatorPinchStrength: 0.55,
              selectedIconColor: SLineColors.accentA,
              unselectedIconColor: const Color(0xFF8E8E93),
              selectedLabelColor: SLineColors.accentA,
              unselectedLabelColor: const Color(0xFF8E8E93),
            ),
          ),
        ),
      ),
    );
  }
}

String dmPairKey(String a, String b) {
  final ids = [a, b]..sort();
  return '${ids[0]}_${ids[1]}';
}

/// Синхронизация списка чатов после отправки / входящего сообщения
class ChatListSync {
  static final ValueNotifier<String?> lastChatKey = ValueNotifier<String?>(null);

  /// Пишет чат в user_chat_index (свой всегда; собеседника — если rules позволяют)
  static Future<void> ensureIndexed({
    required String myUid,
    required String chatKey,
    String? peerUid,
  }) async {
    try {
      await FirebaseDatabase.instance
          .ref('user_chat_index/$myUid/$chatKey')
          .set(true);
    } catch (_) {}
    if (peerUid != null &&
        peerUid.isNotEmpty &&
        peerUid != myUid &&
        !chatKey.startsWith('g_') &&
        !chatKey.startsWith('c_')) {
      try {
        await FirebaseDatabase.instance
            .ref('user_chat_index/$peerUid/$chatKey')
            .set(true);
      } catch (_) {}
    }
    lastChatKey.value = chatKey;
  }
}

DatabaseReference profilesRef() =>
    FirebaseDatabase.instance.ref('tables/profiles');
DatabaseReference chatMsgsRef(String key) =>
    FirebaseDatabase.instance.ref('chat_msgs/$key');

/// Глобальная тема
class ThemeController extends ChangeNotifier {
  bool light = true; // светлая тема по умолчанию
  Color bubbleMeA = SLineColors.accentA;
  Color bubbleMeB = SLineColors.accentB;
  Color? chatWallpaper; // null = стандартный фон
  int wallpaperIndex = 0;

  /// Обои как на вебе (градиенты + сплошные)
  static const wallpapers = <Color?>[
    null,
    Color(0xFFE8F0FE), // светло-синий
    Color(0xFFFCE8E6), // розовый
    Color(0xFFE6F4EA), // зелёный
    Color(0xFFF3E8FD), // фиолетовый
    Color(0xFFFFF8E1), // жёлтый
    Color(0xFFE0F7FA), // бирюза
    Color(0xFF1E293B), // slate (как grad web)
    Color(0xFF312E81), // indigo
    Color(0xFF164E63), // cyan dark
    Color(0xFF7C2D12), // orange dark
    Color(0xFF365314), // lime dark
    Color(0xFF0F172A), // deep
  ];

  static const wallpaperGrads = <List<Color>?>[
    null,
    [Color(0xFFE8F0FE), Color(0xFFD2E3FC)],
    [Color(0xFFFCE8E6), Color(0xFFFAD2CF)],
    [Color(0xFFE6F4EA), Color(0xFFCEEAD6)],
    [Color(0xFFF3E8FD), Color(0xFFE9D2FD)],
    [Color(0xFFFFF8E1), Color(0xFFFFECB3)],
    [Color(0xFFE0F7FA), Color(0xFFB2EBF2)],
    [Color(0xFF1E293B), Color(0xFF0F172A)],
    [Color(0xFF312E81), Color(0xFF1E1B4B)],
    [Color(0xFF164E63), Color(0xFF083344)],
    [Color(0xFF7C2D12), Color(0xFF431407)],
    [Color(0xFF365314), Color(0xFF1A2E05)],
    [Color(0xFF0F172A), Color(0xFF1E293B)],
  ];

  List<Color>? get wallpaperGradient {
    final i = wallpaperIndex.clamp(0, wallpaperGrads.length - 1);
    return wallpaperGrads[i];
  }

  void toggle() {
    light = !light;
    notifyListeners();
  }

  void setBubbleColors(Color a, Color b) {
    bubbleMeA = a;
    bubbleMeB = b;
    notifyListeners();
  }

  void setWallpaper(int index) {
    wallpaperIndex = index.clamp(0, wallpapers.length - 1);
    chatWallpaper = wallpapers[wallpaperIndex];
    notifyListeners();
  }

  Color get bg => light ? SLineColors.lBg : SLineColors.dBg;
  Color get panel => light ? SLineColors.lPanel : SLineColors.dPanel;
  Color get hover => light ? SLineColors.lHover : SLineColors.dHover;
  Color get text => light ? SLineColors.lText : SLineColors.dText;
  Color get muted => light ? SLineColors.lMuted : SLineColors.dMuted;
  Color get input => light ? SLineColors.lInput : SLineColors.dInput;
  Color get bubbleThem => light ? SLineColors.lBubble : SLineColors.dBubble;
  Color get line =>
      light ? const Color(0x14000000) : const Color(0x1AFFFFFF);
  Color get chatBg => chatWallpaper ?? bg;
}

final themeCtrl = ThemeController();

// ── Backblaze B2 через Cloudflare Worker (как на веб-версии SLine) ──
// Ключи B2 НЕ лежат в клиенте — их выдаёт прокси Worker.
// PROXY: https://old-band-f00b.dimasik-228-dima-super.workers.dev
class B2Storage {
  static const proxyUrl =
      'https://old-band-f00b.dimasik-228-dima-super.workers.dev';
  static const bucketName = 'sline-media';

  static String? _authToken;
  static String? _apiUrl;
  static String? _downloadUrl;
  static String? _uploadUrl;
  static String? _uploadAuth;
  static String? _accountId;
  static String? _bucketId;
  static String _bucket = bucketName;
  static DateTime? _authAt;
  static final Map<String, (String, DateTime)> _dlCache = {};

  /// Получить upload URL + auth через Cloudflare Worker (как на вебе).
  static Future<void> _authorize() async {
    if (_uploadUrl != null &&
        _authAt != null &&
        DateTime.now().difference(_authAt!) < const Duration(minutes: 45)) {
      return;
    }
    String idToken = '';
    try {
      final u = FirebaseAuth.instance.currentUser;
      if (u != null) idToken = await u.getIdToken() ?? '';
    } catch (_) {}

    final res = await http
        .post(
          Uri.parse('$proxyUrl/api/b2/upload-url'),
          headers: {
            'Content-Type': 'application/json',
            if (idToken.isNotEmpty) 'Authorization': 'Bearer $idToken',
          },
        )
        .timeout(const Duration(seconds: 20));

    if (res.statusCode != 200) {
      throw Exception('B2 proxy ${res.statusCode}: ${res.body}');
    }
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    _apiUrl = data['apiUrl'] as String?;
    _authToken = data['authorizationToken'] as String?;
    _downloadUrl = data['downloadUrl'] as String?;
    _uploadUrl = data['uploadUrl'] as String?;
    _uploadAuth = (data['uploadAuthorizationToken'] ??
        data['authorizationToken']) as String?;
    _accountId = (data['accountId'] ?? data['account_id'])?.toString();
    if (data['bucketName'] != null) _bucket = data['bucketName'].toString();
    if (data['bucketId'] != null) _bucketId = data['bucketId'].toString();
    _authAt = DateTime.now();
    if (_uploadUrl == null || _uploadAuth == null) {
      throw Exception('B2 proxy: нет uploadUrl');
    }
  }

  static Future<String?> _resolveBucketId() async {
    if (_bucketId != null) return _bucketId;
    await _authorize();
    if (_apiUrl == null || _authToken == null) return null;
    if (_accountId == null) return null;
    try {
      final res = await http
          .post(
            Uri.parse('$_apiUrl/b2api/v2/b2_list_buckets'),
            headers: {
              'Authorization': _authToken!,
              'Content-Type': 'application/json',
            },
            body: jsonEncode({'accountId': _accountId}),
          )
          .timeout(const Duration(seconds: 15));
      if (res.statusCode != 200) return null;
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final buckets = (data['buckets'] as List?) ?? [];
      Map? found;
      for (final b in buckets) {
        if (b is Map && b['bucketName'] == _bucket) {
          found = b;
          break;
        }
      }
      if (found == null && buckets.isNotEmpty && buckets.first is Map) {
        found = buckets.first as Map;
      }
      if (found == null) return null;
      _bucketId = found['bucketId']?.toString();
      if (found['bucketName'] != null) {
        _bucket = found['bucketName'].toString();
      }
      return _bucketId;
    } catch (_) {
      return null;
    }
  }

  /// Из URL B2 достаём имя файла: .../file/sline-media/path/to/file.jpg
  static String? _fileNameFromUrl(String url) {
    final u = url.trim();
    final markers = [
      '/file/$_bucket/',
      '/file/$bucketName/',
      '/file/sline-media/',
      '/file/',
    ];
    for (final m in markers) {
      final i = u.indexOf(m);
      if (i >= 0) {
        var name = u.substring(i + m.length);
        final q = name.indexOf('?');
        if (q >= 0) name = name.substring(0, q);
        try {
          name = Uri.decodeFull(name);
        } catch (_) {}
        if (name.isNotEmpty) return name;
      }
    }
    return null;
  }

  static bool isB2Url(String url) {
    final low = url.toLowerCase();
    return low.contains('backblazeb2.com') ||
        low.contains('backblaze.com') ||
        low.contains('/file/sline-media/') ||
        low.contains('/file/${_bucket.toLowerCase()}/') ||
        low.contains('sline-media');
  }

  /// Private B2 → временный signed URL через Cloudflare Worker
  static Future<String> resolveDownloadUrl(String url) async {
    final raw = url.trim();
    if (raw.isEmpty || !raw.startsWith('http')) return raw;
    if (!isB2Url(raw)) return raw;
    // Уже с Authorization=
    if (raw.contains('Authorization=')) return raw;

    final cached = _dlCache[raw];
    if (cached != null &&
        DateTime.now().isBefore(cached.$2.subtract(const Duration(minutes: 5)))) {
      return cached.$1;
    }

    final fileName = _fileNameFromUrl(raw);
    try {
      String idToken = '';
      try {
        final u = FirebaseAuth.instance.currentUser;
        if (u != null) idToken = await u.getIdToken() ?? '';
      } catch (_) {}

      final res = await http
          .post(
            Uri.parse('$proxyUrl/api/b2/download-url'),
            headers: {
              'Content-Type': 'application/json',
              if (idToken.isNotEmpty) 'Authorization': 'Bearer $idToken',
            },
            body: jsonEncode({
              'url': raw,
              if (fileName != null) 'fileName': fileName,
            }),
          )
          .timeout(const Duration(seconds: 20));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final signed = (data['url'] ?? '').toString();
        if (signed.startsWith('http')) {
          _dlCache[raw] =
              (signed, DateTime.now().add(const Duration(days: 6)));
          return signed;
        }
      }
    } catch (_) {}
    return raw;
  }

  static Future<String> uploadFile(File file, String folder, String uid) async {
    Object? lastErr;
    // 1) B2 через Cloudflare proxy
    try {
      return await _uploadB2(file, folder, uid)
          .timeout(const Duration(seconds: 25));
    } catch (e) {
      lastErr = e;
    }
    // 2) публичные хосты (catbox / 0x0 / litterbox / gofile / tmpfiles)
    try {
      final url = await MediaFallbacks.upload(file)
          .timeout(const Duration(seconds: 30));
      if (url != null && url.startsWith('http')) return url;
    } catch (e) {
      lastErr = e;
    }
    throw Exception('Не удалось загрузить файл. $lastErr');
  }

  /// Аватарка: B2 → public hosts → data:image (всегда что-то сохранится)
  static Future<String> uploadAvatar(File file, String uid) async {
    try {
      return await uploadFile(file, 'avatars', uid)
          .timeout(const Duration(seconds: 35));
    } catch (_) {}
    // Fallback: base64 data URL (для маленьких JPEG из picker quality:70)
    final bytes = await file.readAsBytes();
    if (bytes.length > 180000) {
      throw Exception(
          'Файл слишком большой для офлайн-загрузки. Проверьте интернет.');
    }
    final b64 = base64Encode(bytes);
    final mime = file.path.toLowerCase().endsWith('.png')
        ? 'image/png'
        : 'image/jpeg';
    return 'data:$mime;base64,$b64';
  }

  static Future<String> _uploadB2(File file, String folder, String uid) async {
    await _authorize();
    final bytes = await file.readAsBytes();
    final sha = sha1.convert(bytes).toString();
    var ext = file.path.contains('.')
        ? file.path.split('.').last.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '')
        : 'bin';
    if (folder.contains('circle') || folder.contains('video')) {
      if (ext.isEmpty || ext == 'bin' || ext.length > 5) ext = 'mp4';
    }
    if (folder.contains('voice') && (ext == 'bin' || ext.isEmpty)) ext = 'm4a';
    if (folder.contains('avatar') &&
        (ext == 'bin' || ext.isEmpty || ext.length > 5)) {
      ext = 'jpg';
    }
    final name =
        '$folder/$uid/${DateTime.now().millisecondsSinceEpoch}_${sha.substring(0, 8)}.$ext';
    final encodedName =
        name.split('/').map(Uri.encodeComponent).join('/');

    String contentType = 'application/octet-stream';
    final low = file.path.toLowerCase();
    if (low.endsWith('.jpg') || low.endsWith('.jpeg')) {
      contentType = 'image/jpeg';
    } else if (low.endsWith('.png')) {
      contentType = 'image/png';
    } else if (low.endsWith('.gif')) {
      contentType = 'image/gif';
    } else if (low.endsWith('.webp')) {
      contentType = 'image/webp';
    } else if (low.endsWith('.mp4') ||
        low.endsWith('.mov') ||
        folder.contains('circle') ||
        folder.contains('video')) {
      contentType = 'video/mp4';
    } else if (low.endsWith('.webm')) {
      contentType = 'video/webm';
    } else if (low.endsWith('.m4a') ||
        low.endsWith('.aac') ||
        folder.contains('voice')) {
      contentType = 'audio/mp4';
    } else if (low.endsWith('.mp3')) {
      contentType = 'audio/mpeg';
    } else if (folder.contains('avatar') || folder.contains('image')) {
      contentType = 'image/jpeg';
    }

    // Retry upload URL once on 401
    for (var attempt = 0; attempt < 2; attempt++) {
      if (attempt > 0) {
        _authAt = null;
        _uploadUrl = null;
        await _authorize();
      }
      final up = await http
          .post(
            Uri.parse(_uploadUrl!),
            headers: {
              'Authorization': _uploadAuth!,
              'X-Bz-File-Name': encodedName,
              'Content-Type': contentType,
              'X-Bz-Content-Sha1': sha,
              'Content-Length': '${bytes.length}',
            },
            body: bytes,
          )
          .timeout(const Duration(seconds: 30));
      if (up.statusCode == 200) {
        final base = _downloadUrl ?? 'https://f005.backblazeb2.com';
        return '$base/file/$bucketName/$name';
      }
      if (up.statusCode == 401 || up.statusCode == 408 || up.statusCode >= 500) {
        continue;
      }
      throw Exception('B2 upload ${up.statusCode}: ${up.body}');
    }
    throw Exception('B2 upload failed after retry');
  }
}

/// Запасные хосты. catbox часто рвёт соединение — пробуем 0x0/litterbox раньше.
class MediaFallbacks {
  static Future<String?> upload(File file) async {
    // tmpfiles часто отдаёт битые ссылки для клиентов — в конце
    for (final fn in [_zeroX0, _litterbox, _gofile, _catbox, _tmpfiles]) {
      try {
        final u = await fn(file).timeout(const Duration(seconds: 18));
        if (u != null && u.startsWith('http')) return u;
      } catch (_) {}
    }
    return null;
  }

  static Future<String?> _catbox(File file) async {
    final req = http.MultipartRequest(
        'POST', Uri.parse('https://catbox.moe/user/api.php'));
    req.fields['reqtype'] = 'fileupload';
    req.files.add(await http.MultipartFile.fromPath('fileToUpload', file.path));
    final res = await req.send().timeout(const Duration(seconds: 15));
    final body =
        await res.stream.bytesToString().timeout(const Duration(seconds: 15));
    if (res.statusCode == 200 && body.trim().startsWith('http')) {
      return body.trim();
    }
    return null;
  }

  static Future<String?> _litterbox(File file) async {
    final req = http.MultipartRequest('POST',
        Uri.parse('https://litterbox.catbox.moe/resources/internals/api.php'));
    req.fields['reqtype'] = 'fileupload';
    req.fields['time'] = '72h';
    req.files.add(await http.MultipartFile.fromPath('fileToUpload', file.path));
    final res = await req.send().timeout(const Duration(seconds: 15));
    final body =
        await res.stream.bytesToString().timeout(const Duration(seconds: 15));
    if (res.statusCode == 200 && body.trim().startsWith('http')) {
      return body.trim();
    }
    return null;
  }

  static Future<String?> _zeroX0(File file) async {
    final req = http.MultipartRequest('POST', Uri.parse('https://0x0.st'));
    req.files.add(await http.MultipartFile.fromPath('file', file.path));
    final res = await req.send().timeout(const Duration(seconds: 15));
    final body =
        await res.stream.bytesToString().timeout(const Duration(seconds: 15));
    if (res.statusCode == 200 && body.trim().startsWith('http')) {
      return body.trim();
    }
    return null;
  }

  static Future<String?> _tmpfiles(File file) async {
    final req = http.MultipartRequest(
        'POST', Uri.parse('https://tmpfiles.org/api/v1/upload'));
    req.files.add(await http.MultipartFile.fromPath('file', file.path));
    final res = await req.send().timeout(const Duration(seconds: 15));
    final body =
        await res.stream.bytesToString().timeout(const Duration(seconds: 15));
    if (res.statusCode != 200) return null;
    try {
      final j = jsonDecode(body) as Map<String, dynamic>;
      var url = (j['data'] as Map?)?['url'] as String?;
      if (url == null) return null;
      url = url.replaceFirst('tmpfiles.org/', 'tmpfiles.org/dl/');
      return url;
    } catch (_) {
      return null;
    }
  }

  static Future<String?> _gofile(File file) async {
    try {
      final srvRes = await http
          .get(Uri.parse('https://api.gofile.io/servers'))
          .timeout(const Duration(seconds: 8));
      if (srvRes.statusCode != 200) return null;
      final sj = jsonDecode(srvRes.body) as Map<String, dynamic>;
      final servers = (sj['data'] as Map?)?['servers'] as List? ?? [];
      if (servers.isEmpty) return null;
      final server = (servers.first as Map)['name'] as String? ?? '';
      if (server.isEmpty) return null;
      final req = http.MultipartRequest(
          'POST', Uri.parse('https://$server.gofile.io/uploadFile'));
      req.files.add(await http.MultipartFile.fromPath('file', file.path));
      final res = await req.send().timeout(const Duration(seconds: 20));
      final body =
          await res.stream.bytesToString().timeout(const Duration(seconds: 15));
      if (res.statusCode != 200) return null;
      final uj = jsonDecode(body) as Map<String, dynamic>;
      if (uj['status'] != 'ok') return null;
      final d = uj['data'] as Map<String, dynamic>?;
      if (d == null) return null;
      final url = (d['directLink'] ?? d['downloadPage']) as String?;
      if (url != null && url.startsWith('http')) return url;
      final fid = d['fileId'] as String?;
      if (fid != null) return 'https://gofile.io/d/$fid';
    } catch (_) {}
    return null;
  }
}


@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // фон: система сама покажет notification payload
}

Future<void> setupPushNotifications(User user) async {
  await oneSignalLogin(user);
  // ntfy как запасной канал, пока приложение открыто
  try {
    await NtfyListener.start(user.uid);
  } catch (_) {}
}


// ── OneSignal (пуши без Firebase Blaze) ──────────────────────
// 1) https://onesignal.com → New App → Google Android
// 2) App ID и REST API Key вставить сюда:
class OneSignalConfig {
  // App ID нужен SDK на клиенте (это не секрет). REST API Key — ТОЛЬКО в Cloudflare Worker.
  static const appId = '2630be0e-9fbd-4750-8d65-b50232a7eb27';
  static const proxyUrl =
      'https://old-band-f00b.dimasik-228-dima-super.workers.dev';
}


/// На переднем плане — только in-app, в фоне — системные пуши
class SLineAppLifecycle {
  static final ValueNotifier<bool> foreground = ValueNotifier<bool>(true);
  static final ValueNotifier<SLineInAppNote?> inAppNote =
      ValueNotifier<SLineInAppNote?>(null);

  static void setForeground(bool v) => foreground.value = v;
  static bool get isForeground => foreground.value;

  static void showInApp(String title, String body, {String? chatKey}) {
    inAppNote.value = SLineInAppNote(
      title: title,
      body: body,
      chatKey: chatKey,
      id: DateTime.now().millisecondsSinceEpoch,
    );
  }

  static void clearInApp() => inAppNote.value = null;
}

class SLineInAppNote {
  final String title;
  final String body;
  final String? chatKey;
  final int id;
  SLineInAppNote({
    required this.title,
    required this.body,
    this.chatKey,
    required this.id,
  });
}

Future<void> initOneSignal() async {
  if (OneSignalConfig.appId.startsWith('YOUR_')) return;
  OneSignal.Debug.setLogLevel(OSLogLevel.warn);
  OneSignal.initialize(OneSignalConfig.appId);
  await OneSignal.Notifications.requestPermission(true);

  // Пока приложение открыто — не показываем системный баннер, только in-app
  try {
    OneSignal.Notifications.addForegroundWillDisplayListener((event) {
      try {
        if (SLineAppLifecycle.isForeground) {
          event.preventDefault();
          final n = event.notification;
          final title = n.title ?? 'SLine';
          final body = n.body ?? '';
          String? chatKey;
          try {
            final data = n.additionalData;
            if (data != null && data['chat_key'] != null) {
              chatKey = data['chat_key'].toString();
            }
          } catch (_) {}
          SLineAppLifecycle.showInApp(title, body, chatKey: chatKey);
        }
        // если в фоне — listener не вызывается, система сама покажет
      } catch (_) {}
    });
  } catch (_) {}
}

Future<void> oneSignalLogin(User user) async {
  if (OneSignalConfig.appId.startsWith('YOUR_')) return;
  try {
    await OneSignal.login(user.uid);
    final subId = OneSignal.User.pushSubscription.id;
    final data = {
      'provider': 'onesignal',
      'onesignal_id': subId,
      'external_id': user.uid,
      'user_id': user.uid,
      'platform': Platform.isIOS ? 'ios' : 'android',
      'updated_at': DateTime.now().toIso8601String(),
    };
    try {
      await FirebaseDatabase.instance.ref('fcm_tokens/${user.uid}').set(data);
    } catch (_) {}
    try {
      await FirebaseDatabase.instance
          .ref('tables/push_subscriptions/${user.uid}')
          .set({...data, 'id': user.uid});
    } catch (_) {}
  } catch (_) {}
}

/// Пуш: OneSignal (основной) + ntfy fallback.
Future<void> enqueuePushNotify({
  required String toUid,
  required String title,
  required String body,
  String? chatKey,
}) async {
  if (toUid.isEmpty) return;

  // 1) OneSignal через Cloudflare Worker (REST key НЕ в клиенте)
  if (!OneSignalConfig.appId.startsWith('YOUR_')) {
    try {
      final user = FirebaseAuth.instance.currentUser;
      final idToken = await user?.getIdToken();
      if (idToken != null && idToken.isNotEmpty) {
        final res = await http.post(
          Uri.parse('${OneSignalConfig.proxyUrl}/api/onesignal/notify'),
          headers: {
            'Content-Type': 'application/json; charset=utf-8',
            'Authorization': 'Bearer $idToken',
          },
          body: jsonEncode({
            'to_uid': toUid,
            'title': title,
            'body': body,
            'chat_key': chatKey ?? '',
          }),
        );
        if (res.statusCode >= 200 && res.statusCode < 300) {
          return;
        }
      }
    } catch (_) {}
  }

  // 2) ntfy fallback
  try {
    await http.post(
      Uri.parse('https://ntfy.sh/sline-$toUid'),
      headers: {
        'Title': 'SLine',
        'Priority': 'high',
        'Tags': 'speech_balloon',
        'Content-Type': 'text/plain; charset=utf-8',
      },
      body: utf8.encode('$title: $body'),
    );
  } catch (_) {}
}

/// Слушатель ntfy (пока приложение открыто / в фоне с частичной поддержкой).
class NtfyListener {
  static http.Client? _client;
  static StreamSubscription<String>? _sub;
  static void Function(String title, String body)? onMessage;

  static Future<void> start(String uid) async {
    await stop();
    final topic = 'sline-$uid';
    _client = http.Client();
    try {
      final req = http.Request(
        'GET',
        Uri.parse('https://ntfy.sh/$topic/json'),
      );
      final res = await _client!.send(req);
      _sub = res.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
        if (line.trim().isEmpty) return;
        try {
          final j = jsonDecode(line) as Map<String, dynamic>;
          if (j['event'] != 'message') return;
          final title = (j['title'] ?? 'SLine').toString();
          final body = (j['message'] ?? '').toString();
          if (SLineAppLifecycle.isForeground) {
            SLineAppLifecycle.showInApp(title, body);
          }
          onMessage?.call(title, body);
        } catch (_) {}
      }, onError: (_) {}, onDone: () {});
    } catch (_) {}
  }

  static Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
    _client?.close();
    _client = null;
  }
}



Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await LiquidGlassShaders.ensureLoaded();
  try { await LiquidGlassWidgets.initialize(); } catch (_) {}
  } catch (_) {}
  try {
    // На Skia/Web — lite (frost), на Impeller — полная рефракция
    LiquidGlassEngine.liteGlassOnSkia = true;
  } catch (_) {}
  String? initError;
  try {
    await Firebase.initializeApp(
      options: const FirebaseOptions(
        apiKey: 'AIzaSyDyF5921HWi5_keJdHXcle6iOWMxccCdU0',
        appId: '1:144193056770:android:37396dd4931fbe7f79771b',
        messagingSenderId: '144193056770',
        projectId: 'sline-chat',
        databaseURL: 'https://sline-chat-default-rtdb.firebaseio.com',
        storageBucket: 'sline-chat.firebasestorage.app',
      ),
    ).timeout(const Duration(seconds: 15),
        onTimeout: () => throw Exception('Firebase timeout'));
  } catch (e) {
    initError = e.toString();
  }
  try {
    await initOneSignal();
  } catch (_) {}
  runApp(LiquidGlassWidgets.wrap(
    child: SLineApp(initError: initError),
    brightnessResolver: Theme.maybeBrightnessOf,
  ));
}

class SLineApp extends StatelessWidget {
  final String? initError;
  const SLineApp({super.key, this.initError});
  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: themeCtrl,
      builder: (_, __) {
        final light = themeCtrl.light;
        SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness:
              light ? Brightness.dark : Brightness.light,
          systemNavigationBarColor: themeCtrl.bg,
        ));
        return MaterialApp(
          title: 'SLine',
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            brightness: light ? Brightness.light : Brightness.dark,
            scaffoldBackgroundColor: themeCtrl.bg,
            primaryColor: SLineColors.accentA,
            fontFamily: null,
            colorScheme: light
                ? ColorScheme.light(
                    primary: SLineColors.accentA,
                    secondary: SLineColors.accentB,
                    surface: themeCtrl.panel,
                  )
                : ColorScheme.dark(
                    primary: SLineColors.accentA,
                    secondary: SLineColors.accentB,
                    surface: themeCtrl.panel,
                  ),
            useMaterial3: true,
            splashFactory: InkSparkle.splashFactory,
            appBarTheme: AppBarTheme(
              backgroundColor: themeCtrl.panel.withValues(alpha: 0.92),
              foregroundColor: themeCtrl.text,
              elevation: 0,
              centerTitle: false,
              titleTextStyle: TextStyle(
                color: themeCtrl.text,
                fontSize: 18,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.2,
              ),
              surfaceTintColor: Colors.transparent,
            ),
            cardTheme: CardThemeData(
              elevation: 0,
              color: themeCtrl.panel,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
            ),
            inputDecorationTheme: InputDecorationTheme(
              filled: true,
              fillColor: themeCtrl.input,
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none),
              enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none),
              focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(
                      color: SLineColors.accentA, width: 1.4)),
              contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 14),
            ),
            elevatedButtonTheme: ElevatedButtonThemeData(
              style: ElevatedButton.styleFrom(
                backgroundColor: SLineColors.accentA,
                foregroundColor: Colors.white,
                elevation: 0,
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
                textStyle: const TextStyle(
                    fontWeight: FontWeight.w700, fontSize: 15),
              ),
            ),
          ),
          home: initError != null
              ? _Err(initError!)
              : const AuthGate(),
        );
      },
    );
  }
}

class _Err extends StatelessWidget {
  final String m;
  const _Err(this.m);
  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
            child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text('Ошибка:\n$m',
              textAlign: TextAlign.center,
              style: const TextStyle(color: SLineColors.danger)),
        )),
      );
}

/// Пока true — после пароля ждём код SLine, MainShell не открываем
class SLineAuthLock {
  /// true = ждём код SLine (экран SLineCodeGate)
  static final ValueNotifier<bool> pendingCode = ValueNotifier<bool>(false);
  /// true = не уходим с LoginScreen (диалог резервных кодов после регистрации)
  static final ValueNotifier<bool> holdLogin = ValueNotifier<bool>(false);
}

/// Флаг «нужен код» в RTDB — переживает перезапуск приложения
Future<void> slSetAwaitingLoginCode(String uid, bool awaiting) async {
  try {
    await FirebaseDatabase.instance.ref('sessions/$uid/awaiting_code').set(
      awaiting
          ? {
              'v': true,
              'at': DateTime.now().millisecondsSinceEpoch,
            }
          : null,
    );
  } catch (_) {}
  SLineAuthLock.pendingCode.value = awaiting;
}

Future<bool> slIsAwaitingLoginCode(String uid) async {
  try {
    final s = await FirebaseDatabase.instance.ref('sessions/$uid/awaiting_code').get();
    if (s.exists && s.value is Map) {
      final m = Map<String, dynamic>.from(s.value as Map);
      if (m['v'] == true) return true;
    }
    if (s.exists && s.value == true) return true;
  } catch (_) {}
  return SLineAuthLock.pendingCode.value;
}


/// Локальный список аккаунтов (переключение как в TG)
class SLineSavedAccount {
  final String uid;
  final String login; // email или phone@synthetic
  final String password;
  final String label;
  final String? avatarUrl;
  SLineSavedAccount({
    required this.uid,
    required this.login,
    required this.password,
    required this.label,
    this.avatarUrl,
  });
  Map<String, dynamic> toJson() => {
        'uid': uid,
        'login': login,
        'password': password,
        'label': label,
        if (avatarUrl != null) 'avatarUrl': avatarUrl,
      };
  factory SLineSavedAccount.fromJson(Map m) => SLineSavedAccount(
        uid: (m['uid'] ?? '').toString(),
        login: (m['login'] ?? '').toString(),
        password: (m['password'] ?? '').toString(),
        label: (m['label'] ?? m['login'] ?? 'Аккаунт').toString(),
        avatarUrl: m['avatarUrl']?.toString(),
      );
}

class SLineAccounts {
  static const _fileName = 'sline_accounts_v1.json';
  static List<SLineSavedAccount> cache = [];

  static Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_fileName');
  }

  static Future<List<SLineSavedAccount>> load() async {
    try {
      final f = await _file();
      if (!await f.exists()) {
        cache = [];
        return cache;
      }
      final raw = jsonDecode(await f.readAsString());
      if (raw is List) {
        cache = raw
            .whereType<Map>()
            .map((e) => SLineSavedAccount.fromJson(Map<String, dynamic>.from(e)))
            .where((a) => a.login.isNotEmpty && a.password.isNotEmpty)
            .toList();
      }
    } catch (_) {
      cache = [];
    }
    return cache;
  }

  static Future<void> save(List<SLineSavedAccount> list) async {
    cache = list;
    try {
      final f = await _file();
      await f.writeAsString(
          jsonEncode(list.map((e) => e.toJson()).toList()),
          flush: true);
    } catch (_) {}
  }

  static Future<void> upsert({
    required String uid,
    required String login,
    required String password,
    String? label,
    String? avatarUrl,
  }) async {
    final list = await load();
    final i = list.indexWhere((a) => a.uid == uid || a.login == login);
    final acc = SLineSavedAccount(
      uid: uid,
      login: login,
      password: password,
      label: label ?? login,
      avatarUrl: avatarUrl,
    );
    if (i >= 0) {
      list[i] = acc;
    } else {
      list.add(acc);
    }
    await save(list);
  }

  static Future<void> removeUid(String uid) async {
    final list = await load();
    list.removeWhere((a) => a.uid == uid);
    await save(list);
  }

  static Future<bool> switchTo(SLineSavedAccount acc) async {
    try {
      SLineAuthLock.holdLogin.value = true;
      SLineAuthLock.pendingCode.value = false;
      try {
        await FirebaseAuth.instance.signOut();
      } catch (_) {}
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: acc.login,
        password: acc.password,
      );
      final u = FirebaseAuth.instance.currentUser;
      if (u != null) {
        await slTouchUserSession(u.uid);
        // код при наличии других сессий
        try {
          if (await slNeedSLineCode(u.uid)) {
            SLineAuthLock.pendingCode.value = true;
          }
        } catch (_) {}
      }
      SLineAuthLock.holdLogin.value = false;
      return true;
    } catch (e) {
      SLineAuthLock.holdLogin.value = false;
      SLineAuthLock.pendingCode.value = false;
      return false;
    }
  }
}


class AuthGate extends StatelessWidget {
  const AuthGate({super.key});
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, s) {
        if (s.connectionState == ConnectionState.waiting) {
          return Scaffold(
              backgroundColor: themeCtrl.bg,
              body: const Center(child: CircularProgressIndicator()));
        }
        // После перезапуска: восстановить pending из RTDB
        if (s.hasData) {
          return FutureBuilder<bool>(
            future: slIsAwaitingLoginCode(s.data!.uid),
            builder: (context, aw) {
              if (aw.connectionState == ConnectionState.waiting) {
                return Scaffold(
                    backgroundColor: themeCtrl.bg,
                    body: const Center(child: CircularProgressIndicator()));
              }
              final mustCode = (aw.data == true) || SLineAuthLock.pendingCode.value;
              if (mustCode) {
                SLineAuthLock.pendingCode.value = true;
                return SLineCodeGate(user: s.data!);
              }
              return ValueListenableBuilder<bool>(
                valueListenable: SLineAuthLock.pendingCode,
                builder: (_, pending, __) {
                  return ValueListenableBuilder<bool>(
                    valueListenable: SLineAuthLock.holdLogin,
                    builder: (_, hold, __) {
                      if (pending) return SLineCodeGate(user: s.data!);
                      if (hold) return const LoginScreen();
                      return MainShell(user: s.data!);
                    },
                  );
                },
              );
            },
          );
        }
        return ValueListenableBuilder<bool>(
          valueListenable: SLineAuthLock.holdLogin,
          builder: (_, hold, __) {
            return const LoginScreen();
          },
        );
      },
    );
  }
}

/// Экран ввода кода из SLine / резервного после пароля
class SLineCodeGate extends StatefulWidget {
  final User user;
  const SLineCodeGate({super.key, required this.user});
  @override
  State<SLineCodeGate> createState() => _SLineCodeGateState();
}

class _SLineCodeGateState extends State<SLineCodeGate> {
  final codeC = TextEditingController();
  bool loading = false;
  String? error;
  String? sentCodeHint;
  bool codeSent = false;

  @override
  void initState() {
    super.initState();
    _sendCode();
  }

  @override
  void dispose() {
    codeC.dispose();
    super.dispose();
  }

  Future<void> _sendCode() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final uid = widget.user.uid;
      await ensureSLineSystemChat(uid);
      // Один код на 5 минут (как на вебе)
      String code;
      try {
        final prev = await FirebaseDatabase.instance
            .ref('sessions/$uid/last_login_code')
            .get();
        final pm = prev.value is Map
            ? Map<String, dynamic>.from(prev.value as Map)
            : null;
        final oldC = (pm?['code'] ?? '').toString();
        final oldTs = int.tryParse('${pm?['ts'] ?? 0}') ?? 0;
        if (oldC.length >= 4 &&
            DateTime.now().millisecondsSinceEpoch - oldTs < 5 * 60 * 1000) {
          code = oldC;
        } else {
          code = (100000 +
                  (DateTime.now().millisecondsSinceEpoch % 900000))
              .toString();
          await FirebaseDatabase.instance
              .ref('sessions/$uid/last_login_code')
              .set({
            'code': code,
            'ts': DateTime.now().millisecondsSinceEpoch,
          });
        }
      } catch (_) {
        code = (100000 +
                (DateTime.now().millisecondsSinceEpoch % 900000))
            .toString();
      }
      try {
        await FirebaseDatabase.instance.ref('pending_login_codes/$uid/$code').set({
          'code': code,
          'created': DateTime.now().millisecondsSinceEpoch,
          'expires': DateTime.now()
              .add(const Duration(minutes: 10))
              .millisecondsSinceEpoch,
        });
      } catch (_) {}
      try {
        await FirebaseDatabase.instance.ref('device_link/$code').set({
          'uid': uid,
          'code': code,
          'created': DateTime.now().millisecondsSinceEpoch,
          'status': 'pending',
          'for_sline': true,
        });
      } catch (_) {}
      // Чат SLine
      try {
        await sendSLineSystemMessage(uid, formatSLineLoginCodeMessage(code));
      } catch (e) {
        try {
          await sendSLineSystemMessage(
            uid,
            'Код для входа в SLine: $code. Не давайте код никому.',
          );
        } catch (_) {}
      }
      // Email (основной или привязанный)
      String? emailHint;
      String? emailErr;
      try {
        final mail = await resolveUserRealEmail(widget.user);
        if (mail == null) {
          emailErr = 'no_email';
        } else {
          final err = await slSendLoginEmailCode(mail, code);
          if (err == null) {
            emailHint = mail;
          } else {
            emailErr = err;
            emailHint = null;
            // сохраняем, чтобы видеть в UI
            try {
              await FirebaseDatabase.instance
                  .ref('email_send_log/${widget.user.uid}')
                  .push()
                  .set({
                'to': mail,
                'error': err,
                'at': DateTime.now().millisecondsSinceEpoch,
              });
            } catch (_) {}
          }
        }
      } catch (e) {
        emailErr = '$e';
      }
      // Telegram @SLineCodesBot — синхронизируем код с тем, что реально в боте
      String? tgHint;
      String? tgErr;
      try {
        var terr = await slSendTelegramCodeViaWorker(code: code, uid: uid);
        if (terr != null && terr.startsWith('SYNC:')) {
          final synced = terr.substring(5);
          code = synced;
          try {
            await FirebaseDatabase.instance
                .ref('pending_login_codes/$uid/$code')
                .set({
              'code': code,
              'created': DateTime.now().millisecondsSinceEpoch,
              'expires': DateTime.now()
                  .add(const Duration(minutes: 10))
                  .millisecondsSinceEpoch,
            });
            await FirebaseDatabase.instance.ref('device_link/$code').set({
              'uid': uid,
              'code': code,
              'created': DateTime.now().millisecondsSinceEpoch,
              'status': 'pending',
              'for_sline': true,
            });
            await FirebaseDatabase.instance
                .ref('sessions/$uid/last_login_code')
                .set({
              'code': code,
              'ts': DateTime.now().millisecondsSinceEpoch,
            });
            await sendSLineSystemMessage(uid, formatSLineLoginCodeMessage(code));
          } catch (_) {}
          terr = null;
          tgHint = 'Telegram';
        } else if (terr == null) {
          tgHint = 'Telegram';
        } else if (terr == 'not_linked') {
          tgErr = 'not_linked';
        } else {
          tgErr = terr;
        }
      } catch (e) {
        tgErr = '$e';
      }
      // уведомление о попытке входа в чат
      try {
        final un = (await loadProfile(uid))?.username ?? 'user';
        await sendSLineSystemMessage(
          uid,
          formatSLineNewDeviceMessage(
            username: un,
            device: 'Android / SLine App',
            place: 'Неизвестно',
          ),
        );
      } catch (_) {}
      if (mounted) {
        setState(() {
          codeSent = true;
          final parts = <String>['Код в чате SLine'];
          if (emailHint != null) parts.add('email $emailHint');
          if (tgHint != null) parts.add('Telegram');
          if (emailErr == 'no_email') {
            /* skip */ }
          else if (emailErr != null) parts.add('email ошибка');
          if (tgErr == 'not_linked') {
            parts.add('TG: откройте t.me/SLineCodesBot?start=${widget.user.uid}');
          } else if (tgErr != null) {
            parts.add('TG ошибка');
          }
          sentCodeHint = parts.join(' · ');
          loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          loading = false;
          error =
              'Ошибка, код не отправился. Введите резервный код или второй пароль (PIN).';
          codeSent = true;
        });
      }
    }
  }

  Future<void> _verify() async {
    final enteredRaw = codeC.text.trim();
    final entered = enteredRaw.replaceAll(RegExp(r'\s+'), '');
    final digits = entered.replaceAll(RegExp(r'\D'), '');
    if (entered.isEmpty) {
      setState(() => error = 'Введите код');
      return;
    }
    setState(() {
      loading = true;
      error = null;
    });
    final uid = widget.user.uid;
    var ok = false;
    try {
      final snap =
          await FirebaseDatabase.instance.ref('pending_login_codes/$uid').get();
      if (snap.exists && snap.value is Map) {
        final now = DateTime.now().millisecondsSinceEpoch;
        for (final e in (snap.value as Map).entries) {
          if (e.value is! Map) continue;
          final m = Map<String, dynamic>.from(e.value as Map);
          final codeVal = (m['code'] ?? e.key).toString().trim();
          final exp = int.tryParse('${m['expires'] ?? 0}') ?? 0;
          if (exp > 0 && exp < now) {
            try {
              await FirebaseDatabase.instance
                  .ref('pending_login_codes/$uid/${e.key}')
                  .remove();
            } catch (_) {}
            continue;
          }
          if (codeVal == entered || codeVal == digits) {
            ok = true;
            try {
              await FirebaseDatabase.instance
                  .ref('pending_login_codes/$uid/${e.key}')
                  .remove();
            } catch (_) {}
            break;
          }
        }
      }
      if (!ok) {
        for (final key in {entered, digits}) {
          if (key.isEmpty) continue;
          final dl =
              await FirebaseDatabase.instance.ref('device_link/$key').get();
          if (dl.exists) {
            ok = true;
            break;
          }
        }
      }
      // sessions last_login_code
      if (!ok) {
        try {
          final prev = await FirebaseDatabase.instance
              .ref('sessions/$uid/last_login_code')
              .get();
          if (prev.value is Map) {
            final c = (Map<String, dynamic>.from(prev.value as Map)['code'] ?? '')
                .toString();
            if (c == entered || c == digits) ok = true;
          }
        } catch (_) {}
      }
      // Worker KV (код из Telegram)
      if (!ok && digits.length >= 4) {
        try {
          final token = await widget.user.getIdToken();
          final res = await http
              .post(
                Uri.parse(
                    '${B2Storage.proxyUrl}/api/telegram/verify-code'),
                headers: {
                  'Content-Type': 'application/json',
                  if (token != null && token.isNotEmpty)
                    'Authorization': 'Bearer $token',
                },
                body: jsonEncode({'code': digits, 'uid': uid}),
              )
              .timeout(const Duration(seconds: 12));
          if (res.statusCode == 200) {
            final data = jsonDecode(res.body);
            if (data is Map && data['ok'] == true) ok = true;
          }
        } catch (_) {}
      }
      if (!ok) {
        ok = await consumeRecoveryCode(uid, entered.toUpperCase());
        if (!ok) ok = await consumeRecoveryCode(uid, entered);
      }
      // Второй пароль (PIN)
      if (!ok) {
        ok = await verifySecondPin(uid, entered);
        if (!ok && digits.isNotEmpty) {
          ok = await verifySecondPin(uid, digits);
        }
      }
    } catch (_) {}
    if (!ok) {
      if (mounted) {
        setState(() {
          loading = false;
          error =
              'Неверный код. Подойдут: код SLine, Telegram, второй PIN или ключ восстановления';
        });
      }
      return;
    }
    // успех — сообщение о входе ОБЯЗАТЕЛЬНО в чат SLine (и на этом телефоне тоже)
    try {
      await ensureSLineSystemChat(uid);
      final un = (await loadProfile(uid))?.username ?? 'user';
      final device = 'Android / SLine App';
      final place = 'Неизвестно';
      final text = formatSLineNewDeviceMessage(
        username: un,
        device: device,
        place: place,
      );
      // Пишем напрямую несколько раз / путей, чтобы точно появилось
      await sendSLineSystemMessage(uid, text);
      try { await slNotifyTelegramLogin(device: device, place: place); } catch (_) {}
      // Баннер «Это были Вы?» не показываем — вход уже подтверждён кодом/PIN
      try {
        await slTouchUserSession(uid, announceLogin: false);
      } catch (_) {}
      // Снимаем висящие security_alerts (если были)
      try {
        final alerts = await FirebaseDatabase.instance.ref('security_alerts/$uid').get();
        if (alerts.exists && alerts.value is Map) {
          final map = Map<String, dynamic>.from(alerts.value as Map);
          for (final e in map.entries) {
            if (e.value is Map && (e.value as Map)['status'] == 'pending') {
              await FirebaseDatabase.instance
                  .ref('security_alerts/$uid/${e.key}')
                  .update({
                'status': 'confirmed',
                'resolved_at': DateTime.now().millisecondsSinceEpoch,
              });
            }
          }
        }
      } catch (_) {}
    } catch (_) {
      try {
        await sendSLineSystemMessage(
          uid,
          'Вход с нового устройства. Android / SLine App. Если это были не Вы — завершите сеанс в Настройках → Сеансы.',
        );
      } catch (_) {}
    }
    await slSetAwaitingLoginCode(widget.user.uid, false);
  }

  Future<void> _cancel() async {
    try {
      await slSetAwaitingLoginCode(widget.user.uid, false);
    } catch (_) {
      SLineAuthLock.pendingCode.value = false;
    }
    try {
      await FirebaseAuth.instance.signOut();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final dark = !themeCtrl.light;
    return Scaffold(
      backgroundColor: themeCtrl.bg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 24),
              const Icon(Icons.shield_outlined, size: 48, color: Color(0xFF4C7CF3)),
              const SizedBox(height: 16),
              Text(
                'Подтверждение входа',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: themeCtrl.text,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                sentCodeHint ??
                    'Введите один из вариантов:\n• код из чата SLine\n• код из Telegram (@SLineCodesBot)\n• второй пароль (PIN)\n• ключ / резервный код',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  height: 1.4,
                  color: themeCtrl.muted,
                ),
              ),
              const SizedBox(height: 28),
              TextField(
                controller: codeC,
                keyboardType: TextInputType.text,
                textAlign: TextAlign.center,
                textCapitalization: TextCapitalization.characters,
                maxLength: 12,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 3,
                ),
                decoration: InputDecoration(
                  labelText: 'SLine / Telegram / PIN / ключ',
                  hintText: 'код из SLine, TG, PIN или recovery',
                  counterText: '',
                  filled: true,
                  fillColor: dark ? const Color(0xFF151C27) : const Color(0xFFF0F2F5),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                onSubmitted: (_) => _verify(),
              ),
              if (error != null) ...[
                const SizedBox(height: 10),
                Text(error!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Color(0xFFFF5C7A))),
              ],
              const SizedBox(height: 12),
              TextButton(
                onPressed: loading
                    ? null
                    : () async {
                        final pin = await Navigator.of(context).push<String>(
                          MaterialPageRoute(
                            builder: (_) => const SLinePinPadPage(
                              title: 'Второй пароль',
                              subtitle: 'Введите PIN вместо кода',
                            ),
                          ),
                        );
                        if (pin != null && pin.isNotEmpty) {
                          codeC.text = pin;
                          await _verify();
                        }
                      },
                child: const Text('Ввести второй пароль (PIN)'),
              ),
              const SizedBox(height: 8),
              FilledButton(
                onPressed: loading ? null : _verify,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                child: loading
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Подтвердить'),
              ),
              const SizedBox(height: 10),
              TextButton(
                onPressed: loading
                    ? null
                    : () async {
                        final link = slineTelegramBotLink(widget.user.uid);
                        try {
                          await launchUrl(Uri.parse(link),
                              mode: LaunchMode.externalApplication);
                        } catch (_) {}
                      },
                child: const Text('Открыть бота Telegram'),
              ),
              TextButton(
                onPressed: loading ? null : _sendCode,
                child: const Text('Отправить код ещё раз'),
              ),
              TextButton(
                onPressed: loading ? null : _cancel,
                child: const Text('Отмена'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── models ──────────────────────────────────────────────────
class Profile {
  final String id;
  final String firstName;
  final String lastName;
  final String username;
  final String? email;
  final String color;
  final String? avatarUrl;
  final String? bio;
  final bool isSaved;
  Profile({
    required this.id,
    required this.firstName,
    this.lastName = '',
    required this.username,
    this.email,
    this.color = '#4C7CF3',
    this.avatarUrl,
    this.bio,
    this.isSaved = false,
  });
  String get displayName {
    if (isSaved) return 'Избранное';
    final n = '$firstName $lastName'.trim();
    return n.isEmpty ? (username.isNotEmpty ? username : 'User') : n;
  }

  Color get colorValue {
    try {
      return Color(int.parse('FF${color.replaceAll('#', '')}', radix: 16));
    } catch (_) {
      return SLineColors.accentA;
    }
  }

  factory Profile.fromMap(String id, Map data) {
    String? av = (data['avatar_url'] ??
            data['avatar'] ??
            data['photo'] ??
            data['photo_url'] ??
            data['image'])
        ?.toString()
        .trim();
    if (av == null || av.isEmpty || av == 'null') {
      av = null;
    } else if (av.startsWith('//')) {
      av = 'https:$av';
    }
    return Profile(
      id: id,
      firstName: (data['first_name'] ?? data['name'] ?? '').toString(),
      lastName: (data['last_name'] ?? '').toString(),
      username: (data['username'] ?? '').toString().toLowerCase(),
      email: data['email']?.toString(),
      color: (data['color'] ?? '#4C7CF3').toString(),
      avatarUrl: av,
      bio: data['bio']?.toString(),
    );
  }

  static Profile saved(String uid) => Profile(
      id: uid,
      firstName: 'Избранное',
      username: 'saved',
      color: '#F5A623',
      isSaved: true);
}

class ChatPreview {
  final String chatKey;
  final String peerId;
  final Profile? peer;
  final String lastMessage;
  final int lastAt;
  final bool isSaved;
  final bool pinned;
  final bool archived;
  final String kind; // dm | group | channel | saved
  final int unread;
  ChatPreview({
    required this.chatKey,
    required this.peerId,
    this.peer,
    this.lastMessage = '',
    this.lastAt = 0,
    this.isSaved = false,
    this.pinned = false,
    this.archived = false,
    this.kind = 'dm',
    this.unread = 0,
  });
}

/// Tenor + Giphy fallback для GIF
class TenorGif {
  static const apiKey = 'AIzaSyAyimkuZywAyKCF0GDVzwRJD9GtqJL2QfA';
  static const clientKey = 'sline_flutter';
  static const base = 'https://tenor.googleapis.com/v2';
  // публичный beta-ключ Giphy (часто работает без регистрации)
  static const giphyKey = 'sxpRBM6XW27ZSGPJzxSmbjU9Yd8L9G0Q';

  static Future<List<String>> search(String q, {int limit = 24}) async {
    final fromTenor = await _tenor(q, limit: limit);
    if (fromTenor.isNotEmpty) return fromTenor;
    return _giphy(q, limit: limit);
  }

  static Future<List<String>> _tenor(String q, {int limit = 24}) async {
    final path = q.trim().isEmpty ? 'featured' : 'search';
    final uri = Uri.parse('$base/$path').replace(queryParameters: {
      'key': apiKey,
      'client_key': clientKey,
      'limit': '$limit',
      'media_filter': 'gif,tinygif,mediumgif,nanogif',
      'contentfilter': 'medium',
      if (q.trim().isNotEmpty) 'q': q.trim(),
    });
    try {
      final res = await http.get(uri).timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return [];
      final j = jsonDecode(res.body) as Map<String, dynamic>;
      final results = (j['results'] as List?) ?? [];
      final urls = <String>[];
      for (final item in results) {
        if (item is! Map) continue;
        final m = item['media_formats'];
        if (m is! Map) continue;
        String? best;
        for (final k in ['gif', 'mediumgif', 'tinygif', 'nanogif']) {
          final f = m[k];
          if (f is Map && f['url'] is String) {
            best = f['url'] as String;
            if (k == 'gif' || k == 'mediumgif') break;
          }
        }
        if (best != null) urls.add(best);
      }
      return urls;
    } catch (_) {
      return [];
    }
  }

  static Future<List<String>> _giphy(String q, {int limit = 24}) async {
    try {
      final path = q.trim().isEmpty ? 'trending' : 'search';
      final uri = Uri.parse('https://api.giphy.com/v1/gifs/$path').replace(
        queryParameters: {
          'api_key': giphyKey,
          'limit': '$limit',
          'rating': 'pg-13',
          if (q.trim().isNotEmpty) 'q': q.trim(),
        },
      );
      final res = await http.get(uri).timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return [];
      final j = jsonDecode(res.body) as Map<String, dynamic>;
      final data = (j['data'] as List?) ?? [];
      final urls = <String>[];
      for (final item in data) {
        if (item is! Map) continue;
        final images = item['images'];
        if (images is! Map) continue;
        final fixed = images['fixed_height'] ?? images['original'] ?? images['downsized'];
        if (fixed is Map && fixed['url'] is String) {
          urls.add(fixed['url'] as String);
        }
      }
      return urls;
    } catch (_) {
      return [];
    }
  }
}


/// Убираем хвост взлома вида " — @USERNAME" / "\n— @xxx" в конце текста
String sanitizeChatText(String s) {
  if (s.isEmpty) return s;
  var out = s;
  // многострочный хвост "— @name" / "- @name" в конце любой строки
  out = out.replaceAll(
      RegExp(r'[ \t]*[—\-]\s*@[A-Za-z0-9_]+\s*$', multiLine: true), '');
  // если весь хвост был на отдельной строке
  out = out.replaceAll(RegExp(r'\n[ \t]*$'), '');
  return out.trimRight();
}


/// Нормализация URL медиа с веба (percent-encoding, media_url, data URI)
String normalizeMediaUrl(String raw) {
  var u = raw.trim();
  if (u.isEmpty) return u;
  // Повторное декодирование %XX (веб иногда двойно кодирует)
  for (var i = 0; i < 2; i++) {
    try {
      if (u.contains('%')) {
        final d = Uri.decodeFull(u);
        if (d.isNotEmpty) u = d;
      }
    } catch (_) {
      try {
        final d = Uri.decodeComponent(u);
        if (d.isNotEmpty) u = d;
      } catch (_) {}
    }
  }
  // data:image/svg+xml;charset=utf-8,<svg...  /  base64
  if (u.startsWith('data:image')) {
    return u;
  }
  // Обрезанные/кривые схемы
  if (u.startsWith('//')) u = 'https:$u';
  return u;
}

class ChatMessage {
  final String id;
  final String senderId;
  final String? receiverId;
  final String content;
  final String type;
  final String? fileUrl;
  final int createdAt;
  final String? replyToId;
  final String? replyPreview;
  final bool pinned;
  final bool fromSline;
  /// emoji → list of user ids (как на вебе)
  final Map<String, List<String>> reactions;
  ChatMessage({
    required this.id,
    required this.senderId,
    this.receiverId,
    required this.content,
    this.type = 'text',
    this.fileUrl,
    required this.createdAt,
    this.replyToId,
    this.replyPreview,
    this.pinned = false,
    this.fromSline = false,
    this.reactions = const {},
  });

  static const reactionEmojis = ['❤️', '😂', '👍', '😮', '😢', '🔥'];

  factory ChatMessage.fromMap(String id, Map data) {
    int at = 0;
    final raw = data['created_at'] ?? data['created_at_ms'];
    if (raw is int) {
      at = raw > 1000000000000 ? raw : raw * 1000;
    } else if (raw != null) {
      final p = int.tryParse(raw.toString());
      if (p != null) {
        at = p > 1000000000000 ? p : p * 1000;
      } else {
        at = DateTime.tryParse(raw.toString())?.millisecondsSinceEpoch ?? 0;
      }
    }
    // web reply format: content starts with ↪ #id|preview\n
    String content = (data['content'] ?? data['text'] ?? '').toString();
    content = sanitizeChatText(content);
    String? replyId;
    String? replyPrev;
    final m = RegExp(r'^↪ #([^|]+)\|([^\n]*)\n([\s\S]*)$').firstMatch(content);
    if (m != null) {
      replyId = m.group(1);
      replyPrev = m.group(2);
      content = m.group(3) ?? '';
    }
    var type = (data['type'] ?? 'text').toString();
    var fileUrl = (data['file_url'] ??
            data['url'] ??
            data['media_url'] ??
            data['image_url'] ??
            data['photo_url'])
        ?.toString();
    if (fileUrl != null) fileUrl = normalizeMediaUrl(fileUrl);
    // Подарок с веба/приложения
    if (type == 'gift' ||
        type == 'scoin_transfer' ||
        content.startsWith('gift:') ||
        (data['gift_id'] != null)) {
      type = type == 'scoin_transfer' ? 'scoin_transfer' : 'gift';
      if (fileUrl == null || fileUrl.isEmpty) {
        fileUrl = (data['gift_id'] ??
                (content.startsWith('gift:')
                    ? content.substring(5)
                    : content))
            .toString();
      }
    }
    // Аудио-файл не путать с voice, если type=file
    if (type == 'file' && fileUrl != null) {
      final low = '${fileUrl.toLowerCase()} ${content.toLowerCase()}';
      if (low.contains('.mp3') ||
          low.contains('.m4a') ||
          low.contains('.ogg') ||
          low.contains('.opus') ||
          low.contains('.wav')) {
        // остаётся file — UI откроет плеер
      }
    }
    // Иногда веб кладёт ссылку только в content
    if ((fileUrl == null || fileUrl.isEmpty) &&
        (type == 'image' ||
            type == 'gif' ||
            type == 'sticker' ||
            type == 'video' ||
            type == 'photo')) {
      final c = content.trim();
      if (c.startsWith('http') || c.startsWith('data:image')) {
        fileUrl = normalizeMediaUrl(c);
      }
    }
    // веб: gif часто type=image/gif или url содержит tenor/giphy
    if (type == 'image' &&
        fileUrl != null &&
        (fileUrl.contains('.gif') ||
            fileUrl.contains('tenor.com') ||
            fileUrl.contains('giphy.com'))) {
      type = 'gif';
    }
    final reactions = <String, List<String>>{};
    final rawR = data['reactions'];
    if (rawR is Map) {
      rawR.forEach((k, v) {
        if (v is List) {
          reactions[k.toString()] =
              v.map((e) => e.toString()).toList();
        } else if (v is Map) {
          // {uid: true}
          reactions[k.toString()] =
              v.keys.map((e) => e.toString()).toList();
        }
      });
    }
    final sid = (data['sender_id'] ?? '').toString();
    final fromSline = data['from_sline'] == true ||
        data['system_notice'] == true ||
        sid == kSLineSystemUid;
    return ChatMessage(
      id: id,
      senderId: sid,
      receiverId: data['receiver_id']?.toString(),
      content: content,
      type: type,
      fileUrl: fileUrl,
      createdAt: at,
      replyToId: replyId ?? data['reply_to_msg_id']?.toString(),
      replyPreview: replyPrev,
      pinned: data['pinned'] == true,
      fromSline: fromSline,
      reactions: reactions,
    );
  }

  String get timeLabel {
    if (createdAt <= 0) return '';
    final dt = DateTime.fromMillisecondsSinceEpoch(createdAt);
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}

/// Подарки 1:1 как на веб-версии SLine (id, emoji, name, price, sell)
class SLineGifts {
  /// (id, emoji, name, price, sellPrice)
  static const items = <(String, String, String, int, int)>[
    ('gift', '🎁', 'Подарок', 10, 8),
    ('bear', '🧸', 'Мишка', 15, 13),
    ('star', '⭐', 'Звезда', 20, 17),
    ('rose', '🌹', 'Роза', 25, 21),
    ('heart', '💝', 'Сердце', 30, 26),
    ('party', '🎉', 'Праздник', 35, 30),
    ('cake', '🎂', 'Торт', 40, 34),
    ('bouquet', '💐', 'Букет', 50, 43),
    ('unicorn', '🦄', 'Единорог', 80, 68),
    ('diamond', '💎', 'Алмаз', 100, 85),
  ];

  static (String, String, String, int, int)? byId(String? id) {
    if (id == null || id.isEmpty) return null;
    final clean = id.startsWith('gift:') ? id.substring(5) : id;
    for (final g in items) {
      if (g.$1 == clean) return g;
    }
    return null;
  }

  static String emojiFor(String? id) => byId(id)?.$2 ?? '🎁';

  static String labelFor(String? id) => byId(id)?.$3 ?? 'Подарок';

  static int priceFor(String? id) => byId(id)?.$4 ?? 10;

  static int sellFor(String? id) => byId(id)?.$5 ?? 8;
}

/// SCoin — внутренняя валюта (синхрон с web: tables/profiles/$uid/scoin)
class SCoin {
  static Future<int> balance(String uid) async {
    try {
      final snap = await FirebaseDatabase.instance
          .ref('tables/profiles/$uid/scoin')
          .get();
      final v = snap.value;
      if (v is num) return v.toInt().clamp(0, 1 << 30);
      if (v is String) return (int.tryParse(v) ?? 0).clamp(0, 1 << 30);
    } catch (_) {}
    return 0;
  }

  static Future<void> setBalance(String uid, int n) async {
    n = n.clamp(0, 1 << 30);
    await FirebaseDatabase.instance.ref('tables/profiles/$uid').update({
      'scoin': n,
      'scoin_updated': DateTime.now().millisecondsSinceEpoch,
    });
  }

  /// Первый вход — 10 SCoin
  static Future<int> ensureStarter(String uid) async {
    final b = await balance(uid);
    if (b > 0) return b;
    try {
      final flag = await FirebaseDatabase.instance
          .ref('tables/profiles/$uid/scoin_granted')
          .get();
      if (flag.exists) return b;
      await FirebaseDatabase.instance.ref('tables/profiles/$uid').update({
        'scoin': 10,
        'scoin_granted': true,
        'scoin_updated': DateTime.now().millisecondsSinceEpoch,
      });
      return 100;
    } catch (_) {
      return b;
    }
  }

  static Future<bool> spend(String uid, int amount) async {
    final b = await balance(uid);
    if (b < amount) return false;
    await setBalance(uid, b - amount);
    return true;
  }

  static Future<void> add(String uid, int amount) async {
    final b = await balance(uid);
    await setBalance(uid, b + amount);
  }
}

Future<Profile> ensureWebProfile(User user) async {
  final ref = profilesRef().child(user.uid);
  try {
    final snap = await ref.get();
    if (snap.exists && snap.value is Map) {
      // выдать стартовые 10 SCoin при первом входе
      try {
        await SCoin.ensureStarter(user.uid);
      } catch (_) {}
      return Profile.fromMap(
          user.uid, Map<String, dynamic>.from(snap.value as Map));
    }
  } catch (e) {
    // permission — вернём локальный профиль
    return Profile(
      id: user.uid,
      firstName: user.displayName ?? 'User',
      username: user.email?.split('@').first ?? 'user',
      email: user.email,
    );
  }
  final username = (user.email?.split('@').first ?? user.uid.substring(0, 8))
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9_]'), '');
  final data = {
    'id': user.uid,
    'email': user.email,
    'first_name': user.displayName ?? 'User',
    'last_name': '',
    'username': username,
    'color': '#4C7CF3',
    'avatar_url': user.photoURL,
    'bio': '',
    'scoin': 10,
    'scoin_granted': true,
    'created_at': DateTime.now().toIso8601String(),
  };
  try {
    await ref.set(data);
  } catch (_) {}
  return Profile.fromMap(user.uid, data);
}


const kSLineSystemUid = 'sline_system';

String slineSystemChatKey(String uid) => dmPairKey(uid, kSLineSystemUid);

/// Cloudflare Worker (Resend ключ ТОЛЬКО на Worker, не в приложении/GitHub)
const kSLineWorkerBase =
    'https://old-band-f00b.dimasik-228-dima-super.workers.dev';


Future<String?> resolveUserRealEmail(User user) async {
  final candidates = <String>[];
  try {
    final p = await loadProfile(user.uid);
    if (p?.email != null) candidates.add(p!.email!);
  } catch (_) {}
  try {
    final snap =
        await profilesRef().child(user.uid).child('email').get();
    if (snap.exists && snap.value != null) {
      candidates.add(snap.value.toString());
    }
  } catch (_) {}
  if (user.email != null) candidates.add(user.email!);
  try {
    // иногда email лежит в providerData
    for (final info in user.providerData) {
      if (info.email != null) candidates.add(info.email!);
    }
  } catch (_) {}
  for (final raw in candidates) {
    final e = raw.trim().toLowerCase();
    if (e.contains('@') && !isSyntheticPhoneEmail(e)) return e;
  }
  return null;
}

bool isSyntheticPhoneEmail(String? email) {
  final e = (email ?? '').trim().toLowerCase();
  if (e.isEmpty) return true;
  return e.endsWith('@phone.signal-line.local') ||
      e.endsWith('@signal-line.local') ||
      e.contains('phone.signal-line');
}

/// Нужна привязка реальной почты (рег. по номеру / нет email)
bool profileNeedsEmailBind(User user, Profile? p) {
  final em = (p?.email ?? user.email ?? '').trim();
  return isSyntheticPhoneEmail(em);
}

String hashSecondPin(String uid, String pin) {
  final bytes = utf8.encode('$uid|sline_second_pin|$pin');
  return sha256.convert(bytes).toString();
}

Future<void> saveSecondPin(String uid, String pin) async {
  final h = hashSecondPin(uid, pin);
  await FirebaseDatabase.instance.ref('user_second_pin/$uid').set({
    'hash': h,
    'updated_at': DateTime.now().millisecondsSinceEpoch,
    'len': pin.length,
  });
}

Future<bool> hasSecondPin(String uid) async {
  try {
    final s = await FirebaseDatabase.instance.ref('user_second_pin/$uid/hash').get();
    return s.exists && (s.value?.toString().isNotEmpty ?? false);
  } catch (_) {
    return false;
  }
}

Future<bool> verifySecondPin(String uid, String pin) async {
  if (pin.length < 4) return false;
  try {
    final s = await FirebaseDatabase.instance.ref('user_second_pin/$uid/hash').get();
    if (!s.exists) return false;
    return s.value.toString() == hashSecondPin(uid, pin);
  } catch (_) {
    return false;
  }
}

Future<void> clearSecondPin(String uid) async {
  try {
    await FirebaseDatabase.instance.ref('user_second_pin/$uid').remove();
  } catch (_) {}
}

/// Отправка письма через Worker (ключ Resend на сервере)
/// Результат отправки: null = ок, иначе текст ошибки
Future<String?> slSendEmailViaWorker({
  required String to,
  required String subject,
  required String html,
}) async {
  HttpClient? client;
  try {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return 'Нет сессии Firebase';
    final token = await user.getIdToken(true);
    if (token == null || token.isEmpty) return 'Нет Firebase token';

    final uri = Uri.parse('$kSLineWorkerBase/api/send-email');
    client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 20);
    final req = await client.postUrl(uri);
    req.headers.set(HttpHeaders.contentTypeHeader, 'application/json; charset=utf-8');
    req.headers.set(HttpHeaders.acceptHeader, 'application/json');
    req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');

    final payload = utf8.encode(jsonEncode({
      'to': to.trim().toLowerCase(),
      'subject': subject,
      'html': html,
      'from': 'SLine <onboarding@resend.dev>',
    }));
    req.contentLength = payload.length;
    req.add(payload);

    final resp = await req.close().timeout(const Duration(seconds: 25));
    final body = await resp.transform(utf8.decoder).join();
    final code = resp.statusCode;
    if (code >= 200 && code < 300) return null;

    // Разбор типичных ошибок Resend
    String detail = body;
    try {
      final m = jsonDecode(body);
      if (m is Map) {
        detail = (m['error'] ?? m['message'] ?? m['details'] ?? body).toString();
        if (m['details'] is Map) {
          detail = (m['details']['message'] ?? m['details']['name'] ?? detail).toString();
        }
      }
    } catch (_) {}
    if (code == 401) return 'Worker: нужен вход (401)';
    if (code == 403) {
      return 'Resend запретил отправку. На бесплатном плане письмо уходит только на email владельца аккаунта Resend, либо подтвердите свой домен.';
    }
    if (detail.toLowerCase().contains('resend_api_key')) {
      return 'На Worker не задан RESEND_API_KEY';
    }
    return 'HTTP $code: $detail';
  } catch (e) {
    return 'Сеть: $e';
  } finally {
    client?.close(force: true);
  }
}


Future<String?> slSendTelegramCodeViaWorker({
  required String code,
  String? uid,
}) async {
  HttpClient? client;
  try {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return 'Нет сессии Firebase';
    final token = await user.getIdToken(true);
    if (token == null || token.isEmpty) return 'Нет Firebase token';
    final uri = Uri.parse('$kSLineWorkerBase/api/telegram/send-code');
    client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 20);
    final req = await client.postUrl(uri);
    req.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
    req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
    req.add(utf8.encode(jsonEncode({
      'code': code,
      'uid': uid ?? user.uid,
    })));
    final res = await req.close().timeout(const Duration(seconds: 25));
    final body = await res.transform(utf8.decoder).join();
    Map<String, dynamic>? m;
    try {
      final j = jsonDecode(body);
      if (j is Map) m = Map<String, dynamic>.from(j);
    } catch (_) {}
    // 200 OK или 404 code_queued — код валиден
    if (res.statusCode >= 200 && res.statusCode < 300) {
      final rc = (m?['code'] ?? '').toString();
      if (rc.length >= 4 && rc != code) return 'SYNC:$rc';
      return null;
    }
    if (m != null) {
      if (m['error'] == 'telegram_not_linked') {
        final rc = (m['code'] ?? '').toString();
        if (rc.length >= 4 && rc != code) return 'SYNC:$rc';
        return 'not_linked';
      }
      if (m['message'] != null) return m['message'].toString();
      if (m['error'] != null) return m['error'].toString();
    }
    return 'Telegram HTTP ${res.statusCode}: $body';
  } catch (e) {
    return '$e';
  } finally {
    try {
      client?.close(force: true);
    } catch (_) {}
  }
}

String slineTelegramBotLink(String uid) =>
    'https://t.me/SLineCodesBot?start=${Uri.encodeComponent(uid)}';

Future<String?> slSendLoginEmailCode(String toEmail, String code) async {
  return slSendEmailViaWorker(
    to: toEmail,
    subject: 'Код SLine: $code',
    html:
        '<p>Ваш код для <strong>SLine</strong>: <strong style="font-size:20px">$code</strong></p>'
        '<p>Никому не сообщайте этот код.</p>',
  );
}



Profile slineSystemProfile() => Profile(
      id: kSLineSystemUid,
      firstName: 'SLine',
      lastName: '',
      username: 'sline',
      color: '#4C7CF3',
      bio: 'Служба уведомлений SLine',
      avatarUrl: 'asset:assets/icon/app_icon.png',
    );


const _kSessionTwoDaysMs = 2 * 24 * 60 * 60 * 1000;
/// Сеанс удаляется после 12 месяцев без активности
const _kSessionTwelveMonthsMs = 365 * 24 * 60 * 60 * 1000;

String _mobileSessionDeviceId() {
  // стабильный id устройства на установку
  return 'android_${DateTime.now().millisecondsSinceEpoch}';
}

Future<String> slLocalDeviceId() async {
  try {
    final dir = await getTemporaryDirectory();
    final f = File('${dir.path}/sl_session_device_id.txt');
    if (await f.exists()) {
      final id = (await f.readAsString()).trim();
      if (id.isNotEmpty) return id;
    }
    final id = 'android_${DateTime.now().millisecondsSinceEpoch}';
    await f.writeAsString(id);
    return id;
  } catch (_) {
    return 'android_${DateTime.now().millisecondsSinceEpoch}';
  }
}

/// Обновить сеанс. Возвращает deviceId.
Future<String> slTouchUserSession(String uid, {bool announceLogin = false}) async {
  if (uid.isEmpty) return '';
  try {
    try {
      await slPruneOldSessions(uid);
    } catch (_) {}
    final id = await slLocalDeviceId();
    final ref = FirebaseDatabase.instance.ref('user_sessions/$uid/$id');
    await ref.update({
      'last_active': DateTime.now().millisecondsSinceEpoch,
      'device': 'Android / SLine App',
      'platform': 'android',
      'updated_at': DateTime.now().toIso8601String(),
    });
    if (announceLogin) {
      await slPublishSecurityAlert(
        uid: uid,
        sessionId: id,
        device: 'Android / SLine App',
        place: 'Неизвестно',
      );
    }
    return id;
  } catch (_) {
    return '';
  }
}


Future<void> slNotifyTelegramLogin({required String device, required String place}) async {
  try {
    final u = FirebaseAuth.instance.currentUser;
    if (u == null) return;
    final token = await u.getIdToken();
    await http.post(
      Uri.parse('https://old-band-f00b.dimasik-228-dima-super.workers.dev/api/telegram/notify-login'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode({'uid': u.uid, 'device': device, 'place': place}),
    );
  } catch (_) {}
}

/// Алерт для других устройств (баннер + сообщение в SLine)
Future<void> slPublishSecurityAlert({
  required String uid,
  required String sessionId,
  required String device,
  required String place,
}) async {
  if (uid.isEmpty || sessionId.isEmpty) return;
  try {
    // Сообщение в чат SLine — всегда
    try {
      final un = (await loadProfile(uid))?.username ?? 'user';
      await sendSLineSystemMessage(
        uid,
        formatSLineNewDeviceMessage(
          username: un,
          device: device,
          place: place,
        ),
      );
    } catch (_) {}

    // Баннер на других устройствах — только если есть другие сеансы
    final snap =
        await FirebaseDatabase.instance.ref('user_sessions/$uid').get();
    var other = false;
    if (snap.exists && snap.value is Map) {
      for (final e in (snap.value as Map).entries) {
        if (e.key.toString() != sessionId) {
          other = true;
          break;
        }
      }
    }
    if (!other) return;
    final alertRef =
        FirebaseDatabase.instance.ref('security_alerts/$uid').push();
    await alertRef.set({
      'session_id': sessionId,
      'device': device,
      'place': place,
      'platform': 'android',
      'created_at': DateTime.now().millisecondsSinceEpoch,
      'status': 'pending',
    });
  } catch (_) {}
}

Future<void> slConfirmSecurityAlert(String uid, String alertId) async {
  try {
    await FirebaseDatabase.instance
        .ref('security_alerts/$uid/$alertId')
        .update({
      'status': 'confirmed',
      'resolved_at': DateTime.now().millisecondsSinceEpoch,
    });
  } catch (_) {}
}

Future<void> slRejectSecurityAlert(String uid, String alertId, String sessionId) async {
  try {
    await FirebaseDatabase.instance
        .ref('security_alerts/$uid/$alertId')
        .update({
      'status': 'rejected',
      'resolved_at': DateTime.now().millisecondsSinceEpoch,
    });
    if (sessionId.isNotEmpty) {
      await FirebaseDatabase.instance
          .ref('user_sessions/$uid/$sessionId')
          .remove();
    }
  } catch (_) {}
}


/// true = есть сеанс активный за 2 дня → нужен код SLine
/// Всегда запрашивать код из SLine / резервный при входе (после пароля).
/// Удаляет сеансы без активности 12+ месяцев. Возвращает число оставшихся (чужих+своих).
Future<int> slPruneOldSessions(String uid) async {
  if (uid.isEmpty) return 0;
  var left = 0;
  try {
    final ref = FirebaseDatabase.instance.ref('user_sessions/$uid');
    final snap = await ref.get();
    if (!snap.exists || snap.value is! Map) return 0;
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final e in (snap.value as Map).entries) {
      if (e.value is! Map) continue;
      final m = Map<String, dynamic>.from(e.value as Map);
      final la = int.tryParse(
              (m['last_active'] ?? m['lastActive'] ?? m['ts'] ?? 0).toString()) ??
          0;
      if (la > 0 && (now - la) >= _kSessionTwelveMonthsMs) {
        try {
          await ref.child(e.key.toString()).remove();
        } catch (_) {}
      } else {
        left++;
      }
    }
  } catch (_) {}
  // legacy path
  try {
    final ref = FirebaseDatabase.instance.ref('sessions/$uid');
    final snap = await ref.get();
    if (snap.exists && snap.value is Map) {
      final now = DateTime.now().millisecondsSinceEpoch;
      for (final e in (snap.value as Map).entries) {
        if (e.value is! Map) continue;
        final m = Map<String, dynamic>.from(e.value as Map);
        final la = int.tryParse(
                (m['last_active'] ?? m['lastActive'] ?? m['ts'] ?? 0)
                    .toString()) ??
            0;
        if (la > 0 && (now - la) >= _kSessionTwelveMonthsMs) {
          try {
            await ref.child(e.key.toString()).remove();
          } catch (_) {}
        }
      }
    }
  } catch (_) {}
  return left;
}

/// Код нужен, если есть хотя бы один сеанс **другого** устройства (после очистки 12 мес.).
/// Нет сеансов → вход без кода.
Future<bool> slNeedSLineCode(String uid) async {
  if (uid.isEmpty) return false;
  try {
    await slPruneOldSessions(uid);
    String myId = '';
    try {
      myId = await slLocalDeviceId();
    } catch (_) {}
    final snap =
        await FirebaseDatabase.instance.ref('user_sessions/$uid').get();
    if (!snap.exists || snap.value is! Map) return false;
    for (final e in (snap.value as Map).entries) {
      final sid = e.key.toString();
      if (myId.isNotEmpty && sid == myId) continue;
      if (e.value is! Map) continue;
      // любой оставшийся чужой сеанс → нужен код
      return true;
    }
    return false;
  } catch (_) {
    return false;
  }
}

Future<void> ensureSLineSystemChat(String uid) async {
  if (uid.isEmpty || uid == kSLineSystemUid) return;
  final key = slineSystemChatKey(uid);
  try {
    await FirebaseDatabase.instance.ref('user_chat_index/$uid/$key').set({
      't': true,
      'peer': kSLineSystemUid,
      'updated_at': DateTime.now().millisecondsSinceEpoch,
    });
  } catch (_) {
    try {
      await FirebaseDatabase.instance.ref('user_chat_index/$uid/$key').set(true);
    } catch (_) {}
  }
  // Профиль системы: создать если нет (rules: !data.exists())
  try {
    final pref = FirebaseDatabase.instance.ref('tables/profiles/$kSLineSystemUid');
    final snap = await pref.get();
    if (!snap.exists) {
      await pref.set({
        'id': kSLineSystemUid,
        'username': 'sline',
        'first_name': 'SLine',
        'last_name': '',
        'color': '#4C7CF3',
        'bio': 'Служба уведомлений SLine',
      });
    }
  } catch (_) {}
}


// ─── Резервные коды (recovery) ───────────────────────────────
List<String> generateRecoveryCodes({int count = 8}) {
  const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  final rnd = math.Random.secure();
  String chunk() =>
      List.generate(4, (_) => alphabet[rnd.nextInt(alphabet.length)]).join();
  final out = <String>[];
  final seen = <String>{};
  while (out.length < count) {
    final c = '${chunk()}-${chunk()}';
    if (seen.add(c)) out.add(c);
  }
  return out;
}

String hashRecoveryCode(String uid, String code) {
  final n = code.replaceAll(RegExp(r'[^A-Za-z0-9]'), '').toUpperCase();
  return sha256.convert(utf8.encode('$uid:$n')).toString();
}

Future<void> saveRecoveryCodes(String uid, List<String> codes) async {
  if (uid.isEmpty || codes.isEmpty) return;
  final hashes = <String, dynamic>{};
  for (final c in codes) {
    final h = hashRecoveryCode(uid, c);
    hashes[h] = {
      'used': false,
      'created': DateTime.now().millisecondsSinceEpoch,
    };
  }
  await FirebaseDatabase.instance.ref('user_recovery_codes/$uid').set({
    'generated_at': DateTime.now().millisecondsSinceEpoch,
    'count': codes.length,
    'hashes': hashes,
  });
}

Future<bool> consumeRecoveryCode(String uid, String code) async {
  if (uid.isEmpty || code.trim().isEmpty) return false;
  final h = hashRecoveryCode(uid, code.trim());
  try {
    final ref =
        FirebaseDatabase.instance.ref('user_recovery_codes/$uid/hashes/$h');
    final snap = await ref.get();
    if (!snap.exists || snap.value is! Map) return false;
    final m = Map<String, dynamic>.from(snap.value as Map);
    if (m['used'] == true) return false;
    await ref.update({
      'used': true,
      'used_at': DateTime.now().millisecondsSinceEpoch,
    });
    return true;
  } catch (_) {
    return false;
  }
}

Future<bool> hasRecoveryCodes(String uid) async {
  try {
    final snap = await FirebaseDatabase.instance
        .ref('user_recovery_codes/$uid/hashes')
        .get();
    if (!snap.exists || snap.value is! Map) return false;
    for (final e in (snap.value as Map).entries) {
      if (e.value is Map && (e.value as Map)['used'] != true) return true;
    }
  } catch (_) {}
  return false;
}

Future<void> sendSLineSystemMessage(String toUid, String text) async {
  if (toUid.isEmpty || text.trim().isEmpty) return;
  final key = slineSystemChatKey(toUid);
  await ensureSLineSystemChat(toUid);
  final now = DateTime.now();
  final ms = now.millisecondsSinceEpoch;
  final base = <String, dynamic>{
    'type': 'text',
    'content': text,
    'text': text,
    'from_sline': true,
    'system_notice': true,
    'created_at': now.toIso8601String(),
    'created_at_ms': ms,
  };

  Future<bool> pushChat(Map<String, dynamic> body) async {
    try {
      final ref = FirebaseDatabase.instance.ref('chat_msgs/$key').push();
      body['id'] = ref.key;
      await ref.set(body);
      return true;
    } catch (_) {
      return false;
    }
  }

  // 1) от sline_system (входящее)
  var ok = await pushChat({
    ...base,
    'sender_id': kSLineSystemUid,
    'receiver_id': toUid,
  });
  // 2) fallback: от пользователя с флагом from_sline (rules всегда пускают sender==auth.uid)
  if (!ok) {
    ok = await pushChat({
      ...base,
      'sender_id': toUid,
      'receiver_id': kSLineSystemUid,
    });
  }
  // 3) tables/messages — для веб/инбокса
  try {
    final mid = 'sl_${ms}_${toUid.hashCode.abs()}';
    await FirebaseDatabase.instance.ref('tables/messages/$mid').set({
      ...base,
      'id': mid,
      'sender_id': ok ? kSLineSystemUid : toUid,
      'receiver_id': ok ? toUid : kSLineSystemUid,
    });
  } catch (_) {
    try {
      final mid = 'sl2_${ms}_${toUid.hashCode.abs()}';
      await FirebaseDatabase.instance.ref('tables/messages/$mid').set({
        ...base,
        'id': mid,
        'sender_id': toUid,
        'receiver_id': kSLineSystemUid,
      });
    } catch (_) {}
  }
  // Индекс как map (не boolean) — иначе update ломается
  try {
    await FirebaseDatabase.instance.ref('user_chat_index/$toUid/$key').set({
      't': true,
      'last_msg': text.length > 80 ? '${text.substring(0, 80)}…' : text,
      'updated_at': ms,
      'peer': kSLineSystemUid,
    });
  } catch (_) {
    try {
      await FirebaseDatabase.instance.ref('user_chat_index/$toUid/$key').set(true);
    } catch (_) {}
  }
}

String formatSLineLoginCodeMessage(String code) {
  return 'Код для входа в SLine: $code. Не давайте код никому, даже если его требуют от имени SLine!\n\n'
      '❗️Этот код используется для входа в Ваш аккаунт в SLine. Он не может быть использован для чего-либо ещё.\n\n'
      'Если Вы не запрашивали код для входа, проигнорируйте это сообщение.';
}

String formatSLineNewDeviceMessage({
  required String username,
  required String device,
  required String place,
  DateTime? when,
}) {
  final t = when ?? DateTime.now().toUtc();
  final dd = t.day.toString().padLeft(2, '0');
  final mm = t.month.toString().padLeft(2, '0');
  final yyyy = t.year.toString();
  final hh = t.hour.toString().padLeft(2, '0');
  final mi = t.minute.toString().padLeft(2, '0');
  final ss = t.second.toString().padLeft(2, '0');
  final un = username.startsWith('@') ? username : '@$username';
  return 'Вход с нового устройства. $un, мы обнаружили вход в Ваш аккаунт с нового устройства $dd/$mm/$yyyy в $hh:$mi:$ss UTC.\n\n'
      'Устройство: $device\n'
      'Место входа: $place\n\n'
      'Если это были не Вы, как можно скорее перейдите в Настройки > Устройства (или Конфиденциальность > Активные сеансы) и завершите новый сеанс.';
}

Future<Profile?> loadProfile(String uid) async {
  if (uid == kSLineSystemUid) return slineSystemProfile();
  try {
    final snap = await profilesRef().child(uid).get();
    if (snap.exists && snap.value is Map) {
      return Profile.fromMap(uid, Map<String, dynamic>.from(snap.value as Map));
    }
  } catch (_) {}
  return null;
}

/// true, если username уже занят (profiles)
Future<bool> isUsernameTaken(String username, {String? excludeUid}) async {
  final u = username.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9_]'), '');
  if (u.isEmpty) return false;
  try {
    final snap = await profilesRef()
        .orderByChild('username')
        .equalTo(u)
        .limitToFirst(5)
        .get();
    if (snap.exists && snap.value is Map) {
      for (final e in (snap.value as Map).entries) {
        final id = e.key.toString();
        if (excludeUid != null && id == excludeUid) continue;
        if (e.value is Map) {
          final un = (e.value as Map)['username']?.toString().toLowerCase() ?? '';
          if (un == u) return true;
        }
      }
    }
  } catch (_) {}
  // fallback: скан (на случай без индекса)
  try {
    final snap = await profilesRef().limitToFirst(800).get();
    if (snap.exists && snap.value is Map) {
      for (final e in (snap.value as Map).entries) {
        final id = e.key.toString();
        if (excludeUid != null && id == excludeUid) continue;
        if (e.value is! Map) continue;
        final un =
            (e.value as Map)['username']?.toString().toLowerCase() ?? '';
        if (un == u) return true;
      }
    }
  } catch (_) {}
  return false;
}

/// true, если slug группы/канала занят
Future<bool> isSlugTaken(String slug, {String? excludeId}) async {
  final s = slug.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9_]'), '');
  if (s.isEmpty) return false;
  try {
    for (final path in ['channels', 'groups']) {
      final snap = await FirebaseDatabase.instance
          .ref(path)
          .orderByChild('slug')
          .equalTo(s)
          .limitToFirst(3)
          .get();
      if (snap.exists && snap.value is Map) {
        for (final e in (snap.value as Map).entries) {
          if (excludeId != null && e.key.toString() == excludeId) continue;
          return true;
        }
      }
      final snap2 = await FirebaseDatabase.instance
          .ref(path)
          .orderByChild('username')
          .equalTo(s)
          .limitToFirst(3)
          .get();
      if (snap2.exists && snap2.value is Map) {
        for (final e in (snap2.value as Map).entries) {
          if (excludeId != null && e.key.toString() == excludeId) continue;
          return true;
        }
      }
    }
  } catch (_) {}
  return false;
}

Future<List<Profile>> searchProfiles(String query,
    {String? excludeUid, int limit = 40}) async {
  final q = query.trim().toLowerCase().replaceAll('@', '');
  if (q.length < 2) return [];
  final byId = <String, Profile>{};
  try {
    final snap = await profilesRef()
        .orderByChild('username')
        .equalTo(q)
        .limitToFirst(limit)
        .get();
    if (snap.exists && snap.value is Map) {
      Map<String, dynamic>.from(snap.value as Map).forEach((k, v) {
        if (v is Map) {
          final id = (v['id'] ?? k).toString();
          if (excludeUid != null && id == excludeUid) return;
          byId[id] = Profile.fromMap(id, Map<String, dynamic>.from(v));
        }
      });
    }
  } catch (_) {}
  try {
    final snap = await profilesRef().limitToFirst(500).get();
    if (snap.exists && snap.value is Map) {
      for (final e in (snap.value as Map).entries) {
        final id = e.key.toString();
        if (excludeUid != null && id == excludeUid) continue;
        if (e.value is! Map) continue;
        final p = Profile.fromMap(id, Map<String, dynamic>.from(e.value as Map));
        final hay =
            '${p.username} ${p.displayName} ${p.email ?? ''} ${p.bio ?? ''}'
                .toLowerCase();
        if (hay.contains(q)) byId[id] = p;
      }
    }
  } catch (_) {}
  return byId.values.take(limit).toList();
}


class StoryItem {
  final String id;
  final String userId;
  final String? mediaUrl;
  final String type;
  final DateTime? expiresAt;
  StoryItem({
    required this.id,
    required this.userId,
    this.mediaUrl,
    this.type = 'image',
    this.expiresAt,
  });
  bool get isActive {
    if (expiresAt == null) return true;
    return expiresAt!.isAfter(DateTime.now());
  }

  factory StoryItem.fromMap(String id, Map data) {
    DateTime? exp;
    final raw = data['expires_at'];
    if (raw != null) {
      exp = DateTime.tryParse(raw.toString());
      if (exp == null) {
        final n = int.tryParse(raw.toString());
        if (n != null) {
          exp = DateTime.fromMillisecondsSinceEpoch(
              n > 1000000000000 ? n : n * 1000);
        }
      }
    }
    return StoryItem(
      id: id,
      userId: (data['user_id'] ?? '').toString(),
      mediaUrl: (data['media_url'] ?? data['url'])?.toString(),
      type: (data['type'] ?? 'image').toString(),
      expiresAt: exp,
    );
  }
}

String permissionHelp(Object e) {
  final s = e.toString();
  // Как на вебе: permission-denied не показываем пользователю
  if (s.contains('permission-denied') ||
      s.contains('Permission denied') ||
      s.contains('PERMISSION_DENIED')) {
    return '';
  }
  return s;
}

bool _isPermError(Object e) {
  final s = e.toString();
  return s.contains('permission-denied') ||
      s.contains('Permission denied') ||
      s.contains('PERMISSION_DENIED');
}

// ── login ───────────────────────────────────────────────────
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with TickerProviderStateMixin {
  final emailC = TextEditingController();
  final phoneC = TextEditingController();
  /// Код страны (не только +7)
  String _ccCode = '+7';
  String _ccDigits = '7';
  String _ccFlag = '🇷🇺';
  String _ccLabel = 'Россия';
  final passC = TextEditingController();
  final nameC = TextEditingController();
  final userC = TextEditingController();
  bool isLogin = true, loading = false, obscure = true;
  /// Согласие с политикой и офертой (только регистрация)
  bool acceptedTerms = false;
  /// 0 = email/pass, 1 = имя+username (только регистрация)
  int regStep = 0;
  String? error;
  late final AnimationController _logoCtrl;
  late final AnimationController _cardCtrl;
  late final AnimationController _blobCtrl;
  late final AnimationController _pulseCtrl;
  late final AnimationController _shimmerCtrl;

  /// Показать email, если телефон пустой
  bool get _showEmail => phoneC.text.trim().isEmpty;
  /// Показать телефон, если email пустой
  bool get _showPhone => emailC.text.trim().isEmpty;

  void _onContactChanged() {
    if (mounted) setState(() {});
  }

  static final _countries = <Map<String, String>>[
    {'code': '+1', 'digits': '1', 'flag': '🇺🇸', 'label': 'США / Канада'},
    {'code': '+7', 'digits': '7', 'flag': '🇷🇺', 'label': 'Россия'},
    {'code': '+7', 'digits': '7', 'flag': '🇰🇿', 'label': 'Казахстан'},
    {'code': '+20', 'digits': '20', 'flag': '🇪🇬', 'label': 'Египет'},
    {'code': '+27', 'digits': '27', 'flag': '🇿🇦', 'label': 'ЮАР'},
    {'code': '+30', 'digits': '30', 'flag': '🇬🇷', 'label': 'Греция'},
    {'code': '+31', 'digits': '31', 'flag': '🇳🇱', 'label': 'Нидерланды'},
    {'code': '+32', 'digits': '32', 'flag': '🇧🇪', 'label': 'Бельгия'},
    {'code': '+33', 'digits': '33', 'flag': '🇫🇷', 'label': 'Франция'},
    {'code': '+34', 'digits': '34', 'flag': '🇪🇸', 'label': 'Испания'},
    {'code': '+36', 'digits': '36', 'flag': '🇭🇺', 'label': 'Венгрия'},
    {'code': '+39', 'digits': '39', 'flag': '🇮🇹', 'label': 'Италия'},
    {'code': '+40', 'digits': '40', 'flag': '🇷🇴', 'label': 'Румыния'},
    {'code': '+41', 'digits': '41', 'flag': '🇨🇭', 'label': 'Швейцария'},
    {'code': '+43', 'digits': '43', 'flag': '🇦🇹', 'label': 'Австрия'},
    {'code': '+44', 'digits': '44', 'flag': '🇬🇧', 'label': 'Великобритания'},
    {'code': '+45', 'digits': '45', 'flag': '🇩🇰', 'label': 'Дания'},
    {'code': '+46', 'digits': '46', 'flag': '🇸🇪', 'label': 'Швеция'},
    {'code': '+47', 'digits': '47', 'flag': '🇳🇴', 'label': 'Норвегия'},
    {'code': '+48', 'digits': '48', 'flag': '🇵🇱', 'label': 'Польша'},
    {'code': '+49', 'digits': '49', 'flag': '🇩🇪', 'label': 'Германия'},
    {'code': '+51', 'digits': '51', 'flag': '🇵🇪', 'label': 'Перу'},
    {'code': '+52', 'digits': '52', 'flag': '🇲🇽', 'label': 'Мексика'},
    {'code': '+54', 'digits': '54', 'flag': '🇦🇷', 'label': 'Аргентина'},
    {'code': '+55', 'digits': '55', 'flag': '🇧🇷', 'label': 'Бразилия'},
    {'code': '+56', 'digits': '56', 'flag': '🇨🇱', 'label': 'Чили'},
    {'code': '+57', 'digits': '57', 'flag': '🇨🇴', 'label': 'Колумбия'},
    {'code': '+58', 'digits': '58', 'flag': '🇻🇪', 'label': 'Венесуэла'},
    {'code': '+60', 'digits': '60', 'flag': '🇲🇾', 'label': 'Малайзия'},
    {'code': '+61', 'digits': '61', 'flag': '🇦🇺', 'label': 'Австралия'},
    {'code': '+62', 'digits': '62', 'flag': '🇮🇩', 'label': 'Индонезия'},
    {'code': '+63', 'digits': '63', 'flag': '🇵🇭', 'label': 'Филиппины'},
    {'code': '+64', 'digits': '64', 'flag': '🇳🇿', 'label': 'Новая Зеландия'},
    {'code': '+65', 'digits': '65', 'flag': '🇸🇬', 'label': 'Сингапур'},
    {'code': '+66', 'digits': '66', 'flag': '🇹🇭', 'label': 'Таиланд'},
    {'code': '+81', 'digits': '81', 'flag': '🇯🇵', 'label': 'Япония'},
    {'code': '+82', 'digits': '82', 'flag': '🇰🇷', 'label': 'Южная Корея'},
    {'code': '+84', 'digits': '84', 'flag': '🇻🇳', 'label': 'Вьетнам'},
    {'code': '+86', 'digits': '86', 'flag': '🇨🇳', 'label': 'Китай'},
    {'code': '+90', 'digits': '90', 'flag': '🇹🇷', 'label': 'Турция'},
    {'code': '+91', 'digits': '91', 'flag': '🇮🇳', 'label': 'Индия'},
    {'code': '+92', 'digits': '92', 'flag': '🇵🇰', 'label': 'Пакистан'},
    {'code': '+93', 'digits': '93', 'flag': '🇦🇫', 'label': 'Афганистан'},
    {'code': '+94', 'digits': '94', 'flag': '🇱🇰', 'label': 'Шри-Ланка'},
    {'code': '+95', 'digits': '95', 'flag': '🇲🇲', 'label': 'Мьянма'},
    {'code': '+98', 'digits': '98', 'flag': '🇮🇷', 'label': 'Иран'},
    {'code': '+211', 'digits': '211', 'flag': '🇸🇸', 'label': 'Южный Судан'},
    {'code': '+212', 'digits': '212', 'flag': '🇲🇦', 'label': 'Марокко'},
    {'code': '+213', 'digits': '213', 'flag': '🇩🇿', 'label': 'Алжир'},
    {'code': '+216', 'digits': '216', 'flag': '🇹🇳', 'label': 'Тунис'},
    {'code': '+218', 'digits': '218', 'flag': '🇱🇾', 'label': 'Ливия'},
    {'code': '+220', 'digits': '220', 'flag': '🇬🇲', 'label': 'Гамбия'},
    {'code': '+221', 'digits': '221', 'flag': '🇸🇳', 'label': 'Сенегал'},
    {'code': '+234', 'digits': '234', 'flag': '🇳🇬', 'label': 'Нигерия'},
    {'code': '+250', 'digits': '250', 'flag': '🇷🇼', 'label': 'Руанда'},
    {'code': '+251', 'digits': '251', 'flag': '🇪🇹', 'label': 'Эфиопия'},
    {'code': '+254', 'digits': '254', 'flag': '🇰🇪', 'label': 'Кения'},
    {'code': '+255', 'digits': '255', 'flag': '🇹🇿', 'label': 'Танзания'},
    {'code': '+256', 'digits': '256', 'flag': '🇺🇬', 'label': 'Уганда'},
    {'code': '+260', 'digits': '260', 'flag': '🇿🇲', 'label': 'Замбия'},
    {'code': '+263', 'digits': '263', 'flag': '🇿🇼', 'label': 'Зимбабве'},
    {'code': '+351', 'digits': '351', 'flag': '🇵🇹', 'label': 'Португалия'},
    {'code': '+352', 'digits': '352', 'flag': '🇱🇺', 'label': 'Люксембург'},
    {'code': '+353', 'digits': '353', 'flag': '🇮🇪', 'label': 'Ирландия'},
    {'code': '+354', 'digits': '354', 'flag': '🇮🇸', 'label': 'Исландия'},
    {'code': '+355', 'digits': '355', 'flag': '🇦🇱', 'label': 'Албания'},
    {'code': '+356', 'digits': '356', 'flag': '🇲🇹', 'label': 'Мальта'},
    {'code': '+357', 'digits': '357', 'flag': '🇨🇾', 'label': 'Кипр'},
    {'code': '+358', 'digits': '358', 'flag': '🇫🇮', 'label': 'Финляндия'},
    {'code': '+359', 'digits': '359', 'flag': '🇧🇬', 'label': 'Болгария'},
    {'code': '+370', 'digits': '370', 'flag': '🇱🇹', 'label': 'Литва'},
    {'code': '+371', 'digits': '371', 'flag': '🇱🇻', 'label': 'Латвия'},
    {'code': '+372', 'digits': '372', 'flag': '🇪🇪', 'label': 'Эстония'},
    {'code': '+373', 'digits': '373', 'flag': '🇲🇩', 'label': 'Молдова'},
    {'code': '+374', 'digits': '374', 'flag': '🇦🇲', 'label': 'Армения'},
    {'code': '+375', 'digits': '375', 'flag': '🇧🇾', 'label': 'Беларусь'},
    {'code': '+376', 'digits': '376', 'flag': '🇦🇩', 'label': 'Андорра'},
    {'code': '+377', 'digits': '377', 'flag': '🇲🇨', 'label': 'Монако'},
    {'code': '+378', 'digits': '378', 'flag': '🇸🇲', 'label': 'Сан-Марино'},
    {'code': '+380', 'digits': '380', 'flag': '🇺🇦', 'label': 'Украина'},
    {'code': '+381', 'digits': '381', 'flag': '🇷🇸', 'label': 'Сербия'},
    {'code': '+382', 'digits': '382', 'flag': '🇲🇪', 'label': 'Черногория'},
    {'code': '+383', 'digits': '383', 'flag': '🇽🇰', 'label': 'Косово'},
    {'code': '+385', 'digits': '385', 'flag': '🇭🇷', 'label': 'Хорватия'},
    {'code': '+386', 'digits': '386', 'flag': '🇸🇮', 'label': 'Словения'},
    {'code': '+387', 'digits': '387', 'flag': '🇧🇦', 'label': 'Босния и Герцеговина'},
    {'code': '+389', 'digits': '389', 'flag': '🇲🇰', 'label': 'Северная Македония'},
    {'code': '+420', 'digits': '420', 'flag': '🇨🇿', 'label': 'Чехия'},
    {'code': '+421', 'digits': '421', 'flag': '🇸🇰', 'label': 'Словакия'},
    {'code': '+423', 'digits': '423', 'flag': '🇱🇮', 'label': 'Лихтенштейн'},
    {'code': '+852', 'digits': '852', 'flag': '🇭🇰', 'label': 'Гонконг'},
    {'code': '+853', 'digits': '853', 'flag': '🇲🇴', 'label': 'Макао'},
    {'code': '+855', 'digits': '855', 'flag': '🇰🇭', 'label': 'Камбоджа'},
    {'code': '+856', 'digits': '856', 'flag': '🇱🇦', 'label': 'Лаос'},
    {'code': '+880', 'digits': '880', 'flag': '🇧🇩', 'label': 'Бангладеш'},
    {'code': '+886', 'digits': '886', 'flag': '🇹🇼', 'label': 'Тайвань'},
    {'code': '+960', 'digits': '960', 'flag': '🇲🇻', 'label': 'Мальдивы'},
    {'code': '+961', 'digits': '961', 'flag': '🇱🇧', 'label': 'Ливан'},
    {'code': '+962', 'digits': '962', 'flag': '🇯🇴', 'label': 'Иордания'},
    {'code': '+963', 'digits': '963', 'flag': '🇸🇾', 'label': 'Сирия'},
    {'code': '+964', 'digits': '964', 'flag': '🇮🇶', 'label': 'Ирак'},
    {'code': '+965', 'digits': '965', 'flag': '🇰🇼', 'label': 'Кувейт'},
    {'code': '+966', 'digits': '966', 'flag': '🇸🇦', 'label': 'Саудовская Аравия'},
    {'code': '+967', 'digits': '967', 'flag': '🇾🇪', 'label': 'Йемен'},
    {'code': '+968', 'digits': '968', 'flag': '🇴🇲', 'label': 'Оман'},
    {'code': '+970', 'digits': '970', 'flag': '🇵🇸', 'label': 'Палестина'},
    {'code': '+971', 'digits': '971', 'flag': '🇦🇪', 'label': 'ОАЭ'},
    {'code': '+972', 'digits': '972', 'flag': '🇮🇱', 'label': 'Израиль'},
    {'code': '+973', 'digits': '973', 'flag': '🇧🇭', 'label': 'Бахрейн'},
    {'code': '+974', 'digits': '974', 'flag': '🇶🇦', 'label': 'Катар'},
    {'code': '+975', 'digits': '975', 'flag': '🇧🇹', 'label': 'Бутан'},
    {'code': '+976', 'digits': '976', 'flag': '🇲🇳', 'label': 'Монголия'},
    {'code': '+977', 'digits': '977', 'flag': '🇳🇵', 'label': 'Непал'},
    {'code': '+992', 'digits': '992', 'flag': '🇹🇯', 'label': 'Таджикистан'},
    {'code': '+993', 'digits': '993', 'flag': '🇹🇲', 'label': 'Туркменистан'},
    {'code': '+994', 'digits': '994', 'flag': '🇦🇿', 'label': 'Азербайджан'},
    {'code': '+995', 'digits': '995', 'flag': '🇬🇪', 'label': 'Грузия'},
    {'code': '+996', 'digits': '996', 'flag': '🇰🇬', 'label': 'Кыргызстан'},
    {'code': '+998', 'digits': '998', 'flag': '🇺🇿', 'label': 'Узбекистан'},
  ];

  Future<void> _pickCountryCode() async {
    final q = TextEditingController();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1C1C1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setS) {
          final f = q.text.trim().toLowerCase();
          final list = _countries.where((c) {
            if (f.isEmpty) return true;
            return '${c['label']}${c['code']}${c['digits']}'.toLowerCase().contains(f);
          }).toList();
          return SizedBox(
            height: MediaQuery.of(ctx).size.height * 0.7,
            child: Column(children: [
              const SizedBox(height: 10),
              Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
              Padding(
                padding: const EdgeInsets.all(12),
                child: TextField(
                  controller: q,
                  onChanged: (_) => setS(() {}),
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    hintText: 'Страна или код',
                    hintStyle: TextStyle(color: Colors.white54),
                    prefixIcon: Icon(Icons.search, color: Colors.white54),
                  ),
                ),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: list.length,
                  itemBuilder: (_, i) {
                    final c = list[i];
                    return ListTile(
                      title: Text('${c['flag']} ${c['label']}', style: const TextStyle(color: Colors.white)),
                      trailing: Text(c['code']!, style: const TextStyle(color: Colors.white70)),
                      onTap: () {
                        setState(() {
                          _ccCode = c['code']!;
                          _ccDigits = c['digits']!;
                          _ccFlag = c['flag']!;
                          _ccLabel = c['label']!;
                        });
                        Navigator.pop(ctx);
                      },
                    );
                  },
                ),
              ),
            ]),
          );
        });
      },
    );
    q.dispose();
  }

  /// Национальный номер + выбранный код страны (выбор пользователя)
  String _canonicalizePhoneDigits(String raw) {
    var dig = raw.replaceAll(RegExp(r'[^\d]'), '');
    if (dig.isEmpty) return '';
    // если вставили полный номер с кодом страны — не дублируем
    if (dig.startsWith(_ccDigits) && dig.length > _ccDigits.length + 6) {
      return dig; // already has country digits
    }
    // Россия/Казахстан: 8XXXXXXXXXX → 7…
    if (_ccDigits == '7' && dig.length == 11 && dig.startsWith('8')) {
      dig = '7${dig.substring(1)}';
      return dig;
    }
    if (dig.startsWith(_ccDigits)) return dig;
    return '$_ccDigits$dig';
  }

  /// Synthetic email как на вебе: `цифры@phone.signal-line.local`
  List<String> _phoneAuthEmails(String raw) {
    final digitsRaw = raw.replaceAll(RegExp(r'[^\d]'), '');
    final canon = _canonicalizePhoneDigits(raw);
    if (canon.length < 10) return const [];
    final variants = <String>{
      canon,
      if (digitsRaw.isNotEmpty) digitsRaw,
      if (canon.length == 11 && canon.startsWith('7')) '8${canon.substring(1)}',
      if (digitsRaw.length == 11 && digitsRaw.startsWith('7'))
        '8${digitsRaw.substring(1)}',
    };
    return variants
        .map((d) => '$d@phone.signal-line.local')
        .toList();
  }

  String? _resolveLoginEmail() {
    final email = emailC.text.trim().toLowerCase();
    final phone = phoneC.text.trim();
    if (email.isNotEmpty) return email;
    if (phone.isNotEmpty) {
      final list = _phoneAuthEmails(phone);
      if (list.isEmpty) return null;
      return list.first;
    }
    return null;
  }

  /// Кандидаты для входа — те же варианты, что перебирает веб
  List<String> _loginEmailCandidates() {
    final email = emailC.text.trim().toLowerCase();
    final phone = phoneC.text.trim();
    final out = <String>{};
    if (email.isNotEmpty) out.add(email);
    if (phone.isNotEmpty) out.addAll(_phoneAuthEmails(phone));
    return out.toList();
  }

  @override
  void initState() {
    super.initState();
    emailC.addListener(_onContactChanged);
    phoneC.addListener(_onContactChanged);
    _logoCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..forward();
    _cardCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 750),
    )..forward();
    _blobCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    )..repeat(reverse: true);
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);
    _shimmerCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat();
  }

  @override
  void dispose() {
    emailC.removeListener(_onContactChanged);
    phoneC.removeListener(_onContactChanged);
    _logoCtrl.dispose();
    _cardCtrl.dispose();
    _blobCtrl.dispose();
    _pulseCtrl.dispose();
    _shimmerCtrl.dispose();
    emailC.dispose();
    phoneC.dispose();
    passC.dispose();
    nameC.dispose();
    userC.dispose();
    super.dispose();
  }

  void _switchMode(bool login) {
    setState(() {
      isLogin = login;
      regStep = 0;
      acceptedTerms = false;
      error = null;
      emailC.clear();
      phoneC.clear();
    });
    _cardCtrl
      ..reset()
      ..forward();
  }

  void _openLegal(String kind) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SLineLegalDocScreen(kind: kind),
      ),
    );
  }


  /// Диалог: код из чата SLine (не из почты)
  Future<String?> _askSLineCode({String? hint}) async {
    final c = TextEditingController();
    final code = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Подтверждение входа'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                hint ??
                    'Вам придёт код в SLine, введите его здесь для подтверждения личности.',
                style: TextStyle(
                  fontSize: 13.5,
                  height: 1.4,
                  color: Colors.black.withValues(alpha: 0.55),
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: c,
                keyboardType: TextInputType.text,
                maxLength: 12,
                autofocus: true,
                textAlign: TextAlign.center,
                textCapitalization: TextCapitalization.characters,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 2,
                ),
                decoration: const InputDecoration(
                  labelText: 'Код из SLine или резервный',
                  hintText: '123456 или AB12-CD34',
                  counterText: '',
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
              ),
              const SizedBox(height: 8),
              Text(
                'Нет доступа к SLine? Введите резервный код (Настройки → Резервные коды).',
                style: TextStyle(fontSize: 12, color: Colors.black.withValues(alpha: 0.45)),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, null),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, c.text.trim()),
              child: const Text('Подтвердить'),
            ),
          ],
        );
      },
    );
    c.dispose();
    return code;
  }

  /// Запросить код в SLine-чат целевого аккаунта (как на вебе)
  Future<void> _requestSLineLoginCode(String login) async {
    final code =
        (100000 + (DateTime.now().millisecondsSinceEpoch % 900000)).toString();
    String? uid;
    try {
      // поиск профиля по email / username / phone
      final q = login.trim().toLowerCase().replaceAll('@', '');
      final dig = q.replaceAll(RegExp(r'[^\d]'), '');
      final snap = await profilesRef().limitToFirst(500).get();
      if (snap.exists && snap.value is Map) {
        for (final e in (snap.value as Map).entries) {
          if (e.value is! Map) continue;
          final m = Map<String, dynamic>.from(e.value as Map);
          final un = (m['username'] ?? '').toString().toLowerCase();
          final em = (m['email'] ?? '').toString().toLowerCase();
          final ph = (m['phone'] ?? '').toString().replaceAll(RegExp(r'[^\d]'), '');
          if (un == q ||
              em == q ||
              (dig.length >= 8 && ph.contains(dig))) {
            uid = e.key.toString();
            break;
          }
        }
      }
    } catch (_) {}
    try {
      await FirebaseDatabase.instance.ref('device_link/$code').set({
        'login': login.toLowerCase(),
        'uid': uid,
        'created': DateTime.now().millisecondsSinceEpoch,
        'status': 'pending',
        'code': code,
        'for_sline': true,
      });
      if (uid != null) {
        await FirebaseDatabase.instance
            .ref('pending_login_codes/$uid/$code')
            .set({
          'code': code,
          'login': login.toLowerCase(),
          'created': DateTime.now().millisecondsSinceEpoch,
          'expires': DateTime.now()
              .add(const Duration(minutes: 5))
              .millisecondsSinceEpoch,
        });
        await sendSLineSystemMessage(uid, formatSLineLoginCodeMessage(code));
      }
    } catch (_) {}
  }

  Future<void> submit() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      // Неверные дата/время на телефоне ломают Firebase Auth
      final now = DateTime.now();
      if (now.year < 2024 || now.year > 2035) {
        setState(() => error =
            'Смените дату или время на телефоне, чтобы приложение работало');
        return;
      }
      final pass = passC.text.trim();
      final loginEmail = _resolveLoginEmail();
      final phoneRaw = phoneC.text.trim();
      final phoneDigits = phoneRaw.isEmpty
          ? ''
          : _canonicalizePhoneDigits(phoneRaw);
      final displayEmail = emailC.text.trim().toLowerCase();

      if (isLogin) {
        final candidates = _loginEmailCandidates();
        if (candidates.isEmpty) {
          setState(() => error = 'Введите email или номер телефона');
          return;
        }
        if (pass.isEmpty) {
          setState(() => error = 'Введите пароль');
          return;
        }
        if (pass.length < 6) {
          setState(() => error = 'Пароль не менее 6 символов');
          return;
        }
        // Как на вебе: пробуем все варианты email (7…/8… @phone.signal-line.local)
        // Держим LoginScreen, пока не решим: код или MainShell
        // (иначе AuthGate на долю секунды открывает чаты)
        SLineAuthLock.holdLogin.value = true;
        SLineAuthLock.pendingCode.value = false;
        Object? lastErr;
        var signedIn = false;
        try {
          for (final em in candidates) {
            try {
              final _cred = await FirebaseAuth.instance
                  .signInWithEmailAndPassword(email: em, password: pass);
              if (_cred.user != null) {
                signedIn = true;
                break;
              }
            } catch (e) {
              lastErr = e;
            }
          }
          if (!signedIn) {
            SLineAuthLock.holdLogin.value = false;
            if (lastErr != null) throw lastErr;
            throw Exception('Неверный логин или пароль');
          }
          final u = FirebaseAuth.instance.currentUser;
          if (u == null) {
            SLineAuthLock.holdLogin.value = false;
            throw Exception('Неверный логин или пароль');
          }
          // Сохранить в список аккаунтов для переключения
          try {
            final loginUsed = (u.email ?? candidates.first).toString();
            String label = loginUsed;
            try {
              final pr = await loadProfile(u.uid);
              if (pr != null) {
                label = pr.username.isNotEmpty
                    ? '@${pr.username}'
                    : pr.displayName;
              }
            } catch (_) {}
            await SLineAccounts.upsert(
              uid: u.uid,
              login: loginUsed,
              password: pass,
              label: label,
            );
          } catch (_) {}
          // Сначала решаем, нужен ли код — только потом снимаем hold
          // Вход по номеру: всегда код (Telegram / SLine / PIN / ключ)
          final phoneLogin = phoneC.text.trim().isNotEmpty && emailC.text.trim().isEmpty;
          final needCode = phoneLogin || await slNeedSLineCode(u.uid);
          try {
            await slTouchUserSession(u.uid, announceLogin: false);
          } catch (_) {}
          try {
            await ensureWebProfile(u);
          } catch (_) {}
          if (needCode) {
            await slSetAwaitingLoginCode(u.uid, true);
            SLineAuthLock.holdLogin.value = false; // → SLineCodeGate
          } else {
            try {
              await ensureSLineSystemChat(u.uid);
            } catch (_) {}
            SLineAuthLock.pendingCode.value = false;
            SLineAuthLock.holdLogin.value = false; // → MainShell
          }
        } catch (e) {
          SLineAuthLock.holdLogin.value = false;
          SLineAuthLock.pendingCode.value = false;
          rethrow;
        }
      } else {
        if (!acceptedTerms) {
          setState(() =>
              error = 'Примите Пользовательское соглашение и Политику конфиденциальности');
          return;
        }
        if (regStep == 0) {
          if (loginEmail == null || loginEmail.isEmpty) {
            setState(() => error = 'Введите email или номер телефона');
            return;
          }
          if (displayEmail.isNotEmpty && !displayEmail.contains('@')) {
            setState(() => error = 'Введите корректный email');
            return;
          }
          if (phoneRaw.isNotEmpty && phoneDigits.length < 10) {
            setState(() => error = 'Введите корректный номер телефона');
            return;
          }
          if (pass.length < 6) {
            setState(() => error = 'Пароль не менее 6 символов');
            return;
          }
          setState(() {
            regStep = 1;
            loading = false;
            error = null;
          });
          _cardCtrl
            ..reset()
            ..forward();
          return;
        }
        final name = nameC.text.trim();
        final username = userC.text
            .trim()
            .toLowerCase()
            .replaceAll(RegExp(r'[^a-z0-9_]'), '');
        if (name.isEmpty) {
          setState(() => error = 'Как вас зовут?');
          return;
        }
        if (username.length < 3) {
          setState(() => error = 'Username от 3 символов (a-z, 0-9, _)');
          return;
        }
        if (loginEmail == null || loginEmail.isEmpty) {
          setState(() => error = 'Введите email или номер телефона');
          return;
        }
        // Нельзя занять уже существующий username
        try {
          final taken = await isUsernameTaken(username);
          if (taken) {
            setState(() => error = 'Username @$username уже занят');
            return;
          }
        } catch (_) {}
        // Тот же synthetic email, что на вебе: N@phone.signal-line.local
        final cred = await FirebaseAuth.instance
            .createUserWithEmailAndPassword(email: loginEmail, password: pass);
        final newUser = FirebaseAuth.instance.currentUser;
        if (newUser != null) {
          await slTouchUserSession(newUser.uid);
          await ensureSLineSystemChat(newUser.uid);
          // Код на email при регистрации по почте
          try {
            String? realMail;
            if (displayEmail.isNotEmpty &&
                displayEmail.contains('@') &&
                !isSyntheticPhoneEmail(displayEmail)) {
              realMail = displayEmail;
            } else if (loginEmail != null &&
                loginEmail.contains('@') &&
                !isSyntheticPhoneEmail(loginEmail)) {
              realMail = loginEmail.trim().toLowerCase();
            }
            if (realMail != null) {
              final regCode = (100000 +
                      (DateTime.now().millisecondsSinceEpoch % 900000))
                  .toString();
              try {
                await FirebaseDatabase.instance
                    .ref('email_bind_codes/${newUser.uid}')
                    .set({
                  'email': realMail,
                  'code': regCode,
                  'purpose': 'register',
                  'expires': DateTime.now()
                      .add(const Duration(minutes: 15))
                      .millisecondsSinceEpoch,
                });
              } catch (_) {}
              final mailErr = await slSendLoginEmailCode(realMail, regCode);
              if (mounted) {
                final entered = await showDialog<String>(
                  context: context,
                  barrierDismissible: false,
                  builder: (ctx) {
                    final c = TextEditingController();
                    return AlertDialog(
                      title: const Text('Код с email'),
                      content: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            mailErr == null
                                ? 'Мы отправили код на $realMail. Введите его для подтверждения.'
                                : 'Не удалось отправить письмо ($mailErr). Если письмо не пришло — проверьте Resend / домен. Можно пропустить и сохранить резервные коды.',
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: c,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Код из письма',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ],
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, ''),
                          child: const Text('Пропустить'),
                        ),
                        FilledButton(
                          onPressed: () => Navigator.pop(ctx, c.text.trim()),
                          child: const Text('Подтвердить'),
                        ),
                      ],
                    );
                  },
                );
                if (entered != null && entered.isNotEmpty) {
                  var ok = entered == regCode;
                  if (!ok) {
                    try {
                      final s = await FirebaseDatabase.instance
                          .ref('email_bind_codes/${newUser.uid}')
                          .get();
                      if (s.exists && s.value is Map) {
                        final m = Map<String, dynamic>.from(s.value as Map);
                        ok = (m['code'] ?? '').toString() == entered;
                      }
                    } catch (_) {}
                  }
                  if (!ok && mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content: Text('Неверный код email — продолжаем')),
                    );
                  } else if (ok) {
                    try {
                      await profilesRef().child(newUser.uid).update({
                        'email': realMail,
                        'email_bound': true,
                        'email_verified_at':
                            DateTime.now().millisecondsSinceEpoch,
                      });
                    } catch (_) {}
                  }
                }
              }
            }
          } catch (_) {}
          try {
            final codes = generateRecoveryCodes();
            await saveRecoveryCodes(newUser.uid, codes);
            SLineAuthLock.holdLogin.value = true;
            if (mounted) {
              await showDialog(
                context: context,
                barrierDismissible: false,
                builder: (ctx) => AlertDialog(
                  title: const Text('Резервные коды'),
                  content: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text(
                          'Сохраните эти коды. Если потеряете устройство, ими можно войти без кода из чата SLine. Каждый код — одноразовый.',
                          style: TextStyle(fontSize: 13),
                        ),
                        const SizedBox(height: 12),
                        ...codes.map((c) => Padding(
                              padding: const EdgeInsets.symmetric(vertical: 3),
                              child: SelectableText(
                                c,
                                style: const TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 1.2,
                                ),
                              ),
                            )),
                      ],
                    ),
                  ),
                  actions: [
                    FilledButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('Я сохранил коды'),
                    ),
                  ],
                ),
              );
            }
            // Регистрация по номеру — код из Telegram/SLine обязателен
            if (phoneC.text.trim().isNotEmpty) {
              await slSetAwaitingLoginCode(newUser.uid, true);
            }
            SLineAuthLock.holdLogin.value = false;
          } catch (_) {
            SLineAuthLock.holdLogin.value = false;
          }
          try {
            await SLineAccounts.upsert(
              uid: newUser.uid,
              login: loginEmail ?? newUser.email ?? '',
              password: pass,
              label: username.isNotEmpty ? '@$username' : name,
            );
          } catch (_) {}
        }
        await cred.user!.updateDisplayName(name);
        final colors = [
          '#4C7CF3',
          '#6D5DF6',
          '#14B8A6',
          '#F59E0B',
          '#EC4899',
          '#8B5CF6'
        ];
        final color = colors[name.hashCode.abs() % colors.length];
        final canonPhone = phoneDigits.isNotEmpty
            ? _canonicalizePhoneDigits(phoneDigits)
            : '';
        try {
          await profilesRef().child(cred.user!.uid).set({
            'id': cred.user!.uid,
            // В профиле как на вебе: synthetic email при регистрации по телефону
            'email': displayEmail.isNotEmpty ? displayEmail : loginEmail,
            if (canonPhone.isNotEmpty) 'phone': '+$canonPhone',
            'first_name': name,
            'last_name': '',
            'username': username,
            'color': color,
            'bio': '',
            'created_at': DateTime.now().toIso8601String(),
          });
        } catch (e) {
          setState(() => error = permissionHelp(e));
          return;
        }
        // Служебный чат SLine
        try {
          final uid = cred.user!.uid;
          await ensureSLineSystemChat(uid);
          await sendSLineSystemMessage(
            uid,
            'Добро пожаловать в SLine, @$username!\n\n'
            'Сюда будут приходить коды подтверждения и уведомления о входе с новых устройств. '
            'Этот чат можно удалить в любой момент.',
          );
        } catch (_) {}
      }
    } on FirebaseAuthException catch (e) {
      final now = DateTime.now();
      if (now.year < 2024 || now.year > 2035) {
        setState(() => error =
            'Смените дату или время на телефоне, чтобы приложение работало');
      } else {
        final map = {
          'email-already-in-use': 'Этот email уже зарегистрирован',
          'weak-password': 'Слишком простой пароль',
          'invalid-email': 'Некорректный email',
          'user-not-found': 'Аккаунт не найден',
          'wrong-password': 'Неверный пароль',
          'invalid-credential': 'Неверный email, номер или пароль',
          'too-many-requests': 'Слишком много попыток, подождите',
          'network-request-failed':
              'Нет сети. Если дата на телефоне неверная — исправьте её.',
        };
        setState(() => error = map[e.code] ?? e.message ?? e.code);
      }
    } catch (e) {
      setState(() => error = permissionHelp(e));
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  InputDecoration _fieldDeco({
    required String label,
    required IconData icon,
    String? prefix,
    Widget? suffix,
  }) {
    return InputDecoration(
      labelText: label,
      prefixText: prefix,
      prefixIcon: Icon(icon, size: 20, color: const Color(0xFF2563EB)),
      suffixIcon: suffix,
      filled: true,
      fillColor: const Color(0xFFF1F5F9),
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: Colors.black.withValues(alpha: 0.04)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Color(0xFF2563EB), width: 1.6),
      ),
      labelStyle: TextStyle(
          color: Colors.black.withValues(alpha: 0.42), fontSize: 14),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: Stack(
        children: [
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFF1E3A8A),
                    Color(0xFF1D4ED8),
                    Color(0xFF2563EB),
                    Color(0xFF3B82F6),
                  ],
                ),
              ),
            ),
          ),
          AnimatedBuilder(
            animation: _blobCtrl,
            builder: (_, __) {
              final t = _blobCtrl.value;
              return Stack(children: [
                Positioned(
                  top: -90 + 20 * t,
                  right: -70,
                  child: _AuthBlob(
                    size: 260,
                    color: Colors.white.withValues(alpha: 0.10 + 0.05 * t),
                  ),
                ),
                Positioned(
                  bottom: -60 + 16 * (1 - t),
                  left: -50,
                  child: _AuthBlob(
                    size: 220,
                    color: const Color(0xFF93C5FD)
                        .withValues(alpha: 0.18 + 0.08 * t),
                  ),
                ),
                Positioned(
                  top: size.height * 0.4,
                  right: -30 + 12 * t,
                  child: _AuthBlob(
                    size: 140,
                    color: Colors.white.withValues(alpha: 0.07 + 0.04 * t),
                  ),
                ),
              ]);
            },
          ),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(20, 16, 20, 16 + bottomInset * 0.2),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 400),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      FadeTransition(
                        opacity: CurvedAnimation(
                            parent: _logoCtrl, curve: Curves.easeOut),
                        child: ScaleTransition(
                          scale: Tween(begin: 0.6, end: 1.0).animate(
                            CurvedAnimation(
                              parent: _logoCtrl,
                              curve: Curves.elasticOut,
                            ),
                          ),
                          child: Column(
                            children: [
                              AnimatedBuilder(
                                animation: _pulseCtrl,
                                builder: (_, child) {
                                  final p = _pulseCtrl.value;
                                  return Container(
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.white
                                              .withValues(alpha: 0.28 + 0.18 * p),
                                          blurRadius: 30 + 16 * p,
                                          spreadRadius: 2 + 5 * p,
                                        ),
                                      ],
                                    ),
                                    child: child,
                                  );
                                },
                                child: Container(
                                  width: 104,
                                  height: 104,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: Colors.white
                                          .withValues(alpha: 0.4),
                                      width: 3,
                                    ),
                                  ),
                                  child: ClipOval(
                                    child: Image.asset(
                                      'assets/icon/app_icon.png',
                                      width: 104,
                                      height: 104,
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, __, ___) =>
                                          const _SLineLogoMark(size: 104),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 16),
                              const Text(
                                'SLine',
                                style: TextStyle(
                                  fontSize: 32,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -0.6,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Мессенджер с E2EE',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white.withValues(alpha: 0.85),
                                ),
                              ),
                              const SizedBox(height: 10),
                              AnimatedSwitcher(
                                duration: const Duration(milliseconds: 360),
                                child: Text(
                                  isLogin
                                      ? 'С возвращением'
                                      : (regStep == 0
                                          ? 'Создайте аккаунт'
                                          : 'Как вас зовут?'),
                                  key: ValueKey('h-$isLogin-$regStep'),
                                  style: TextStyle(
                                    fontSize: 15,
                                    color: Colors.white.withValues(alpha: 0.7),
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 22),
                      FadeTransition(
                        opacity: CurvedAnimation(
                            parent: _cardCtrl, curve: Curves.easeOut),
                        child: SlideTransition(
                          position: Tween(
                            begin: const Offset(0, 0.12),
                            end: Offset.zero,
                          ).animate(CurvedAnimation(
                              parent: _cardCtrl, curve: Curves.easeOutCubic)),
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(28),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.2),
                                  blurRadius: 40,
                                  offset: const Offset(0, 16),
                                ),
                              ],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                    if (isLogin || regStep == 0)
                                      Container(
                                        padding: const EdgeInsets.all(4),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFF1F5F9),
                                          borderRadius:
                                              BorderRadius.circular(14),
                                        ),
                                        child: Row(
                                          children: [
                                            Expanded(
                                              child: _AuthTab(
                                                label: 'Вход',
                                                active: isLogin,
                                                onTap: () => _switchMode(true),
                                              ),
                                            ),
                                            Expanded(
                                              child: _AuthTab(
                                                label: 'Регистрация',
                                                active: !isLogin,
                                                onTap: () =>
                                                    _switchMode(false),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    if (!isLogin) ...[
                                      const SizedBox(height: 18),
                                      Row(
                                        children: [
                                          _RegDot(
                                              active: true, done: regStep > 0),
                                          Expanded(
                                            child: Container(
                                              height: 2,
                                              color: regStep > 0
                                                  ? const Color(0xFF2563EB)
                                                  : Colors.black12,
                                            ),
                                          ),
                                          _RegDot(
                                              active: regStep >= 1,
                                              done: false),
                                        ],
                                      ),
                                      const SizedBox(height: 6),
                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text(
                                            'Аккаунт',
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600,
                                              color: regStep == 0
                                                  ? const Color(0xFF2563EB)
                                                  : Colors.black38,
                                            ),
                                          ),
                                          Text(
                                            'Профиль',
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600,
                                              color: regStep == 1
                                                  ? const Color(0xFF2563EB)
                                                  : Colors.black38,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                    const SizedBox(height: 20),
                                    AnimatedSwitcher(
                                      duration:
                                          const Duration(milliseconds: 320),
                                      switchInCurve: Curves.easeOut,
                                      switchOutCurve: Curves.easeIn,
                                      transitionBuilder: (child, anim) =>
                                          FadeTransition(
                                        opacity: anim,
                                        child: SlideTransition(
                                          position: Tween(
                                            begin: const Offset(0.04, 0),
                                            end: Offset.zero,
                                          ).animate(anim),
                                          child: child,
                                        ),
                                      ),
                                      child: isLogin || regStep == 0
                                          ? Column(
                                              key: const ValueKey('step0'),
                                              children: [
                                                AnimatedSize(
                                                  duration: const Duration(
                                                      milliseconds: 280),
                                                  curve: Curves.easeOutCubic,
                                                  alignment: Alignment.topCenter,
                                                  child: _showEmail
                                                      ? Padding(
                                                          padding:
                                                              EdgeInsets.only(
                                                            bottom: _showPhone
                                                                ? 12
                                                                : 0,
                                                          ),
                                                          child: TextField(
                                                            controller: emailC,
                                                            keyboardType:
                                                                TextInputType
                                                                    .emailAddress,
                                                            textInputAction:
                                                                TextInputAction
                                                                    .next,
                                                            decoration:
                                                                _fieldDeco(
                                                              label: 'Email / username',
                                                              icon: Icons
                                                                  .mail_outline_rounded,
                                                            ),
                                                          ),
                                                        )
                                                      : const SizedBox
                                                          .shrink(),
                                                ),
                                                AnimatedSize(
                                                  duration: const Duration(
                                                      milliseconds: 280),
                                                  curve: Curves.easeOutCubic,
                                                  alignment: Alignment.topCenter,
                                                  child: _showPhone
                                                      ? Padding(
                                                          padding:
                                                              const EdgeInsets
                                                                  .only(
                                                                  bottom: 12),
                                                          child: Row(
                                                          children: [
                                                            InkWell(
                                                              onTap: _pickCountryCode,
                                                              borderRadius: BorderRadius.circular(14),
                                                              child: Container(
                                                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                                                                decoration: BoxDecoration(
                                                                  borderRadius: BorderRadius.circular(14),
                                                                  border: Border.all(color: Colors.white24),
                                                                  color: Colors.white.withOpacity(0.06),
                                                                ),
                                                                child: Text(
                                                                  '$_ccFlag $_ccCode',
                                                                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                                                                ),
                                                              ),
                                                            ),
                                                            const SizedBox(width: 8),
                                                            Expanded(
                                                              child: TextField(
                                                                controller: phoneC,
                                                                keyboardType: TextInputType.phone,
                                                                textInputAction: TextInputAction.next,
                                                                decoration: _fieldDeco(
                                                                  label: 'Номер телефона',
                                                                  icon: Icons.phone_outlined,
                                                                ),
                                                              ),
                                                            ),
                                                          ],
                                                        ),
                                                        )
                                                      : const SizedBox
                                                          .shrink(),
                                                ),
                                                if (_showEmail && _showPhone)
                                                  Padding(
                                                    padding:
                                                        const EdgeInsets.only(
                                                            bottom: 10),
                                                    child: Text(
                                                      'Email или номер целиком. Код страны (+7) не подставляется',
                                                      style: TextStyle(
                                                        fontSize: 11.5,
                                                        color: Colors.black
                                                            .withValues(
                                                                alpha: 0.38),
                                                      ),
                                                    ),
                                                  ),
                                                TextField(
                                                  controller: passC,
                                                  obscureText: obscure,
                                                  textInputAction: isLogin
                                                      ? TextInputAction.done
                                                      : TextInputAction.next,
                                                  onSubmitted: (_) {
                                                    if (isLogin) submit();
                                                  },
                                                  decoration: _fieldDeco(
                                                    label: 'Пароль',
                                                    icon: Icons
                                                        .lock_outline_rounded,
                                                    suffix: IconButton(
                                                      icon: Icon(
                                                        obscure
                                                            ? Icons
                                                                .visibility_outlined
                                                            : Icons
                                                                .visibility_off_outlined,
                                                        size: 20,
                                                        color: Colors.black45,
                                                      ),
                                                      onPressed: () =>
                                                          setState(() =>
                                                              obscure =
                                                                  !obscure),
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            )
                                          : Column(
                                              key: const ValueKey('step1'),
                                              children: [
                                                TextField(
                                                  controller: nameC,
                                                  textCapitalization:
                                                      TextCapitalization
                                                          .words,
                                                  textInputAction:
                                                      TextInputAction.next,
                                                  decoration: _fieldDeco(
                                                    label: 'Ваше имя',
                                                    icon:
                                                        Icons.badge_outlined,
                                                  ),
                                                ),
                                                const SizedBox(height: 12),
                                                TextField(
                                                  controller: userC,
                                                  textInputAction:
                                                      TextInputAction.done,
                                                  onSubmitted: (_) => submit(),
                                                  decoration: _fieldDeco(
                                                    label: 'Username',
                                                    icon: Icons
                                                        .alternate_email_rounded,
                                                    prefix: '@',
                                                  ),
                                                ),
                                                const SizedBox(height: 8),
                                                Text(
                                                  'Так вас будут находить в SLine',
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    color: Colors.black
                                                        .withValues(
                                                            alpha: 0.4),
                                                  ),
                                                ),
                                              ],
                                            ),
                                    ),
                                    if (error != null) ...[
                                      const SizedBox(height: 14),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 12, vertical: 10),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFFEE2E2),
                                          borderRadius:
                                              BorderRadius.circular(12),
                                        ),
                                        child: Row(
                                          children: [
                                            const Icon(Icons.error_outline,
                                                size: 18,
                                                color: Color(0xFFDC2626)),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: Text(
                                                error!,
                                                style: const TextStyle(
                                                  color: Color(0xFFB91C1C),
                                                  fontSize: 13,
                                                  fontWeight: FontWeight.w500,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                    if (!isLogin) ...[
                                      const SizedBox(height: 16),
                                      Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          SizedBox(
                                            width: 24,
                                            height: 24,
                                            child: Checkbox(
                                              value: acceptedTerms,
                                              activeColor:
                                                  const Color(0xFF2563EB),
                                              materialTapTargetSize:
                                                  MaterialTapTargetSize
                                                      .shrinkWrap,
                                              visualDensity:
                                                  VisualDensity.compact,
                                              onChanged: loading
                                                  ? null
                                                  : (v) => setState(() =>
                                                      acceptedTerms =
                                                          v ?? false),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Wrap(
                                              crossAxisAlignment:
                                                  WrapCrossAlignment.center,
                                              children: [
                                                Text(
                                                  'Я принимаю ',
                                                  style: TextStyle(
                                                    fontSize: 12.5,
                                                    height: 1.35,
                                                    color: Colors.black
                                                        .withValues(
                                                            alpha: 0.65),
                                                  ),
                                                ),
                                                GestureDetector(
                                                  onTap: () =>
                                                      _openLegal('terms'),
                                                  child: const Text(
                                                    'Пользовательское соглашение',
                                                    style: TextStyle(
                                                      fontSize: 12.5,
                                                      height: 1.35,
                                                      color: Color(0xFF2563EB),
                                                      fontWeight:
                                                          FontWeight.w600,
                                                      decoration: TextDecoration
                                                          .underline,
                                                    ),
                                                  ),
                                                ),
                                                Text(
                                                  ' и ',
                                                  style: TextStyle(
                                                    fontSize: 12.5,
                                                    height: 1.35,
                                                    color: Colors.black
                                                        .withValues(
                                                            alpha: 0.65),
                                                  ),
                                                ),
                                                GestureDetector(
                                                  onTap: () =>
                                                      _openLegal('privacy'),
                                                  child: const Text(
                                                    'Политику конфиденциальности',
                                                    style: TextStyle(
                                                      fontSize: 12.5,
                                                      height: 1.35,
                                                      color: Color(0xFF2563EB),
                                                      fontWeight:
                                                          FontWeight.w600,
                                                      decoration: TextDecoration
                                                          .underline,
                                                    ),
                                                  ),
                                                ),
                                                Text(
                                                  ' и даю согласие на обработку персональных данных.',
                                                  style: TextStyle(
                                                    fontSize: 12.5,
                                                    height: 1.35,
                                                    color: Colors.black
                                                        .withValues(
                                                            alpha: 0.65),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                    const SizedBox(height: 22),
                                    SizedBox(
                                      height: 52,
                                      child: Opacity(
                                        opacity: (!isLogin &&
                                                !acceptedTerms &&
                                                !loading)
                                            ? 0.45
                                            : 1,
                                        child: DecoratedBox(
                                          decoration: BoxDecoration(
                                            borderRadius:
                                                BorderRadius.circular(16),
                                            gradient: const LinearGradient(
                                              colors: [
                                                Color(0xFF3B82F6),
                                                Color(0xFF2563EB),
                                              ],
                                            ),
                                            boxShadow: [
                                              BoxShadow(
                                                color: const Color(0xFF2563EB)
                                                    .withValues(alpha: 0.4),
                                                blurRadius: 16,
                                                offset: const Offset(0, 8),
                                              ),
                                            ],
                                          ),
                                          child: Material(
                                            color: Colors.transparent,
                                            child: InkWell(
                                              borderRadius:
                                                  BorderRadius.circular(16),
                                              onTap: loading ||
                                                      (!isLogin &&
                                                          !acceptedTerms)
                                                  ? null
                                                  : submit,
                                              child: Center(
                                                child: loading
                                                    ? const SizedBox(
                                                        width: 24,
                                                        height: 24,
                                                        child:
                                                            CircularProgressIndicator(
                                                          strokeWidth: 2.4,
                                                          color: Colors.white,
                                                        ),
                                                      )
                                                    : Text(
                                                        isLogin
                                                            ? 'Войти'
                                                            : (regStep == 0
                                                                ? 'Продолжить'
                                                                : 'Создать аккаунт'),
                                                        style: const TextStyle(
                                                          color: Colors.white,
                                                          fontSize: 16,
                                                          fontWeight:
                                                              FontWeight.w700,
                                                          letterSpacing: 0.2,
                                                        ),
                                                      ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                    if (!isLogin && regStep == 1) ...[
                                      const SizedBox(height: 12),
                                      TextButton(
                                        onPressed: loading
                                            ? null
                                            : () => setState(() {
                                                  regStep = 0;
                                                  error = null;
                                                }),
                                        child: Text(
                                          '← Назад',
                                          style: TextStyle(
                                            color: Colors.black
                                                .withValues(alpha: 0.5),
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                    ],
                                    const SizedBox(height: 8),
                                    Text(
                                      'Безопасный мессенджер с E2EE',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        fontSize: 11.5,
                                        color: Colors.black
                                            .withValues(alpha: 0.32),
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),

                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}


/// Политика конфиденциальности и Пользовательское соглашение SLine
class SLineLegalDocScreen extends StatelessWidget {
  /// 'privacy' | 'terms'
  final String kind;
  const SLineLegalDocScreen({super.key, required this.kind});

  static const operatorName = 'Дмитрий Близнюк';
  static const operatorEmail = 'dimasik.228.dima.super@gmail.com';
  static const appName = 'SLine';
  static const updated = '24 сентября 2026 г.';

  bool get isPrivacy => kind == 'privacy';

  String get title =>
      isPrivacy ? 'Политика конфиденциальности' : 'Пользовательское соглашение';

  List<String> get body {
    if (isPrivacy) {
      return [
        'Дата обновления: $updated',
        '',
        '1. Оператор',
        'Оператором сервиса $appName и персональных данных является $operatorName.',
        'Контакт для вопросов по персональным данным: $operatorEmail',
        '',
        '2. Какие данные мы обрабатываем',
        '• Данные аккаунта: адрес электронной почты, имя, username, аватар, краткое описание профиля (bio), цвет профиля.',
        '• Данные переписки: сообщения, файлы, фото, видео, голосовые, видеокружки, стикеры, реакции, подарки, которые вы отправляете или получаете.',
        '• Технические данные: идентификатор пользователя (UID), токены push-уведомлений (FCM/OneSignal), сведения об устройстве в объёме, необходимом для работы приложения, данные о сессии и статусе «в сети».',
        '• Контакты: при вашем разрешении — номера из телефонной книги для поиска знакомых в $appName (сопоставление только с уже зарегистрированными пользователями).',
        '• Медиа и файлы: загруженные вами изображения, видео, аудио и документы, в том числе через облачное хранилище / прокси, используемые сервисом.',
        '• Платёжные/игровые условные единицы (SCoin) и сведения о подарках — если вы пользуетесь этими функциями.',
        '',
        '3. Цели обработки',
        '• создание и обслуживание аккаунта;',
        '• обмен сообщениями, звонками и медиа;',
        '• доставка уведомлений;',
        '• безопасность, предотвращение злоупотреблений и восстановление доступа;',
        '• улучшение работы сервиса и поддержка пользователей;',
        '• исполнение требований законодательства.',
        '',
        '4. Правовые основания',
        'Обработка осуществляется на основании вашего согласия (чекбокс при регистрации), исполнения договора (Пользовательского соглашения) и законных интересов оператора в обеспечении безопасности сервиса.',
        '',
        '5. Шифрование (E2EE)',
        '$appName использует сквозное шифрование (E2EE) для защиты содержимого личных переписок на устройствах пользователей. Оператор не ставит целью читать текст ваших личных сообщений. При этом технические метаданные (например, факт отправки, идентификаторы участников, время) могут обрабатываться для доставки сообщений, уведомлений и безопасности.',
        '',
        '6. Где хранятся данные и кому передаются',
        'Для работы сервиса используются сторонние инфраструктуры, в частности:',
        '• Firebase (аутентификация, база данных в реальном времени, push);',
        '• сервисы push-уведомлений (в т.ч. OneSignal — при подключении);',
        '• облачное хранение и/или прокси для медиафайлов (в т.ч. через Cloudflare Workers / объектное хранилище).',
        'Передача данных таким провайдерам ограничена целями работы $appName. Мы не продаём ваши персональные данные.',
        '',
        '7. Срок хранения',
        'Данные аккаунта и переписки хранятся, пока аккаунт активен, либо до удаления вами / по запросу, либо в сроки, необходимые для безопасности и исполнения закона. Истории и временный контент могут удаляться по истечении срока жизни, заданного в приложении.',
        '',
        '8. Ваши права',
        'Вы можете запросить доступ, уточнение, удаление данных или отзыв согласия, написав на $operatorEmail. Удаление аккаунта может быть доступно в настройках приложения; после удаления часть технических логов может храниться ограниченное время для безопасности.',
        '',
        '9. Дети',
        'Сервис не предназначен для лиц младше 16 лет (или иного возраста, установленного законом вашей страны). Если вам нет этого возраста, не регистрируйтесь без согласия законного представителя.',
        '',
        '10. Изменения',
        'Мы можем обновлять эту Политику. Актуальная версия всегда доступна в приложении. Продолжение использования после обновления означает согласие с новой редакцией, если иное не требуется законом.',
        '',
        '11. Контакты',
        'По всем вопросам: $operatorEmail',
        'Оператор: $operatorName',
      ];
    }
    return [
      'Дата обновления: $updated',
      '',
      '1. Общие положения',
      'Настоящее Пользовательское соглашение (далее — Соглашение) регулирует использование мобильного и веб-приложения $appName (далее — Сервис). Регистрируясь или используя Сервис, вы подтверждаете, что прочитали и приняли условия Соглашения и Политики конфиденциальности.',
      'Оператор Сервиса: $operatorName, контакт: $operatorEmail.',
      '',
      '2. Описание сервиса',
      '$appName — мессенджер для обмена сообщениями, медиа, звонков, историй, каналов и групп, с функциями шифрования (E2EE), уведомлений и связанных возможностей, описанных в интерфейсе.',
      '',
      '3. Аккаунт',
      'Вы обязуетесь указывать достоверные данные, сохранять пароль в тайне и не передавать доступ третьим лицам. Запрещается создавать аккаунты автоматизированно, выдавать себя за другого человека или организацию без права на это.',
      '',
      '4. Правила использования',
      'Запрещается:',
      '• распространять незаконный, вредоносный, мошеннический контент;',
      '• преследовать, угрожать, оскорблять пользователей;',
      '• взламывать, сканировать уязвимости, нарушать работу Сервиса;',
      '• распространять вредоносное ПО, спам, фишинг;',
      '• нарушать права интеллектуальной собственности и частной жизни других лиц;',
      '• использовать Сервис способами, прямо запрещёнными законом.',
      'Оператор вправе ограничить доступ, удалить контент или аккаунт при нарушении правил.',
      '',
      '5. Контент пользователей',
      'Вы несёте ответственность за контент, который отправляете. Отправляя контент, вы подтверждаете, что имеете на это права. Оператор может удалять контент, нарушающий Соглашение или закон.',
      '',
      '6. Интеллектуальная собственность',
      'Название $appName, дизайн, логотипы и программный код Сервиса принадлежат оператору или правообладателям. Запрещается копировать, модифицировать и распространять Сервис без разрешения, кроме случаев, прямо разрешённых законом.',
      '',
      '7. Платные и условные функции',
      'Отдельные функции (например, подарки, SCoin) могут иметь условную или фактическую стоимость, отображаемую в интерфейсе. Условия таких функций доводятся до пользователя в момент использования.',
      '',
      '8. Ограничение ответственности',
      'Сервис предоставляется «как есть». Оператор не гарантирует бесперебойную работу и не отвечает за косвенные убытки, потерю данных на стороне пользователя или действия третьих лиц, в пределах, допускаемых применимым правом. Ничто в Соглашении не ограничивает права потребителя, которые нельзя ограничить по закону.',
      '',
      '9. Прекращение доступа',
      'Вы можете прекратить использование Сервиса в любой момент. Оператор может приостановить или прекратить доступ при нарушении Соглашения, требованиях закона или прекращении работы Сервиса.',
      '',
      '10. Изменения Соглашения',
      'Оператор может обновлять Соглашение. Актуальная версия доступна в приложении. Существенные изменения при необходимости могут сопровождаться уведомлением в Сервисе.',
      '',
      '11. Контакты',
      'По вопросам Соглашения: $operatorEmail',
      'Оператор: $operatorName',
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FC),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        title: Text(
          title,
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  appName,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF6D5DF6),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 16),
                ...body.map((line) {
                  if (line.isEmpty) return const SizedBox(height: 10);
                  final isH = RegExp(r'^\d+\.\s').hasMatch(line);
                  return Padding(
                    padding: EdgeInsets.only(bottom: isH ? 6 : 4),
                    child: Text(
                      line,
                      style: TextStyle(
                        fontSize: isH ? 14.5 : 13.5,
                        height: 1.45,
                        fontWeight:
                            isH ? FontWeight.w700 : FontWeight.w400,
                        color: Colors.black.withValues(alpha: isH ? 0.88 : 0.72),
                      ),
                    ),
                  );
                }),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AuthTab extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _AuthTab(
      {required this.label, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(vertical: 11),
        decoration: BoxDecoration(
          color: active ? const Color(0xFF2563EB) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          boxShadow: active
              ? [
                  BoxShadow(
                    color: const Color(0xFF2563EB).withValues(alpha: 0.28),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontWeight: active ? FontWeight.w700 : FontWeight.w500,
            fontSize: 14,
            color: active
                ? Colors.white
                : Colors.black.withValues(alpha: 0.4),
          ),
        ),
      ),
    );
  }
}

class _RegDot extends StatelessWidget {
  final bool active;
  final bool done;
  const _RegDot({required this.active, required this.done});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 280),
      width: active || done ? 12 : 8,
      height: active || done ? 12 : 8,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: active || done
            ? const Color(0xFF2563EB)
            : Colors.black.withValues(alpha: 0.12),
      ),
    );
  }
}

/// Круглый логотип SLine — как иконка приложения
class _SLineLogoMark extends StatelessWidget {
  final double size;
  const _SLineLogoMark({required this.size});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF60A5FA),
            Color(0xFF3B82F6),
            Color(0xFF2563EB),
          ],
        ),
      ),
      child: Center(
        child: Container(
          width: size * 0.48,
          height: size * 0.42,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(size * 0.18),
              topRight: Radius.circular(size * 0.18),
              bottomRight: Radius.circular(size * 0.18),
              bottomLeft: Radius.circular(size * 0.04),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.12),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Декоративный пузырёк чата на фоне
class _FloatChatBubble extends StatelessWidget {
  final String text;
  final bool alignRight;
  final double opacity;
  final double scale;
  const _FloatChatBubble({
    required this.text,
    required this.alignRight,
    required this.opacity,
    required this.scale,
  });

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Opacity(
        opacity: opacity.clamp(0.0, 1.0),
        child: Transform.scale(
          scale: scale,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.9),
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(16),
                topRight: const Radius.circular(16),
                bottomLeft: Radius.circular(alignRight ? 16 : 4),
                bottomRight: Radius.circular(alignRight ? 4 : 16),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.1),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Color(0xFF1E3A8A),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AuthBlob extends StatelessWidget {
  final double size;
  final Color color;
  const _AuthBlob({required this.size, required this.color});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: ImageFiltered(
        imageFilter: ImageFilter.blur(sigmaX: 36, sigmaY: 36),
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color,
          ),
        ),
      ),
    );
  }
}

// ── shell ───────────────────────────────────────────────────

class _SLineInAppBanner extends StatefulWidget {
  final SLineInAppNote note;
  final VoidCallback onDismiss;
  const _SLineInAppBanner({super.key, required this.note, required this.onDismiss});
  @override
  State<_SLineInAppBanner> createState() => _SLineInAppBannerState();
}

class _SLineInAppBannerState extends State<_SLineInAppBanner>
    with SingleTickerProviderStateMixin {
  double _drag = 0;
  late final AnimationController _ac;

  @override
  void initState() {
    super.initState();
    _ac = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 280))
      ..forward();
    Future.delayed(const Duration(seconds: 4), () {
      if (mounted) widget.onDismiss();
    });
  }

  @override
  void dispose() {
    _ac.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = !themeCtrl.light;
    return GestureDetector(
      onVerticalDragUpdate: (d) {
        if (d.delta.dy < 0) {
          setState(() => _drag += d.delta.dy);
        }
      },
      onVerticalDragEnd: (d) {
        if (_drag < -40 || (d.primaryVelocity ?? 0) < -400) {
          widget.onDismiss();
        } else {
          setState(() => _drag = 0);
        }
      },
      onTap: widget.onDismiss,
      child: AnimatedBuilder(
        animation: _ac,
        builder: (_, child) {
          final t = Curves.easeOutCubic.transform(_ac.value);
          return Opacity(
            opacity: t,
            child: Transform.translate(
              offset: Offset(0, -24 * (1 - t) + _drag),
              child: child,
            ),
          );
        },
        child: Container(
          margin: const EdgeInsets.fromLTRB(12, 6, 12, 0),
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          decoration: BoxDecoration(
            color: dark ? const Color(0xE61C1C1E) : const Color(0xF2FFFFFF),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.18),
                blurRadius: 18,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  gradient: const LinearGradient(
                    colors: [Color(0xFF4C7CF3), Color(0xFF6D5DF6)],
                  ),
                ),
                child: const Icon(Icons.chat_bubble_rounded,
                    color: Colors.white, size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(widget.note.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                          color: themeCtrl.text,
                        )),
                    const SizedBox(height: 2),
                    Text(widget.note.body,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.25,
                          color: themeCtrl.muted,
                        )),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class MainShell extends StatefulWidget {
  final User user;
  const MainShell({super.key, required this.user});
  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> with WidgetsBindingObserver {
  int tab = 2; // Чаты по умолчанию (как в TG)
  Profile? myProfile;
  String? dbError;
  StreamSubscription? _callsSub;
  final Set<String> _shownCalls = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SLineAppLifecycle.setForeground(true);
    _boot();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final fg = state == AppLifecycleState.resumed;
    SLineAppLifecycle.setForeground(fg);
  }

  Future<void> _boot() async {
    try {
      final p = await ensureWebProfile(widget.user);
      if (mounted) setState(() => myProfile = p);
      try {
        NtfyListener.onMessage = (title, body) {
          if (!mounted) return;
          if (SLineAppLifecycle.isForeground) {
            SLineAppLifecycle.showInApp(title, body);
            return;
          }
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('$title: $body'),
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 4),
            ),
          );
        };
        await setupPushNotifications(widget.user);
      } catch (_) {}
      _listenIncomingCalls();
    } catch (e) {
      if (mounted && !_isPermError(e)) {
        final msg = permissionHelp(e);
        if (msg.isNotEmpty) setState(() => dbError = msg);
      }
    }
  }

  void _listenIncomingCalls() {
    _callsSub?.cancel();
    final me = widget.user.uid;
    _callsSub = FirebaseDatabase.instance.ref('calls').onChildAdded.listen((ev) async {
      if (!ev.snapshot.exists || ev.snapshot.value is! Map) return;
      final id = ev.snapshot.key ?? '';
      final m = Map<String, dynamic>.from(ev.snapshot.value as Map);
      if ((m['to'] ?? '').toString() != me) return;
      if ((m['status'] ?? '') != 'ringing') return;
      if (_shownCalls.contains(id)) return;
      _shownCalls.add(id);
      final from = (m['from'] ?? '').toString();
      if (from.isEmpty || from == me) return;
      Profile? peer = await loadProfile(from);
      peer ??= Profile(id: from, firstName: 'Звонок', username: from);
      final audioOnly = (m['type'] ?? 'audio').toString() != 'video';
      if (!mounted) return;
      // Полноэкранный входящий
      await Navigator.of(context).push(MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => IncomingCallScreen(
          callId: id,
          user: widget.user,
          peer: peer!,
          audioOnly: audioOnly,
        ),
      ));
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _callsSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: themeCtrl,
      builder: (_, __) => Scaffold(
        backgroundColor: themeCtrl.bg,
        extendBody: true,
        // Панель НЕ через bottomNavigationBar — только Positioned(bottom),
        // иначе GlassTabBar иногда рисуется посреди списка.
        body: Stack(
          fit: StackFit.expand,
          children: [
            Column(
              children: [
                if (dbError != null && dbError!.isNotEmpty)
                  Material(
                    color: SLineColors.danger.withValues(alpha: 0.15),
                    child: SafeArea(
                      bottom: false,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(dbError!,
                            style: const TextStyle(
                                color: SLineColors.danger, fontSize: 12)),
                      ),
                    ),
                  ),
                Expanded(
                  child: IndexedStack(index: tab, children: [
                    ContactsPage(user: widget.user, myProfile: myProfile),
                    CallsPage(user: widget.user, myProfile: myProfile),
                    ChatsPage(
                        user: widget.user,
                        myProfile: myProfile,
                        onProfileTap: (p) => _openProfile(p)),
                    SettingsPage(
                        user: widget.user,
                        myProfile: myProfile,
                        onRefresh: _boot),
                  ]),
                ),
              ],
            ),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                bottom: false,
                child: ValueListenableBuilder<SLineInAppNote?>(
                  valueListenable: SLineAppLifecycle.inAppNote,
                  builder: (_, note, __) {
                    if (note == null) return const SizedBox.shrink();
                    return _SLineInAppBanner(
                      key: ValueKey(note.id),
                      note: note,
                      onDismiss: () => SLineAppLifecycle.clearInApp(),
                    );
                  },
                ),
              ),
            ),
            // СТРОГО внизу экрана
            Align(
              alignment: Alignment.bottomCenter,
              child: SafeArea(
                top: false,
                minimum: const EdgeInsets.only(bottom: 4),
                child: _TgIosBottomBar(
                  index: tab,
                  onChanged: (i) {
                    HapticFeedback.selectionClick();
                    setState(() => tab = i);
                  },
                  badges: const {},
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openProfile(Profile p) {
    Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => ProfilePage(
            user: widget.user, profile: p, isMe: p.id == widget.user.uid)));
  }

  Widget _nav(IconData i, String l, int idx) {
    final on = tab == idx;
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () {
          HapticFeedback.selectionClick();
          setState(() => tab = idx);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          margin: const EdgeInsets.symmetric(horizontal: 6),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: on
                ? SLineColors.accentA.withValues(alpha: 0.12)
                : Colors.transparent,
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            AnimatedScale(
              scale: on ? 1.08 : 1.0,
              duration: const Duration(milliseconds: 200),
              child: Icon(i,
                  size: 22,
                  color: on ? SLineColors.accentA : themeCtrl.muted),
            ),
            const SizedBox(height: 2),
            Text(l,
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: on ? FontWeight.w700 : FontWeight.w500,
                    color: on ? SLineColors.accentA : themeCtrl.muted)),
          ]),
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  final String name;
  final Color color;
  final String? url;
  final double size;
  final VoidCallback? onTap;
  const _Avatar(
      {required this.name,
      required this.color,
      this.url,
      this.size = 48,
      this.onTap});

  Widget _letter() => Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(shape: BoxShape.circle, color: color),
        child: Text(name.isNotEmpty ? name[0].toUpperCase() : '?',
            style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: size * 0.38)),
      );

  @override
  Widget build(BuildContext context) {
    final u = (url ?? '').trim();
    Widget child;
    if (u.isEmpty) {
      child = _letter();
    } else if (u.startsWith('asset:')) {
      final path = u.substring(6);
      child = ClipOval(
        child: Image.asset(
          path,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _letter(),
        ),
      );
    } else if (!u.startsWith('http://') &&
        !u.startsWith('https://') &&
        !u.startsWith('data:')) {
      // локальный файл
      child = ClipOval(
        child: Image.file(
          File(u),
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _letter(),
        ),
      );
    } else if (u.startsWith('data:image')) {
      try {
        final comma = u.indexOf(',');
        final bytes = base64Decode(u.substring(comma + 1));
        child = ClipOval(
          child: Image.memory(bytes, width: size, height: size, fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => _letter()),
        );
      } catch (_) {
        child = _letter();
      }
    } else {
      child = ClipOval(
        child: Image.network(
          u,
          width: size,
          height: size,
          fit: BoxFit.cover,
          headers: kMediaHeaders,
          errorBuilder: (_, __, ___) => _letter(),
          loadingBuilder: (c, ch, prog) {
            if (prog == null) return ch;
            return Container(
                width: size,
                height: size,
                color: color,
                alignment: Alignment.center,
                child: const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2)));
          },
        ),
      );
    }
    if (onTap != null) {
      return GestureDetector(onTap: onTap, child: child);
    }
    return child;
  }
}

// ── chats ───────────────────────────────────────────────────
class ChatsPage extends StatefulWidget {
  final User user;
  final Profile? myProfile;
  final ValueChanged<Profile>? onProfileTap;
  const ChatsPage(
      {super.key, required this.user, this.myProfile, this.onProfileTap});
  @override
  State<ChatsPage> createState() => _ChatsPageState();
}

class _ChatsPageState extends State<ChatsPage> {
  StreamSubscription? _pendingCodesSub;
  StreamSubscription? _deviceLinkSub;
  StreamSubscription? _securityAlertsSub;
  StreamSubscription? _mySessionWatch;
  Map<String, dynamic>? _securityAlert; // id + fields
  final Map<String, ChatPreview> chatsMap = {};
  final Set<String> listening = {};
  final Map<String, StreamSubscription> subs = {};
  StreamSubscription? indexSub;
  StreamSubscription? indexChildSub;
  StreamSubscription? inboxSub;
  StreamSubscription? outboxSub;
  VoidCallback? _syncListener;
  String? listError;
  /// uid → stories (только активные)
  final Map<String, List<StoryItem>> storiesByUser = {};
  final Set<String> contactIds = {};
  bool storiesLoading = true;
  /// Папки как на вебе: all | private | groups | channels | archive
  String folder = 'all';
  final Set<String> pinnedKeys = {};
  final Set<String> archivedKeys = {};
  final Set<String> mutedKeys = {};
  /// 0 = истории полностью, 1 = схлопнуты (анимация при скролле как в TG)
  double _storiesCollapse = 0;
  /// Режим выделения чатов (как в TG)
  bool selectMode = false;
  final Set<String> selectedKeys = {};

  @override
  void initState() {
    super.initState();
    final me = widget.user.uid;
    slTouchUserSession(me);
    _listenSecurityAlerts(me);
    _watchMySession(me);
    final sk = dmPairKey(me, me);
    chatsMap[sk] = ChatPreview(
        chatKey: sk,
        peerId: me,
        peer: Profile.saved(me),
        lastMessage: 'Заметки и файлы',
        lastAt: DateTime.now().millisecondsSinceEpoch,
        isSaved: true,
        kind: 'saved');
    try {
      final indexRef = FirebaseDatabase.instance.ref('user_chat_index/$me');
      indexSub = indexRef.onValue.listen((ev) {
        if (ev.snapshot.exists && ev.snapshot.value is Map) {
          for (final k in (ev.snapshot.value as Map).keys) {
            _attach(k.toString());
          }
        }
      }, onError: (e) {
        if (mounted && !_isPermError(e)) {
          final msg = permissionHelp(e);
          if (msg.isNotEmpty) setState(() => listError = msg);
        }
      });
      // Новый чат в индексе → сразу в список
      indexChildSub = indexRef.onChildAdded.listen((ev) {
        final k = ev.snapshot.key;
        if (k != null && k.isNotEmpty) _attach(k);
      }, onError: (_) {});
    } catch (e) {
      if (!_isPermError(e)) {
        final msg = permissionHelp(e);
        if (msg.isNotEmpty) listError = msg;
      }
    }
    // Входящие: если кто-то написал нам — добавляем чат в СВОЙ индекс
    try {
      inboxSub = FirebaseDatabase.instance
          .ref('tables/messages')
          .orderByChild('receiver_id')
          .equalTo(me)
          .limitToLast(40)
          .onChildAdded
          .listen((ev) {
        if (ev.snapshot.value is! Map) return;
        final d = Map<String, dynamic>.from(ev.snapshot.value as Map);
        final sender = (d['sender_id'] ?? '').toString();
        final receiver = (d['receiver_id'] ?? me).toString();
        if (sender.isEmpty) return;
        final key = dmPairKey(sender, receiver);
        ChatListSync.ensureIndexed(myUid: me, chatKey: key, peerUid: sender);
        _attach(key);
      }, onError: (_) {});
    } catch (_) {}
    // Исходящие (на случай если индекс не записался)
    try {
      outboxSub = FirebaseDatabase.instance
          .ref('tables/messages')
          .orderByChild('sender_id')
          .equalTo(me)
          .limitToLast(40)
          .onChildAdded
          .listen((ev) {
        if (ev.snapshot.value is! Map) return;
        final d = Map<String, dynamic>.from(ev.snapshot.value as Map);
        final sender = (d['sender_id'] ?? me).toString();
        final receiver = (d['receiver_id'] ?? '').toString();
        if (receiver.isEmpty) return;
        final key = dmPairKey(sender, receiver);
        ChatListSync.ensureIndexed(
            myUid: me, chatKey: key, peerUid: receiver);
        _attach(key);
      }, onError: (_) {});
    } catch (_) {}
    // Мгновенное обновление после отправки из ChatScreen
    _syncListener = () {
      final k = ChatListSync.lastChatKey.value;
      if (k != null && k.isNotEmpty) _attach(k);
    };
    ChatListSync.lastChatKey.addListener(_syncListener!);

    FirebaseDatabase.instance.ref('chat_msgs').limitToFirst(200).get().then((snap) {
      if (!snap.exists || snap.value is! Map) return;
      for (final k in (snap.value as Map).keys) {
        final key = k.toString();
        if (!key.startsWith('g_') && key.contains(me)) _attach(key);
      }
    }).catchError((_) {});
    _loadContacts();
    _loadStories();
    _loadPinsAndArchive();
    _ensureSLineSystem();
  }

  Future<void> _ensureSLineSystem() async {
    final me = widget.user.uid;
    try {
      await ensureSLineSystemChat(me);
      final key = slineSystemChatKey(me);
      _attach(key);
      final dir = await getApplicationDocumentsDirectory();
      final marker = File('${dir.path}/sl_device_notice_v1.txt');
      final deviceId = 'Android ${DateTime.now().millisecondsSinceEpoch}';
      var should = true;
      try {
        if (await marker.exists()) {
          final prev = await marker.readAsString();
          if (prev.isNotEmpty) should = false;
        }
      } catch (_) {}
      if (should) {
        final uname = widget.myProfile?.username ?? 'user';
        await sendSLineSystemMessage(
          me,
          formatSLineNewDeviceMessage(
            username: uname,
            device: 'Android / SLine App',
            place: 'Неизвестно',
          ),
        );
        try {
          await marker.writeAsString(deviceId);
        } catch (_) {}
      }
      // Коды входа → чат SLine (веб + мобилка)
      _pendingCodesSub?.cancel();
      _pendingCodesSub = FirebaseDatabase.instance
          .ref('pending_login_codes/$me')
          .onChildAdded
          .listen((ev) async {
        if (ev.snapshot.value is! Map) return;
        final d = Map<String, dynamic>.from(ev.snapshot.value as Map);
        final code = (d['code'] ?? '').toString();
        if (code.isEmpty || d['_delivered'] == true) return;
        try {
          await sendSLineSystemMessage(me, formatSLineLoginCodeMessage(code));
          await ev.snapshot.ref.update({'_delivered': true});
        } catch (_) {}
      });
      final email = (widget.myProfile?.email ?? '').toLowerCase();
      final uname = (widget.myProfile?.username ?? '').toLowerCase();
      _deviceLinkSub?.cancel();
      _deviceLinkSub = FirebaseDatabase.instance
          .ref('device_link')
          .limitToLast(25)
          .onChildAdded
          .listen((ev) async {
        if (ev.snapshot.value is! Map) return;
        final d = Map<String, dynamic>.from(ev.snapshot.value as Map);
        if (d['for_sline'] != true) return;
        final login = (d['login'] ?? '').toString().toLowerCase();
        final code = (d['code'] ?? '').toString();
        final match = (email.isNotEmpty && login == email) ||
            (uname.isNotEmpty && login == uname) ||
            (d['uid']?.toString() == me);
        if (!match || code.isEmpty || d['_pushed_chat'] == true) return;
        try {
          await sendSLineSystemMessage(me, formatSLineLoginCodeMessage(code));
          await ev.snapshot.ref.update({'_pushed_chat': true});
        } catch (_) {}
      });
    } catch (_) {}
  }


  Future<void> _loadPinsAndArchive() async {
    final me = widget.user.uid;
    try {
      final p = await FirebaseDatabase.instance.ref('user_pins/$me').get();
      if (p.exists && p.value is Map) {
        pinnedKeys.addAll((p.value as Map).keys.map((e) => e.toString()));
      }
    } catch (_) {}
    try {
      final a = await FirebaseDatabase.instance.ref('user_archive/$me').get();
      if (a.exists && a.value is Map) {
        archivedKeys.addAll((a.value as Map).keys.map((e) => e.toString()));
      }
    } catch (_) {}
    try {
      final m = await FirebaseDatabase.instance.ref('user_mutes/$me').get();
      if (m.exists && m.value is Map) {
        mutedKeys
          ..clear()
          ..addAll((m.value as Map).keys.map((e) => e.toString()));
      }
    } catch (_) {}
    if (mounted) setState(() {});
  }

  Future<void> _loadContacts() async {
    try {
      final snap = await FirebaseDatabase.instance
          .ref('my_contacts/${widget.user.uid}')
          .get();
      final ids = <String>{};
      if (snap.exists && snap.value is Map) {
        for (final k in (snap.value as Map).keys) {
          ids.add(k.toString());
        }
      }
      // люди, с кем уже есть чат — тоже «контакты» для историй (как на вебе)
      for (final c in chatsMap.values) {
        if (!c.isSaved) ids.add(c.peerId);
      }
      if (mounted) setState(() => contactIds.addAll(ids));
    } catch (_) {}
  }

  Future<void> _loadStories() async {
    setState(() => storiesLoading = true);
    try {
      final byUser = <String, List<StoryItem>>{};
      void ingest(dynamic value) {
        if (value is! Map) return;
        for (final e in value.entries) {
          if (e.value is! Map) continue;
          final s = StoryItem.fromMap(
              e.key.toString(), Map<String, dynamic>.from(e.value as Map));
          if (!s.isActive || s.userId.isEmpty) continue;
          final media = (s.mediaUrl ?? '').trim();
          if (media.isEmpty) continue;
          byUser.putIfAbsent(s.userId, () => []).add(s);
        }
      }
      for (final path in ['tables/stories', 'stories']) {
        try {
          final snap = await FirebaseDatabase.instance.ref(path).get();
          if (snap.exists) ingest(snap.value);
        } catch (_) {}
      }
      if (mounted) {
        setState(() {
          storiesByUser
            ..clear()
            ..addAll(byUser);
          storiesLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => storiesLoading = false);
    }
  }

  Future<Profile?> _loadChannelOrGroupPeer(String key) async {
    if (key.startsWith('c_')) {
      try {
        final cs = await FirebaseDatabase.instance
            .ref('channels/${key.substring(2)}')
            .get();
        if (cs.exists && cs.value is Map) {
          final d = Map<String, dynamic>.from(cs.value as Map);
          final uname = (d['username'] ?? d['slug'] ?? '').toString().trim();
          return Profile(
            id: key,
            firstName: (d['name'] ?? 'Канал').toString(),
            username: uname.isNotEmpty ? uname : 'channel',
            avatarUrl: d['avatar_url']?.toString(),
            color: '#6D5DF6',
            bio: (d['admin_id'] ?? '').toString(), // временно admin_id
          );
        }
      } catch (_) {}
    } else if (key.startsWith('g_')) {
      try {
        final gs = await FirebaseDatabase.instance
            .ref('groups/${key.substring(2)}')
            .get();
        if (gs.exists && gs.value is Map) {
          final d = Map<String, dynamic>.from(gs.value as Map);
          final uname = (d['username'] ?? d['slug'] ?? '').toString().trim();
          return Profile(
            id: key,
            firstName: (d['name'] ?? 'Группа').toString(),
            username: uname.isNotEmpty ? uname : 'group',
            avatarUrl: d['avatar_url']?.toString(),
            color: '#6D5DF6',
            bio: (d['admin_id'] ?? '').toString(),
          );
        }
      } catch (_) {}
    }
    return null;
  }

  void _attach(String key) {
    if (listening.contains(key)) return;
    listening.add(key);

    // Сразу показать канал/группу даже без сообщений
    if (key.startsWith('c_') || key.startsWith('g_')) {
      _loadChannelOrGroupPeer(key).then((peer) {
        if (peer == null || !mounted) return;
        if (chatsMap.containsKey(key)) return;
        final kind = key.startsWith('c_') ? 'channel' : 'group';
        chatsMap[key] = ChatPreview(
          chatKey: key,
          peerId: key.startsWith('c_') ? key.substring(2) : key,
          peer: peer,
          lastMessage: kind == 'channel' ? 'Канал' : 'Группа',
          lastAt: DateTime.now().millisecondsSinceEpoch,
          isSaved: false,
          kind: kind,
        );
        if (mounted) setState(() {});
      });
    }

    subs[key] = chatMsgsRef(key).limitToLast(1).onValue.listen((ev) async {
      final me = widget.user.uid;
      ChatMessage? last;
      if (ev.snapshot.exists && ev.snapshot.value is Map) {
        for (final e
            in Map<String, dynamic>.from(ev.snapshot.value as Map).entries) {
          if (e.value is Map) {
            final m = ChatMessage.fromMap(
                e.key, Map<String, dynamic>.from(e.value as Map));
            if (last == null || m.createdAt > last.createdAt) last = m;
          }
        }
      }

      // Для DM без сообщений — ничего; для g_/c_ уже посеяли выше
      if (last == null) {
        if (key.startsWith('c_') || key.startsWith('g_')) return;
        return;
      }

      String peerId = me;
      if (key != dmPairKey(me, me)) {
        if (last.receiverId != null && last.receiverId!.isNotEmpty) {
          peerId = last.senderId == me ? last.receiverId! : last.senderId;
        } else if (key.startsWith('${me}_')) {
          peerId = key.substring(me.length + 1);
        } else if (key.endsWith('_$me')) {
          peerId = key.substring(0, key.length - me.length - 1);
        }
      }
      Profile? peer = await _loadChannelOrGroupPeer(key);
      if (peerId == kSLineSystemUid || key.contains(kSLineSystemUid)) {
        peer = slineSystemProfile();
        peerId = kSLineSystemUid;
      }
      peer ??=
          peerId == me ? Profile.saved(me) : await loadProfile(peerId);
      peer ??= Profile(
          id: peerId,
          firstName: peerId == kSLineSystemUid ? 'SLine' : 'User',
          username: peerId == kSLineSystemUid
              ? 'sline'
              : (peerId.length > 6 ? peerId.substring(0, 6) : peerId));
      String preview = last.content;
      switch (last.type) {
        case 'voice':
          preview = '🎤 Голосовое';
          break;
        case 'circle':
          preview = '⭕ Кружок';
          break;
        case 'image':
          preview = '📷 Фото';
          break;
        case 'video':
          preview = '🎬 Видео';
          break;
        case 'gif':
          preview = 'GIF';
          break;
        case 'sticker':
          preview = 'Стикер';
          break;
        case 'gift':
          preview = '🎁 ${SLineGifts.labelFor(last.fileUrl)}';
          break;
        case 'location':
          preview = '📍 Геопозиция';
          break;
        case 'poll':
          preview = '📊 Опрос';
          break;
      }
      String kind = 'dm';
      if (key.startsWith('c_')) {
        kind = 'channel';
        if (peerId == me) peerId = key.substring(2);
      } else if (key.startsWith('g_')) {
        kind = 'group';
        if (peerId == me) peerId = key;
      } else if (key == dmPairKey(me, me) || peerId == me) {
        kind = 'saved';
        peerId = me;
      }
      final isSavedChat = kind == 'saved';
      final prev = chatsMap[key];
      chatsMap[key] = ChatPreview(
          chatKey: key,
          peerId: peerId,
          peer: peer,
          lastMessage: preview,
          lastAt: last.createdAt,
          isSaved: isSavedChat,
          pinned: prev?.pinned ?? false,
          archived: prev?.archived ?? false,
          kind: kind);
      if (mounted) setState(() {});
    }, onError: (e) {
      if (mounted && !_isPermError(e)) {
        final msg = permissionHelp(e);
        if (msg.isNotEmpty) setState(() => listError = msg);
      }
    });
  }

  @override
  void dispose() {
    indexSub?.cancel();
    indexChildSub?.cancel();
    inboxSub?.cancel();
    outboxSub?.cancel();
    if (_syncListener != null) {
      ChatListSync.lastChatKey.removeListener(_syncListener!);
    }
    for (final s in subs.values) {
      s.cancel();
    }
    _pendingCodesSub?.cancel();
    _deviceLinkSub?.cancel();
    _securityAlertsSub?.cancel();
    _mySessionWatch?.cancel();
    super.dispose();
  }

  void _listenSecurityAlerts(String uid) {
    _securityAlertsSub?.cancel();
    _securityAlertsSub = FirebaseDatabase.instance
        .ref('security_alerts/$uid')
        .onValue
        .listen((ev) async {
      try {
        final myId = await slLocalDeviceId();
        if (!ev.snapshot.exists || ev.snapshot.value is! Map) {
          if (mounted) setState(() => _securityAlert = null);
          return;
        }
        final map = Map<String, dynamic>.from(ev.snapshot.value as Map);
        Map<String, dynamic>? best;
        String? bestId;
        var bestTs = 0;
        for (final e in map.entries) {
          if (e.value is! Map) continue;
          final m = Map<String, dynamic>.from(e.value as Map);
          if (m['status'] != 'pending') continue;
          // не показываем себе алерт о своём же входе
          if ((m['session_id'] ?? '') == myId) continue;
          // не показываем старые алерты (> 24ч)
          final ts0 = int.tryParse((m['created_at'] ?? 0).toString()) ?? 0;
          if (ts0 > 0 && DateTime.now().millisecondsSinceEpoch - ts0 > 86400000) continue;
          final ts = int.tryParse((m['created_at'] ?? 0).toString()) ?? 0;
          if (ts >= bestTs) {
            bestTs = ts;
            best = m;
            bestId = e.key.toString();
          }
        }
        if (mounted) {
          setState(() {
            if (best != null && bestId != null) {
              _securityAlert = {...best, '_id': bestId};
            } else {
              _securityAlert = null;
            }
          });
        }
      } catch (_) {}
    });
  }

  void _watchMySession(String uid) {
    _mySessionWatch?.cancel();
    () async {
      final myId = await slLocalDeviceId();
      // Гарантируем запись своего сеанса, иначе onValue приходит пустым → ложный logout
      try {
        await slTouchUserSession(uid, announceLogin: false);
      } catch (_) {}
      var everExisted = false;
      _mySessionWatch = FirebaseDatabase.instance
          .ref('user_sessions/$uid/$myId')
          .onValue
          .listen((ev) async {
        if (ev.snapshot.exists) {
          everExisted = true;
          return;
        }
        // Выходим только если сеанс УЖЕ был и его удалили («Нет, не я»)
        if (!everExisted) {
          // ещё не создан — не выходим, пробуем записать
          try {
            await slTouchUserSession(uid, announceLogin: false);
          } catch (_) {}
          return;
        }
        try {
          final u = FirebaseAuth.instance.currentUser;
          if (u != null && u.uid == uid) {
            await FirebaseAuth.instance.signOut();
          }
        } catch (_) {}
      });
    }();
  }

  Future<void> _onSecurityYes() async {
    final a = _securityAlert;
    if (a == null) return;
    final id = (a['_id'] ?? '').toString();
    await slConfirmSecurityAlert(widget.user.uid, id);
    if (mounted) setState(() => _securityAlert = null);
  }

  Future<void> _onSecurityNo() async {
    final a = _securityAlert;
    if (a == null) return;
    final id = (a['_id'] ?? '').toString();
    final sid = (a['session_id'] ?? '').toString();
    await slRejectSecurityAlert(widget.user.uid, id, sid);
    if (mounted) setState(() => _securityAlert = null);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Сеанс завершён. Если это были не вы — смените пароль.')),
      );
    }
  }

  Widget _buildSecurityBanner() {
    final a = _securityAlert;
    if (a == null) return const SizedBox.shrink();
    final device = (a['device'] ?? 'Неизвестное устройство').toString();
    final place = (a['place'] ?? 'Неизвестно').toString();
    final dark = !themeCtrl.light;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
      decoration: BoxDecoration(
        color: dark ? const Color(0xFF1C1C1E) : const Color(0xFFF2F2F7),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Кто-то получил доступ к Вашим чатам…',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 15,
              color: themeCtrl.text,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Обнаружен вход в Ваш аккаунт с $device, $place. Это были Вы?',
            style: TextStyle(
              fontSize: 13.5,
              height: 1.35,
              color: themeCtrl.muted,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextButton(
                  onPressed: _onSecurityYes,
                  child: const Text('Да, это я',
                      style: TextStyle(
                          color: Color(0xFF3B82F6),
                          fontWeight: FontWeight.w600)),
                ),
              ),
              Expanded(
                child: TextButton(
                  onPressed: _onSecurityNo,
                  child: const Text('Нет, не я!',
                      style: TextStyle(
                          color: Color(0xFFFF3B30),
                          fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }


  List<ChatPreview> get list {
    var l = chatsMap.values.map((c) {
      final pin = pinnedKeys.contains(c.chatKey) || c.pinned;
      final arch = archivedKeys.contains(c.chatKey) || c.archived;
      return ChatPreview(
        chatKey: c.chatKey,
        peerId: c.peerId,
        peer: c.peer,
        lastMessage: c.lastMessage,
        lastAt: c.lastAt,
        isSaved: c.isSaved,
        pinned: pin,
        archived: arch,
        kind: c.kind,
      );
    }).toList();
    switch (folder) {
      case 'private':
        l = l.where((c) => c.kind == 'dm' || c.kind == 'saved').toList();
        break;
      case 'groups':
        l = l.where((c) => c.kind == 'group').toList();
        break;
      case 'channels':
        l = l.where((c) => c.kind == 'channel').toList();
        break;
      case 'archive':
        l = l.where((c) => c.archived).toList();
        break;
      default:
        l = l.where((c) => !c.archived).toList();
    }
    l.sort((a, b) {
      if (a.isSaved != b.isSaved) return a.isSaved ? -1 : 1;
      if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
      return b.lastAt.compareTo(a.lastAt);
    });
    return l;
  }

  Future<void> _togglePin(ChatPreview c) async {
    final next = !pinnedKeys.contains(c.chatKey);
    setState(() {
      if (next) {
        pinnedKeys.add(c.chatKey);
      } else {
        pinnedKeys.remove(c.chatKey);
      }
    });
    try {
      await FirebaseDatabase.instance
          .ref('user_pins/${widget.user.uid}/${c.chatKey}')
          .set(next ? true : null);
    } catch (_) {}
  }

  Future<void> _toggleArchive(ChatPreview c) async {
    final next = !archivedKeys.contains(c.chatKey);
    setState(() {
      if (next) {
        archivedKeys.add(c.chatKey);
      } else {
        archivedKeys.remove(c.chatKey);
      }
    });
    try {
      await FirebaseDatabase.instance
          .ref('user_archive/${widget.user.uid}/${c.chatKey}')
          .set(next ? true : null);
    } catch (_) {}
  }

  Future<void> _toggleMute(ChatPreview c) async {
    final next = !mutedKeys.contains(c.chatKey);
    setState(() {
      if (next) {
        mutedKeys.add(c.chatKey);
      } else {
        mutedKeys.remove(c.chatKey);
      }
    });
    try {
      await FirebaseDatabase.instance
          .ref('user_mutes/${widget.user.uid}/${c.chatKey}')
          .set(next ? true : null);
    } catch (_) {}
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(next
              ? 'Уведомления отключены'
              : 'Уведомления включены'),
        ),
      );
    }
  }

  /// Удаление группы/канала: админ выбирает «Передать права и выйти» или «Удалить навсегда»
  Future<void> _deleteGroupOrChannel(ChatPreview c) async {
    final isChannel = c.chatKey.startsWith('c_');
    final id = c.chatKey.substring(2);
    final label = isChannel ? 'канал' : 'группу';
    final Label = isChannel ? 'Канал' : 'Группу';
    final me = widget.user.uid;

    // Проверяем, админ ли
    bool isAdmin = false;
    String? currentAdmin;
    try {
      final path = isChannel ? 'channels/$id' : 'groups/$id';
      final snap = await FirebaseDatabase.instance.ref(path).get();
      if (snap.exists && snap.value is Map) {
        currentAdmin = (snap.value as Map)['admin_id']?.toString();
        isAdmin = currentAdmin == me;
      }
      if (!isAdmin) {
        final mPath = isChannel
            ? 'channel_members/$id/$me'
            : 'group_members/$id/$me';
        final ms = await FirebaseDatabase.instance.ref(mPath).get();
        if (ms.exists && ms.value is Map) {
          final role = (ms.value as Map)['role']?.toString() ?? '';
          if (role == 'admin') isAdmin = true;
        }
      }
    } catch (_) {}

    if (!isAdmin) {
      // Просто выйти
      final ok = await showModalBottomSheet<bool>(
            context: context,
            backgroundColor: Colors.transparent,
            builder: (ctx) => _confirmSheet(
              ctx,
              title: 'Выйти из $label?',
              actionLabel: 'Выйти',
            ),
          ) ??
          false;
      if (!ok) return;
      try {
        if (isChannel) {
          await FirebaseDatabase.instance
              .ref('channel_members/$id/$me')
              .remove();
        } else {
          await FirebaseDatabase.instance
              .ref('group_members/$id/$me')
              .remove();
        }
        await FirebaseDatabase.instance
            .ref('user_chat_index/$me/${c.chatKey}')
            .remove();
      } catch (_) {}
      if (mounted) {
        setState(() {
          chatsMap.remove(c.chatKey);
          subs.remove(c.chatKey)?.cancel();
          listening.remove(c.chatKey);
        });
      }
      return;
    }

    // Админ: выбор действия
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final isLight = themeCtrl.light;
        final bg = isLight ? Colors.white : const Color(0xFF2C2C2E);
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: bg,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
                        child: Text(
                          'Удалить $label?',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 13,
                            color: isLight ? Colors.black54 : Colors.white70,
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                        child: Text(
                          'Вы администратор. Можно передать права другому участнику и выйти, либо удалить $label для всех.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 13,
                            color: isLight ? Colors.black45 : Colors.white54,
                          ),
                        ),
                      ),
                      Divider(
                          height: 1,
                          color: isLight ? Colors.black12 : Colors.white12),
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: TextButton(
                          onPressed: () =>
                              Navigator.pop(ctx, 'transfer'),
                          child: Text(
                            'Передать права и выйти',
                            style: TextStyle(
                              color: SLineColors.accentA,
                              fontSize: 17,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                      Divider(
                          height: 1,
                          color: isLight ? Colors.black12 : Colors.white12),
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: TextButton(
                          onPressed: () => Navigator.pop(ctx, 'delete'),
                          child: Text(
                            'Удалить $Label навсегда',
                            style: const TextStyle(
                              color: Color(0xFFFF3B30),
                              fontSize: 17,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  height: 52,
                  decoration: BoxDecoration(
                    color: bg,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: Text(
                      'Отменить',
                      style: TextStyle(
                        color: SLineColors.accentA,
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (action == null) return;

    if (action == 'transfer') {
      // Список участников для передачи
      final members = <Profile>[];
      try {
        final mPath =
            isChannel ? 'channel_members/$id' : 'group_members/$id';
        final ms = await FirebaseDatabase.instance.ref(mPath).get();
        if (ms.exists && ms.value is Map) {
          for (final e in (ms.value as Map).entries) {
            final uid = e.key.toString();
            if (uid == me) continue;
            final p = await loadProfile(uid);
            if (p != null) members.add(p);
          }
        }
      } catch (_) {}

      if (members.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text(
                  'Нет других участников. Удалите навсегда или добавьте кого-то.')));
        }
        return;
      }

      final newAdmin = await showModalBottomSheet<Profile>(
        context: context,
        backgroundColor: themeCtrl.panel,
        builder: (ctx) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'Кому передать права?',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: themeCtrl.text,
                  ),
                ),
              ),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: members.length,
                  itemBuilder: (_, i) {
                    final p = members[i];
                    return ListTile(
                      leading: _Avatar(
                          name: p.displayName,
                          color: p.colorValue,
                          url: p.avatarUrl),
                      title: Text(p.displayName),
                      subtitle: Text(p.username.isNotEmpty
                          ? '@${p.username}'
                          : ''),
                      onTap: () => Navigator.pop(ctx, p),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      );
      if (newAdmin == null) return;

      try {
        final path = isChannel ? 'channels/$id' : 'groups/$id';
        await FirebaseDatabase.instance
            .ref(path)
            .update({'admin_id': newAdmin.id});
        if (isChannel) {
          await FirebaseDatabase.instance
              .ref('channel_members/$id/${newAdmin.id}')
              .update({'role': 'admin'});
          await FirebaseDatabase.instance
              .ref('channel_members/$id/$me')
              .remove();
        } else {
          await FirebaseDatabase.instance
              .ref('group_members/$id/${newAdmin.id}')
              .set(true);
          await FirebaseDatabase.instance
              .ref('group_members/$id/$me')
              .remove();
        }
        await FirebaseDatabase.instance
            .ref('user_chat_index/$me/${c.chatKey}')
            .remove();
        if (mounted) {
          setState(() {
            chatsMap.remove(c.chatKey);
            subs.remove(c.chatKey)?.cancel();
            listening.remove(c.chatKey);
          });
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(
                  'Права переданы ${newAdmin.displayName}, вы вышли')));
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text('$e')));
        }
      }
      return;
    }

    if (action == 'delete') {
      final confirm = await showModalBottomSheet<bool>(
            context: context,
            backgroundColor: Colors.transparent,
            builder: (ctx) => _confirmSheet(
              ctx,
              title: 'Удалить $Label навсегда для всех?',
              body:
                  'Сообщения, участники и данные будут удалены. Восстановить нельзя.',
              actionLabel: 'Удалить навсегда',
            ),
          ) ??
          false;
      if (!confirm) return;
      try {
        // Удалить members у всех + их индекс
        final mPath =
            isChannel ? 'channel_members/$id' : 'group_members/$id';
        final ms = await FirebaseDatabase.instance.ref(mPath).get();
        if (ms.exists && ms.value is Map) {
          for (final uid in (ms.value as Map).keys) {
            try {
              await FirebaseDatabase.instance
                  .ref('user_chat_index/$uid/${c.chatKey}')
                  .remove();
            } catch (_) {}
          }
        }
        await FirebaseDatabase.instance.ref(mPath).remove();
        final path = isChannel ? 'channels/$id' : 'groups/$id';
        await FirebaseDatabase.instance.ref(path).remove();
        try {
          await chatMsgsRef(c.chatKey).remove();
        } catch (_) {}
        await FirebaseDatabase.instance
            .ref('user_chat_index/$me/${c.chatKey}')
            .remove();
        if (mounted) {
          setState(() {
            chatsMap.remove(c.chatKey);
            subs.remove(c.chatKey)?.cancel();
            listening.remove(c.chatKey);
          });
          ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('$Label удалён(а) для всех')));
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text('$e')));
        }
      }
    }
  }

  Widget _confirmSheet(BuildContext ctx,
      {required String title, String? body, required String actionLabel}) {
    final isLight = themeCtrl.light;
    final bg = isLight ? Colors.white : const Color(0xFF2C2C2E);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
                    child: Text(
                      title,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        color: isLight ? Colors.black54 : Colors.white70,
                      ),
                    ),
                  ),
                  if (body != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                      child: Text(
                        body,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13,
                          color: isLight ? Colors.black45 : Colors.white54,
                        ),
                      ),
                    ),
                  Divider(
                      height: 1,
                      color: isLight ? Colors.black12 : Colors.white12),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: TextButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: Text(
                        actionLabel,
                        style: const TextStyle(
                          color: Color(0xFFFF3B30),
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              height: 52,
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(14),
              ),
              child: TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(
                  'Отменить',
                  style: TextStyle(
                    color: SLineColors.accentA,
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void openChat(ChatPreview c) async {
    if (selectMode) {
      _toggleSelect(c.chatKey);
      return;
    }
    if (c.chatKey.startsWith('c_')) {
      final id = c.chatKey.substring(2);
      // admin_id хранится в peer.bio (см. _loadChannelOrGroupPeer)
      var isAdmin = (c.peer?.bio ?? '') == widget.user.uid;
      String slug = c.peer?.username ?? '';
      String desc = '';
      bool isPublic = true;
      try {
        final cs =
            await FirebaseDatabase.instance.ref('channels/$id').get();
        if (cs.exists && cs.value is Map) {
          final d = Map<String, dynamic>.from(cs.value as Map);
          isAdmin = (d['admin_id'] ?? '').toString() == widget.user.uid;
          slug = (d['slug'] ?? d['username'] ?? slug).toString();
          desc = (d['description'] ?? '').toString();
          isPublic = d['public'] != false;
        }
        // роль в members
        final ms = await FirebaseDatabase.instance
            .ref('channel_members/$id/${widget.user.uid}')
            .get();
        if (ms.exists && ms.value is Map) {
          final role = (ms.value as Map)['role']?.toString() ?? '';
          if (role == 'admin') isAdmin = true;
        }
      } catch (_) {}
      if (!mounted) return;
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => ChannelScreen(
          user: widget.user,
          channelId: id,
          channelName: c.peer?.displayName ?? 'Канал',
          avatarUrl: c.peer?.avatarUrl,
          description: desc,
          isAdmin: isAdmin,
          isPublic: isPublic,
          slug: slug,
        ),
      ));
      return;
    }
    final peer = c.peer ??
        Profile(
            id: c.peerId,
            firstName: 'User',
            username: c.peerId.substring(0, c.peerId.length.clamp(0, 6)));
    Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => ChatScreen(
            user: widget.user,
            peer: c.isSaved ? Profile.saved(widget.user.uid) : peer,
            chatKey: c.chatKey,
            myProfile: widget.myProfile)));
  }

  void _enterSelect(String key) {
    HapticFeedback.mediumImpact();
    setState(() {
      selectMode = true;
      selectedKeys
        ..clear()
        ..add(key);
    });
  }

  void _toggleSelect(String key) {
    setState(() {
      if (selectedKeys.contains(key)) {
        selectedKeys.remove(key);
        if (selectedKeys.isEmpty) selectMode = false;
      } else {
        selectedKeys.add(key);
      }
    });
  }

  void _exitSelect() {
    setState(() {
      selectMode = false;
      selectedKeys.clear();
    });
  }

  Future<void> _deleteSelected() async {
    final keys = selectedKeys.toList();
    for (final k in keys) {
      setState(() {
        chatsMap.remove(k);
        subs.remove(k)?.cancel();
        listening.remove(k);
        pinnedKeys.remove(k);
        archivedKeys.remove(k);
      });
      try {
        await FirebaseDatabase.instance
            .ref('user_chat_index/${widget.user.uid}/$k')
            .remove();
      } catch (_) {}
      try {
        await FirebaseDatabase.instance
            .ref('user_pins/${widget.user.uid}/$k')
            .remove();
      } catch (_) {}
      try {
        await FirebaseDatabase.instance
            .ref('user_archive/${widget.user.uid}/$k')
            .remove();
      } catch (_) {}
    }
    if (mounted) {
      _exitSelect();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Удалено: ${keys.length}')),
      );
    }
  }

  Future<void> _archiveSelected() async {
    final keys = selectedKeys.toList();
    for (final k in keys) {
      setState(() => archivedKeys.add(k));
      try {
        await FirebaseDatabase.instance
            .ref('user_archive/${widget.user.uid}/$k')
            .set(true);
      } catch (_) {}
    }
    if (mounted) {
      _exitSelect();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('В архиве: ${keys.length}')),
      );
    }
  }

  Future<void> _unarchiveSelected() async {
    final keys = selectedKeys.toList();
    for (final k in keys) {
      setState(() => archivedKeys.remove(k));
      try {
        await FirebaseDatabase.instance
            .ref('user_archive/${widget.user.uid}/$k')
            .remove();
      } catch (_) {}
    }
    if (mounted) {
      _exitSelect();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Из архива: ${keys.length}')),
      );
    }
  }

  Future<void> _muteSelected() async {
    final keys = selectedKeys.toList();
    final me = widget.user.uid;
    // Если все выбранные уже muted → включаем, иначе выключаем
    final allMuted =
        keys.isNotEmpty && keys.every((k) => mutedKeys.contains(k));
    for (final k in keys) {
      setState(() {
        if (allMuted) {
          mutedKeys.remove(k);
        } else {
          mutedKeys.add(k);
        }
      });
      try {
        await FirebaseDatabase.instance
            .ref('user_mutes/$me/$k')
            .set(allMuted ? null : true);
      } catch (_) {}
    }
    if (mounted) {
      _exitSelect();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(allMuted
                ? 'Уведомления включены: ${keys.length}'
                : 'Уведомления отключены: ${keys.length}')),
      );
    }
  }

  void _markReadSelected() {
    // Пока нет счётчика непрочитанных — просто выходим
    final n = selectedKeys.length;
    _exitSelect();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text(n <= 1
              ? 'Отмечено как прочитанное'
              : 'Прочитано: $n')),
    );
  }

  void _openSearch() {
    Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => SearchPage(
            user: widget.user,
            myProfile: widget.myProfile,
            onOpenChat: (p) {
              Navigator.pop(context);
              final key = dmPairKey(widget.user.uid, p.id);
              Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => ChatScreen(
                      user: widget.user,
                      peer: p,
                      chatKey: key,
                      myProfile: widget.myProfile)));
            })));
  }

  @override
  Widget build(BuildContext context) {
    final items = list;
    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          if (_securityAlert != null) _buildSecurityBanner(),
          Expanded(
            child: NotificationListener<ScrollNotification>(
              onNotification: (n) {
                if (n is ScrollUpdateNotification && n.depth == 0) {
                  final dy = n.scrollDelta ?? 0;
                  final next =
                      (_storiesCollapse + dy / 90.0).clamp(0.0, 1.0);
                  if ((next - _storiesCollapse).abs() > 0.01) {
                    setState(() => _storiesCollapse = next);
                  }
                }
                return false;
              },
              child: CustomScrollView(
              slivers: [
                // Шапка «Чаты» + кнопки сжимается вместе с историями
                if (_storiesCollapse < 0.98)
                  ...[
                SliverToBoxAdapter(
                  child: Opacity(
                    opacity: (1 - _storiesCollapse).clamp(0.0, 1.0),
                    child: Transform.translate(
                      offset: Offset(0, -12 * _storiesCollapse),
                      child: Padding(
                    padding: const EdgeInsets.fromLTRB(8, 10, 12, 4),
                    child: Row(children: [
                      if (selectMode)
                        TextButton(
                          onPressed: _exitSelect,
                          child: Text('Готово',
                              style: TextStyle(
                                  color: SLineColors.accentA,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 16)),
                        )
                      else
                        Expanded(
                            child: Padding(
                          padding: const EdgeInsets.only(left: 8),
                          child: Text('Чаты',
                              style: TextStyle(
                                  fontSize: 30,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -0.6,
                                  color: themeCtrl.text)),
                        )),
                      if (selectMode)
                        Expanded(
                          child: Text(
                            selectedKeys.isEmpty
                                ? 'Выберите'
                                : 'Выбрано: ${selectedKeys.length}',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: themeCtrl.text),
                          ),
                        ),
                      if (!selectMode) ...[
                        IconButton(
                            onPressed: _openSearch,
                            icon: Icon(Icons.search, color: themeCtrl.text)),
                        IconButton(
                            onPressed: _showCreateMenu,
                            style: IconButton.styleFrom(
                                backgroundColor: SLineColors.accentA,
                                foregroundColor: Colors.white),
                            icon: const Icon(Icons.edit_square, size: 18)),
                      ],
                    ]),
                  ),
                    ),
                    ),
                  ),
                  ], // end collapse header
                if (!selectMode) ...[
                  // Истории: схлопываются при скролле (как в TG видео 1)
                  SliverToBoxAdapter(
                    child: ClipRect(
                      child: Align(
                        alignment: Alignment.topCenter,
                        heightFactor: (1.0 - _storiesCollapse * 0.92)
                            .clamp(0.0, 1.0),
                        child: Opacity(
                          opacity: (1.0 - _storiesCollapse).clamp(0.0, 1.0),
                          child: Transform.scale(
                            scale: 1.0 - _storiesCollapse * 0.15,
                            alignment: Alignment.topCenter,
                            child: SizedBox(
                              height: 96,
                              child: _buildStoriesBar(items),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: SizedBox(
                      height: 40 * (1.0 - _storiesCollapse * 0.5)
                          .clamp(0.35, 1.0),
                      child: Opacity(
                        opacity: (1.0 - _storiesCollapse * 0.5).clamp(0.4, 1.0),
                        child: ListView(
                          scrollDirection: Axis.horizontal,
                          padding:
                              const EdgeInsets.symmetric(horizontal: 12),
                          children: [
                            for (final f in const [
                              ('all', 'Все'),
                              ('private', 'Личные'),
                              ('groups', 'Группы'),
                              ('channels', 'Каналы'),
                              ('archive', 'Архив'),
                            ])
                              Padding(
                                padding: const EdgeInsets.only(right: 6),
                                child: ChoiceChip(
                                  label: Text(f.$2,
                                      style: TextStyle(
                                          fontSize: 13,
                                          color: folder == f.$1
                                              ? Colors.white
                                              : themeCtrl.muted)),
                                  selected: folder == f.$1,
                                  selectedColor: SLineColors.accentA,
                                  backgroundColor: themeCtrl.input,
                                  onSelected: (_) =>
                                      setState(() => folder = f.$1),
                                  visualDensity: VisualDensity.compact,
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
                if (listError != null && listError!.isNotEmpty)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(listError!,
                          style: const TextStyle(
                              color: SLineColors.danger, fontSize: 12)),
                    ),
                  ),
                if (!selectMode)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 4),
                      child: GestureDetector(
                        onTap: _openSearch,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 12),
                          decoration: BoxDecoration(
                            color: themeCtrl.input,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(children: [
                            Icon(Icons.search,
                                color: themeCtrl.muted, size: 20),
                            const SizedBox(width: 10),
                            Text('Поиск',
                                style: TextStyle(color: themeCtrl.muted)),
                          ]),
                        ),
                      ),
                    ),
                  ),
                SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (_, i) {
                      final c = items[i];
                      final peer = c.peer;
                      final selected = selectedKeys.contains(c.chatKey);
                      return _SwipeChatRow(
                        isSaved: c.isSaved,
                        pinned: c.pinned,
                        isArchived: archivedKeys.contains(c.chatKey) ||
                            c.archived,
                        isMuted: mutedKeys.contains(c.chatKey),
                        enabled: !selectMode,
                        onOpen: () => openChat(c),
                        onLongPress: () => _enterSelect(c.chatKey),
                        onPin: () => _togglePin(c),
                        onArchive: () => _toggleArchive(c),
                        onMute: () => _toggleMute(c),
                        onUnread: () {
                          // Пометить как непрочитанное (локально + индекс)
                          setState(() {
                            final cur = chatsMap[c.chatKey];
                            if (cur != null) {
                              chatsMap[c.chatKey] = ChatPreview(
                                chatKey: cur.chatKey,
                                peerId: cur.peerId,
                                peer: cur.peer,
                                lastMessage: cur.lastMessage,
                                lastAt: cur.lastAt,
                                isSaved: cur.isSaved,
                                kind: cur.kind,
                                pinned: cur.pinned,
                                unread: (cur.unread < 1) ? 1 : cur.unread,
                              );
                            }
                          });
                        },
                        onDelete: () async {
                          if (c.isSaved) {
                            final ok = await showDialog<bool>(
                                  context: context,
                                  builder: (ctx) => AlertDialog(
                                    title: const Text(
                                        'Вы точно хотите очистить избранное?'),
                                    content: const Text(
                                        'Восстановить сохранённые сообщения, медиа и файлы не получится'),
                                    actions: [
                                      TextButton(
                                          onPressed: () =>
                                              Navigator.pop(ctx, false),
                                          child: const Text('Отменить')),
                                      TextButton(
                                          onPressed: () =>
                                              Navigator.pop(ctx, true),
                                          child: const Text(
                                              'Очистить избранное',
                                              style: TextStyle(
                                                  color: Color(0xFFE53955)))),
                                    ],
                                  ),
                                ) ??
                                false;
                            if (!ok) return;
                            try {
                              await chatMsgsRef(c.chatKey).remove();
                            } catch (_) {}
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                      content: Text('Избранное очищено')));
                            }
                            return;
                          }
                          // Группа/канал: у админа — передать права или удалить навсегда
                          if (c.chatKey.startsWith('c_') ||
                              c.chatKey.startsWith('g_')) {
                            await _deleteGroupOrChannel(c);
                            return;
                          }
                          // Обычный чат — убрать только у себя
                          try {
                            await FirebaseDatabase.instance
                                .ref(
                                    'user_chat_index/${widget.user.uid}/${c.chatKey}')
                                .remove();
                          } catch (_) {}
                          setState(() {
                            chatsMap.remove(c.chatKey);
                            subs.remove(c.chatKey)?.cancel();
                            listening.remove(c.chatKey);
                          });
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 10),
                          child: Row(children: [
                            if (selectMode) ...[
                              AnimatedContainer(
                                duration: const Duration(milliseconds: 160),
                                width: 24,
                                height: 24,
                                margin: const EdgeInsets.only(right: 12),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: selected
                                      ? SLineColors.accentA
                                      : Colors.transparent,
                                  border: Border.all(
                                    color: selected
                                        ? SLineColors.accentA
                                        : themeCtrl.muted
                                            .withValues(alpha: 0.5),
                                    width: 2,
                                  ),
                                ),
                                child: selected
                                    ? const Icon(Icons.check,
                                        size: 14, color: Colors.white)
                                    : null,
                              ),
                            ],
                            c.kind == 'saved' || c.isSaved
                                ? Container(
                                    width: 52,
                                    height: 52,
                                    decoration: const BoxDecoration(
                                        shape: BoxShape.circle,
                                        gradient: LinearGradient(colors: [
                                          Color(0xFFF5A623),
                                          Color(0xFFE67E22)
                                        ])),
                                    child: const Icon(Icons.bookmark,
                                        color: Colors.white))
                                : c.kind == 'channel'
                                    ? Container(
                                        width: 52,
                                        height: 52,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: peer?.colorValue ??
                                              const Color(0xFF6D5DF6),
                                        ),
                                        child: peer?.avatarUrl != null &&
                                                peer!.avatarUrl!.isNotEmpty
                                            ? ClipOval(
                                                child: SLineNetImage(
                                                  url: peer.avatarUrl!,
                                                  width: 52,
                                                  height: 52,
                                                  fit: BoxFit.cover,
                                                ),
                                              )
                                            : Center(
                                                child: Text(
                                                  () {
                                                    final n =
                                                        peer?.displayName ??
                                                            'К';
                                                    return n.isEmpty
                                                        ? 'К'
                                                        : n[0].toUpperCase();
                                                  }(),
                                                  style: const TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 22,
                                                    fontWeight: FontWeight.w700,
                                                  ),
                                                ),
                                              ),
                                      )
                                    // Тап по аватару = открыть чат (не профиль)
                                    : _Avatar(
                                        name: peer?.displayName ?? '?',
                                        color: peer?.colorValue ??
                                            SLineColors.accentA,
                                        url: peer?.avatarUrl,
                                        size: 52,
                                      ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(children: [
                                    Expanded(
                                      child: Text(peer?.displayName ?? 'User',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.w600,
                                              color: themeCtrl.text)),
                                    ),
                                    if (c.pinned)
                                      const Padding(
                                        padding: EdgeInsets.only(left: 4),
                                        child: Icon(Icons.push_pin,
                                            size: 14,
                                            color: SLineColors.mint),
                                      ),
                                    if (c.lastAt > 0)
                                      Padding(
                                        padding:
                                            const EdgeInsets.only(left: 6),
                                        child: Text(
                                          () {
                                            final dt = DateTime
                                                .fromMillisecondsSinceEpoch(
                                                    c.lastAt);
                                            final now = DateTime.now();
                                            if (dt.year == now.year &&
                                                dt.month == now.month &&
                                                dt.day == now.day) {
                                              return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
                                            }
                                            return '${dt.day}.${dt.month.toString().padLeft(2, '0')}';
                                          }(),
                                          style: TextStyle(
                                              fontSize: 12,
                                              color: themeCtrl.muted),
                                        ),
                                      ),
                                  ]),
                                  const SizedBox(height: 3),
                                  Text(c.lastMessage,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                          fontSize: 14,
                                          color: themeCtrl.muted)),
                                ],
                              ),
                            ),
                          ]),
                        ),
                      );
                    },
                    childCount: items.length,
                  ),
                ),
                // Место под стеклянную нижнюю панель (контент просвечивает)
                SliverToBoxAdapter(
                    child: SizedBox(height: selectMode ? 80 : 88)),
              ],
            ), // CustomScrollView
            ), // NotificationListener
          ), // Expanded
          if (selectMode)
            Material(
              color: themeCtrl.light
                  ? Colors.white.withValues(alpha: 0.95)
                  : const Color(0xFF1C1C1E).withValues(alpha: 0.96),
              elevation: 8,
              child: SafeArea(
                top: false,
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _selAction(
                        Icons.done_all,
                        'Прочитать',
                        selectedKeys.isEmpty ? null : _markReadSelected,
                      ),
                      _selAction(
                        folder == 'archive'
                            ? Icons.unarchive_outlined
                            : Icons.archive_outlined,
                        folder == 'archive' ? 'Из архива' : 'В архив',
                        selectedKeys.isEmpty
                            ? null
                            : (folder == 'archive'
                                ? _unarchiveSelected
                                : _archiveSelected),
                      ),
                      _selAction(
                        selectedKeys.isNotEmpty &&
                                selectedKeys
                                    .every((k) => mutedKeys.contains(k))
                            ? Icons.notifications_active_outlined
                            : Icons.notifications_off_outlined,
                        selectedKeys.isNotEmpty &&
                                selectedKeys
                                    .every((k) => mutedKeys.contains(k))
                            ? 'Вкл. уведомл.'
                            : 'Откл. уведомл.',
                        selectedKeys.isEmpty ? null : _muteSelected,
                      ),
                      _selAction(
                        Icons.delete_outline,
                        'Удалить',
                        selectedKeys.isEmpty ? null : _deleteSelected,
                        danger: true,
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _selAction(IconData icon, String label, VoidCallback? onTap,
      {bool danger = false}) {
    final color = onTap == null
        ? themeCtrl.muted.withValues(alpha: 0.4)
        : (danger ? SLineColors.danger : themeCtrl.text);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: 2),
            Text(label, style: TextStyle(fontSize: 12, color: color)),
          ],
        ),
      ),
    );
  }

  void _showCreateMenu() {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => StartChatPage(
        user: widget.user,
        myProfile: widget.myProfile,
      ),
    ));
  }


  bool _userHasStories(String uid) {
    final list = storiesByUser[uid];
    if (list == null || list.isEmpty) return false;
    return list.any((s) => (s.mediaUrl ?? '').trim().isNotEmpty);
  }

  Widget _buildStoriesBar(List<ChatPreview> items) {
    final me = widget.user.uid;
    for (final c in items) {
      if (!c.isSaved) contactIds.add(c.peerId);
    }
    final friendUids = <String>[];
    final interestingUids = <String>[];
    for (final uid in storiesByUser.keys) {
      if (uid == me) continue;
      // Не показываем кольцо, если у человека нет активных историй
      if (!_userHasStories(uid)) continue;
      if (contactIds.contains(uid)) {
        friendUids.add(uid);
      } else {
        interestingUids.add(uid);
      }
    }
    final myStories = _userHasStories(me) ? (storiesByUser[me] ?? []) : <StoryItem>[];

    return ListView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      children: [
        _storyAdd(),
        if (myStories.isNotEmpty)
          _storyRing(
            label: 'Моя',
            name: widget.myProfile?.displayName ?? 'Я',
            color: widget.myProfile?.colorValue ?? SLineColors.accentA,
            url: widget.myProfile?.avatarUrl,
            onTap: () => _openStories(me, 'Моя'),
          ),
        ...friendUids.map((uid) {
          Profile? peer;
          for (final c in items) {
            if (c.peerId == uid && c.peer != null) {
              peer = c.peer;
              break;
            }
          }
          return _StoryRingLoader(
            uid: uid,
            peer: peer,
            onTap: (p) =>
                _openStories(uid, p?.displayName ?? 'История'),
          );
        }),
        if (interestingUids.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Column(children: [
              GestureDetector(
                onTap: () => _openInteresting(interestingUids),
                child: Container(
                  width: 60,
                  height: 60,
                  padding: const EdgeInsets.all(3),
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(colors: [
                      Color(0xFF8B7CFF),
                      Color(0xFF6D5DF6),
                      Color(0xFF5B8CFF),
                    ]),
                  ),
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: themeCtrl.bg,
                    ),
                    alignment: Alignment.center,
                    child: Container(
                      width: 48,
                      height: 48,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(colors: [
                          Color(0xFF9B8CFF),
                          Color(0xFF6D5DF6),
                        ]),
                      ),
                      child: const Icon(Icons.star_rounded,
                          color: Colors.white, size: 28),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              SizedBox(
                width: 66,
                child: Text(
                  'Интересное',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 11, color: themeCtrl.muted),
                ),
              ),
            ]),
          ),
      ],
    );
  }

  void _openStories(String uid, String title, {String? avatar}) {
    final list = storiesByUser[uid] ?? [];
    final urls = list
        .map((s) => s.mediaUrl)
        .whereType<String>()
        .map((u) => u.trim())
        .where((u) => u.isNotEmpty)
        .toList();
    if (urls.isEmpty) return;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => StoryViewer(
        name: title,
        avatar: avatar,
        mediaUrls: urls,
      ),
    ));
  }

  void _openInteresting(List<String> uids) {
    final urls = <String>[];
    for (final uid in uids) {
      for (final s in storiesByUser[uid] ?? []) {
        if (s.mediaUrl != null && s.mediaUrl!.isNotEmpty) {
          urls.add(s.mediaUrl!);
        }
      }
    }
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => StoryViewer(
        name: 'Интересное',
        mediaUrls: urls,
      ),
    ));
  }

  Widget _storyRing({
    required String label,
    required String name,
    required Color color,
    String? url,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Column(children: [
        GestureDetector(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(2),
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                  colors: [SLineColors.accentA, SLineColors.mint]),
            ),
            child: Container(
              padding: const EdgeInsets.all(2),
              decoration:
                  BoxDecoration(shape: BoxShape.circle, color: themeCtrl.bg),
              child: _Avatar(name: name, color: color, url: url, size: 52),
            ),
          ),
        ),
        const SizedBox(height: 4),
        SizedBox(
          width: 64,
          child: Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11, color: themeCtrl.muted)),
        ),
      ]),
    );
  }


  Future<void> _publishStory() async {
    // как на вебе: выбор источника → галерея / камера / видео
    final src = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: themeCtrl.hover,
      builder: (ctx) => SafeArea(
        child: Wrap(children: [
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: const Text('Из галереи'),
            onTap: () => Navigator.pop(ctx, 'gallery'),
          ),
          ListTile(
            leading: const Icon(Icons.photo_camera_outlined),
            title: const Text('Камера'),
            onTap: () => Navigator.pop(ctx, 'camera'),
          ),
          ListTile(
            leading: const Icon(Icons.videocam_outlined),
            title: const Text('Видео из галереи'),
            onTap: () => Navigator.pop(ctx, 'video'),
          ),
        ]),
      ),
    );
    if (src == null) return;
    try {
      String? path;
      var type = 'image';
      if (src == 'camera') {
        try {
          final x = await ImagePicker()
              .pickImage(source: ImageSource.camera, imageQuality: 85);
          path = x?.path;
        } catch (_) {
          path = null;
        }
        // Если камеры нет — галерея
        if (path == null || path.isEmpty) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                  content: Text('Камера недоступна, откройте галерею')),
            );
          }
          path = await showModalBottomSheet<String>(
            context: context,
            isScrollControlled: true,
            backgroundColor: Colors.transparent,
            builder: (_) =>
                const InAppGalleryPicker(requestType: RequestType.image),
          );
        }
      } else if (src == 'video') {
        type = 'video';
        path = await showModalBottomSheet<String>(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (_) =>
              const InAppGalleryPicker(requestType: RequestType.video),
        );
      } else {
        path = await showModalBottomSheet<String>(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (_) =>
              const InAppGalleryPicker(requestType: RequestType.image),
        );
      }
      if (path == null || path.isEmpty) return;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Публикация…')));
      }
      final url = await B2Storage.uploadFile(
          File(path), 'stories', widget.user.uid);
      final now = DateTime.now();
      final payload = {
        'user_id': widget.user.uid,
        'media_url': url,
        'type': type,
        'created_at': now.toIso8601String(),
        'expires_at': now.add(const Duration(hours: 24)).toIso8601String(),
      };
      // Пишем и в tables/stories, и в stories (как на вебе / разные rules)
      Object? lastStoryErr;
      for (final path in ['tables/stories', 'stories']) {
        try {
          final ref = FirebaseDatabase.instance.ref(path).push();
          await ref.set({...payload, 'id': ref.key});
          lastStoryErr = null;
          break;
        } catch (e) {
          lastStoryErr = e;
        }
      }
      if (lastStoryErr != null) throw lastStoryErr;
      await _loadStories();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('История опубликована')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  Widget _storyAdd() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Column(children: [
        GestureDetector(
          onTap: () => _publishStory(),
          child: Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: themeCtrl.muted, width: 2)),
            child: Icon(Icons.add, color: themeCtrl.muted),
          ),
        ),
        const SizedBox(height: 4),
        Text('Моя история',
            style: TextStyle(fontSize: 11, color: themeCtrl.muted)),
      ]),
    );
  }
}

class _StoryRingLoader extends StatelessWidget {
  final String uid;
  final Profile? peer;
  final void Function(Profile?) onTap;
  const _StoryRingLoader(
      {required this.uid, this.peer, required this.onTap});
  @override
  Widget build(BuildContext context) {
    if (peer != null) {
      return _ring(peer!);
    }
    return FutureBuilder<Profile?>(
      future: loadProfile(uid),
      builder: (ctx, snap) {
        final p = snap.data;
        if (p == null) {
          return const SizedBox(width: 72, height: 96);
        }
        return _ring(p);
      },
    );
  }

  Widget _ring(Profile p) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Column(children: [
        GestureDetector(
          onTap: () => onTap(p),
          child: Container(
            padding: const EdgeInsets.all(2),
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                  colors: [SLineColors.accentA, SLineColors.mint]),
            ),
            child: Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                  shape: BoxShape.circle, color: themeCtrl.bg),
              child: _Avatar(
                  name: p.displayName,
                  color: p.colorValue,
                  url: p.avatarUrl,
                  size: 52),
            ),
          ),
        ),
        const SizedBox(height: 4),
        SizedBox(
          width: 64,
          child: Text(p.displayName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11, color: themeCtrl.muted)),
        ),
      ]),
    );
  }
}


class _SwipeChatRow extends StatefulWidget {
  final Widget child;
  final VoidCallback onOpen;
  final VoidCallback onDelete;
  final VoidCallback? onPin;
  final VoidCallback? onArchive;
  final VoidCallback? onMute;
  final VoidCallback? onUnread;
  final VoidCallback? onLongPress;
  final bool isSaved;
  final bool pinned;
  final bool isArchived;
  final bool isMuted;
  final bool enabled;
  const _SwipeChatRow(
      {required this.child,
      required this.onOpen,
      required this.onDelete,
      this.onPin,
      this.onArchive,
      this.onMute,
      this.onUnread,
      this.onLongPress,
      this.isSaved = false,
      this.pinned = false,
      this.isArchived = false,
      this.isMuted = false,
      this.enabled = true});
  @override
  State<_SwipeChatRow> createState() => _SwipeChatRowState();
}

/// Свайп как в MAX:
/// вправо → «Не прочитан» + «Закрепить» (далеко → растягивается «Не прочитан»)
/// влево  → «Откл. звук» + «Удалить» (далеко → растягивается «Удалить»/«Очистить»)
/// полный свайп + отпускание → диалог «Вы точно хотите …?»
class _SwipeChatRowState extends State<_SwipeChatRow>
    with SingleTickerProviderStateMixin {
  double dx = 0;
  static const btnW = 88.0;
  static const twoBtns = 176.0;
  /// Порог «далёкого» свайпа — кнопка растягивается на всю ширину
  static const fullThreshold = 220.0;

  late final AnimationController _snap;

  @override
  void initState() {
    super.initState();
    _snap = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 220));
  }

  @override
  void dispose() {
    _snap.dispose();
    super.dispose();
  }

  Future<void> _confirmAndRun({
    required String title,
    required String actionLabel,
    String? body,
    required VoidCallback action,
  }) async {
    final ok = await showModalBottomSheet<bool>(
          context: context,
          backgroundColor: Colors.transparent,
          builder: (ctx) {
            final isLight = themeCtrl.light;
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: isLight
                            ? Colors.white
                            : const Color(0xFF2C2C2E),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Column(
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
                            child: Text(
                              title,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 13,
                                color: isLight
                                    ? Colors.black54
                                    : Colors.white70,
                              ),
                            ),
                          ),
                          if (body != null)
                            Padding(
                              padding:
                                  const EdgeInsets.fromLTRB(16, 0, 16, 12),
                              child: Text(
                                body,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: isLight
                                      ? Colors.black45
                                      : Colors.white54,
                                ),
                              ),
                            ),
                          Divider(
                              height: 1,
                              color: isLight
                                  ? Colors.black12
                                  : Colors.white12),
                          SizedBox(
                            width: double.infinity,
                            height: 52,
                            child: TextButton(
                              onPressed: () => Navigator.pop(ctx, true),
                              child: Text(
                                actionLabel,
                                style: const TextStyle(
                                  color: Color(0xFFFF3B30),
                                  fontSize: 17,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      height: 52,
                      decoration: BoxDecoration(
                        color: isLight
                            ? Colors.white
                            : const Color(0xFF2C2C2E),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: Text(
                          'Отменить',
                          style: TextStyle(
                            color: SLineColors.accentA,
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ) ??
        false;
    setState(() => dx = 0);
    if (ok) action();
  }

  Future<void> _onDragEnd(DragEndDetails d) async {
    final v = d.primaryVelocity ?? 0;
    // Полный свайп влево → удалить/очистить с подтверждением
    if (dx < -fullThreshold || (dx < -120 && v < -800)) {
      setState(() => dx = -MediaQuery.of(context).size.width * 0.55);
      await Future.delayed(const Duration(milliseconds: 80));
      if (!mounted) return;
      if (widget.isSaved) {
        await _confirmAndRun(
          title: 'Вы точно хотите очистить избранное?',
          body:
              'Восстановить сохранённые сообщения, медиа и файлы не получится',
          actionLabel: 'Очистить избранное',
          action: widget.onDelete,
        );
      } else {
        await _confirmAndRun(
          title: 'Вы точно хотите удалить чат?',
          body: 'Чат исчезнет из списка. История на сервере может остаться.',
          actionLabel: 'Удалить',
          action: widget.onDelete,
        );
      }
      return;
    }
    // Полный свайп вправо → «Не прочитан» (мягкое действие без диалога)
    if (dx > fullThreshold || (dx > 120 && v > 800)) {
      setState(() => dx = 0);
      widget.onUnread?.call();
      return;
    }
    // Обычный snap к открытым кнопкам или закрытие
    setState(() {
      if (dx > 48 || v > 400) {
        dx = twoBtns;
      } else if (dx < -40 || v < -350) {
        dx = widget.isSaved ? -btnW : -twoBtns;
      } else {
        dx = 0;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final bg = themeCtrl.light ? Colors.white : const Color(0xFF0E1218);
    final screenW = MediaQuery.of(context).size.width;
    // Насколько «далеко» уехали влево/вправо
    final leftReveal = dx.clamp(-screenW, 0.0).abs();
    final rightReveal = dx.clamp(0.0, screenW);

    // Растягивание крайней кнопки при глубоком свайпе (как в MAX)
    final deleteExpanded = leftReveal > twoBtns + 20;
    double deleteW;
    double muteW;
    if (widget.isSaved) {
      muteW = 0;
      deleteW = leftReveal.clamp(0.0, screenW * 0.75);
    } else if (deleteExpanded) {
      muteW = 0;
      deleteW = leftReveal.clamp(btnW, screenW * 0.75);
    } else {
      // Сначала появляется «Удалить», потом «Откл. звук»
      deleteW = leftReveal.clamp(0.0, btnW);
      muteW = (leftReveal - btnW).clamp(0.0, btnW);
    }

    final unreadExpanded = rightReveal > twoBtns + 20;
    double unreadW;
    double pinW;
    if (unreadExpanded) {
      pinW = 0;
      unreadW = rightReveal.clamp(btnW, screenW * 0.75);
    } else {
      // Сначала «Не прочитан», потом «Закрепить»
      unreadW = rightReveal.clamp(0.0, btnW);
      pinW = (rightReveal - btnW).clamp(0.0, btnW);
    }

    return SizedBox(
      height: 72,
      child: Stack(children: [
        if (widget.enabled) ...[
          // LEFT (свайп вправо): Не прочитан + Закрепить
          Positioned.fill(
            child: Row(children: [
              if (unreadW > 0)
                _actionBtn(
                  const Color(0xFF2A6AF0),
                  Icons.chat_bubble_rounded,
                  'Не прочитан',
                  () {
                    setState(() => dx = 0);
                    widget.onUnread?.call();
                  },
                  width: unreadW,
                ),
              if (pinW > 0)
                _actionBtn(
                  const Color(0xFF34C759),
                  widget.pinned ? Icons.push_pin : Icons.push_pin_outlined,
                  widget.pinned ? 'Откреп.' : 'Закрепить',
                  () {
                    setState(() => dx = 0);
                    widget.onPin?.call();
                  },
                  width: pinW,
                ),
              const Spacer(),
            ]),
          ),
          // RIGHT (свайп влево)
          Positioned.fill(
            child: Row(children: [
              const Spacer(),
              if (widget.isSaved) ...[
                if (deleteW > 0)
                  _actionBtn(
                    const Color(0xFFE53975),
                    Icons.delete_outline_rounded,
                    'Очистить',
                    () async {
                      await _confirmAndRun(
                        title: 'Вы точно хотите очистить избранное?',
                        body:
                            'Восстановить сохранённые сообщения, медиа и файлы не получится',
                        actionLabel: 'Очистить избранное',
                        action: widget.onDelete,
                      );
                    },
                    width: deleteW,
                  ),
              ] else ...[
                if (muteW > 0)
                  _actionBtn(
                    const Color(0xFFFF9500),
                    widget.isArchived
                        ? Icons.unarchive_outlined
                        : (widget.isMuted
                            ? Icons.notifications_active_outlined
                            : Icons.notifications_off_outlined),
                    widget.isArchived
                        ? 'Из архива'
                        : (widget.isMuted
                            ? 'Вкл. уведомл.'
                            : 'Откл. уведомл.'),
                    () {
                      setState(() => dx = 0);
                      if (widget.isArchived) {
                        widget.onArchive?.call();
                      } else {
                        (widget.onMute ?? widget.onArchive)?.call();
                      }
                    },
                    width: muteW,
                  ),
                if (deleteW > 0)
                  _actionBtn(
                    const Color(0xFFFF2D55),
                    Icons.delete_outline_rounded,
                    'Удалить',
                    () async {
                      await _confirmAndRun(
                        title: 'Вы точно хотите удалить чат?',
                        body:
                            'Чат исчезнет из списка. История на сервере может остаться.',
                        actionLabel: 'Удалить',
                        action: widget.onDelete,
                      );
                    },
                    width: deleteW,
                  ),
              ],
            ]),
          ),
        ],
        Transform.translate(
          offset: Offset(widget.enabled ? dx : 0, 0),
          child: Material(
            color: bg,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onHorizontalDragUpdate: widget.enabled
                  ? (d) {
                      setState(() {
                        dx = (dx + d.delta.dx)
                            .clamp(-screenW * 0.75, screenW * 0.75);
                      });
                    }
                  : null,
              onHorizontalDragEnd:
                  widget.enabled ? _onDragEnd : null,
              onLongPress: widget.onLongPress,
              onTap: () {
                if (dx.abs() > 8 && widget.enabled) {
                  setState(() => dx = 0);
                } else {
                  widget.onOpen();
                }
              },
              child: SizedBox(height: 72, child: widget.child),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _actionBtn(Color c, IconData i, String t, VoidCallback? onTap,
      {double width = 88}) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 40),
      width: width,
      height: 72,
      color: c,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: width < 36
              ? const SizedBox.shrink()
              : Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(i, color: Colors.white, size: width > 70 ? 24 : 20),
                    if (width > 56) ...[
                      const SizedBox(height: 2),
                      Text(
                        t,
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
        ),
      ),
    );
  }
}

// ── search page ─────────────────────────────────────────────
class SearchPage extends StatefulWidget {
  final User user;
  final Profile? myProfile;
  final ValueChanged<Profile> onOpenChat;
  final bool focusNew;
  const SearchPage(
      {super.key,
      required this.user,
      this.myProfile,
      required this.onOpenChat,
      this.focusNew = false});
  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final q = TextEditingController();
  List<Profile> results = [];
  List<Map<String, dynamic>> channels = [];
  bool loading = false;
  Timer? deb;

  @override
  void initState() {
    super.initState();
    _load('');
  }

  Future<void> _load(String query) async {
    setState(() => loading = true);
    try {
      final qn = query.trim().toLowerCase();
      if (qn.length < 2) {
        final snap = await profilesRef().limitToFirst(40).get();
        final list = <Profile>[];
        if (snap.exists && snap.value is Map) {
          for (final e in (snap.value as Map).entries) {
            if (e.key.toString() == widget.user.uid) continue;
            if (e.value is Map) {
              list.add(Profile.fromMap(
                  e.key.toString(), Map<String, dynamic>.from(e.value as Map)));
            }
          }
        }
        if (mounted) {
          setState(() {
            results = list;
            channels = [];
          });
        }
      } else {
        final list =
            await searchProfiles(query, excludeUid: widget.user.uid);
        // Публичные каналы по имени/slug
        final chList = <Map<String, dynamic>>[];
        try {
          final cs = await FirebaseDatabase.instance.ref('channels').get();
          if (cs.exists && cs.value is Map) {
            for (final e in (cs.value as Map).entries) {
              if (e.value is! Map) continue;
              final d = Map<String, dynamic>.from(e.value as Map);
              if (d['public'] == false) continue;
              final name = (d['name'] ?? '').toString().toLowerCase();
              final slug =
                  (d['slug'] ?? d['username'] ?? '').toString().toLowerCase();
              if (name.contains(qn) || slug.contains(qn)) {
                chList.add({...d, 'id': e.key.toString()});
              }
            }
          }
        } catch (_) {}
        if (mounted) {
          setState(() {
            results = list;
            channels = chList;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(permissionHelp(e))));
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      backgroundColor: themeCtrl.bg,
      appBar: AppBar(
        title: TextField(
          controller: q,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Люди, каналы, @username',
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            filled: false,
          ),
          onChanged: (v) {
            deb?.cancel();
            deb = Timer(const Duration(milliseconds: 300), () => _load(v));
          },
        ),
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                ListTile(
                  leading: Container(
                      width: 48,
                      height: 48,
                      decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(colors: [
                            Color(0xFFF5A623),
                            Color(0xFFE67E22)
                          ])),
                      child:
                          const Icon(Icons.bookmark, color: Colors.white)),
                  title: const Text('Избранное'),
                  onTap: () =>
                      widget.onOpenChat(Profile.saved(widget.user.uid)),
                ),
                if (channels.isNotEmpty) ...[
                  const Divider(),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                    child: Text('Каналы',
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: themeCtrl.muted)),
                  ),
                  ...channels.map((d) {
                    final id = (d['id'] ?? '').toString();
                    final name = (d['name'] ?? 'Канал').toString();
                    final slug =
                        (d['slug'] ?? d['username'] ?? '').toString();
                    return ListTile(
                      leading: _Avatar(
                          name: name,
                          color: SLineColors.accentB,
                          url: d['avatar_url']?.toString()),
                      title: Text(name),
                      subtitle: Text(slug.isNotEmpty ? '@$slug' : 'канал'),
                      trailing: const Icon(Icons.campaign_outlined, size: 18),
                      onTap: () {
                        Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => ChannelScreen(
                            user: widget.user,
                            channelId: id,
                            channelName: name,
                            avatarUrl: d['avatar_url']?.toString(),
                            description: (d['description'] ?? '').toString(),
                            isAdmin: (d['admin_id'] ?? '') == widget.user.uid,
                            isPublic: d['public'] != false,
                            slug: slug,
                          ),
                        ));
                      },
                    );
                  }),
                ],
                const Divider(),
                ...results.map((p) => ListTile(
                      leading: _Avatar(
                          name: p.displayName,
                          color: p.colorValue,
                          url: p.avatarUrl),
                      title: Text(p.displayName),
                      subtitle: Text(p.username.isNotEmpty
                          ? '@${p.username}'
                          : ''),
                      onTap: () => widget.onOpenChat(p),
                      onLongPress: () {
                        Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) => ProfilePage(
                                user: widget.user,
                                profile: p,
                                isMe: false)));
                      },
                    )),
              ],
            ),
    );
  }
}

// ── profile ─────────────────────────────────────────────────
class ProfilePage extends StatefulWidget {
  final User user;
  final Profile profile;
  final bool isMe;
  const ProfilePage(
      {super.key,
      required this.user,
      required this.profile,
      required this.isMe});
  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  bool isContact = false;
  late final nameC =
      TextEditingController(text: widget.profile.firstName);
  late final bioC = TextEditingController(text: widget.profile.bio ?? '');
  late final avatarC =
      TextEditingController(text: widget.profile.avatarUrl ?? '');
  bool saving = false;

  @override
  void initState() {
    super.initState();
    _checkContact();
  }

  Future<void> _checkContact() async {
    if (widget.isMe) return;
    try {
      final snap = await FirebaseDatabase.instance
          .ref('my_contacts/${widget.user.uid}/${widget.profile.id}')
          .get();
      if (mounted) setState(() => isContact = snap.exists);
    } catch (_) {}
  }

  Future<void> _startCall({required bool audioOnly}) async {
    final peer = widget.profile;
    if (peer.isSaved) return;
    try {
      final callRef = FirebaseDatabase.instance.ref('calls').push();
      final id = callRef.key!;
      await callRef.set({
        'from': widget.user.uid,
        'to': peer.id,
        'type': audioOnly ? 'audio' : 'video',
        'status': 'ringing',
        'created_at': DateTime.now().millisecondsSinceEpoch,
      });
      if (!mounted) return;
      await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => InAppCallScreen(
          callId: id,
          user: widget.user,
          peer: peer,
          audioOnly: audioOnly,
          isCaller: true,
        ),
      ));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }


  String? _localAvatarPath;

  Future<void> _pickAvatar() async {
    try {
      final x = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        imageQuality: 70,
        maxWidth: 512,
        maxHeight: 512,
      );
      if (x == null) return;
      final file = File(x.path);
      if (!await file.exists()) {
        throw Exception('Файл не найден');
      }
      // Сразу превью
      setState(() {
        saving = true;
        _localAvatarPath = x.path;
      });
      final url = await B2Storage.uploadAvatar(file, widget.user.uid)
          .timeout(const Duration(seconds: 40));
      if (url.isEmpty) throw Exception('Пустой URL');
      avatarC.text = url;
      await profilesRef()
          .child(widget.user.uid)
          .update({
            'avatar_url': url,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .timeout(const Duration(seconds: 15));
      if (mounted) {
        setState(() {
          saving = false;
          _localAvatarPath = null; // теперь из URL
        });
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Аватар обновлён')));
      }
    } catch (e) {
      if (mounted) {
        setState(() => saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Аватар: $e'),
            duration: const Duration(seconds: 6),
          ),
        );
      }
    }
  }

  Future<void> _save() async {
    setState(() => saving = true);
    try {
      await profilesRef().child(widget.user.uid).update({
        'first_name': nameC.text.trim(),
        'bio': bioC.text.trim(),
        'avatar_url': avatarC.text.trim().isEmpty ? null : avatarC.text.trim(),
      });
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Сохранено')));
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(permissionHelp(e))));
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> _addContact() async {
    try {
      await FirebaseDatabase.instance
          .ref('my_contacts/${widget.user.uid}/${widget.profile.id}')
          .set(true);
      if (mounted) {
        setState(() => isContact = true);
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Добавлен в контакты')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  Future<void> _sendGiftFromProfile() async {
    final id = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: themeCtrl.panel,
      isScrollControlled: true,
      builder: (ctx) => _GiftPickerSheet(uid: widget.user.uid),
    );
    if (id == null || !mounted) return;
    final price = SLineGifts.priceFor(id);
    final ok = await SCoin.spend(widget.user.uid, price);
    if (!ok) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Недостаточно SCoin (нужно $price)')),
        );
      }
      return;
    }
    final key = dmPairKey(widget.user.uid, widget.profile.id);
    try {
      final ref = chatMsgsRef(key).push();
      final now = DateTime.now();
      final mid = ref.key!;
      await ref.set({
        'id': mid,
        'sender_id': widget.user.uid,
        'receiver_id': widget.profile.id,
        'content': 'gift:$id',
        'type': 'gift',
        'file_url': id,
        'gift_id': id,
        'gift_emoji': SLineGifts.emojiFor(id),
        'gift_name': SLineGifts.labelFor(id),
        'gift_price': price,
        'gift_sell': SLineGifts.sellFor(id),
        'created_at': now.toIso8601String(),
        'created_at_ms': now.millisecondsSinceEpoch,
      });
      await FirebaseDatabase.instance
          .ref('user_gifts/${widget.profile.id}/$mid')
          .set({
        'id': mid,
        'gift_id': id,
        'gift_emoji': SLineGifts.emojiFor(id),
        'gift_name': SLineGifts.labelFor(id),
        'gift_price': price,
        'gift_sell': SLineGifts.sellFor(id),
        'from_id': widget.user.uid,
        'visible': true,
        'created_at': now.toIso8601String(),
        'created_at_ms': now.millisecondsSinceEpoch,
      });
      await ChatListSync.ensureIndexed(
        myUid: widget.user.uid,
        chatKey: key,
        peerUid: widget.profile.id,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Подарок отправлен')));
      }
    } catch (e) {
      // вернуть SCoin при ошибке
      try {
        await SCoin.add(widget.user.uid, price);
      } catch (_) {}
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.profile;
    final avUrl = widget.isMe
        ? (_localAvatarPath != null
            ? _localAvatarPath
            : (avatarC.text.trim().isEmpty
                ? p.avatarUrl
                : avatarC.text.trim()))
        : p.avatarUrl;
    return Scaffold(
      backgroundColor: themeCtrl.bg,
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(
            parent: AlwaysScrollableScrollPhysics()),
        slivers: [
          SliverAppBar(
            expandedHeight: 260,
            pinned: true,
            stretch: true,
            elevation: 0,
            backgroundColor: themeCtrl.panel,
            flexibleSpace: FlexibleSpaceBar(
              stretchModes: const [
                StretchMode.zoomBackground,
                StretchMode.blurBackground,
                StretchMode.fadeTitle,
              ],
              collapseMode: CollapseMode.parallax,
              centerTitle: true,
              title: Text(
                p.displayName,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: themeCtrl.text,
                  shadows: const [
                    Shadow(color: Colors.black26, blurRadius: 6)
                  ],
                ),
              ),
              background: Stack(
                fit: StackFit.expand,
                children: [
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          p.colorValue.withValues(alpha: 0.95),
                          SLineColors.accentB.withValues(alpha: 0.8),
                          themeCtrl.bg,
                        ],
                        stops: const [0.0, 0.55, 1.0],
                      ),
                    ),
                  ),
                  // большой аватар с параллаксом при скролле
                  Align(
                    alignment: const Alignment(0, 0.15),
                    child: GestureDetector(
                      onTap: () {
                        final u = (avUrl ?? '').trim();
                        if (u.isEmpty) return;
                        Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) =>
                              _MediaViewerPage(url: u, isVideo: false),
                        ));
                      },
                      child: Hero(
                        tag: 'profile_av_${p.id}',
                        child: Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                                color: Colors.white.withValues(alpha: 0.85),
                                width: 3),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.25),
                                blurRadius: 18,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          child: _Avatar(
                              name: p.displayName,
                              color: p.colorValue,
                              url: avUrl,
                              size: 112),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              if (widget.isMe)
                IconButton(
                    icon: const Icon(Icons.edit_outlined),
                    onPressed: () {}),
            ],
          ),
          // Контент профиля
          SliverToBoxAdapter(
            child: Column(children: [
              const SizedBox(height: 12),
              Text(p.displayName,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: themeCtrl.text)),
              if (p.username.isNotEmpty)
                Text('@${p.username}',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 14, color: themeCtrl.muted)),
              const SizedBox(height: 16),
              if (!widget.isMe) ...[
                  // Кнопки как на вебе: Звонок | Видео | Ещё
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        Expanded(
                          child: _ProfileActionChip(
                            icon: Icons.call,
                            label: 'Звонок',
                            onTap: () => _startCall(audioOnly: true),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _ProfileActionChip(
                            icon: Icons.videocam,
                            label: 'Видео',
                            onTap: () => _startCall(audioOnly: false),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _ProfileActionChip(
                            icon: Icons.more_horiz,
                            label: 'Ещё',
                            onTap: () {
                              showModalBottomSheet(
                                context: context,
                                backgroundColor: themeCtrl.hover,
                                builder: (ctx) => SafeArea(
                                  child: Wrap(children: [
                                    ListTile(
                                      leading: const Icon(Icons.chat),
                                      title: const Text('Написать'),
                                      onTap: () {
                                        Navigator.pop(ctx);
                                        final key = dmPairKey(
                                            widget.user.uid, p.id);
                                        Navigator.of(context)
                                            .pushReplacement(
                                                MaterialPageRoute(
                                                    builder: (_) =>
                                                        ChatScreen(
                                                          user: widget.user,
                                                          peer: p,
                                                          chatKey: key,
                                                          myProfile: null,
                                                        )));
                                      },
                                    ),
                                    ListTile(
                                      leading: const Icon(Icons.card_giftcard),
                                      title: const Text('Подарок'),
                                      onTap: () {
                                        Navigator.pop(ctx);
                                        _sendGiftFromProfile();
                                      },
                                    ),
                                    if (!isContact)
                                      ListTile(
                                        leading: const Icon(Icons.person_add),
                                        title: const Text('В контакты'),
                                        onTap: () {
                                          Navigator.pop(ctx);
                                          _addContact();
                                        },
                                      ),
                                    ListTile(
                                      leading: const Icon(Icons.block,
                                          color: SLineColors.danger),
                                      title: const Text('Заблокировать',
                                          style: TextStyle(
                                              color: SLineColors.danger)),
                                      onTap: () => Navigator.pop(ctx),
                                    ),
                                  ]),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton(
                        onPressed: () {
                          final key = dmPairKey(widget.user.uid, p.id);
                          Navigator.of(context).pushReplacement(
                              MaterialPageRoute(
                                  builder: (_) => ChatScreen(
                                        user: widget.user,
                                        peer: p,
                                        chatKey: key,
                                        myProfile: null,
                                      )));
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF3B82F6),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14)),
                        ),
                        child: const Text('Написать',
                            style: TextStyle(
                                fontWeight: FontWeight.w700, fontSize: 16)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (!isContact)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: SizedBox(
                        width: double.infinity,
                        height: 44,
                        child: OutlinedButton.icon(
                          onPressed: _addContact,
                          icon: const Icon(Icons.person_add_alt_1),
                          label: const Text('В контакты'),
                          style: OutlinedButton.styleFrom(
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14)),
                          ),
                        ),
                      ),
                    ),
                ],
                // Info block
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: themeCtrl.panel,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: themeCtrl.line),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (p.username.isNotEmpty) ...[
                          Text('имя пользователя',
                              style: TextStyle(
                                  fontSize: 12, color: themeCtrl.muted)),
                          const SizedBox(height: 2),
                          Text('@${p.username}',
                              style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: themeCtrl.text)),
                          if ((p.bio ?? '').isNotEmpty || widget.isMe)
                            Divider(height: 24, color: themeCtrl.line),
                        ],
                        Text('о себе',
                            style: TextStyle(
                                fontSize: 12, color: themeCtrl.muted)),
                        const SizedBox(height: 2),
                        if (widget.isMe)
                          TextField(
                            controller: bioC,
                            decoration: const InputDecoration(
                              hintText: 'Не указано',
                              border: InputBorder.none,
                              enabledBorder: InputBorder.none,
                              focusedBorder: InputBorder.none,
                              filled: false,
                              contentPadding: EdgeInsets.zero,
                            ),
                            maxLines: 3,
                            style: TextStyle(
                                fontSize: 15, color: themeCtrl.text),
                          )
                        else
                          Text(
                            (p.bio ?? '').isEmpty ? 'Не указано' : p.bio!,
                            style: TextStyle(
                                fontSize: 15,
                                color: (p.bio ?? '').isEmpty
                                    ? themeCtrl.muted
                                    : themeCtrl.text),
                          ),
                      ],
                    ),
                  ),
                ),
                // Tabs: Медиа | Файлы | Подарки
                _ProfileMediaGiftsTabs(
                  profileId: p.id,
                  myUid: widget.user.uid,
                ),
                if (widget.isMe) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                    child: TextButton.icon(
                      onPressed: _pickAvatar,
                      icon: const Icon(Icons.photo_library_outlined),
                      label: const Text('Аватар из галереи'),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: TextField(
                        controller: nameC,
                        decoration:
                            const InputDecoration(labelText: 'Имя')),
                  ),
                  const SizedBox(height: 12),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: TextField(
                        controller: avatarC,
                        decoration: const InputDecoration(
                            labelText: 'URL аватарки',
                            hintText: 'https://...'),
                        onChanged: (_) => setState(() {})),
                  ),
                  const SizedBox(height: 20),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton(
                        onPressed: saving ? null : _save,
                        style: ElevatedButton.styleFrom(
                            backgroundColor: SLineColors.accentA,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14))),
                        child: saving
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white))
                            : const Text('Сохранить'),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 48),
              ]),
          ),
        ],
      ),
    );
  }
}

class _ProfileActionChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _ProfileActionChip(
      {required this.icon, required this.label, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return Material(
      color: themeCtrl.input,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(children: [
            Icon(icon, color: SLineColors.accentA, size: 22),
            const SizedBox(height: 4),
            Text(label,
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: themeCtrl.text)),
          ]),
        ),
      ),
    );
  }
}

/// Вкладки профиля: Медиа / Файлы / Подарки (как на вебе)
class _ProfileMediaGiftsTabs extends StatefulWidget {
  final String profileId;
  final String myUid;
  const _ProfileMediaGiftsTabs(
      {required this.profileId, required this.myUid});
  @override
  State<_ProfileMediaGiftsTabs> createState() =>
      _ProfileMediaGiftsTabsState();
}

class _ProfileMediaGiftsTabsState extends State<_ProfileMediaGiftsTabs> {
  int tab = 0;
  List<Map<String, dynamic>> gifts = [];
  bool loadingGifts = true;

  @override
  void initState() {
    super.initState();
    _loadGifts();
  }

  Future<void> _loadGifts() async {
    setState(() => loadingGifts = true);
    try {
      final snap = await FirebaseDatabase.instance
          .ref('user_gifts/${widget.profileId}')
          .get();
      final list = <Map<String, dynamic>>[];
      if (snap.exists && snap.value is Map) {
        final map = Map<String, dynamic>.from(snap.value as Map);
        for (final e in map.entries) {
          if (e.value is Map) {
            final g = Map<String, dynamic>.from(e.value as Map);
            g['id'] = e.key;
            if (g['visible'] != false) list.add(g);
          }
        }
      }
      list.sort((a, b) {
        final am = (a['created_at_ms'] as num?)?.toInt() ?? 0;
        final bm = (b['created_at_ms'] as num?)?.toInt() ?? 0;
        return bm.compareTo(am);
      });
      if (mounted) {
        setState(() {
          gifts = list;
          loadingGifts = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => loadingGifts = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(children: [
            for (var i = 0; i < 3; i++)
              Expanded(
                child: InkWell(
                  onTap: () => setState(() => tab = i),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(
                          color: tab == i
                              ? SLineColors.accentA
                              : Colors.transparent,
                          width: 2,
                        ),
                      ),
                    ),
                    child: Text(
                      i == 0
                          ? 'Медиа'
                          : i == 1
                              ? 'Файлы'
                              : 'Подарки 🎁',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontWeight:
                            tab == i ? FontWeight.w700 : FontWeight.w500,
                        color: tab == i ? themeCtrl.text : themeCtrl.muted,
                      ),
                    ),
                  ),
                ),
              ),
          ]),
        ),
        if (tab == 0)
          Padding(
            padding: const EdgeInsets.all(24),
            child: Text('Общие медиа появятся здесь',
                textAlign: TextAlign.center,
                style: TextStyle(color: themeCtrl.muted)),
          )
        else if (tab == 1)
          Padding(
            padding: const EdgeInsets.all(24),
            child: Text('Общие файлы появятся здесь',
                textAlign: TextAlign.center,
                style: TextStyle(color: themeCtrl.muted)),
          )
        else
          loadingGifts
              ? const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(
                      child: CircularProgressIndicator(strokeWidth: 2)))
              : gifts.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text('Пока нет подарков',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: themeCtrl.muted)),
                    )
                  : Padding(
                      padding: const EdgeInsets.all(12),
                      child: GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: gifts.length,
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 4,
                          mainAxisSpacing: 8,
                          crossAxisSpacing: 8,
                        ),
                        itemBuilder: (_, i) {
                          final g = gifts[i];
                          final eid = (g['gift_id'] ?? '').toString();
                          final em = (g['gift_emoji'] ??
                                  SLineGifts.emojiFor(eid))
                              .toString();
                          final isMine =
                              widget.profileId == widget.myUid;
                          return InkWell(
                            onTap: isMine
                                ? () async {
                                    final sell =
                                        (g['gift_sell'] as num?)?.toInt() ??
                                            SLineGifts.sellFor(eid);
                                    final act = await showDialog<String>(
                                      context: context,
                                      builder: (d) => AlertDialog(
                                        title: Text('$em Подарок'),
                                        content: Text(
                                            'Продать за $sell SL или скрыть?'),
                                        actions: [
                                          TextButton(
                                              onPressed: () =>
                                                  Navigator.pop(d, 'hide'),
                                              child: const Text('Скрыть')),
                                          TextButton(
                                              onPressed: () =>
                                                  Navigator.pop(d, 'sell'),
                                              child: Text(
                                                  'Продать $sell SL')),
                                        ],
                                      ),
                                    );
                                    if (act == 'sell') {
                                      await SCoin.add(
                                          widget.myUid, sell);
                                      await FirebaseDatabase.instance
                                          .ref(
                                              'user_gifts/${widget.myUid}/${g['id']}')
                                          .remove();
                                      _loadGifts();
                                    } else if (act == 'hide') {
                                      await FirebaseDatabase.instance
                                          .ref(
                                              'user_gifts/${widget.myUid}/${g['id']}/visible')
                                          .set(false);
                                      _loadGifts();
                                    }
                                  }
                                : null,
                            borderRadius: BorderRadius.circular(12),
                            child: Container(
                              decoration: BoxDecoration(
                                color: themeCtrl.input,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              alignment: Alignment.center,
                              child: Text(em,
                                  style: const TextStyle(fontSize: 28)),
                            ),
                          );
                        },
                      ),
                    ),
      ],
    );
  }
}

class _GiftPickerSheet extends StatefulWidget {
  final String uid;
  const _GiftPickerSheet({required this.uid});
  @override
  State<_GiftPickerSheet> createState() => _GiftPickerSheetState();
}

class _GiftPickerSheetState extends State<_GiftPickerSheet> {
  int bal = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await SCoin.ensureStarter(widget.uid);
    final b = await SCoin.balance(widget.uid);
    if (mounted) setState(() => bal = b);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(
            children: [
              Text('Подарок',
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: themeCtrl.text)),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: SLineColors.accentA.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text('$bal SL',
                    style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        color: SLineColors.accentA)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          GridView.count(
            shrinkWrap: true,
            crossAxisCount: 4,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            children: [
              for (final g in SLineGifts.items)
                InkWell(
                  onTap: () {
                    if (bal < g.$4) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                            content: Text(
                                'Нужно ${g.$4} SL, у вас $bal')),
                      );
                      return;
                    }
                    Navigator.pop(context, g.$1);
                  },
                  borderRadius: BorderRadius.circular(14),
                  child: Container(
                    decoration: BoxDecoration(
                      color: themeCtrl.input,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                          color: bal >= g.$4
                              ? themeCtrl.line
                              : themeCtrl.muted.withValues(alpha: 0.3)),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(g.$2, style: const TextStyle(fontSize: 28)),
                        const SizedBox(height: 2),
                        Text(g.$3,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 10, color: themeCtrl.muted)),
                        Text('${g.$4} SL',
                            style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: bal >= g.$4
                                    ? SLineColors.accentA
                                    : themeCtrl.muted)),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
        ]),
      ),
    );
  }
}

// ── chat ────────────────────────────────────────────────────
class ChatScreen extends StatefulWidget {
  final User user;
  final Profile peer;
  final String chatKey;
  final Profile? myProfile;
  const ChatScreen(
      {super.key,
      required this.user,
      required this.peer,
      required this.chatKey,
      this.myProfile});
  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final msgCtrl = TextEditingController();
  final scrollCtrl = ScrollController();
  final _msgFocus = FocusNode();
  List<ChatMessage> messages = [];
  final List<ChatMessage> pendingLocal = [];
  StreamSubscription? sub;
  StreamSubscription? typingSub;
  bool sending = false;
  bool recording = false;
  bool recordingLocked = false;
  bool recordingCancelZone = false;
  bool peerTyping = false;
  bool hasText = false;
  /// false = голосовое, true = кружок (как на вебе)
  bool circleMode = false;
  Offset _recDrag = Offset.zero;
  DateTime? _recStartedAt;
  Timer? _recTick;
  int _recSeconds = 0;
  /// Кружок записывается В чате (оверлей), не на отдельной странице
  CameraController? _circleCam;
  bool _circleCamReady = false;
  /// Инвалидирует незавершённый async-старт камеры (анти-race dispose)
  int _circleSession = 0;
  /// Непрерывный жест микрофона/кружка (Pointer, не LongPress)
  int? _micPointer;
  Offset _micOrigin = Offset.zero;
  Timer? _micHoldTimer;
  bool _micHoldStarted = false;
  ChatMessage? replyTo;
  String? _highlightMsgId;
  /// Режим выделения сообщений (как в TG: long-press = select, tap = menu)
  bool _selecting = false;
  final Set<String> _selectedMsgIds = {};
  final Map<String, GlobalKey> _msgKeys = {};
  final AudioRecorder _recorder = AudioRecorder();
  final AudioPlayer _player = AudioPlayer();
  String? playingId;
  Timer? _typingDebounce;
  Timer? _typingClear;
  bool showScrollDown = false;
  bool isContact = true;
  bool contactBannerDismissed = false;
  /// не показывать «Нет сообщений» пока не пришёл первый снимок из Firebase
  bool msgsReady = false;
  /// Свайп всего чата вправо → назад к списку (как в TG)
  double _pageDx = 0;
  /// Свои стикеры (набор), не отправляются сразу
  final List<String> myStickers = [];

  // стикеры-картинки (открытые CDN)
  static const stickerUrls = [
    'https://cdn.jsdelivr.net/gh/twitter/twemoji@14.0.2/assets/72x72/1f600.png',
    'https://cdn.jsdelivr.net/gh/twitter/twemoji@14.0.2/assets/72x72/1f602.png',
    'https://cdn.jsdelivr.net/gh/twitter/twemoji@14.0.2/assets/72x72/2764.png',
    'https://cdn.jsdelivr.net/gh/twitter/twemoji@14.0.2/assets/72x72/1f525.png',
    'https://cdn.jsdelivr.net/gh/twitter/twemoji@14.0.2/assets/72x72/1f44d.png',
    'https://cdn.jsdelivr.net/gh/twitter/twemoji@14.0.2/assets/72x72/1f389.png',
    'https://cdn.jsdelivr.net/gh/twitter/twemoji@14.0.2/assets/72x72/1f60e.png',
    'https://cdn.jsdelivr.net/gh/twitter/twemoji@14.0.2/assets/72x72/1f914.png',
    'https://cdn.jsdelivr.net/gh/twitter/twemoji@14.0.2/assets/72x72/1f44b.png',
    'https://cdn.jsdelivr.net/gh/twitter/twemoji@14.0.2/assets/72x72/1f4af.png',
    'https://cdn.jsdelivr.net/gh/twitter/twemoji@14.0.2/assets/72x72/1f680.png',
    'https://cdn.jsdelivr.net/gh/twitter/twemoji@14.0.2/assets/72x72/2728.png',
    'https://cdn.jsdelivr.net/gh/twitter/twemoji@14.0.2/assets/72x72/1f62d.png',
    'https://cdn.jsdelivr.net/gh/twitter/twemoji@14.0.2/assets/72x72/1f64f.png',
    'https://cdn.jsdelivr.net/gh/twitter/twemoji@14.0.2/assets/72x72/1f4aa.png',
    'https://cdn.jsdelivr.net/gh/twitter/twemoji@14.0.2/assets/72x72/1f3af.png',
    'https://cdn.jsdelivr.net/gh/twitter/twemoji@14.0.2/assets/72x72/1f921.png',
    'https://cdn.jsdelivr.net/gh/twitter/twemoji@14.0.2/assets/72x72/1f92a.png',
    'https://cdn.jsdelivr.net/gh/twitter/twemoji@14.0.2/assets/72x72/1f970.png',
    'https://cdn.jsdelivr.net/gh/twitter/twemoji@14.0.2/assets/72x72/1f60d.png',
  ];

  @override
  void initState() {
    super.initState();
    msgCtrl.addListener(_onComposeChanged);
    _loadDraft();
    scrollCtrl.addListener(() {
      if (!scrollCtrl.hasClients) return;
      final max = scrollCtrl.position.maxScrollExtent;
      final show = max > 200 && (max - scrollCtrl.offset) > 280;
      if (show != showScrollDown && mounted) {
        setState(() => showScrollDown = show);
      }
    });
    _checkContact();
    sub = chatMsgsRef(widget.chatKey).limitToLast(200).onValue.listen((ev) {
      final list = <ChatMessage>[];
      if (ev.snapshot.exists && ev.snapshot.value is Map) {
        for (final e
            in Map<String, dynamic>.from(ev.snapshot.value as Map).entries) {
          if (e.value is Map) {
            list.add(ChatMessage.fromMap(
                e.key, Map<String, dynamic>.from(e.value as Map)));
          }
        }
      }
      list.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      if (mounted) {
        final atBottom = !scrollCtrl.hasClients ||
            (scrollCtrl.position.maxScrollExtent - scrollCtrl.offset) < 120;
        setState(() {
          messages = list;
          msgsReady = true;
        });
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (scrollCtrl.hasClients && atBottom) {
            scrollCtrl.jumpTo(scrollCtrl.position.maxScrollExtent);
          }
        });
      }
    }, onError: (e) {
      if (mounted) {
        setState(() => msgsReady = true);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(permissionHelp(e))));
      }
    });
    if (!widget.peer.isSaved) {
      typingSub = FirebaseDatabase.instance
          .ref('typing/${widget.chatKey}/${widget.peer.id}')
          .onValue
          .listen((ev) {
        final v = ev.snapshot.value;
        final on = v == true ||
            (v is Map &&
                (v['at'] is int) &&
                DateTime.now().millisecondsSinceEpoch - (v['at'] as int) <
                    4000);
        if (mounted) setState(() => peerTyping = on);
      });
    }
  }

  Timer? _draftDebounce;

  Future<void> _loadDraft() async {
    try {
      final snap = await FirebaseDatabase.instance
          .ref('drafts/${widget.user.uid}/${widget.chatKey}')
          .get();
      if (!snap.exists || !mounted) return;
      String text = '';
      final v = snap.value;
      if (v is String) {
        text = v;
      } else if (v is Map) {
        text = (v['text'] ?? v['content'] ?? '').toString();
      }
      if (text.isNotEmpty && msgCtrl.text.isEmpty) {
        msgCtrl.text = text;
        msgCtrl.selection = TextSelection.collapsed(offset: text.length);
        setState(() => hasText = true);
      }
    } catch (_) {}
  }

  Future<void> _saveDraft(String text) async {
    try {
      final ref = FirebaseDatabase.instance
          .ref('drafts/${widget.user.uid}/${widget.chatKey}');
      final t = text.trim();
      if (t.isEmpty) {
        await ref.remove();
      } else {
        await ref.set({
          'text': text,
          'updated_at': DateTime.now().millisecondsSinceEpoch,
        });
      }
    } catch (_) {}
  }

  void _onComposeChanged() {
    final t = msgCtrl.text.trim().isNotEmpty;
    if (t != hasText && mounted) setState(() => hasText = t);
    // Черновик: синхронизация между веб и приложением
    _draftDebounce?.cancel();
    _draftDebounce = Timer(const Duration(milliseconds: 600), () {
      _saveDraft(msgCtrl.text);
    });
    if (widget.peer.isSaved) return;
    _typingDebounce?.cancel();
    _typingDebounce = Timer(const Duration(milliseconds: 250), () async {
      try {
        await FirebaseDatabase.instance
            .ref('typing/${widget.chatKey}/${widget.user.uid}')
            .set({
          'at': DateTime.now().millisecondsSinceEpoch,
          'on': true,
        });
      } catch (_) {}
    });
    _typingClear?.cancel();
    _typingClear = Timer(const Duration(seconds: 3), () async {
      try {
        await FirebaseDatabase.instance
            .ref('typing/${widget.chatKey}/${widget.user.uid}')
            .remove();
      } catch (_) {}
    });
  }

  Future<void> _send(
      {required String type, String content = '', String? fileUrl}) async {
    if (sending) return;
    setState(() => sending = true);
    try {
      var text = content;
      if (replyTo != null && type == 'text') {
        final prev = replyTo!.content.isEmpty
            ? (replyTo!.type)
            : replyTo!.content;
        final short =
            prev.length > 60 ? '${prev.substring(0, 60)}…' : prev;
        text = '↪ #${replyTo!.id}|$short\n$text';
      }
      final ref = chatMsgsRef(widget.chatKey).push();
      final now = DateTime.now();
      final payload = {
        'id': ref.key,
        'sender_id': widget.user.uid,
        'receiver_id':
            widget.peer.isSaved ? widget.user.uid : widget.peer.id,
        'content': text,
        'type': type,
        'file_url': fileUrl,
        'created_at': now.toIso8601String(),
        'created_at_ms': now.millisecondsSinceEpoch,
      };
      await ref.set(payload);
      // дубль для веб-таблицы messages (нужен для появления чата у собеседника)
      try {
        await FirebaseDatabase.instance
            .ref('tables/messages/${ref.key}')
            .set({
          ...payload,
          'group_id': null,
        });
      } catch (_) {}
      // очистить черновик после отправки
      if (type == 'text') {
        try {
          await FirebaseDatabase.instance
              .ref('drafts/${widget.user.uid}/${widget.chatKey}')
              .remove();
        } catch (_) {}
      }
      setState(() => replyTo = null);
      // Свой индекс + собеседника (если rules позволяют) → чат в списке
      final peerUid = (widget.peer.isSaved || _isGroupOrChannel)
          ? null
          : widget.peer.id;
      await ChatListSync.ensureIndexed(
        myUid: widget.user.uid,
        chatKey: widget.chatKey,
        peerUid: peerUid,
      );
      // push outbox для Cloud Function / сервера
      if (!widget.peer.isSaved) {
        final preview = type == 'text'
            ? (content.length > 80 ? '${content.substring(0, 80)}…' : content)
            : (type == 'image'
                ? '📷 Фото'
                : type == 'voice'
                    ? '🎤 Голосовое'
                    : type == 'circle'
                        ? '⭕ Кружок'
                        : type == 'video'
                            ? '🎬 Видео'
                            : type == 'sticker'
                                ? 'Стикер'
                                : type == 'gif'
                                    ? 'GIF'
                                    : type == 'gift'
                                        ? '🎁 Подарок'
                                        : type == 'poll'
                                            ? '📊 Опрос'
                                            : 'Сообщение');
        final from = widget.myProfile?.displayName ??
            widget.user.email ??
            'SLine';
        await enqueuePushNotify(
          toUid: widget.peer.id,
          title: from,
          body: preview,
          chatKey: widget.chatKey,
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(permissionHelp(e))));
      }
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }


  Future<String?> _uploadFile(File file, String folder) async {
    return await B2Storage.uploadFile(file, folder, widget.user.uid);
  }

  void _openMediaViewer(String url, {required bool isVideo}) {
    if (url.trim().isEmpty) return;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => _MediaViewerPage(url: url, isVideo: isVideo),
    ));
  }

  bool _isAudioFileName(String name, String url) {
    final s = '${name.toLowerCase()} ${url.toLowerCase()}';
    return s.contains('.mp3') ||
        s.contains('.m4a') ||
        s.contains('.aac') ||
        s.contains('.ogg') ||
        s.contains('.opus') ||
        s.contains('.wav') ||
        s.contains('.flac') ||
        s.contains('audio/');
  }

  Future<void> _openOrDownloadFile(String url, String name) async {
    final u = url.trim();
    if (u.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Нет ссылки на файл')));
      }
      return;
    }
    // Аудио, присланное как «файл» — полноценный плеер
    if (_isAudioFileName(name, u)) {
      if (!mounted) return;
      await showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => _AudioFilePlayerSheet(
          url: u,
          title: name.isNotEmpty ? name : 'Аудио',
        ),
      );
      return;
    }
    try {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Скачивание $name…')));
      }
      final ext = name.contains('.')
          ? name.split('.').last
          : (u.contains('.') ? u.split('.').last.split('?').first : 'bin');
      final f = await downloadMediaToTemp(u, extHint: ext);
      Directory dir;
      try {
        dir = await getApplicationDocumentsDirectory();
      } catch (_) {
        dir = await getTemporaryDirectory();
      }
      final safe = name
          .replaceAll(RegExp(r'[^\w\.\-а-яА-ЯёЁ]+'), '_')
          .replaceAll(RegExp(r'_+'), '_');
      final outName = safe.isEmpty
          ? 'file_${DateTime.now().millisecondsSinceEpoch}.$ext'
          : safe;
      final out = File('${dir.path}/$outName');
      if (f.absolute.path != out.absolute.path) {
        await f.copy(out.path);
      }
      if (!mounted) return;
      // Попробовать открыть системным приложением
      var opened = false;
      try {
        final uri = Uri.file(out.path);
        opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      } catch (_) {
        opened = false;
      }
      if (!opened) {
        try {
          // Android content-less fallback: open original signed URL
          final resolved = B2Storage.isB2Url(u)
              ? await B2Storage.resolveDownloadUrl(u)
              : u;
          if (resolved.startsWith('http')) {
            opened = await launchUrl(Uri.parse(resolved),
                mode: LaunchMode.externalApplication);
          }
        } catch (_) {}
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(opened
              ? 'Открыто: $outName'
              : 'Сохранено: ${out.path}'),
          duration: const Duration(seconds: 4),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Файл: $e')));
      }
    }
  }

  Future<void> _playVoice(ChatMessage m) async {
    final raw = (m.fileUrl ?? '').trim();
    if (raw.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Нет файла голосового')));
      }
      return;
    }
    try {
      if (playingId == m.id) {
        await _player.stop();
        if (mounted) setState(() => playingId = null);
        return;
      }
      await _player.stop();
      await _player.setReleaseMode(ReleaseMode.stop);
      await _player.setVolume(1.0);

      try {
        await _player.setAudioContext(AudioContext(
          android: AudioContextAndroid(
            isSpeakerphoneOn: true,
            stayAwake: true,
            contentType: AndroidContentType.music,
            usageType: AndroidUsageType.media,
            audioFocus: AndroidAudioFocus.gain,
          ),
          iOS: AudioContextIOS(
            category: AVAudioSessionCategory.playback,
            options: {AVAudioSessionOptions.defaultToSpeaker},
          ),
        ));
      } catch (_) {}

      if (raw.startsWith('data:')) {
        final comma = raw.indexOf(',');
        if (comma < 0) throw Exception('bad data uri');
        final bytes = base64Decode(raw.substring(comma + 1));
        final dir = await getTemporaryDirectory();
        var ext = 'm4a';
        final head = raw.substring(0, comma).toLowerCase();
        if (head.contains('ogg')) {
          ext = 'ogg';
        } else if (head.contains('mpeg') || head.contains('mp3')) {
          ext = 'mp3';
        } else if (head.contains('wav')) {
          ext = 'wav';
        } else if (head.contains('webm')) {
          ext = 'webm';
        }
        final f = File(
            '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.$ext');
        await f.writeAsBytes(bytes, flush: true);
        await _player.play(DeviceFileSource(f.path));
      } else {
        // 1) скачать локально (с ретраями) 2) UrlSource как запас
        try {
          final f = await downloadMediaToTemp(raw, extHint: 'm4a');
          if (!await f.exists() || await f.length() < 32) {
            throw Exception('пустой файл');
          }
          await _player.play(DeviceFileSource(f.path));
        } catch (_) {
          await _player.play(UrlSource(raw));
        }
      }
      if (mounted) setState(() => playingId = m.id);
      _player.onPlayerComplete.first.then((_) {
        if (mounted && playingId == m.id) {
          setState(() => playingId = null);
        }
      });
    } catch (e) {
      if (mounted) {
        setState(() => playingId = null);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Голосовое: $e')),
        );
      }
    }
  }

  Future<void> _pickAndSendImage() async {
    try {
      String? path;
      try {
        path = await showModalBottomSheet<String>(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (_) =>
              const InAppGalleryPicker(requestType: RequestType.image),
        );
      } catch (_) {}
      if (path == null || path.isEmpty) {
        final x = await ImagePicker().pickImage(
          source: ImageSource.gallery,
          imageQuality: 85,
        );
        path = x?.path;
      }
      if (path == null || path.isEmpty) return;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Загрузка фото…')));
      }
      final url = await _uploadFile(File(path), 'chat_images');
      if (url != null && url.isNotEmpty) {
        await _send(type: 'image', fileUrl: url);
      } else {
        throw Exception('Не удалось загрузить');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Фото: $e')));
      }
    }
  }

  Future<void> _pickAndSendVideo() async {
    try {
      final path = await showModalBottomSheet<String>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => const InAppGalleryPicker(requestType: RequestType.video),
      );
      if (path == null || path.isEmpty) return;
      final url = await _uploadFile(File(path), 'chat_videos');
      if (url != null) await _send(type: 'video', fileUrl: url);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Видео: $e')));
      }
    }
  }

  Future<void> _pickAndSendFile() async {
    try {
      final x = await openFile();
      if (x == null) return;
      final path = x.path;
      if (path.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Не удалось открыть файл')));
        }
        return;
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Загрузка ${x.name}…')));
      }
      final url = await _uploadFile(File(path), 'chat_files');
      if (url != null) {
        await _send(
          type: 'file',
          content: x.name,
          fileUrl: url,
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Файл: $e')));
      }
    }
  }

  Future<void> _startCircleInChat() async {
    // Новая сессия — всё, что стартовало раньше, считается отменённым
    final session = ++_circleSession;
    _recTick?.cancel();

    if (mounted) {
      setState(() {
        recording = true;
        recordingLocked = false;
        recordingCancelZone = false;
        _recDrag = Offset.zero;
        _recStartedAt = DateTime.now();
        _recSeconds = 0;
        _circleCamReady = false;
      });
    }
    // Таймер сразу (даже пока камера поднимается)
    _recTick = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (!mounted || !recording || session != _circleSession) return;
      final s = DateTime.now().difference(_recStartedAt!).inMilliseconds;
      setState(() => _recSeconds = s);
    });

    CameraController? ctrl;
    try {
      final cam = await Permission.camera.request();
      final mic = await Permission.microphone.request();
      if (session != _circleSession) return;
      if (!cam.isGranted || !mic.isGranted) {
        if (mounted && session == _circleSession) {
          setState(() => recording = false);
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Нужен доступ к камере и микрофону')));
        }
        return;
      }

      final cams = await availableCameras();
      if (session != _circleSession) return;
      if (cams.isEmpty) throw Exception('Камера не найдена');

      final front = cams.indexWhere(
          (c) => c.lensDirection == CameraLensDirection.front);
      final desc = cams[front >= 0 ? front : 0];

      // Старый контроллер убираем только через сессию
      final old = _circleCam;
      _circleCam = null;
      if (mounted) setState(() => _circleCamReady = false);
      if (old != null) {
        try {
          if (old.value.isRecordingVideo) await old.stopVideoRecording();
        } catch (_) {}
        try {
          await old.dispose();
        } catch (_) {}
      }
      if (session != _circleSession) return;

      ctrl = CameraController(
        desc,
        ResolutionPreset.medium,
        enableAudio: true,
        imageFormatGroup: ImageFormatGroup.yuv420,
      );
      await ctrl.initialize();
      if (session != _circleSession || !mounted) {
        try {
          await ctrl.dispose();
        } catch (_) {}
        return;
      }

      // Превью сразу, запись — следом
      _circleCam = ctrl;
      if (mounted) setState(() => _circleCamReady = true);

      await ctrl.startVideoRecording();
      if (session != _circleSession || !mounted || !recording) {
        // Сессию отменили во время старта — аккуратно гасим ТОЛЬКО этот ctrl
        try {
          if (ctrl.value.isRecordingVideo) await ctrl.stopVideoRecording();
        } catch (_) {}
        if (identical(_circleCam, ctrl)) {
          _circleCam = null;
          if (mounted) setState(() => _circleCamReady = false);
        }
        try {
          await ctrl.dispose();
        } catch (_) {}
        return;
      }

      HapticFeedback.mediumImpact();
    } catch (e) {
      if (session != _circleSession) return;
      try {
        await ctrl?.dispose();
      } catch (_) {}
      if (identical(_circleCam, ctrl)) {
        _circleCam = null;
      }
      if (mounted) {
        setState(() {
          recording = false;
          recordingLocked = false;
          _circleCamReady = false;
        });
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Кружок: $e')));
      }
    }
  }

  Future<void> _disposeCircleCam() async {
    final c = _circleCam;
    _circleCam = null;
    if (mounted) {
      setState(() => _circleCamReady = false);
    } else {
      _circleCamReady = false;
    }
    // Дать кадру убрать CameraPreview до dispose
    await Future<void>.delayed(const Duration(milliseconds: 50));
    try {
      if (c != null && c.value.isInitialized) {
        if (c.value.isRecordingVideo) {
          try {
            await c.stopVideoRecording();
          } catch (_) {}
        }
        await c.dispose();
      }
    } catch (_) {}
  }

  Future<void> _finishCircleInChat({required bool send}) async {
    if (!circleMode) return;
    // Инвалидируем незавершённый start
    _circleSession++;
    final c = _circleCam;
    final elapsed = _recSeconds;
    _recTick?.cancel();
    _recTick = null;

    // Сначала убираем превью из дерева
    if (mounted) {
      setState(() {
        recording = false;
        recordingLocked = false;
        recordingCancelZone = false;
        _recDrag = Offset.zero;
        _recSeconds = 0;
        _circleCamReady = false;
        _circleCam = null; // CameraPreview больше не ссылается
      });
    } else {
      _circleCam = null;
      _circleCamReady = false;
      recording = false;
    }

    await Future<void>.delayed(const Duration(milliseconds: 50));

    XFile? file;
    try {
      if (c != null && c.value.isInitialized) {
        try {
          if (c.value.isRecordingVideo) {
            file = await c.stopVideoRecording();
          }
        } catch (_) {}
        try {
          await c.dispose();
        } catch (_) {}
      }
    } catch (_) {}

    if (!send || file == null) {
      try {
        if (file != null) await File(file.path).delete();
      } catch (_) {}
      return;
    }
    if (elapsed < 500) {
      try {
        await File(file.path).delete();
      } catch (_) {}
      return;
    }

    try {
      var localPath = file.path;
      final dir = await getTemporaryDirectory();
      final stable = File(
          '${dir.path}/circle_local_${DateTime.now().millisecondsSinceEpoch}.mp4');
      try {
        await File(file.path).copy(stable.path);
        localPath = stable.path;
      } catch (_) {}
      final localId = 'local_${DateTime.now().millisecondsSinceEpoch}';
      final localMsg = ChatMessage(
        id: localId,
        senderId: widget.user.uid,
        receiverId: widget.peer.isSaved ? widget.user.uid : widget.peer.id,
        content: '',
        type: 'circle',
        fileUrl: localPath,
        createdAt: DateTime.now().millisecondsSinceEpoch,
      );
      if (mounted) setState(() => pendingLocal.add(localMsg));
      final url = await _uploadFile(File(localPath), 'chat_circles');
      if (url == null || url.isEmpty) throw Exception('Не удалось загрузить');
      await _send(type: 'circle', fileUrl: url, content: '');
      if (mounted) {
        setState(() => pendingLocal.removeWhere((m) => m.id == localId));
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          pendingLocal.removeWhere((m) => m.id.startsWith('local_'));
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Кружок: $e'),
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  }

  Future<void> _finishAnyRecord({required bool send}) async {
    if (circleMode) {
      await _finishCircleInChat(send: send);
    } else {
      await _finishVoiceRecord(send: send);
    }
  }

  Future<void> _startVoiceRecord() async {
    try {
      final mic = await Permission.microphone.request();
      if (!mic.isGranted) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Нужен доступ к микрофону')));
        }
        return;
      }
      final dir = await getTemporaryDirectory();
      final path =
          '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
      await _recorder.start(
          const RecordConfig(encoder: AudioEncoder.aacLc), path: path);
      if (mounted) {
        _recTick?.cancel();
        _recStartedAt = DateTime.now();
        _recSeconds = 0;
        _recTick = Timer.periodic(const Duration(milliseconds: 100), (_) {
          if (!mounted || !recording) return;
          final s = DateTime.now().difference(_recStartedAt!).inMilliseconds;
          setState(() => _recSeconds = s);
        });
        setState(() {
          recording = true;
          recordingLocked = false;
          recordingCancelZone = false;
          _recDrag = Offset.zero;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => recording = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Голос: $e')));
      }
    }
  }

  Future<void> _finishVoiceRecord({required bool send}) async {
    if (!recording) return;
    try {
      final path = await _recorder.stop();
      _recTick?.cancel();
      _recTick = null;
      setState(() {
        recording = false;
        recordingLocked = false;
        recordingCancelZone = false;
        _recDrag = Offset.zero;
        _recSeconds = 0;
      });
      if (!send || path == null) {
        if (path != null) {
          try {
            await File(path).delete();
          } catch (_) {}
        }
        return;
      }
      final src = File(path);
      if (!await src.exists() || await src.length() < 64) {
        throw Exception('Пустая запись');
      }
      // Стабильный .m4a путь
      final dir = await getTemporaryDirectory();
      final stable = File(
          '${dir.path}/voice_send_${DateTime.now().millisecondsSinceEpoch}.m4a');
      await src.copy(stable.path);
      final url = await _uploadFile(stable, 'chat_voice');
      if (url == null || url.isEmpty) {
        throw Exception('Не удалось загрузить голосовое');
      }
      await _send(type: 'voice', fileUrl: url);
    } catch (e) {
      if (mounted) {
        setState(() {
          recording = false;
          recordingLocked = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Голос: $e'),
            duration: const Duration(seconds: 4),
          ),
        );
      }
    }
  }

  Future<void> _toggleVoice() async {
    if (recording) {
      await _finishVoiceRecord(send: true);
    } else {
      await _startVoiceRecord();
    }
  }

  bool get _isGroupOrChannel =>
      widget.chatKey.startsWith('g_') || widget.chatKey.startsWith('c_');

  Future<void> _openGroupOrChannelInfo() async {
    final isChannel = widget.chatKey.startsWith('c_');
    final id = isChannel
        ? widget.chatKey.substring(2)
        : (widget.chatKey.startsWith('g_')
            ? widget.chatKey.substring(2)
            : widget.chatKey);
    String name = widget.peer.displayName;
    String? avatar = widget.peer.avatarUrl;
    String desc = '';
    String slug = widget.peer.username;
    bool isPublic = true;
    bool isAdmin = false;
    try {
      final path = isChannel ? 'channels/$id' : 'groups/$id';
      final snap = await FirebaseDatabase.instance.ref(path).get();
      if (snap.exists && snap.value is Map) {
        final d = Map<String, dynamic>.from(snap.value as Map);
        name = (d['name'] ?? name).toString();
        avatar = d['avatar_url']?.toString() ?? avatar;
        desc = (d['description'] ?? '').toString();
        slug = (d['slug'] ?? d['username'] ?? slug).toString();
        isPublic = d['public'] != false;
        isAdmin = (d['admin_id'] ?? '').toString() == widget.user.uid;
      }
      if (!isAdmin) {
        final mPath = isChannel
            ? 'channel_members/$id/${widget.user.uid}'
            : 'group_members/$id/${widget.user.uid}';
        final ms = await FirebaseDatabase.instance.ref(mPath).get();
        if (ms.exists && ms.value is Map) {
          final role = (ms.value as Map)['role']?.toString() ?? '';
          if (role == 'admin') isAdmin = true;
        }
      }
    } catch (_) {}
    if (!mounted) return;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => GroupChannelInfoPage(
        user: widget.user,
        chatKey: widget.chatKey,
        entityId: id,
        name: name,
        avatarUrl: avatar,
        description: desc,
        isPublic: isPublic,
        slug: slug,
        isAdmin: isAdmin,
        isChannel: isChannel,
      ),
    ));
  }

  Future<void> _checkContact() async {
    // Группы и каналы — не контакты, баннер не показываем
    if (widget.peer.isSaved || _isGroupOrChannel) {
      isContact = true;
      return;
    }
    try {
      final snap = await FirebaseDatabase.instance
          .ref('my_contacts/${widget.user.uid}/${widget.peer.id}')
          .get();
      if (mounted) setState(() => isContact = snap.exists);
    } catch (_) {
      if (mounted) setState(() => isContact = false);
    }
  }

  Future<void> _addContact() async {
    try {
      await FirebaseDatabase.instance
          .ref('my_contacts/${widget.user.uid}/${widget.peer.id}')
          .set(true);
      if (mounted) {
        setState(() {
          isContact = true;
          contactBannerDismissed = true;
        });
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Добавлен в контакты')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(permissionHelp(e))));
      }
    }
  }

  Future<void> _removeContact(String uid) async {
    try {
      await FirebaseDatabase.instance
          .ref('my_contacts/${widget.user.uid}/$uid')
          .remove();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Удалён из контактов')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(permissionHelp(e))));
      }
    }
  }

  void _replyAndFocus(ChatMessage m) {
    setState(() => replyTo = m);
    Future.microtask(() => _msgFocus.requestFocus());
  }

  Future<void> _jumpToMessage(String? id) async {
    if (id == null || id.isEmpty) return;
    final all = [...messages, ...pendingLocal];
    final idx = all.indexWhere((m) => m.id == id);
    if (idx < 0) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Сообщение не найдено в чате')),
        );
      }
      return;
    }
    setState(() => _highlightMsgId = id);
    // ListView не reverse — индекс сверху вниз
    await Future.delayed(const Duration(milliseconds: 30));
    final key = _msgKeys[id];
    if (key?.currentContext != null) {
      await Scrollable.ensureVisible(
        key!.currentContext!,
        duration: const Duration(milliseconds: 380),
        curve: Curves.easeOutCubic,
        alignment: 0.35,
      );
    } else if (scrollCtrl.hasClients) {
      final max = scrollCtrl.position.maxScrollExtent;
      final est = (idx / all.length.clamp(1, 9999)) * max;
      await scrollCtrl.animateTo(
        est.clamp(0.0, max),
        duration: const Duration(milliseconds: 380),
        curve: Curves.easeOutCubic,
      );
    }
    await Future.delayed(const Duration(milliseconds: 1600));
    if (mounted && _highlightMsgId == id) {
      setState(() => _highlightMsgId = null);
    }
  }

  @override
  void dispose() {
    sub?.cancel();
    typingSub?.cancel();
    _typingDebounce?.cancel();
    _typingClear?.cancel();
    _recTick?.cancel();
    msgCtrl.removeListener(_onComposeChanged);
    _draftDebounce?.cancel();
    // финальный сейв черновика при выходе
    final draftText = msgCtrl.text;
    _saveDraft(draftText);
    msgCtrl.dispose();
    _msgFocus.dispose();
    scrollCtrl.dispose();
    _recorder.dispose();
    _player.dispose();
    _micHoldTimer?.cancel();
    _removeMicGlobalRoute();
    _circleSession++;
    final c = _circleCam;
    _circleCam = null;
    try {
      c?.dispose();
    } catch (_) {}
    try {
      FirebaseDatabase.instance
          .ref('typing/${widget.chatKey}/${widget.user.uid}')
          .remove();
    } catch (_) {}
    super.dispose();
  }


  Widget _glassCircleBtn({
    required Widget icon,
    VoidCallback? onTap,
    double size = 44,
  }) {
    final isLight = themeCtrl.light;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: size,
          height: size,
          child: LiquidGlassLens(
            style: LiquidGlassStyle(
              shape: LiquidGlassShape.continuousRoundedRectangle(cornerRadius: 999),
              appearance: LiquidGlassAppearance(
                color: isLight
                    ? Colors.white.withValues(alpha: 0.22)
                    : Colors.white.withValues(alpha: 0.10),
                saturation: 1.1,
                blur: LiquidGlassBlur(sigmaX: 2, sigmaY: 2),
              ),
              refraction: LiquidGlassRefraction(
                refractionType: OpticalRefraction(
                  refraction: 1.45,
                  refractionWidth: 18,
                  depth: 0.6,
                ),
              ),
            ),
            child: Center(child: icon),
          ),
        ),
      ),
    );
  }

  Widget _glassPill({required Widget child, EdgeInsetsGeometry? padding}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            color: themeCtrl.light
                ? Colors.white.withValues(alpha: 0.40)
                : Colors.white.withValues(alpha: 0.12),
            border: Border.all(
              color: Colors.white.withValues(
                  alpha: themeCtrl.light ? 0.5 : 0.18),
              width: 0.8,
            ),
          ),
          child: child,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final peer = widget.peer;
    final statusText = peerTyping
        ? 'печатает…'
        : peer.isSaved
            ? 'заметки'
            : _isGroupOrChannel
                ? (widget.chatKey.startsWith('c_')
                    ? (peer.username.isNotEmpty &&
                            peer.username != 'channel'
                        ? '@${peer.username}'
                        : 'канал')
                    : (peer.username.isNotEmpty && peer.username != 'group'
                        ? '@${peer.username}'
                        : 'группа'))
                : (peer.username.isNotEmpty
                    ? '@${peer.username}'
                    : 'был(а) недавно');

    final screenW = MediaQuery.of(context).size.width;
    final wall = themeCtrl.chatWallpaper ??
        (themeCtrl.light
            ? const Color(0xFFC8E6C9)
            : const Color(0xFF1A1F18));
    // Весь чат едет за пальцем вправо → назад к списку.
    // Material с цветом обоев — без чёрного экрана под свайпом.
    return GestureDetector(
      onHorizontalDragUpdate: (d) {
        if (d.delta.dx <= 0 && _pageDx <= 0) return;
        setState(() {
          _pageDx = (_pageDx + d.delta.dx).clamp(0.0, screenW);
        });
      },
      onHorizontalDragEnd: (d) {
        final v = d.primaryVelocity ?? 0;
        if (_pageDx > screenW * 0.28 || v > 700) {
          Navigator.of(context).maybePop();
        } else {
          setState(() => _pageDx = 0);
        }
      },
      child: Transform.translate(
        offset: Offset(_pageDx, 0),
        child: Material(
          elevation: _pageDx > 0 ? 12 : 0,
          shadowColor: Colors.black54,
          color: wall,
          child: Scaffold(
      backgroundColor: Colors.transparent,
      resizeToAvoidBottomInset: true,
      // Обои и сообщения заходят под шапку — без серой «рамки»
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        forceMaterialTransparency: true,
        automaticallyImplyLeading: false,
        titleSpacing: 8,
        title: Row(children: [
          _glassCircleBtn(
            icon: Icon(
                _selecting
                    ? Icons.close_rounded
                    : Icons.arrow_back_ios_new_rounded,
                size: 18,
                color: themeCtrl.text),
            onTap: () {
              if (_selecting) {
                setState(() {
                  _selecting = false;
                  _selectedMsgIds.clear();
                });
              } else {
                Navigator.of(context).maybePop();
              }
            },
          ),
          const SizedBox(width: 8),
          if (_selecting)
            Text(
              'Выбрано: ${_selectedMsgIds.length}',
              style: TextStyle(
                color: themeCtrl.text,
                fontWeight: FontWeight.w700,
                fontSize: 17,
              ),
            )
          else
          Expanded(
            child: GestureDetector(
              onTap: peer.isSaved
                  ? () => _openSavedTabs()
                  : _isGroupOrChannel
                      ? () => _openGroupOrChannelInfo()
                      : () {
                          Navigator.of(context).push(MaterialPageRoute(
                              builder: (_) => ProfilePage(
                                  user: widget.user,
                                  profile: peer,
                                  isMe: false)));
                        },
              child: _glassPill(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      peer.isSaved ? 'Избранное' : peer.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: themeCtrl.text,
                      ),
                    ),
                    Text(
                      statusText,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        fontStyle:
                            peerTyping ? FontStyle.italic : FontStyle.normal,
                        color: peerTyping
                            ? SLineColors.mint
                            : themeCtrl.muted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          peer.isSaved
              ? _glassCircleBtn(
                  icon: const Icon(Icons.bookmark_rounded,
                      color: Color(0xFFF5A623), size: 20),
                )
              : GestureDetector(
                  onTap: () {
                    if (_isGroupOrChannel) {
                      _openGroupOrChannelInfo();
                      return;
                    }
                    Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => ProfilePage(
                            user: widget.user,
                            profile: peer,
                            isMe: false)));
                  },
                  child: ClipOval(
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                      child: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.35),
                            width: 1.2,
                          ),
                        ),
                        child: _Avatar(
                          name: peer.displayName,
                          color: peer.colorValue,
                          url: peer.avatarUrl,
                          size: 44,
                        ),
                      ),
                    ),
                  ),
                ),
        ]),
      ),
      // Обои на весь экран (в т.ч. под полем ввода) — как в Telegram
      body: Stack(children: [
        Positioned.fill(
          child: Image.asset(
            themeCtrl.light
                ? 'assets/wallpapers/chat_doodle.jpg'
                : 'assets/wallpapers/chat_doodle_dark.jpg',
            fit: BoxFit.cover,
            alignment: Alignment.center,
            errorBuilder: (_, __, ___) => CustomPaint(
              painter: _ChatDoodlePainter(
                base: themeCtrl.chatWallpaper ??
                    (themeCtrl.light
                        ? const Color(0xFFC8E6C9)
                        : const Color(0xFF0A0E12)),
                light: themeCtrl.light,
              ),
            ),
          ),
        ),
        // Лёгкое затемнение в тёмной теме, чтобы пузыри читались
        if (!themeCtrl.light)
          Positioned.fill(
            child: Container(color: Colors.black.withValues(alpha: 0.35)),
          ),
        Column(children: [
        if (!widget.peer.isSaved &&
            !_isGroupOrChannel &&
            !isContact &&
            !contactBannerDismissed)
          // Баннер только для личных чатов (не группы/каналы)
          Padding(
            padding: EdgeInsets.only(
              top: MediaQuery.of(context).padding.top + kToolbarHeight,
            ),
            child: Material(
              elevation: 2,
              color: themeCtrl.light
                  ? const Color(0xFFE3F2FD)
                  : const Color(0xFF1B2A40),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Добавить ${widget.peer.displayName} в контакты?',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: themeCtrl.text,
                        ),
                      ),
                    ),
                    TextButton(
                        onPressed: () =>
                            setState(() => contactBannerDismissed = true),
                        child: const Text('Отмена')),
                    const SizedBox(width: 4),
                    FilledButton(
                      onPressed: _addContact,
                      style: FilledButton.styleFrom(
                        backgroundColor: SLineColors.accentA,
                        visualDensity: VisualDensity.compact,
                      ),
                      child: const Text('Добавить'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        Expanded(
          child: Stack(
            children: [
            Positioned.fill(
              child: (!msgsReady)
                ? const Center(
                    child: SizedBox(
                      width: 28,
                      height: 28,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : (messages.isEmpty && pendingLocal.isEmpty)
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.chat_bubble_outline,
                            size: 48, color: themeCtrl.muted),
                        const SizedBox(height: 12),
                        Text('Нет сообщений',
                            style: TextStyle(
                                fontSize: 16, color: themeCtrl.muted)),
                        const SizedBox(height: 8),
                        Text('Отправьте стикер, чтобы начать',
                            style: TextStyle(
                                fontSize: 13, color: themeCtrl.muted)),
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          onPressed: _showStickers,
                          icon: const Icon(Icons.emoji_emotions_outlined),
                          label: const Text('Стикер'),
                          style: FilledButton.styleFrom(
                              backgroundColor: SLineColors.accentA),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
            controller: scrollCtrl,
            // низ: место под прозрачную панель (сообщения видны «сквозь» неё)
            padding: EdgeInsets.fromLTRB(
                12,
                8 + MediaQuery.of(context).padding.top + kToolbarHeight,
                12,
                88 + MediaQuery.of(context).padding.bottom),
            itemCount: messages.length + pendingLocal.length,
            itemBuilder: (_, i) {
              final all = [...messages, ...pendingLocal];
              final m = all[i];
              final me = m.senderId == widget.user.uid && !m.fromSline;
              final isPending = m.id.startsWith('local_');
              final gKey = _msgKeys.putIfAbsent(m.id, () => GlobalKey());
              final highlighted = _highlightMsgId == m.id;
              return TweenAnimationBuilder<double>(
                key: ValueKey(m.id),
                tween: Tween(begin: 0, end: 1),
                duration: const Duration(milliseconds: 280),
                curve: Curves.easeOutCubic,
                builder: (ctx, t, child) => Opacity(
                  opacity: t,
                  child: Transform.translate(
                    offset: Offset(me ? 16 * (1 - t) : -16 * (1 - t), 8 * (1 - t)),
                    child: child,
                  ),
                ),
                child: Container(
                key: gKey,
                decoration: highlighted
                    ? BoxDecoration(
                        color: SLineColors.accentA.withValues(alpha: 0.22),
                        borderRadius: BorderRadius.circular(16),
                      )
                    : null,
                child: _SwipeReply(
                onReply: () => _replyAndFocus(m),
                onSwipeBack: () => Navigator.of(context).maybePop(),
                child: Align(
                  alignment: m.type == 'gift'
                      ? Alignment.center
                      : (me ? Alignment.centerRight : Alignment.centerLeft),
                  child: GestureDetector(
                    onTap: () {
                      if (_selecting) {
                        setState(() {
                          if (_selectedMsgIds.contains(m.id)) {
                            _selectedMsgIds.remove(m.id);
                            if (_selectedMsgIds.isEmpty) _selecting = false;
                          } else {
                            _selectedMsgIds.add(m.id);
                          }
                        });
                      } else {
                        _msgMenu(m, me);
                      }
                    },
                    onLongPress: () {
                      HapticFeedback.mediumImpact();
                      setState(() {
                        _selecting = true;
                        _selectedMsgIds.add(m.id);
                      });
                    },
                    onDoubleTap: () {
                      if (!_selecting) _toggleReaction(m, '❤️');
                    },
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      constraints: BoxConstraints(
                          maxWidth: m.type == 'gift'
                              ? MediaQuery.of(context).size.width * 0.7
                              : MediaQuery.of(context).size.width * 0.78),
                      // Медиа / подарки / emoji-games без пузырька (как в Telegram)
                      padding: (m.type == 'circle' ||
                              m.type == 'image' ||
                              m.type == 'video' ||
                              m.type == 'gif' ||
                              m.type == 'sticker' ||
                              m.type == 'gift' ||
                              TgEmojiGame.detect(
                                      sanitizeChatText(m.content).trim()) !=
                                  null)
                          ? EdgeInsets.zero
                          : const EdgeInsets.fromLTRB(14, 10, 14, 8),
                      decoration: () {
                        final noBubble = m.type == 'circle' ||
                            m.type == 'image' ||
                            m.type == 'video' ||
                            m.type == 'gif' ||
                            m.type == 'sticker' ||
                            m.type == 'gift' ||
                            TgEmojiGame.detect(
                                    sanitizeChatText(m.content).trim()) !=
                                null;
                        if (_selectedMsgIds.contains(m.id)) {
                          return BoxDecoration(
                            color: SLineColors.accentA.withValues(alpha: 0.18),
                            borderRadius: BorderRadius.circular(12),
                          );
                        }
                        if (noBubble) {
                          return const BoxDecoration(color: Colors.transparent);
                        }
                        return BoxDecoration(
                          gradient: me
                              ? LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [
                                    themeCtrl.bubbleMeA,
                                    themeCtrl.bubbleMeB,
                                  ],
                                )
                              : null,
                          color: me ? null : themeCtrl.bubbleThem,
                          borderRadius: BorderRadius.only(
                            topLeft: const Radius.circular(18),
                            topRight: const Radius.circular(18),
                            bottomLeft: Radius.circular(me ? 18 : 6),
                            bottomRight: Radius.circular(me ? 6 : 18),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: me
                                  ? themeCtrl.bubbleMeA.withValues(alpha: 0.28)
                                  : Colors.black.withValues(
                                      alpha: themeCtrl.light ? 0.06 : 0.35),
                              blurRadius: 10,
                              offset: const Offset(0, 3),
                            ),
                          ],
                          border: me
                              ? null
                              : Border.all(
                                  color: themeCtrl.light
                                      ? Colors.black.withValues(alpha: 0.04)
                                      : Colors.white.withValues(alpha: 0.06),
                                ),
                        );
                      }(),
                      child: IgnorePointer(
                        ignoring: _selecting,
                        child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (m.replyPreview != null && m.type != 'circle') ...[
                            GestureDetector(
                              onTap: () => _jumpToMessage(m.replyToId),
                              child: Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(6),
                                margin: const EdgeInsets.only(bottom: 6),
                                decoration: BoxDecoration(
                                  border: Border(
                                      left: BorderSide(
                                          color: me
                                              ? Colors.white70
                                              : SLineColors.accentA,
                                          width: 3)),
                                  color: Colors.black12,
                                ),
                                child: Text(m.replyPreview!,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        fontSize: 12,
                                        color: me
                                            ? Colors.white70
                                            : themeCtrl.muted)),
                              ),
                            ),
                          ],
                          _body(m, me),
                          if (isPending)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Icon(Icons.schedule,
                                  size: 14,
                                  color: themeCtrl.muted),
                            ),
                          if (m.reactions.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Wrap(
                                spacing: 4,
                                runSpacing: 4,
                                children: [
                                  for (final e in m.reactions.entries)
                                    if (e.value.isNotEmpty)
                                      GestureDetector(
                                        onTap: () =>
                                            _toggleReaction(m, e.key),
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 7, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: e.value.contains(
                                                    widget.user.uid)
                                                ? SLineColors.mint
                                                    .withValues(alpha: 0.25)
                                                : (me
                                                    ? Colors.white24
                                                    : themeCtrl.panel),
                                            borderRadius:
                                                BorderRadius.circular(999),
                                            border: Border.all(
                                              color: e.value.contains(
                                                      widget.user.uid)
                                                  ? SLineColors.mint
                                                  : themeCtrl.line,
                                            ),
                                          ),
                                          child: Text(
                                              '${e.key} ${e.value.length}',
                                              style: TextStyle(
                                                  fontSize: 12,
                                                  color: me
                                                      ? Colors.white
                                                      : themeCtrl.text)),
                                        ),
                                      ),
                                ],
                              ),
                            ),
                          // Время: для медиа — тёмный бейдж (как в TG), иначе под текстом
                          if (m.timeLabel.isNotEmpty &&
                              m.type != 'image' &&
                              m.type != 'video' &&
                              m.type != 'gif' &&
                              m.type != 'sticker' &&
                              m.type != 'circle' &&
                              m.type != 'gift')
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Align(
                                alignment: Alignment.bottomRight,
                                child: Text(m.timeLabel,
                                    style: TextStyle(
                                        fontSize: 10,
                                        color: me
                                            ? Colors.white70
                                            : themeCtrl.muted)),
                              ),
                            ),
                        ],
                      ),
                      ),
                    ),
                  ),
                ),
                ),
              ),
              );
            },
          ),
            ),
            if (showScrollDown)
              Positioned(
                right: 14,
                bottom: 90 + MediaQuery.of(context).padding.bottom,
                child: Material(
                  color: themeCtrl.light
                      ? Colors.white.withValues(alpha: 0.72)
                      : const Color(0xFF2A2F38).withValues(alpha: 0.85),
                  shape: const CircleBorder(),
                  elevation: 2,
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: () {
                      if (scrollCtrl.hasClients) {
                        scrollCtrl.animateTo(
                          scrollCtrl.position.maxScrollExtent,
                          duration: const Duration(milliseconds: 280),
                          curve: Curves.easeOutCubic,
                        );
                      }
                    },
                    child: const SizedBox(
                      width: 44,
                      height: 44,
                      child: Icon(Icons.arrow_downward_rounded, size: 22),
                    ),
                  ),
                ),
              ),
            // Оверлей кружка прямо в чате (как в TG)
            if (recording && circleMode && _circleCam != null && _circleCamReady)
              Positioned.fill(
                child: IgnorePointer(
                  child: Container(
                    color: Colors.black.withValues(alpha: 0.55),
                    alignment: Alignment.center,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 220,
                          height: 220,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              CustomPaint(
                                size: const Size(220, 220),
                                painter: _CircleProgressPainter(
                                  progress:
                                      (_recSeconds / 60000).clamp(0.0, 1.0),
                                  color: recordingCancelZone
                                      ? const Color(0xFFFF3B30)
                                      : const Color(0xFF3390EC),
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.all(8),
                                child: ClipOval(
                                  child: SizedBox(
                                    width: 200,
                                    height: 200,
                                    child: FittedBox(
                                      fit: BoxFit.cover,
                                      child: SizedBox(
                                        width: _circleCam!.value.previewSize
                                                ?.height ??
                                            200,
                                        height: _circleCam!.value.previewSize
                                                ?.width ??
                                            200,
                                        child: CameraPreview(_circleCam!),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          recordingCancelZone
                              ? 'Отпустите — отмена'
                              : recordingLocked
                                  ? 'Запись закреплена'
                                  : '← отмена  ·  ↑ закрепить',
                          style: TextStyle(
                            color: recordingCancelZone
                                ? const Color(0xFFFF3B30)
                                : Colors.white.withValues(alpha: 0.9),
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: _buildComposerBar(),
            ),
          ], // Expanded Stack children
        ), // Expanded Stack
      ), // Expanded
        ], // Column children
      ), // Column
      ], // body Stack children
    ), // body Stack
      ), // Scaffold
    ), // Material
      ), // Transform.translate
    ); // GestureDetector
  }

  Widget _buildComposerBar() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (replyTo != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
            child: SLineGlass(
              liquid: true,
              radius: BorderRadius.circular(14),
              child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Row(children: [
                    const Icon(Icons.reply,
                        size: 18, color: SLineColors.accentA),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        replyTo!.content.isEmpty
                            ? replyTo!.type
                            : replyTo!.content,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () => setState(() => replyTo = null),
                    ),
                  ]),
                ),
              ),
            ),
        Padding(
          padding: EdgeInsets.fromLTRB(
              6, 4, 6, 6 + MediaQuery.of(context).padding.bottom),
          // Кнопка микрофона не размонтируется при старте записи —
          // иначе long-press обрывается и нельзя сразу тянуть вверх/влево
          child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (!recording) ...[
                    ClipOval(
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                        child: Material(
                          color: themeCtrl.light
                              ? Colors.white.withValues(alpha: 0.16)
                              : Colors.white.withValues(alpha: 0.08),
                          shape: const CircleBorder(),
                          child: InkWell(
                            customBorder: const CircleBorder(),
                            onTap: _showAttachSheet,
                            child: SizedBox(
                              width: 44,
                              height: 44,
                              child: Icon(Icons.attach_file_rounded,
                                  size: 22, color: themeCtrl.text),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: SLineGlass(
                        liquid: true,
                        radius: BorderRadius.circular(24),
                        tint: themeCtrl.light
                            ? Colors.white.withValues(alpha: 0.12)
                            : Colors.white.withValues(alpha: 0.06),
                        child: Container(
                            constraints: const BoxConstraints(minHeight: 44),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Expanded(
                                  child: Theme(
                                    data: Theme.of(context).copyWith(
                                      inputDecorationTheme:
                                          const InputDecorationTheme(
                                        filled: false,
                                        fillColor: Colors.transparent,
                                        border: InputBorder.none,
                                      ),
                                    ),
                                    child: TextField(
                                    controller: msgCtrl,
                                    focusNode: _msgFocus,
                                    cursorColor: SLineColors.accentA,
                                    style: TextStyle(
                                        color: themeCtrl.text, fontSize: 16),
                                    decoration: InputDecoration(
                                      hintText: 'Сообщение',
                                      hintStyle: TextStyle(
                                          color: themeCtrl.muted
                                              .withValues(alpha: 0.9)),
                                      border: InputBorder.none,
                                      enabledBorder: InputBorder.none,
                                      focusedBorder: InputBorder.none,
                                      filled: false,
                                      fillColor: Colors.transparent,
                                      isDense: true,
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                              horizontal: 16, vertical: 12),
                                    ),
                                    minLines: 1,
                                    maxLines: 4,
                                    textInputAction: TextInputAction.send,
                                    onSubmitted: (_) async {
                                      final t = msgCtrl.text.trim();
                                      if (t.isEmpty) return;
                                      msgCtrl.clear();
                                      setState(() => hasText = false);
                                      await _send(type: 'text', content: t);
                                    },
                                  ),
                                  ),
                                ),
                                IconButton(
                                  visualDensity: VisualDensity.compact,
                                  icon: Icon(Icons.emoji_emotions_outlined,
                                      color: themeCtrl.muted, size: 22),
                                  onPressed: _showStickers,
                                ),
                              ],
                            ),
                          ),
                        ),
                    ),
                    const SizedBox(width: 8),
                    if (hasText)
                      Material(
                        color: SLineColors.accentA,
                        shape: const CircleBorder(),
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: () async {
                            final t = msgCtrl.text.trim();
                            if (t.isEmpty) return;
                            msgCtrl.clear();
                            setState(() => hasText = false);
                            await _send(type: 'text', content: t);
                          },
                          child: const SizedBox(
                            width: 44,
                            height: 44,
                            child: Icon(Icons.send_rounded,
                                color: Colors.white, size: 20),
                          ),
                        ),
                      ),
                    ] else ...[
                      // Запись: таймер + подсказки
                      Expanded(child: _buildTgRecordingInfo()),
                      if (recordingLocked)
                        TextButton(
                          onPressed: () => _finishAnyRecord(send: false),
                          child: Text('Отмена',
                              style: TextStyle(color: themeCtrl.muted)),
                        ),
                    ],
                    // Микрофон ВСЕГДА в одном месте Row — жест long-press не обрывается
                    if (!hasText || recording) _buildMicCircleButton(),
                  ],
                ),
        ),
      ],
    );
  }

  void _showAttachSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _TgAttachPanel(
        onPhoto: () async {
          Navigator.pop(ctx);
          await _pickAndSendImage();
        },
        onVideo: () async {
          Navigator.pop(ctx);
          await _pickAndSendVideo();
        },
        onFile: () async {
          Navigator.pop(ctx);
          await _pickAndSendFile();
        },
        onGif: () {
          Navigator.pop(ctx);
          _showGifPanel();
        },
        onSticker: () {
          Navigator.pop(ctx);
          _showStickers();
        },
        onPoll: () {
          Navigator.pop(ctx);
          _createPoll();
        },
        onGiftId: (id) {
          Navigator.pop(ctx);
          _sendPaidGift(id);
        },
        onWallet: () {
          Navigator.pop(ctx);
          _openWallet();
        },
        onLocation: () {
          Navigator.pop(ctx);
          _sendLocation();
        },
        onPickAsset: (path, isVideo) async {
          Navigator.pop(ctx);
          if (isVideo) {
            final url = await _uploadFile(File(path), 'chat_videos');
            if (url != null) await _send(type: 'video', fileUrl: url);
          } else {
            final url = await _uploadFile(File(path), 'chat_images');
            if (url != null) await _send(type: 'image', fileUrl: url);
          }
        },
      ),
    );
  }

  /// Таймер + подсказки во время записи (без своей кнопки — жест на микрофоне)
  Widget _buildTgRecordingInfo() {
    final ms = _recSeconds;
    final sec = (ms / 1000).floor();
    final frac = ((ms % 1000) / 10).floor().toString().padLeft(2, '0');
    final timeStr =
        '${sec ~/ 60}:${(sec % 60).toString().padLeft(2, '0')},$frac';
    return Padding(
      padding: const EdgeInsets.only(left: 8, right: 4),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
              color: Color(0xFFE53935),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Text(timeStr,
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: themeCtrl.text)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              recordingCancelZone
                  ? 'Отпустите — отмена'
                  : recordingLocked
                      ? 'Запись…'
                      : '← отмена  ·  ↑ закрепить',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                color: recordingCancelZone
                    ? SLineColors.danger
                    : themeCtrl.muted,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _addMicGlobalRoute() {
    GestureBinding.instance.pointerRouter
        .addGlobalRoute(_handleMicGlobalPointer);
  }

  void _removeMicGlobalRoute() {
    try {
      GestureBinding.instance.pointerRouter
          .removeGlobalRoute(_handleMicGlobalPointer);
    } catch (_) {}
  }

  void _handleMicGlobalPointer(PointerEvent e) {
    if (_micPointer == null || e.pointer != _micPointer) return;
    if (e is PointerMoveEvent) {
      _onMicPointerMove(e);
    } else if (e is PointerUpEvent) {
      _onMicPointerUp(e);
    } else if (e is PointerCancelEvent) {
      _onMicPointerCancel(e);
    }
  }

  void _onMicPointerDown(PointerDownEvent e) {
    if (_micPointer != null) return;
    _micPointer = e.pointer;
    _micOrigin = e.position;
    _micHoldStarted = false;
    _micHoldTimer?.cancel();
    _addMicGlobalRoute(); // трек пальца по всему экрану (вверх/влево)

    // Уже в режиме записи (закреплено) — тап обработаем на up
    if (recording) return;

    // Короткое удержание ~160мс = старт записи; быстрее = переключение режима
    _micHoldTimer = Timer(const Duration(milliseconds: 160), () {
      if (_micPointer == null || recording) return;
      _micHoldStarted = true;
      HapticFeedback.mediumImpact();
      if (circleMode) {
        _startCircleInChat();
      } else {
        _startVoiceRecord();
      }
    });
  }

  void _onMicPointerMove(PointerMoveEvent e) {
    if (_micPointer != e.pointer) return;
    final o = e.position - _micOrigin;

    // Если ещё не стартовали запись, но палец уже уехал — считаем холд
    if (!recording && !_micHoldStarted) {
      if (o.distance > 12) {
        _micHoldTimer?.cancel();
        _micHoldStarted = true;
        HapticFeedback.mediumImpact();
        if (circleMode) {
          _startCircleInChat();
        } else {
          _startVoiceRecord();
        }
      }
      return;
    }

    if (!recording || recordingLocked) return;
    final cancel = o.dx < -50;
    final lock = o.dy < -50 && !cancel;
    if (!mounted) return;
    setState(() {
      _recDrag = o;
      recordingCancelZone = cancel;
      if (lock) {
        recordingLocked = true;
        recordingCancelZone = false;
        HapticFeedback.mediumImpact();
      }
    });
  }

  void _onMicPointerUp(PointerUpEvent e) {
    if (_micPointer != e.pointer) return;
    _micPointer = null;
    _micHoldTimer?.cancel();
    _micHoldTimer = null;
    _removeMicGlobalRoute();

    if (recording) {
      if (recordingLocked) {
        _micHoldStarted = false;
        return;
      }
      final cancel = recordingCancelZone;
      _micHoldStarted = false;
      _finishAnyRecord(send: !cancel);
      return;
    }

    if (!_micHoldStarted) {
      setState(() => circleMode = !circleMode);
      HapticFeedback.selectionClick();
    }
    _micHoldStarted = false;
  }

  void _onMicPointerCancel(PointerCancelEvent e) {
    if (_micPointer != e.pointer) return;
    _micPointer = null;
    _micHoldTimer?.cancel();
    _micHoldTimer = null;
    _removeMicGlobalRoute();
    if (recording && !recordingLocked) {
      _finishAnyRecord(send: false);
    }
    _micHoldStarted = false;
  }

  Widget _buildMicCircleButton() {
    final activeColor =
        circleMode ? const Color(0xFF6D5DF6) : themeCtrl.text;
    final size = recording ? (recordingLocked ? 56.0 : 64.0) : 44.0;
    final dragOffset = recording && !recordingLocked
        ? Offset(
            _recDrag.dx.clamp(-80.0, 0.0) * 0.25,
            _recDrag.dy.clamp(-100.0, 0.0) * 0.2,
          )
        : Offset.zero;

    return Transform.translate(
      offset: dragOffset,
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: _onMicPointerDown,
        onPointerMove: _onMicPointerMove,
        onPointerUp: _onMicPointerUp,
        onPointerCancel: _onMicPointerCancel,
        child: GestureDetector(
          // Locked: тап = отправить
          onTap: () {
            if (recording && recordingLocked) {
              _finishAnyRecord(send: true);
            }
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            width: size,
            height: size,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: recording
                  ? (recordingCancelZone
                      ? SLineColors.danger
                      : const Color(0xFF3390EC))
                  : (themeCtrl.light
                      ? Colors.white.withValues(alpha: 0.12)
                      : Colors.white.withValues(alpha: 0.08)),
              border: recording
                  ? null
                  : Border.all(
                      color: Colors.white.withValues(
                          alpha: themeCtrl.light ? 0.22 : 0.10),
                      width: 0.5,
                    ),
              boxShadow: recording
                  ? [
                      BoxShadow(
                        color: (recordingCancelZone
                                ? SLineColors.danger
                                : const Color(0xFF3390EC))
                            .withValues(alpha: 0.4),
                        blurRadius: 14,
                        spreadRadius: 1,
                      ),
                    ]
                  : null,
            ),
            child: recording
                ? Icon(
                    recordingLocked
                        ? Icons.send_rounded
                        : (recordingCancelZone
                            ? Icons.delete_outline_rounded
                            : (circleMode
                                ? Icons.radio_button_checked
                                : Icons.mic_rounded)),
                    color: Colors.white,
                    size: recordingLocked ? 24 : 28,
                  )
                : AnimatedSwitcher(
                    duration: const Duration(milliseconds: 280),
                    switchInCurve: Curves.easeOutBack,
                    switchOutCurve: Curves.easeIn,
                    transitionBuilder: (child, anim) {
                      return RotationTransition(
                        turns: Tween<double>(begin: 0.75, end: 1.0)
                            .animate(anim),
                        child: ScaleTransition(
                          scale: anim,
                          child: FadeTransition(opacity: anim, child: child),
                        ),
                      );
                    },
                    child: Icon(
                      circleMode
                          ? Icons.radio_button_checked
                          : Icons.mic_none_rounded,
                      key: ValueKey(circleMode ? 'circle' : 'mic'),
                      color: activeColor,
                      size: 24,
                    ),
                  ),
          ),
        ),
      ),
    );
  }


  void _searchInChat() {
    final q = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Поиск в чате'),
        content: TextField(
          controller: q,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Текст сообщения'),
          onSubmitted: (_) => Navigator.pop(ctx, q.text.trim()),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Отмена')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, q.text.trim()),
              child: const Text('Найти')),
        ],
      ),
    ).then((query) {
      if (query is! String || query.isEmpty) return;
      final qLow = query.toLowerCase();
      final hits = messages
          .where((m) => m.content.toLowerCase().contains(qLow))
          .toList();
      if (!mounted) return;
      if (hits.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Ничего не найдено')));
        return;
      }
      showModalBottomSheet(
        context: context,
        backgroundColor: themeCtrl.panel,
        builder: (c) => ListView.builder(
          shrinkWrap: true,
          itemCount: hits.length.clamp(0, 30),
          itemBuilder: (_, i) {
            final m = hits[i];
            return ListTile(
              title: Text(m.content,
                  maxLines: 2, overflow: TextOverflow.ellipsis),
              subtitle: Text(m.timeLabel),
              onTap: () {
                Navigator.pop(c);
                final idx = messages.indexWhere((x) => x.id == m.id);
                if (idx >= 0 && scrollCtrl.hasClients) {
                  // приблизительно к концу списка
                  final ratio = messages.isEmpty
                      ? 0.0
                      : idx / messages.length;
                  scrollCtrl.jumpTo(
                      scrollCtrl.position.maxScrollExtent * ratio);
                }
              },
            );
          },
        ),
      );
    });
  }

  Future<void> _startCall({required bool audioOnly}) async {
    if (widget.peer.isSaved) return;
    try {
      final callRef = FirebaseDatabase.instance.ref('calls').push();
      final id = callRef.key!;
      await callRef.set({
        'from': widget.user.uid,
        'to': widget.peer.id,
        'type': audioOnly ? 'audio' : 'video',
        'chat_key': widget.chatKey,
        'status': 'ringing',
        'created_at': DateTime.now().millisecondsSinceEpoch,
      });
      try {
        final from = widget.myProfile?.displayName ?? 'SLine';
        await enqueuePushNotify(
          toUid: widget.peer.id,
          title: audioOnly ? 'Входящий звонок' : 'Видеозвонок',
          body: from,
          chatKey: widget.chatKey,
        );
      } catch (_) {}
      if (!mounted) return;
      await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => InAppCallScreen(
          callId: id,
          user: widget.user,
          peer: widget.peer,
          audioOnly: audioOnly,
          isCaller: true,
        ),
      ));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  void _showStickers() {
    showModalBottomSheet(
      context: context,
      backgroundColor: themeCtrl.hover,
      isScrollControlled: true,
      builder: (ctx) => SizedBox(
        height: MediaQuery.of(context).size.height * 0.5,
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: Row(
              children: [
                const Text('Стикеры',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                const Spacer(),
                TextButton.icon(
                  onPressed: () async {
                    Navigator.pop(ctx);
                    await _sendCustomSticker();
                  },
                  icon: const Icon(Icons.add_photo_alternate_outlined, size: 20),
                  label: const Text('Свой'),
                ),
              ],
            ),
          ),
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.all(8),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 4, crossAxisSpacing: 8, mainAxisSpacing: 8),
              itemCount: myStickers.length + stickerUrls.length,
              itemBuilder: (_, i) {
                final u = i < myStickers.length
                    ? myStickers[i]
                    : stickerUrls[i - myStickers.length];
                return InkWell(
                  onTap: () async {
                    Navigator.pop(ctx);
                    try {
                      await _send(type: 'sticker', fileUrl: u, content: '');
                    } catch (e) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Стикер: $e')));
                      }
                    }
                  },
                  child: Image.network(u,
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) =>
                          const Center(child: Text('🙂', style: TextStyle(fontSize: 32)))),
                );
              },
            ),
          ),
        ]),
      ),
    );
  }

  Future<void> _sendCustomSticker() async {
    try {
      final x = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        imageQuality: 90,
      );
      if (x == null) return;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Добавление в набор…')));
      }
      final url = await _uploadFile(File(x.path), 'chat_stickers');
      if (url == null || url.isEmpty) throw Exception('Загрузка не удалась');
      // В набор, не в чат (как в TG)
      setState(() => myStickers.insert(0, url));
      try {
        await FirebaseDatabase.instance
            .ref('tables/user_stickers/${widget.user.uid}')
            .push()
            .set({
          'url': url,
          'created_at': DateTime.now().millisecondsSinceEpoch,
        });
      } catch (_) {}
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Стикер добавлен в набор')));
        _showStickers();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Стикер: $e')));
      }
    }
  }

  void _showGifPanel() {
    showModalBottomSheet(
      context: context,
      backgroundColor: themeCtrl.panel,
      isScrollControlled: true,
      builder: (ctx) => _GifPickerSheet(
        onPick: (url) {
          Navigator.pop(ctx);
          _send(type: 'gif', fileUrl: url, content: '');
        },
      ),
    );
  }


  Future<void> _toggleReaction(ChatMessage m, String emoji) async {
    try {
      final ref = chatMsgsRef(widget.chatKey).child(m.id).child('reactions');
      final snap = await ref.get();
      final map = <String, dynamic>{};
      if (snap.exists && snap.value is Map) {
        map.addAll(Map<String, dynamic>.from(snap.value as Map));
      }
      final uid = widget.user.uid;
      final list = <String>[];
      final cur = map[emoji];
      if (cur is List) {
        list.addAll(cur.map((e) => e.toString()));
      } else if (cur is Map) {
        list.addAll(cur.keys.map((e) => e.toString()));
      }
      // снять свою реакцию с других эмодзи
      for (final k in map.keys.toList()) {
        final v = map[k];
        if (v is List) {
          final filtered = v.map((e) => e.toString()).where((id) => id != uid).toList();
          if (filtered.isEmpty) {
            map.remove(k);
          } else {
            map[k] = filtered;
          }
        } else if (v is Map) {
          final mm = Map<String, dynamic>.from(v);
          mm.remove(uid);
          if (mm.isEmpty) {
            map.remove(k);
          } else {
            map[k] = mm;
          }
        }
      }
      if (list.contains(uid)) {
        // уже стояла — убрать
        map.remove(emoji);
      } else {
        map[emoji] = [...list.where((id) => id != uid), uid];
      }
      await ref.set(map.isEmpty ? null : map);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(permissionHelp(e))));
      }
    }
  }

  Future<void> _createPoll() async {
    final qCtrl = TextEditingController();
    final o1 = TextEditingController();
    final o2 = TextEditingController();
    final o3 = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Опрос'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: qCtrl, decoration: const InputDecoration(labelText: 'Вопрос')),
            const SizedBox(height: 8),
            TextField(controller: o1, decoration: const InputDecoration(labelText: 'Вариант 1')),
            const SizedBox(height: 8),
            TextField(controller: o2, decoration: const InputDecoration(labelText: 'Вариант 2')),
            const SizedBox(height: 8),
            TextField(controller: o3, decoration: const InputDecoration(labelText: 'Вариант 3 (необяз.)')),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Создать')),
        ],
      ),
    );
    if (ok != true) return;
    final q = qCtrl.text.trim();
    final opts = [o1.text.trim(), o2.text.trim(), o3.text.trim()]
        .where((e) => e.isNotEmpty)
        .toList();
    if (q.isEmpty || opts.length < 2) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Нужны вопрос и минимум 2 варианта')));
      }
      return;
    }
    final poll = {
      'q': q,
      'opts': opts.map((t) => {'t': t, 'votes': <String>[]}).toList(),
    };
    await _send(type: 'poll', content: jsonEncode(poll));
  }

  Future<void> _sendGift() async {
    if (widget.peer.isSaved) return;
    final id = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: themeCtrl.panel,
      isScrollControlled: true,
      builder: (ctx) => _GiftPickerSheet(uid: widget.user.uid),
    );
    if (id == null) return;
    await _sendPaidGift(id);
  }

  Future<void> _sendPaidGift(String giftId) async {
    final price = SLineGifts.priceFor(giftId);
    final ok = await SCoin.spend(widget.user.uid, price);
    if (!ok) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'Недостаточно SCoin (нужно $price). Откройте Кошелёк.'),
          ),
        );
      }
      return;
    }
    final sell = SLineGifts.sellFor(giftId);
    final emoji = SLineGifts.emojiFor(giftId);
    final name = SLineGifts.labelFor(giftId);
    await _send(
      type: 'gift',
      content: 'gift:$giftId',
      fileUrl: giftId,
    );
    // Карточка в профиле получателя (как на вебе: user_gifts/$peerId/$msgId)
    try {
      final mid = DateTime.now().millisecondsSinceEpoch.toString();
      await FirebaseDatabase.instance
          .ref('user_gifts/${widget.peer.id}/$mid')
          .set({
        'id': mid,
        'gift_id': giftId,
        'gift_emoji': emoji,
        'gift_name': name,
        'gift_price': price,
        'gift_sell': sell,
        'from_id': widget.user.uid,
        'from_name': widget.myProfile?.displayName ?? 'User',
        'from_avatar': widget.myProfile?.avatarUrl ?? '',
        'visible': true,
        'created_at': DateTime.now().toIso8601String(),
        'created_at_ms': DateTime.now().millisecondsSinceEpoch,
      });
    } catch (_) {}
  }

  Future<void> _openGiftDetail(ChatMessage m, String gid,
      {required bool canSell}) async {
    final sell = SLineGifts.sellFor(gid);
    await showModalBottomSheet(
      context: context,
      backgroundColor: themeCtrl.panel,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: themeCtrl.muted.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 16),
                Text(SLineGifts.emojiFor(gid),
                    style: const TextStyle(fontSize: 72)),
                const SizedBox(height: 8),
                Text(SLineGifts.labelFor(gid),
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: themeCtrl.text)),
                const SizedBox(height: 4),
                Text('${SLineGifts.priceFor(gid)} SL · продажа $sell SL',
                    style: TextStyle(color: themeCtrl.muted, fontSize: 13)),
                const SizedBox(height: 20),
                if (canSell)
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      onPressed: () async {
                        Navigator.pop(ctx);
                        await SCoin.add(widget.user.uid, sell);
                        try {
                          await FirebaseDatabase.instance
                              .ref('user_gifts/${widget.user.uid}/${m.id}')
                              .remove();
                        } catch (_) {}
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                                content: Text('Продано за $sell SCoin')),
                          );
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: SLineColors.accentA,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                      child: Text('Продать за $sell SL'),
                    ),
                  ),
                if (canSell) const SizedBox(height: 10),
                if (canSell)
                  SizedBox(
                    width: double.infinity,
                    height: 44,
                    child: TextButton(
                      onPressed: () async {
                        Navigator.pop(ctx);
                        try {
                          await FirebaseDatabase.instance
                              .ref(
                                  'user_gifts/${widget.user.uid}/${m.id}/visible')
                              .set(false);
                        } catch (_) {}
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text('Скрыто в профиле')),
                          );
                        }
                      },
                      child: const Text('Скрыть в профиле'),
                    ),
                  ),
                if (!canSell)
                  Text('Вы отправили этот подарок',
                      style: TextStyle(color: themeCtrl.muted)),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _openWallet() async {
    await SCoin.ensureStarter(widget.user.uid);
    var bal = await SCoin.balance(widget.user.uid);
    if (!mounted) return;
    await showModalBottomSheet(
      context: context,
      backgroundColor: themeCtrl.panel,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setS) {
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: themeCtrl.muted.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text('Кошелёк',
                      style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: themeCtrl.text)),
                  const SizedBox(height: 4),
                  Text('Внутренняя валюта SLine',
                      style:
                          TextStyle(fontSize: 13, color: themeCtrl.muted)),
                  const SizedBox(height: 16),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF1E3A8A), Color(0xFF3B82F6)],
                      ),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          shape: BoxShape.circle,
                        ),
                        alignment: Alignment.center,
                        child: const Text('SL',
                            style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w900)),
                      ),
                      const SizedBox(width: 14),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Баланс',
                              style: TextStyle(
                                  color: Colors.white70, fontSize: 13)),
                          Text('$bal SLCoin',
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 26,
                                  fontWeight: FontWeight.w800)),
                        ],
                      ),
                    ]),
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      onPressed: () async {
                        final peer = widget.peer;
                        if (peer.isSaved) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text(
                                    'Перевод себе в Избранное недоступен')),
                          );
                          return;
                        }
                        final amountC = TextEditingController();
                        final ok = await showDialog<bool>(
                          context: context,
                          builder: (dCtx) => AlertDialog(
                            title: Text('Перевод ${peer.displayName}'),
                            content: TextField(
                              controller: amountC,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                  labelText: 'Сумма SCoin'),
                            ),
                            actions: [
                              TextButton(
                                  onPressed: () =>
                                      Navigator.pop(dCtx, false),
                                  child: const Text('Отмена')),
                              TextButton(
                                  onPressed: () =>
                                      Navigator.pop(dCtx, true),
                                  child: const Text('Перевести')),
                            ],
                          ),
                        );
                        if (ok != true) return;
                        final n = int.tryParse(amountC.text.trim()) ?? 0;
                        if (n <= 0) return;
                        final spent = await SCoin.spend(widget.user.uid, n);
                        if (!spent) {
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                  content: Text('Недостаточно SCoin')),
                            );
                          }
                          return;
                        }
                        await SCoin.add(peer.id, n);
                        await _send(
                          type: 'text',
                          content: '💸 Перевод $n SCoin',
                        );
                        bal = await SCoin.balance(widget.user.uid);
                        setS(() {});
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                                content: Text('Переведено $n SCoin')),
                          );
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: SLineColors.accentA,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                      child: const Text('Перевести SCoin'),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Закрыть'),
                  ),
                ],
              ),
            ),
          );
        });
      },
    );
  }

  Future<void> _sendLocation() async {
    try {
      final perm = await Permission.locationWhenInUse.request();
      if (!perm.isGranted) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Нужен доступ к геолокации')),
          );
        }
        return;
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Определение координат…')),
        );
      }
      // Без geolocator: через Android LocationManager через platform — 
      // используем упрощённый способ через last known via permission_handler + http IP geo fallback
      double? lat;
      double? lng;
      try {
        // IP-based approximate location (работает без GPS-пакета)
        final res = await http.get(Uri.parse('https://ipapi.co/json/'));
        if (res.statusCode == 200) {
          final j = jsonDecode(res.body) as Map<String, dynamic>;
          lat = (j['latitude'] as num?)?.toDouble();
          lng = (j['longitude'] as num?)?.toDouble();
        }
      } catch (_) {}
      if (lat == null || lng == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Не удалось получить координаты')),
          );
        }
        return;
      }
      final mapsUrl =
          'https://www.google.com/maps?q=$lat,$lng';
      final content = jsonEncode({
        'lat': lat,
        'lng': lng,
        'url': mapsUrl,
        'label': 'Моя геопозиция',
      });
      await _send(type: 'location', content: content, fileUrl: mapsUrl);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Гео: $e')));
      }
    }
  }

  Future<void> _votePoll(ChatMessage m, int index) async {
    try {
      final poll = jsonDecode(m.content) as Map<String, dynamic>;
      final opts = (poll['opts'] as List?) ?? [];
      final uid = widget.user.uid;
      for (final o in opts) {
        if (o is! Map) continue;
        final votes = <String>[];
        final raw = o['votes'];
        if (raw is List) votes.addAll(raw.map((e) => e.toString()));
        o['votes'] = votes.where((v) => v != uid).toList();
      }
      if (index >= 0 && index < opts.length && opts[index] is Map) {
        final votes = List<String>.from(
            ((opts[index] as Map)['votes'] as List?)?.map((e) => e.toString()) ??
                []);
        votes.add(uid);
        (opts[index] as Map)['votes'] = votes;
      }
      poll['opts'] = opts;
      await chatMsgsRef(widget.chatKey)
          .child(m.id)
          .update({'content': jsonEncode(poll)});
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  void _msgMenu(ChatMessage m, bool me, {Offset? pos}) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Реакции — влезают в ширину
                Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  decoration: BoxDecoration(
                    color: themeCtrl.light
                        ? Colors.white
                        : const Color(0xFF2A2F38),
                    borderRadius: BorderRadius.circular(28),
                    boxShadow: [
                      BoxShadow(
                          color: Colors.black.withValues(alpha: 0.15),
                          blurRadius: 10)
                    ],
                  ),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        for (final em in ChatMessage.reactionEmojis)
                          InkWell(
                            onTap: () {
                              Navigator.pop(ctx);
                              _toggleReaction(m, em);
                            },
                            borderRadius: BorderRadius.circular(20),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              child: Text(em,
                                  style: const TextStyle(fontSize: 28)),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: themeCtrl.light
                        ? Colors.white
                        : const Color(0xFF2A2F38),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _menuTile(Icons.reply_rounded, 'Ответить', () {
                        Navigator.pop(ctx);
                        setState(() => replyTo = m);
                        Future.microtask(() =>
                            FocusScope.of(context).requestFocus(_msgFocus));
                      }),
                      _menuTile(Icons.copy_rounded, 'Копировать текст', () {
                        Navigator.pop(ctx);
                        final text = sanitizeChatText(m.content.isNotEmpty
                            ? m.content
                            : (m.fileUrl ?? m.type));
                        Clipboard.setData(ClipboardData(text: text));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Скопировано')),
                        );
                      }),
                      _menuTile(Icons.push_pin_outlined, 'Закрепить', () {
                        Navigator.pop(ctx);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              content: Text('Закреплено (локально)')),
                        );
                      }),
                      _menuTile(Icons.forward_rounded, 'Переслать', () {
                        Navigator.pop(ctx);
                      }),
                      ListTile(
                        dense: true,
                        leading: const Icon(Icons.delete_outline,
                            color: SLineColors.danger),
                        title: Text(
                          me ? 'Удалить' : 'Удалить у себя',
                          style: const TextStyle(color: SLineColors.danger),
                        ),
                        onTap: () async {
                          Navigator.pop(ctx);
                          if (me) {
                            try {
                              await chatMsgsRef(widget.chatKey)
                                  .child(m.id)
                                  .remove();
                            } catch (e) {
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                      content: Text(permissionHelp(e))),
                                );
                              }
                            }
                          } else {
                            setState(() {
                              messages = messages
                                  .where((x) => x.id != m.id)
                                  .toList();
                            });
                          }
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _menuTile(IconData icon, String title, VoidCallback onTap) {
    return ListTile(
      dense: true,
      leading: Icon(icon, color: themeCtrl.text, size: 22),
      title: Text(title, style: const TextStyle(fontSize: 15)),
      onTap: onTap,
    );
  }

  /// Вкладки Избранного (Чаты / Медиа / Файлы / Голосовые / GIF) как в TG
  void _openSavedTabs() {
    final media = messages
        .where((m) =>
            m.type == 'image' ||
            m.type == 'video' ||
            m.type == 'gif' ||
            m.type == 'sticker')
        .toList()
        .reversed
        .toList();
    final files = messages.where((m) => m.type == 'file').toList().reversed.toList();
    final voices = messages
        .where((m) => m.type == 'voice' || m.type == 'circle')
        .toList()
        .reversed
        .toList();
    final gifs = messages.where((m) => m.type == 'gif').toList().reversed.toList();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: themeCtrl.panel,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (ctx) {
        return DefaultTabController(
          length: 5,
          child: SizedBox(
            height: MediaQuery.of(ctx).size.height * 0.72,
            child: Column(
              children: [
                const SizedBox(height: 10),
                Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: themeCtrl.muted.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 8),
                Text('Избранное · ${messages.length}',
                    style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                        color: themeCtrl.text)),
                TabBar(
                  isScrollable: true,
                  labelColor: SLineColors.accentA,
                  unselectedLabelColor: themeCtrl.muted,
                  indicatorColor: SLineColors.accentA,
                  tabs: [
                    Tab(text: 'Сообщения'),
                    Tab(text: 'Медиа (${media.length})'),
                    Tab(text: 'Файлы (${files.length})'),
                    Tab(text: 'Голос (${voices.length})'),
                    Tab(text: 'GIF (${gifs.length})'),
                  ],
                ),
                Expanded(
                  child: TabBarView(children: [
                    ListView.builder(
                      padding: const EdgeInsets.all(12),
                      itemCount: messages.length,
                      itemBuilder: (_, i) {
                        final m = messages[messages.length - 1 - i];
                        return ListTile(
                          dense: true,
                          title: Text(
                            m.content.isNotEmpty
                                ? m.content
                                : m.type,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(m.timeLabel,
                              style: TextStyle(
                                  fontSize: 11, color: themeCtrl.muted)),
                        );
                      },
                    ),
                    media.isEmpty
                        ? Center(
                            child: Text('Нет медиа',
                                style: TextStyle(color: themeCtrl.muted)))
                        : GridView.builder(
                            padding: const EdgeInsets.all(8),
                            gridDelegate:
                                const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 3,
                              mainAxisSpacing: 4,
                              crossAxisSpacing: 4,
                            ),
                            itemCount: media.length,
                            itemBuilder: (_, i) {
                              final m = media[i];
                              final u = (m.fileUrl ?? '').trim();
                              return GestureDetector(
                                onTap: () {
                                  Navigator.pop(ctx);
                                  if (u.isNotEmpty) {
                                    _openMediaViewer(u,
                                        isVideo: m.type == 'video');
                                  }
                                },
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: u.isEmpty
                                      ? Container(color: themeCtrl.input)
                                      : _DlImage(
                                          url: u,
                                          fit: BoxFit.cover,
                                        ),
                                ),
                              );
                            },
                          ),
                    files.isEmpty
                        ? Center(
                            child: Text('Нет файлов',
                                style: TextStyle(color: themeCtrl.muted)))
                        : ListView.builder(
                            itemCount: files.length,
                            itemBuilder: (_, i) {
                              final m = files[i];
                              return ListTile(
                                leading: const Icon(Icons.insert_drive_file),
                                title: Text(m.content.isNotEmpty
                                    ? m.content
                                    : 'Файл'),
                                subtitle: Text(m.timeLabel),
                              );
                            },
                          ),
                    voices.isEmpty
                        ? Center(
                            child: Text('Нет голосовых',
                                style: TextStyle(color: themeCtrl.muted)))
                        : ListView.builder(
                            itemCount: voices.length,
                            itemBuilder: (_, i) {
                              final m = voices[i];
                              return ListTile(
                                leading: Icon(
                                    m.type == 'circle'
                                        ? Icons.radio_button_checked
                                        : Icons.mic),
                                title: Text(m.type == 'circle'
                                    ? 'Видеокружок'
                                    : 'Голосовое'),
                                subtitle: Text(m.timeLabel),
                                onTap: () => _playVoice(m),
                              );
                            },
                          ),
                    gifs.isEmpty
                        ? Center(
                            child: Text('Нет GIF',
                                style: TextStyle(color: themeCtrl.muted)))
                        : GridView.builder(
                            padding: const EdgeInsets.all(8),
                            gridDelegate:
                                const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 3,
                              mainAxisSpacing: 4,
                              crossAxisSpacing: 4,
                            ),
                            itemCount: gifs.length,
                            itemBuilder: (_, i) {
                              final m = gifs[i];
                              final u = (m.fileUrl ?? '').trim();
                              return ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: u.isEmpty
                                    ? Container(color: themeCtrl.input)
                                    : _DlImage(url: u, fit: BoxFit.cover),
                              );
                            },
                          ),
                  ]),
                ),
              ],
            ),
          ),
        );
      },
    );
  }


  Widget _mediaError(String url, bool me) {
    final short = url.length > 40 ? '${url.substring(0, 40)}…' : url;
    return Container(
      width: 180,
      height: 100,
      color: Colors.black26,
      alignment: Alignment.center,
      padding: const EdgeInsets.all(8),
      child: Text(
        'Медиа недоступно\n$short',
        textAlign: TextAlign.center,
        style: TextStyle(
            fontSize: 11,
            color: me ? Colors.white70 : themeCtrl.muted),
      ),
    );
  }

  Widget _body(ChatMessage m, bool me) {
    switch (m.type) {
      case 'image':
      case 'gif':
      case 'sticker':
        final url = normalizeMediaUrl(m.fileUrl ?? '');
        if (url.isEmpty) {
          return Text(m.content.isEmpty ? 'медиа' : m.content,
              style: TextStyle(color: me ? Colors.white : themeCtrl.text));
        }
        final w = m.type == 'sticker' ? 120.0 : 240.0;
        final isGif = m.type == 'gif';
        Widget media;
        if (url.startsWith('data:image/svg') ||
            url.contains('data:image/svg+xml')) {
          // SVG с веба — мягкая заглушка, не «битый» URL
          media = Container(
            width: w,
            height: w * 0.7,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.black12,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.image_outlined,
                size: 40,
                color: me ? Colors.white54 : themeCtrl.muted),
          );
        } else if (url.startsWith('data:image')) {
          try {
            final comma = url.indexOf(',');
            if (comma < 0) throw Exception('bad data uri');
            final payload = url.substring(comma + 1);
            final meta = url.substring(0, comma).toLowerCase();
            final bytes = meta.contains(';base64')
                ? base64Decode(payload)
                : Uint8List.fromList(payload.codeUnits);
            media = ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.memory(
                bytes,
                width: w,
                fit: BoxFit.cover,
                filterQuality: FilterQuality.medium,
                errorBuilder: (_, __, ___) => _mediaError(url, me),
              ),
            );
          } catch (_) {
            media = _mediaError(url, me);
          }
        } else {
          media = ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: _DlImage(
              url: url,
              width: w,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => _mediaError(url, me),
            ),
          );
        }
        media = Stack(
          clipBehavior: Clip.none,
          children: [
            media,
            if (isGif)
              Positioned(
                top: 8,
                left: 8,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text('GIF',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w700)),
                ),
              ),
            // Время внизу справа поверх фото (как в TG)
            if (m.timeLabel.isNotEmpty)
              Positioned(
                right: 6,
                bottom: 6,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    m.timeLabel,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w500),
                  ),
                ),
              ),
          ],
        );
        return GestureDetector(
          onTap: _selecting ? null : () => _openMediaViewer(url, isVideo: false),
          child: media,
        );
      case 'voice':
        final playing = playingId == m.id;
        final bars = List<double>.generate(28, (i) {
          final h = ((m.id.hashCode * (i + 3)) % 17) / 17.0;
          return 0.25 + h * 0.75;
        });
        return InkWell(
          onTap: _selecting ? null : () => _playVoice(m),
          borderRadius: BorderRadius.circular(16),
          child: SizedBox(
            width: 200,
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: me
                        ? Colors.white.withValues(alpha: 0.95)
                        : SLineColors.accentA,
                  ),
                  child: Icon(
                    playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    color: me ? SLineColors.accentA : Colors.white,
                    size: 26,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        height: 28,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            for (var i = 0; i < bars.length; i++)
                              Expanded(
                                child: Padding(
                                  padding:
                                      const EdgeInsets.symmetric(horizontal: 0.6),
                                  child: AnimatedContainer(
                                    duration:
                                        const Duration(milliseconds: 180),
                                    height: 28 * bars[i] *
                                        (playing
                                            ? (0.55 +
                                                (i % 3 == 0 ? 0.45 : 0.2))
                                            : 1.0),
                                    decoration: BoxDecoration(
                                      color: me
                                          ? Colors.white
                                              .withValues(alpha: 0.92)
                                          : themeCtrl.text
                                              .withValues(alpha: 0.55),
                                      borderRadius: BorderRadius.circular(2),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 4),
                      StreamBuilder<Duration>(
                        stream: playing
                            ? _player.onPositionChanged
                            : const Stream.empty(),
                        builder: (_, snap) {
                          final pos = snap.data ?? Duration.zero;
                          String label = '0:00';
                          if (playing && pos.inMilliseconds > 0) {
                            final s = pos.inSeconds;
                            label =
                                '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
                          }
                          return Text(
                            label,
                            style: TextStyle(
                              fontSize: 11,
                              color: me
                                  ? Colors.white.withValues(alpha: 0.85)
                                  : themeCtrl.muted,
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      case 'file':
        final name = m.content.isNotEmpty ? m.content : 'Файл';
        final url = (m.fileUrl ?? '').trim();
        return InkWell(
          onTap: (_selecting || url.isEmpty) ? null : () => _openOrDownloadFile(url, name),
          borderRadius: BorderRadius.circular(12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: me
                      ? Colors.white.withValues(alpha: 0.2)
                      : SLineColors.accentA.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.insert_drive_file_rounded,
                    color: me ? Colors.white : SLineColors.accentA),
              ),
              const SizedBox(width: 10),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: me ? Colors.white : themeCtrl.text)),
                    Text('Нажмите, чтобы скачать',
                        style: TextStyle(
                            fontSize: 11,
                            color: me
                                ? Colors.white70
                                : themeCtrl.muted)),
                  ],
                ),
              ),
            ],
          ),
        );
      case 'circle':
      case 'video':
        final vu = normalizeMediaUrl(m.fileUrl ?? '');
        if (vu.isEmpty) {
          return Text(m.type == 'circle' ? '⭕ Кружок' : '🎬 Видео',
              style: TextStyle(color: me ? Colors.white : themeCtrl.text));
        }
        return GestureDetector(
          onTap: _selecting ? null : () => _openMediaViewer(vu, isVideo: true),
          child: _NetVideo(url: vu, circle: m.type == 'circle'),
        );
      case 'gift':
        final gid = m.fileUrl ??
            (m.content.startsWith('gift:')
                ? m.content.substring(5)
                : m.content);
        final isMine = me;
        final canSell = !isMine; // получатель может продать
        return GestureDetector(
          onTap: () => _openGiftDetail(m, gid, canSell: canSell),
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.2, end: 1),
            duration: const Duration(milliseconds: 550),
            curve: Curves.elasticOut,
            builder: (_, t, child) => Transform.scale(scale: t, child: child),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 22, vertical: 16),
                  decoration: BoxDecoration(
                    color: themeCtrl.light
                        ? Colors.white.withValues(alpha: 0.55)
                        : Colors.white.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(
                      color: themeCtrl.light
                          ? Colors.black.withValues(alpha: 0.06)
                          : Colors.white.withValues(alpha: 0.1),
                    ),
                  ),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Text(SLineGifts.emojiFor(gid),
                        style: const TextStyle(fontSize: 64)),
                    const SizedBox(height: 6),
                    Text(SLineGifts.labelFor(gid),
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: themeCtrl.text)),
                    const SizedBox(height: 2),
                    Text(
                      isMine
                          ? 'Отправлено · ${SLineGifts.priceFor(gid)} SL'
                          : 'Вам подарок · ${SLineGifts.sellFor(gid)} SL',
                      style: TextStyle(
                          fontSize: 11, color: themeCtrl.muted),
                    ),
                  ]),
                ),
              ],
            ),
          ),
        );
      case 'location':
        Map<String, dynamic> loc = {};
        try {
          loc = jsonDecode(m.content) as Map<String, dynamic>;
        } catch (_) {}
        final url = (loc['url'] ?? m.fileUrl ?? '').toString();
        final label = (loc['label'] ?? 'Геопозиция').toString();
        final lat = loc['lat'];
        final lng = loc['lng'];
        return InkWell(
          onTap: () async {
            if (url.isEmpty) return;
            final u = Uri.parse(url);
            if (await canLaunchUrl(u)) {
              await launchUrl(u, mode: LaunchMode.externalApplication);
            }
          },
          child: Container(
            width: 220,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.black12,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Icon(Icons.location_on,
                      color: me ? Colors.white : SLineColors.accentA, size: 22),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(label,
                        style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: me ? Colors.white : themeCtrl.text)),
                  ),
                ]),
                if (lat != null && lng != null) ...[
                  const SizedBox(height: 4),
                  Text('$lat, $lng',
                      style: TextStyle(
                          fontSize: 11,
                          color: me ? Colors.white70 : themeCtrl.muted)),
                ],
                const SizedBox(height: 6),
                Text('Открыть в картах',
                    style: TextStyle(
                        fontSize: 12,
                        color: me ? Colors.white70 : SLineColors.accentA)),
              ],
            ),
          ),
        );
      case 'poll':
        Map<String, dynamic> poll = {};
        try {
          poll = jsonDecode(m.content) as Map<String, dynamic>;
        } catch (_) {}
        final q = (poll['q'] ?? '').toString();
        final opts = (poll['opts'] as List?) ?? [];
        var total = 0;
        for (final o in opts) {
          if (o is Map) {
            final v = o['votes'];
            if (v is List) total += v.length;
          }
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(q,
                style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: me ? Colors.white : themeCtrl.text)),
            const SizedBox(height: 8),
            for (var i = 0; i < opts.length; i++)
              if (opts[i] is Map)
                Builder(builder: (_) {
                  final o = Map<String, dynamic>.from(opts[i] as Map);
                  final votes = (o['votes'] is List)
                      ? (o['votes'] as List).map((e) => e.toString()).toList()
                      : <String>[];
                  final pct =
                      total == 0 ? 0.0 : (votes.length / total * 100);
                  final mine = votes.contains(widget.user.uid);
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: InkWell(
                      onTap: () => _votePoll(m, i),
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        width: 220,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 8),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                              color: me
                                  ? Colors.white38
                                  : themeCtrl.line),
                        ),
                        child: Stack(children: [
                          Positioned.fill(
                            child: FractionallySizedBox(
                              alignment: Alignment.centerLeft,
                              widthFactor: (pct / 100).clamp(0.0, 1.0),
                              child: Container(
                                decoration: BoxDecoration(
                                  color: me
                                      ? Colors.white24
                                      : SLineColors.accentA
                                          .withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                            ),
                          ),
                          Row(
                            mainAxisAlignment:
                                MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Text(
                                  '${o['t']}${mine ? ' ✓' : ''}',
                                  style: TextStyle(
                                      fontSize: 13,
                                      color: me
                                          ? Colors.white
                                          : themeCtrl.text),
                                ),
                              ),
                              Text('${pct.round()}%',
                                  style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: me
                                          ? Colors.white70
                                          : themeCtrl.muted)),
                            ],
                          ),
                        ]),
                      ),
                    ),
                  );
                }),
          ],
        );
      default:
        final plain = sanitizeChatText(m.content).trim();
        // TG emoji games: 🏀 ⚽ 🎯 🎰 🎲
        final game = TgEmojiGame.detect(plain);
        if (game != null) {
          return TgEmojiGame(kind: game, msgId: m.id);
        }
        return Text(plain,
            style: TextStyle(color: me ? Colors.white : themeCtrl.text));
    }
  }
}

/// Мини-игры эмодзи как в Telegram (баскетбол / слоты / кости)
class TgEmojiGame extends StatefulWidget {
  final String kind; // basket | slots | dice
  final String msgId;
  const TgEmojiGame({super.key, required this.kind, required this.msgId});

  static String? detect(String text) {
    final pure = text
        .replaceAll('\uFE0F', '')
        .replaceAll(RegExp(r'\s'), '')
        .trim();
    if (pure == '🏀' || pure == '⚽' || pure == '🎯') return 'basket';
    if (pure == '🎰') return 'slots';
    if (pure == '🎲') return 'dice';
    return null;
  }

  static double _hash(String s) {
    var h = 2166136261;
    for (final c in s.codeUnits) {
      h ^= c;
      h = (h * 16777619) & 0xFFFFFFFF;
    }
    return (h & 0xFFFFFFFF) / 4294967296.0;
  }

  @override
  State<TgEmojiGame> createState() => _TgEmojiGameState();
}

class _TgEmojiGameState extends State<TgEmojiGame>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  late final bool scored;
  late final int diceFace;
  late final List<String> reels;

  @override
  void initState() {
    super.initState();
    final r = TgEmojiGame._hash('${widget.msgId}:${widget.kind}');
    scored = r < 0.38;
    diceFace = 1 + (TgEmojiGame._hash('${widget.msgId}:dice') * 6).floor() % 6;
    const sym = ['7', '🍋', '🍒', '🍇', '🔔', '⭐', '🍌'];
    reels = [
      sym[(TgEmojiGame._hash('${widget.msgId}:a') * sym.length).floor() %
          sym.length],
      sym[(TgEmojiGame._hash('${widget.msgId}:b') * sym.length).floor() %
          sym.length],
      sym[(TgEmojiGame._hash('${widget.msgId}:c') * sym.length).floor() %
          sym.length],
    ];
    _c = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1200))
      ..forward();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.kind == 'slots') return _slots();
    if (widget.kind == 'dice') return _dice();
    return _basket();
  }

  Widget _basket() {
    return SizedBox(
      width: 140,
      height: 168,
      child: ClipRect(
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, __) {
          final t = Curves.easeOutCubic.transform(_c.value);
          // ball path
          double bx, by, scale;
          if (scored) {
            // up into hoop then down through net
            if (t < 0.45) {
              final u = t / 0.45;
              bx = 0;
              by = -90 * Curves.easeOut.transform(u);
              scale = 1.0 - 0.15 * u;
            } else if (t < 0.7) {
              final u = (t - 0.45) / 0.25;
              bx = 0;
              by = -90 + 40 * u;
              scale = 0.85 - 0.25 * u;
            } else {
              final u = (t - 0.7) / 0.3;
              bx = 0;
              by = -50 + 58 * u;
              scale = 0.55;
            }
          } else {
            // miss to the side
            final u = t;
            bx = 48 * Curves.easeIn.transform(u);
            by = -85 * math.sin(u * math.pi) + 10 * u;
            scale = 1.0 - 0.1 * u;
          }
          return Stack(
            alignment: Alignment.center,
            children: [
              // backboard + rim
              Positioned(
                top: 8,
                child: Column(
                  children: [
                    Container(
                      width: 70,
                      height: 48,
                      decoration: BoxDecoration(
                        color: const Color(0xFFF5F5F5),
                        border: Border.all(
                            color: const Color(0xFFE74C3C), width: 3),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    Transform.translate(
                      offset: const Offset(0, -6),
                      child: Container(
                        width: 56,
                        height: 10,
                        decoration: BoxDecoration(
                          border: Border.all(
                              color: const Color(0xFFE74C3C), width: 4),
                          borderRadius: BorderRadius.circular(20),
                        ),
                      ),
                    ),
                    // net
                    CustomPaint(
                      size: const Size(48, 36),
                      painter: _NetPainter(),
                    ),
                  ],
                ),
              ),
              // ball
              Positioned(
                bottom: 18,
                child: Transform.translate(
                  offset: Offset(bx, by),
                  child: Transform.scale(
                    scale: scale,
                    child: Container(
                      width: 52,
                      height: 52,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          center: Alignment(-0.3, -0.3),
                          colors: [Color(0xFFFF9A3C), Color(0xFFD35400)],
                        ),
                        boxShadow: [
                          BoxShadow(
                              color: Colors.black38,
                              blurRadius: 8,
                              offset: Offset(0, 3)),
                        ],
                      ),
                      child: CustomPaint(painter: _BallLinesPainter()),
                    ),
                  ),
                ),
              ),
              if (scored && t > 0.55)
                ...List.generate(8, (i) {
                  final a = i * math.pi / 4;
                  final d = 30 + 40 * ((t - 0.55) / 0.45);
                  return Positioned(
                    left: 70 + math.cos(a) * d,
                    top: 50 + math.sin(a) * d,
                    child: Opacity(
                      opacity: (1 - ((t - 0.55) / 0.45)).clamp(0.0, 1.0),
                      child: Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: [
                            Colors.yellow,
                            Colors.pink,
                            Colors.lightGreen,
                            Colors.cyan
                          ][i % 4],
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  );
                }),
            ],
          );
        },
      ),
      ), // ClipRect
    );
  }

  Widget _slots() {
    // width 160 + padding давали OVERFLOWED BY ~8px — делаем шире и без лишних отступов
    return Container(
      width: 176,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFF5F5F5), Color(0xFFD0D0D0)],
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(color: Colors.black38, blurRadius: 12, offset: Offset(0, 4))
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: List.generate(3, (i) {
          return AnimatedBuilder(
            animation: _c,
            builder: (_, __) {
              final delay = i * 0.15;
              final local =
                  ((_c.value - delay) / (1 - delay)).clamp(0.0, 1.0);
              final blur = (1 - Curves.easeOut.transform(local)) * 2;
              return Container(
                width: 42,
                height: 52,
                margin: EdgeInsets.only(left: i == 0 ? 0 : 6),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: const Color(0xFF1A1A1A),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Opacity(
                  opacity: 0.4 + 0.6 * local,
                  child: Text(
                    reels[i],
                    style: TextStyle(
                      fontSize: 24,
                      color: Colors.white,
                      shadows: blur > 0.2
                          ? [Shadow(color: Colors.white24, blurRadius: blur * 4)]
                          : null,
                    ),
                  ),
                ),
              );
            },
          );
        }),
      ),
    );
  }

  Widget _dice() {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) {
        final rot = _c.value * math.pi * 2;
        final scale = 0.5 + 0.5 * Curves.elasticOut.transform(_c.value);
        return Transform.rotate(
          angle: rot,
          child: Transform.scale(
            scale: scale,
            child: Container(
              width: 64,
              height: 64,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: const [
                  BoxShadow(
                      color: Colors.black38,
                      blurRadius: 10,
                      offset: Offset(0, 4))
                ],
              ),
              child: Text('$diceFace',
                  style: const TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF222222))),
            ),
          ),
        );
      },
    );
  }
}

class _NetPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = Colors.white54
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;
    for (var i = 0; i < 6; i++) {
      final x = size.width * (i / 5);
      canvas.drawLine(Offset(x * 0.85 + size.width * 0.075, 0),
          Offset(x, size.height), p);
    }
    for (var j = 1; j < 4; j++) {
      final y = size.height * (j / 4);
      canvas.drawLine(Offset(size.width * 0.08, y),
          Offset(size.width * 0.92, y), p);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _BallLinesPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = const Color(0xFF2C1810).withValues(alpha: 0.55)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    final c = Offset(size.width / 2, size.height / 2);
    canvas.drawLine(
        Offset(c.dx, 4), Offset(c.dx, size.height - 4), p);
    canvas.drawLine(
        Offset(4, c.dy), Offset(size.width - 4, c.dy), p);
    canvas.drawArc(
        Rect.fromCenter(center: c, width: size.width * 0.7, height: size.height),
        -0.8,
        1.6,
        false,
        p);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _SwipeReply extends StatefulWidget {
  final Widget child;
  final VoidCallback onReply;
  final VoidCallback? onSwipeBack;
  const _SwipeReply({
    required this.child,
    required this.onReply,
    this.onSwipeBack,
  });
  @override
  State<_SwipeReply> createState() => _SwipeReplyState();
}

class _SwipeReplyState extends State<_SwipeReply> {
  double dx = 0;
  @override
  Widget build(BuildContext context) {
    // Только свайп влево = ответ. Выход из чата — свайп всего экрана.
    return GestureDetector(
      onHorizontalDragUpdate: (d) {
        // только влево (ответ)
        if (d.delta.dx > 0 && dx >= 0) return;
        setState(() => dx = (dx + d.delta.dx).clamp(-72.0, 0.0));
      },
      onHorizontalDragEnd: (_) {
        if (dx < -36) {
          widget.onReply();
        }
        setState(() => dx = 0);
      },
      child: Transform.translate(offset: Offset(dx, 0), child: widget.child),
    );
  }
}

// ── stories stub ────────────────────────────────────────────

/// GIF picker (Tenor) — как на веб-версии
class _GifPickerSheet extends StatefulWidget {
  final ValueChanged<String> onPick;
  const _GifPickerSheet({required this.onPick});
  @override
  State<_GifPickerSheet> createState() => _GifPickerSheetState();
}

class _GifPickerSheetState extends State<_GifPickerSheet> {
  final qCtrl = TextEditingController();
  List<String> urls = [];
  bool loading = true;
  Timer? _debounce;

  static const cats = <(String, String)>[
    ('', 'Тренды'),
    ('funny', 'Смешное'),
    ('love', 'Любовь'),
    ('reaction', 'Реакции'),
    ('wow', 'Вау'),
    ('sad', 'Грусть'),
  ];
  String cat = '';

  @override
  void initState() {
    super.initState();
    _load('');
  }

  @override
  void dispose() {
    _debounce?.cancel();
    qCtrl.dispose();
    super.dispose();
  }

  Future<void> _load(String q) async {
    setState(() => loading = true);
    final list = await TenorGif.search(q);
    if (mounted) {
      setState(() {
        urls = list;
        loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final h = MediaQuery.of(context).size.height * 0.55;
    return SizedBox(
      height: h,
      child: Column(children: [
        const SizedBox(height: 8),
        Container(
          width: 36,
          height: 4,
          decoration: BoxDecoration(
              color: themeCtrl.muted.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(2)),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
          child: Row(children: [
            Expanded(
              child: TextField(
                controller: qCtrl,
                decoration: InputDecoration(
                  hintText: 'Поиск GIF',
                  prefixIcon: const Icon(Icons.search, size: 20),
                  filled: true,
                  fillColor: themeCtrl.input,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
                onChanged: (v) {
                  _debounce?.cancel();
                  _debounce = Timer(const Duration(milliseconds: 350), () {
                    _load(v.trim());
                  });
                },
              ),
            ),
            IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(context)),
          ]),
        ),
        SizedBox(
          height: 36,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            children: [
              for (final c in cats)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    label: Text(c.$2, style: const TextStyle(fontSize: 12)),
                    selected: cat == c.$1,
                    selectedColor: SLineColors.accentA,
                    labelStyle: TextStyle(
                        color: cat == c.$1 ? Colors.white : themeCtrl.muted),
                    onSelected: (_) {
                      setState(() => cat = c.$1);
                      qCtrl.text = c.$1;
                      _load(c.$1);
                    },
                    visualDensity: VisualDensity.compact,
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Expanded(
          child: loading
              ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
              : urls.isEmpty
                  ? Center(
                      child: Text('Ничего не найдено',
                          style: TextStyle(color: themeCtrl.muted)))
                  : GridView.builder(
                      padding: const EdgeInsets.fromLTRB(10, 0, 10, 16),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                        crossAxisSpacing: 6,
                        mainAxisSpacing: 6,
                      ),
                      itemCount: urls.length,
                      itemBuilder: (_, i) {
                        final u = urls[i];
                        return InkWell(
                          onTap: () => widget.onPick(u),
                          borderRadius: BorderRadius.circular(14),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(14),
                            child: Image.network(
                              u,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Container(
                                  color: themeCtrl.input,
                                  child: const Icon(Icons.broken_image)),
                            ),
                          ),
                        );
                      },
                    ),
        ),
      ]),
    );
  }
}

class _NetVideo extends StatefulWidget {
  final String url;
  final bool circle;
  const _NetVideo({required this.url, this.circle = false});
  @override
  State<_NetVideo> createState() => _NetVideoState();
}

class _NetVideoState extends State<_NetVideo> {
  VideoPlayerController? c;
  String? _err;
  /// Кружок: true = чуть больше на месте + звук (как TG, не fullscreen)
  bool _circleExpanded = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    var u = widget.url.trim();
    if (u.isEmpty) {
      if (mounted) setState(() => _err = 'empty');
      return;
    }
    // B2 private → signed URL
    try {
      if (B2Storage.isB2Url(u)) {
        u = await B2Storage.resolveDownloadUrl(u);
      }
    } catch (_) {}
    Object? lastErr;
    // Несколько стратегий: local → download file → networkUrl → network без headers
    final strategies = <Future<VideoPlayerController> Function()>[
      () async {
        if (u.startsWith('data:')) {
          final comma = u.indexOf(',');
          if (comma < 0) throw Exception('bad data uri');
          final bytes = base64Decode(u.substring(comma + 1));
          final dir = await getTemporaryDirectory();
          final f = File(
              '${dir.path}/vid_${DateTime.now().millisecondsSinceEpoch}.mp4');
          await f.writeAsBytes(bytes, flush: true);
          final ctrl = VideoPlayerController.file(f);
          await ctrl.initialize();
          return ctrl;
        }
        if (!u.startsWith('http://') && !u.startsWith('https://')) {
          final f = File(u);
          if (!await f.exists()) throw Exception('local missing');
          final ctrl = VideoPlayerController.file(f);
          await ctrl.initialize();
          return ctrl;
        }
        throw Exception('skip');
      },
      () async {
        final f = await downloadMediaToTemp(u, extHint: 'mp4');
        final ctrl = VideoPlayerController.file(f);
        await ctrl.initialize();
        return ctrl;
      },
      () async {
        final ctrl = VideoPlayerController.networkUrl(Uri.parse(u));
        await ctrl.initialize();
        return ctrl;
      },
      () async {
        final ctrl = VideoPlayerController.networkUrl(
          Uri.parse(u),
          httpHeaders: kMediaHeaders,
        );
        await ctrl.initialize();
        return ctrl;
      },
    ];
    for (final s in strategies) {
      try {
        final ctrl = await s();
        await ctrl.setLooping(widget.circle);
        // В ленте кружок без звука (как TG); звук — при открытии
        await ctrl.setVolume(widget.circle ? 0 : 1);
        if (widget.circle) await ctrl.play();
        if (!mounted) {
          await ctrl.dispose();
          return;
        }
        setState(() {
          c = ctrl;
          _err = null;
        });
        return;
      } catch (e) {
        lastErr = e;
      }
    }
    if (mounted) setState(() => _err = '$lastErr');
  }

  @override
  void dispose() {
    c?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_err != null) {
      return GestureDetector(
        onTap: () {
          setState(() {
            _err = null;
            c?.dispose();
            c = null;
          });
          _init();
        },
        child: SizedBox(
          width: widget.circle ? 150 : 220,
          height: widget.circle ? 150 : 120,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.replay, size: 28, color: themeCtrl.muted),
                const SizedBox(height: 6),
                Text('Нажмите, чтобы повторить',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: themeCtrl.muted, fontSize: 11)),
              ],
            ),
          ),
        ),
      );
    }
    final ok = c != null && c!.value.isInitialized;
    if (widget.circle) {
      // Как в TG: на месте, чуть больше при тапе, со звуком; без fullscreen
      final size = _circleExpanded ? 220.0 : 120.0;
      final ringW = _circleExpanded ? 3.5 : 2.0;
      return GestureDetector(
        onTap: () async {
          if (!ok) return;
          final next = !_circleExpanded;
          setState(() => _circleExpanded = next);
          try {
            if (next) {
              await c!.setVolume(1);
              await c!.seekTo(Duration.zero);
              await c!.play();
            } else {
              await c!.setVolume(0);
              if (!c!.value.isPlaying) await c!.play();
            }
          } catch (_) {}
          if (mounted) setState(() {});
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          width: size,
          height: size,
          child: Stack(
            alignment: Alignment.center,
            clipBehavior: Clip.none,
            children: [
              ClipOval(
                child: SizedBox(
                  width: size,
                  height: size,
                  child: ok
                      ? FittedBox(
                          fit: BoxFit.cover,
                          child: SizedBox(
                            width: c!.value.size.width,
                            height: c!.value.size.height,
                            child: VideoPlayer(c!),
                          ),
                        )
                      : const Center(
                          child:
                              CircularProgressIndicator(strokeWidth: 2)),
                ),
              ),
              if (ok)
                Positioned.fill(
                  child: IgnorePointer(
                    child: AnimatedBuilder(
                      animation: c!,
                      builder: (_, __) {
                        final v = c!.value;
                        final t = v.duration.inMilliseconds == 0
                            ? 0.0
                            : v.position.inMilliseconds /
                                v.duration.inMilliseconds;
                        return CustomPaint(
                          painter: _CircleProgressPainter(
                            progress: t.clamp(0.0, 1.0),
                            color: Colors.white.withValues(alpha: 0.9),
                            strokeWidth: ringW,
                          ),
                        );
                      },
                    ),
                  ),
                ),
              if (_circleExpanded && ok)
                Positioned(
                  bottom: 8,
                  child: Icon(
                    c!.value.isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled,
                    color: Colors.white.withValues(alpha: 0.9),
                    size: 28,
                  ),
                ),
            ],
          ),
        ),
      );
    }
    final child = ok
        ? AspectRatio(
            aspectRatio:
                c!.value.aspectRatio == 0 ? 1 : c!.value.aspectRatio,
            child: VideoPlayer(c!))
        : const SizedBox(
            width: 220,
            height: 120,
            child: Center(
                child: CircularProgressIndicator(strokeWidth: 2)));
    return GestureDetector(
      onTap: () {
        if (!ok) return;
        c!.value.isPlaying ? c!.pause() : c!.play();
        setState(() {});
      },
      child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(width: 220, child: child)),
    );
  }

  Future<void> _openCircleViewer() async {
    if (c == null || !c!.value.isInitialized) return;
    await c!.pause();
    if (!mounted) return;
    // Как в TG: чуть больше с места, не на весь экран
    await showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'circle',
      barrierColor: Colors.black.withValues(alpha: 0.45),
      transitionDuration: const Duration(milliseconds: 260),
      pageBuilder: (ctx, a1, a2) {
        return _CircleViewerDialog(url: widget.url);
      },
      transitionBuilder: (ctx, anim, _, child) {
        final curved =
            CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.42, end: 1).animate(curved),
            child: child,
          ),
        );
      },
    );
    if (mounted && c != null) {
      try {
        await c!.setVolume(0);
        await c!.play();
      } catch (_) {}
      setState(() {});
    }
  }
}



/// Плеер аудио-файла (как Spotify-лайт): обложка-нота, seek, play/pause
class _AudioFilePlayerSheet extends StatefulWidget {
  final String url;
  final String title;
  const _AudioFilePlayerSheet({required this.url, required this.title});
  @override
  State<_AudioFilePlayerSheet> createState() => _AudioFilePlayerSheetState();
}

class _AudioFilePlayerSheetState extends State<_AudioFilePlayerSheet> {
  final AudioPlayer _p = AudioPlayer();
  Duration _pos = Duration.zero;
  Duration _dur = Duration.zero;
  bool _playing = false;
  bool _ready = false;
  String? _err;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      _p.onPositionChanged.listen((d) {
        if (mounted) setState(() => _pos = d);
      });
      _p.onDurationChanged.listen((d) {
        if (mounted) setState(() => _dur = d);
      });
      _p.onPlayerComplete.listen((_) {
        if (mounted) setState(() {
          _playing = false;
          _pos = Duration.zero;
        });
      });
      final u = widget.url.trim();
      if (u.startsWith('http')) {
        try {
          final f = await downloadMediaToTemp(u, extHint: 'm4a');
          await _p.play(DeviceFileSource(f.path));
        } catch (_) {
          await _p.play(UrlSource(u));
        }
      } else if (u.startsWith('data:')) {
        final comma = u.indexOf(',');
        final bytes = base64Decode(u.substring(comma + 1));
        final dir = await getTemporaryDirectory();
        final f = File(
            '${dir.path}/aud_${DateTime.now().millisecondsSinceEpoch}.m4a');
        await f.writeAsBytes(bytes, flush: true);
        await _p.play(DeviceFileSource(f.path));
      } else {
        await _p.play(DeviceFileSource(u));
      }
      if (mounted) {
        setState(() {
          _ready = true;
          _playing = true;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _err = '$e');
    }
  }

  @override
  void dispose() {
    _p.dispose();
    super.dispose();
  }

  String _fmt(Duration d) {
    final s = d.inSeconds;
    return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final maxMs = _dur.inMilliseconds <= 0 ? 1.0 : _dur.inMilliseconds.toDouble();
    final posMs = _pos.inMilliseconds.clamp(0, maxMs.toInt()).toDouble();
    return Container(
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
      decoration: BoxDecoration(
        color: themeCtrl.light ? Colors.white : const Color(0xFF1C1C1E),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: themeCtrl.muted.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF4C7CF3), Color(0xFF6D5DF6)],
                ),
              ),
              child: const Icon(Icons.music_note_rounded,
                  size: 56, color: Colors.white),
            ),
            const SizedBox(height: 16),
            Text(
              widget.title,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: themeCtrl.text,
              ),
            ),
            const SizedBox(height: 4),
            Text('Аудиофайл',
                style: TextStyle(fontSize: 13, color: themeCtrl.muted)),
            if (_err != null) ...[
              const SizedBox(height: 10),
              Text(_err!,
                  style: const TextStyle(color: Color(0xFFE53955), fontSize: 12)),
            ],
            const SizedBox(height: 18),
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 3,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                activeTrackColor: SLineColors.accentA,
                inactiveTrackColor: themeCtrl.muted.withValues(alpha: 0.25),
                thumbColor: SLineColors.accentA,
              ),
              child: Slider(
                value: posMs,
                max: maxMs,
                onChanged: (v) {
                  setState(() => _pos = Duration(milliseconds: v.round()));
                },
                onChangeEnd: (v) async {
                  await _p.seek(Duration(milliseconds: v.round()));
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(_fmt(_pos),
                      style: TextStyle(fontSize: 12, color: themeCtrl.muted)),
                  Text(_fmt(_dur),
                      style: TextStyle(fontSize: 12, color: themeCtrl.muted)),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  iconSize: 32,
                  onPressed: () async {
                    final next = _pos - const Duration(seconds: 10);
                    await _p.seek(next < Duration.zero ? Duration.zero : next);
                  },
                  icon: Icon(Icons.replay_10, color: themeCtrl.text),
                ),
                const SizedBox(width: 8),
                Material(
                  color: SLineColors.accentA,
                  shape: const CircleBorder(),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: !_ready
                        ? null
                        : () async {
                            if (_playing) {
                              await _p.pause();
                              setState(() => _playing = false);
                            } else {
                              await _p.resume();
                              setState(() => _playing = true);
                            }
                          },
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Icon(
                        _playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                        color: Colors.white,
                        size: 36,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  iconSize: 32,
                  onPressed: () async {
                    final next = _pos + const Duration(seconds: 10);
                    final cap = _dur > Duration.zero ? _dur : next;
                    await _p.seek(next > cap ? cap : next);
                  },
                  icon: Icon(Icons.forward_10, color: themeCtrl.text),
                ),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: 'Скачать',
                  iconSize: 28,
                  onPressed: () async {
                    try {
                      final u = widget.url.trim();
                      final name = widget.title.isNotEmpty
                          ? widget.title
                          : 'audio.mp3';
                      final ext = name.contains('.')
                          ? name.split('.').last
                          : 'mp3';
                      final f = await downloadMediaToTemp(u, extHint: ext);
                      Directory dir;
                      try {
                        dir = await getApplicationDocumentsDirectory();
                      } catch (_) {
                        dir = await getTemporaryDirectory();
                      }
                      final safe = name.replaceAll(RegExp(r'[^\w\.\-а-яА-ЯёЁ]+'), '_');
                      final out = File('${dir.path}/$safe');
                      await f.copy(out.path);
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Сохранено: ${out.path}'),
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      }
                    } catch (e) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Не удалось скачать: $e')),
                        );
                      }
                    }
                  },
                  icon: Icon(Icons.download_rounded, color: themeCtrl.text),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CircleProgressPainter extends CustomPainter {
  final double progress;
  final Color color;
  final double strokeWidth;
  _CircleProgressPainter({
    required this.progress,
    required this.color,
    this.strokeWidth = 3.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = strokeWidth;
    final rect = Offset(stroke / 2, stroke / 2) &
        Size(size.width - stroke, size.height - stroke);
    final bg = Paint()
      ..color = Colors.white.withValues(alpha: 0.25)
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;
    final fg = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, -1.5708, 6.2832, false, bg);
    canvas.drawArc(rect, -1.5708, 6.2832 * progress, false, fg);
  }

  @override
  bool shouldRepaint(covariant _CircleProgressPainter old) =>
      old.progress != progress;
}

/// Полноэкранный просмотр кружка со звуком и прогрессом (как TG)
class _CircleViewerDialog extends StatefulWidget {
  final String url;
  const _CircleViewerDialog({required this.url});
  @override
  State<_CircleViewerDialog> createState() => _CircleViewerDialogState();
}

class _CircleViewerDialogState extends State<_CircleViewerDialog> {
  VideoPlayerController? c;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final u = widget.url.trim();
    VideoPlayerController? ctrl;
    try {
      if (!u.startsWith('http')) {
        ctrl = VideoPlayerController.file(File(u));
      } else {
        try {
          final f = await downloadMediaToTemp(u, extHint: 'mp4');
          ctrl = VideoPlayerController.file(f);
        } catch (_) {
          ctrl = VideoPlayerController.networkUrl(Uri.parse(u));
        }
      }
      await ctrl.initialize();
      await ctrl.setLooping(true);
      await ctrl.setVolume(1);
      await ctrl.play();
      if (mounted) setState(() => c = ctrl);
    } catch (_) {
      await ctrl?.dispose();
    }
  }

  @override
  void dispose() {
    c?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Чуть больше миниатюры (120), не full-screen
    final size = (MediaQuery.of(context).size.shortestSide * 0.62)
        .clamp(200.0, 300.0);
    final ok = c != null && c!.value.isInitialized;
    return Material(
      color: Colors.transparent,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: size,
              height: size,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  ClipOval(
                    child: Container(
                      width: size,
                      height: size,
                      color: Colors.black,
                      child: ok
                          ? FittedBox(
                              fit: BoxFit.cover,
                              child: SizedBox(
                                width: c!.value.size.width,
                                height: c!.value.size.height,
                                child: VideoPlayer(c!),
                              ),
                            )
                          : const Center(
                              child: CircularProgressIndicator(
                                  color: Colors.white)),
                    ),
                  ),
                  if (ok)
                    Positioned.fill(
                      child: AnimatedBuilder(
                        animation: c!,
                        builder: (_, __) {
                          final v = c!.value;
                          final t = v.duration.inMilliseconds == 0
                              ? 0.0
                              : v.position.inMilliseconds /
                                  v.duration.inMilliseconds;
                          return CustomPaint(
                            painter: _CircleProgressPainter(
                              progress: t.clamp(0.0, 1.0),
                              color: Colors.white,
                            ),
                          );
                        },
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            IconButton(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.close, color: Colors.white, size: 28),
            ),
          ],
        ),
      ),
    );
  }
}

/// Полноэкранный просмотр фото/GIF/видео с зумом
class _MediaViewerPage extends StatefulWidget {
  final String url;
  final bool isVideo;
  const _MediaViewerPage({required this.url, required this.isVideo});
  @override
  State<_MediaViewerPage> createState() => _MediaViewerPageState();
}

class _MediaViewerPageState extends State<_MediaViewerPage> {
  VideoPlayerController? _vc;
  final _transform = TransformationController();

  @override
  void initState() {
    super.initState();
    if (widget.isVideo) {
      _vc = VideoPlayerController.networkUrl(Uri.parse(widget.url))
        ..initialize().then((_) {
          if (mounted) {
            setState(() {});
            _vc?.play();
          }
        });
    }
  }

  @override
  void dispose() {
    _vc?.dispose();
    _transform.dispose();
    super.dispose();
  }

  Widget _image() {
    final u = widget.url;
    if (u.startsWith('data:image')) {
      try {
        final comma = u.indexOf(',');
        final bytes = base64Decode(u.substring(comma + 1));
        return Image.memory(bytes, fit: BoxFit.contain);
      } catch (_) {
        return const Text('Не удалось открыть',
            style: TextStyle(color: Colors.white54));
      }
    }
    return Image.network(
      u,
      fit: BoxFit.contain,
      loadingBuilder: (_, child, p) {
        if (p == null) return child;
        return const Center(
            child: CircularProgressIndicator(color: Colors.white54));
      },
      errorBuilder: (_, __, ___) => const Text('Не загрузилось',
          style: TextStyle(color: Colors.white54)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(children: [
          Center(
            child: widget.isVideo
                ? (_vc != null && _vc!.value.isInitialized
                    ? GestureDetector(
                        onTap: () {
                          _vc!.value.isPlaying
                              ? _vc!.pause()
                              : _vc!.play();
                          setState(() {});
                        },
                        child: InteractiveViewer(
                          minScale: 0.5,
                          maxScale: 4,
                          child: AspectRatio(
                            aspectRatio: _vc!.value.aspectRatio == 0
                                ? 16 / 9
                                : _vc!.value.aspectRatio,
                            child: VideoPlayer(_vc!),
                          ),
                        ),
                      )
                    : const CircularProgressIndicator(color: Colors.white54))
                : InteractiveViewer(
                    transformationController: _transform,
                    minScale: 0.5,
                    maxScale: 5,
                    child: _image(),
                  ),
          ),
          Positioned(
            top: 4,
            left: 4,
            child: IconButton(
              icon: const Icon(Icons.close, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
          ),
          if (widget.isVideo && _vc != null && _vc!.value.isInitialized)
            Positioned(
              bottom: 24,
              left: 0,
              right: 0,
              child: IconButton(
                icon: Icon(
                  _vc!.value.isPlaying
                      ? Icons.pause_circle_filled
                      : Icons.play_circle_filled,
                  color: Colors.white,
                  size: 48,
                ),
                onPressed: () {
                  _vc!.value.isPlaying ? _vc!.pause() : _vc!.play();
                  setState(() {});
                },
              ),
            ),
        ]),
      ),
    );
  }
}

/// Запись кружка как в Telegram: зажал → вверх = замок, влево = отмена
class _InAppCircleRecorder extends StatefulWidget {
  const _InAppCircleRecorder();
  @override
  State<_InAppCircleRecorder> createState() => _InAppCircleRecorderState();
}

class _InAppCircleRecorderState extends State<_InAppCircleRecorder>
    with SingleTickerProviderStateMixin {
  CameraController? _cam;
  bool _ready = false;
  bool _recording = false;
  bool _locked = false;
  bool _cancelZone = false;
  String? _error;
  DateTime? _started;
  int _ms = 0;
  Timer? _tick;
  Offset _drag = Offset.zero;
  int _camIndex = 0;
  List<CameraDescription> _cams = [];
  late final AnimationController _pulse;
  // Непрерывный жест без отпускания (как голосовое)
  int? _activePointer;
  Offset _pointerOrigin = Offset.zero;
  bool _holding = false;
  Offset _pendingDrag = Offset.zero; // накопленный свайп до старта записи

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _init();
  }

  Future<void> _init() async {
    try {
      final cam = await Permission.camera.request();
      final mic = await Permission.microphone.request();
      if (!cam.isGranted || !mic.isGranted) {
        setState(() => _error = 'Нужен доступ к камере и микрофону');
        return;
      }
      _cams = await availableCameras();
      if (_cams.isEmpty) {
        setState(() => _error = 'Камера не найдена');
        return;
      }
      // Фронт приоритетнее
      final front = _cams.indexWhere(
          (c) => c.lensDirection == CameraLensDirection.front);
      if (front >= 0) _camIndex = front;
      await _openCam(_camIndex);
      // Как голосовое: сразу начинаем запись (пользователь уже зажал)
      if (mounted && _ready) await _startRec();
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  Future<void> _openCam(int idx) async {
    try {
      final old = _cam;
      _cam = null;
      await old?.dispose();
      final c = CameraController(
        _cams[idx],
        ResolutionPreset.medium,
        enableAudio: true,
        imageFormatGroup: ImageFormatGroup.yuv420,
      );
      await c.initialize();
      if (!mounted) {
        await c.dispose();
        return;
      }
      setState(() {
        _cam = c;
        _ready = true;
        _camIndex = idx;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = 'Камера: $e');
    }
  }

  Future<void> _flip() async {
    if (_cams.length < 2 || _recording) return;
    final next = (_camIndex + 1) % _cams.length;
    await _openCam(next);
  }

  Future<void> _startRec() async {
    final c = _cam;
    if (c == null || !c.value.isInitialized || _recording) return;
    try {
      // Оптимистично помечаем запись — жесты работают сразу, без ожидания
      setState(() {
        _recording = true;
        _locked = false;
        _cancelZone = false;
        _drag = _pendingDrag;
      });
      await c.startVideoRecording();
      _tick?.cancel();
      _started = DateTime.now();
      _ms = 0;
      _tick = Timer.periodic(const Duration(milliseconds: 50), (_) {
        if (!mounted || !_recording) return;
        setState(() {
          _ms = DateTime.now().difference(_started!).inMilliseconds;
        });
      });
      // Если палец уже уехал вверх/влево до готовности камеры — применить
      if (mounted) _applyDrag(_pendingDrag);
      HapticFeedback.mediumImpact();
      Future.delayed(const Duration(seconds: 60), () async {
        if (_recording && mounted && !_locked) await _finish(send: true);
      });
    } catch (e) {
      if (mounted) {
        setState(() => _recording = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Запись: $e')));
      }
    }
  }

  void _applyDrag(Offset o) {
    if (_locked) return;
    // Пороги как в TG: небольшой свайп уже срабатывает
    final cancel = o.dx < -40;
    final lock = o.dy < -40 && !cancel;
    if (!mounted) return;
    setState(() {
      _drag = o;
      _pendingDrag = o;
      _cancelZone = cancel;
      if (lock) {
        _locked = true;
        _cancelZone = false;
        _activePointer = null;
        _holding = false;
        HapticFeedback.mediumImpact();
      }
    });
  }

  void _onPointerDown(PointerDownEvent e) {
    if (_locked) return;
    if (_activePointer != null && _activePointer != e.pointer) return;
    _activePointer = e.pointer;
    _pointerOrigin = e.position;
    _holding = true;
    _pendingDrag = Offset.zero;
    _drag = Offset.zero;
    _cancelZone = false;
    HapticFeedback.mediumImpact();
    if (!_recording && _ready) {
      _startRec();
    }
  }

  void _onPointerMove(PointerMoveEvent e) {
    if (_locked) return;
    if (_activePointer != e.pointer) return;
    final o = e.position - _pointerOrigin;
    _pendingDrag = o;
    if (_recording || _holding) {
      _applyDrag(o);
    }
  }

  void _onPointerUp(PointerUpEvent e) {
    if (_activePointer != null && _activePointer != e.pointer) return;
    _activePointer = null;
    _holding = false;
    if (!_recording) return;
    if (_locked) return; // ждём кнопки Отправить / Отмена
    if (_cancelZone) {
      _finish(send: false);
    } else {
      _finish(send: true);
    }
  }

  void _onPointerCancel(PointerCancelEvent e) {
    if (_activePointer != e.pointer) return;
    _activePointer = null;
    _holding = false;
  }

  Future<void> _finish({required bool send}) async {
    final c = _cam;
    if (!_recording || c == null) {
      if (mounted) Navigator.pop(context);
      return;
    }
    _tick?.cancel();
    _tick = null;
    try {
      final file = await c.stopVideoRecording();
      setState(() {
        _recording = false;
        _locked = false;
        _cancelZone = false;
      });
      if (!send) {
        try {
          await File(file.path).delete();
        } catch (_) {}
        if (mounted) Navigator.pop(context);
        return;
      }
      var path = file.path;
      if (!path.toLowerCase().endsWith('.mp4')) {
        final dir = await getTemporaryDirectory();
        final out = File(
            '${dir.path}/circle_${DateTime.now().millisecondsSinceEpoch}.mp4');
        await File(path).copy(out.path);
        path = out.path;
      }
      // слишком короткие — отмена
      if (_ms < 400) {
        try {
          await File(path).delete();
        } catch (_) {}
        if (mounted) Navigator.pop(context);
        return;
      }
      if (mounted) Navigator.pop(context, path);
    } catch (e) {
      if (mounted) {
        setState(() => _recording = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Кружок: $e')));
        Navigator.pop(context);
      }
    }
  }

  String get _timeLabel {
    final s = _ms ~/ 1000;
    final frac = (_ms % 1000) ~/ 100;
    return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')},$frac';
  }

  @override
  void dispose() {
    _tick?.cancel();
    _pulse.dispose();
    _cam?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final progress = (_ms / 60000).clamp(0.0, 1.0);
    final bottomPad = MediaQuery.of(context).padding.bottom;
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0C),
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Камера не перехватывает жесты
          if (_ready && _cam != null)
            Positioned.fill(
              child: IgnorePointer(
                child: Opacity(
                  opacity: 0.25,
                  child: FittedBox(
                    fit: BoxFit.cover,
                    child: SizedBox(
                      width: _cam!.value.previewSize?.height ?? 400,
                      height: _cam!.value.previewSize?.width ?? 400,
                      child: CameraPreview(_cam!),
                    ),
                  ),
                ),
              ),
            ),
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    colors: [
                      Colors.black.withValues(alpha: 0.15),
                      Colors.black.withValues(alpha: 0.85),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (_error != null)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(_error!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white70, fontSize: 16)),
              ),
            )
          else if (!_ready || _cam == null)
            const Center(
                child: CircularProgressIndicator(color: Colors.white54))
          else
            Center(
              child: IgnorePointer(
                child: SizedBox(
                  width: MediaQuery.of(context).size.width * 0.82,
                  height: MediaQuery.of(context).size.width * 0.82,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      if (_recording)
                        SizedBox.expand(
                          child: CustomPaint(
                            painter: _CircleProgressPainter(
                              progress: progress,
                              color: _cancelZone
                                  ? const Color(0xFFFF3B30)
                                  : const Color(0xFF3390EC),
                            ),
                          ),
                        ),
                      Padding(
                        padding: const EdgeInsets.all(6),
                        child: ClipOval(
                          child: AspectRatio(
                            aspectRatio: 1,
                            child: FittedBox(
                              fit: BoxFit.cover,
                              child: SizedBox(
                                width: _cam!.value.previewSize?.height ?? 300,
                                height: _cam!.value.previewSize?.width ?? 300,
                                child: CameraPreview(_cam!),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          // Полноэкранный слой жестов ПОВЕРХ камеры
          // зажал → вверх = замок, влево = отмена, отпустил = отправить
          if (!_locked)
            Positioned.fill(
              child: Listener(
                behavior: HitTestBehavior.opaque,
                onPointerDown: _onPointerDown,
                onPointerMove: _onPointerMove,
                onPointerUp: _onPointerUp,
                onPointerCancel: _onPointerCancel,
                child: const ColoredBox(color: Color(0x01000000)),
              ),
            ),
          // Таймер + Отмена (кликабельная когда locked)
          if (_recording)
            Positioned(
              left: 0,
              right: 0,
              bottom: 110 + bottomPad,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  AnimatedBuilder(
                    animation: _pulse,
                    builder: (_, __) => Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Color.lerp(
                          const Color(0xFFFF3B30),
                          const Color(0xFFFF3B30).withValues(alpha: 0.4),
                          _pulse.value,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (_locked)
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => _finish(send: false),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _timeLabel,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.9),
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(width: 14),
                            const Text(
                              'Отмена',
                              style: TextStyle(
                                color: Color(0xFFFF3B30),
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  else
                    Text(
                      _cancelZone
                          ? 'Отпустите, чтобы отменить'
                          : '$_timeLabel  ← Влево — отмена',
                      style: TextStyle(
                        color: _cancelZone
                            ? const Color(0xFFFF3B30)
                            : Colors.white.withValues(alpha: 0.9),
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.2,
                      ),
                    ),
                ],
              ),
            ),
          // Замок (свайп вверх)
          if (_recording && !_locked)
            Positioned(
              right: 28,
              bottom: 180 + bottomPad,
              child: IgnorePointer(
                child: Opacity(
                  opacity: (_drag.dy < -15 ? 1.0 : 0.45)
                      .clamp(0.35, 1.0)
                      .toDouble(),
                  child: Column(
                    children: [
                      Icon(Icons.lock_outline_rounded,
                          color: Colors.white.withValues(alpha: 0.85),
                          size: 26),
                      Icon(Icons.keyboard_arrow_up_rounded,
                          color: Colors.white.withValues(alpha: 0.55),
                          size: 22),
                    ],
                  ),
                ),
              ),
            ),
          if (_recording && _locked)
            Positioned(
              right: 36,
              bottom: 190 + bottomPad,
              child: Icon(Icons.pause_rounded,
                  color: Colors.white.withValues(alpha: 0.7), size: 28),
            ),
          // Левые кнопки
          if (!_recording)
            Positioned(
              left: 20,
              bottom: 28 + bottomPad,
              child: Row(
                children: [
                  _CircleSideBtn(
                    icon: Icons.cameraswitch_rounded,
                    onTap: _flip,
                  ),
                  const SizedBox(width: 12),
                  _CircleSideBtn(
                    icon: Icons.flash_off_rounded,
                    onTap: () {},
                  ),
                ],
              ),
            ),
          // Кнопка: locked → отправить; cancel zone → иконка удаления
          Positioned(
            right: 20,
            bottom: 20 + bottomPad,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                if (!_recording) {
                  if (_ready) _startRec();
                  return;
                }
                if (_locked) {
                  _finish(send: true);
                }
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _cancelZone
                      ? const Color(0xFFFF3B30)
                      : const Color(0xFF3390EC),
                  boxShadow: [
                    BoxShadow(
                      color: (_cancelZone
                              ? const Color(0xFFFF3B30)
                              : const Color(0xFF3390EC))
                          .withValues(alpha: 0.45),
                      blurRadius: 18,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: Icon(
                  _cancelZone
                      ? Icons.delete_outline_rounded
                      : _locked
                          ? Icons.send_rounded
                          : Icons.radio_button_checked,
                  color: Colors.white,
                  size: 32,
                ),
              ),
            ),
          ),
          // Отдельная кнопка «Отмена» снизу когда locked (надёжно)
          if (_recording && _locked)
            Positioned(
              left: 20,
              bottom: 28 + bottomPad,
              child: TextButton(
                onPressed: () => _finish(send: false),
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFFFF3B30),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
                child: const Text(
                  'Отмена',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
              ),
            ),
          // Закрыть (если ещё не пишем)
          if (!_recording)
            Positioned(
              top: MediaQuery.of(context).padding.top + 8,
              left: 8,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white70),
                onPressed: () => Navigator.pop(context),
              ),
            ),
        ],
      ),
    );
  }
}

class _CircleSideBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  const _CircleSideBtn({required this.icon, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.12),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 44,
          height: 44,
          child: Icon(icon, color: Colors.white70, size: 22),
        ),
      ),
    );
  }
}

class StoryViewer extends StatefulWidget {
  final String name;
  final String? avatar;
  final List<String> mediaUrls;
  const StoryViewer({
    super.key,
    required this.name,
    this.avatar,
    this.mediaUrls = const [],
  });
  @override
  State<StoryViewer> createState() => _StoryViewerState();
}

class _StoryViewerState extends State<StoryViewer>
    with SingleTickerProviderStateMixin {
  int idx = 0;
  late final AnimationController _fadeCtrl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 200))
    ..forward();

  bool _isVideo(String url) {
    final u = url.toLowerCase();
    if (u.startsWith('data:')) return u.startsWith('data:video');
    return u.contains('.mp4') ||
        u.contains('.webm') ||
        u.contains('.mov') ||
        u.contains('video');
  }

  Widget _storyImage(String url) {
    final u = url.trim();
    // Веб часто кладёт data:image/jpeg;base64,...
    if (u.startsWith('data:image')) {
      try {
        final comma = u.indexOf(',');
        if (comma < 0) throw Exception('bad data uri');
        final bytes = base64Decode(u.substring(comma + 1));
        return Image.memory(bytes,
            fit: BoxFit.contain, errorBuilder: (_, __, ___) => _fail(u));
      } catch (_) {
        return _fail(u);
      }
    }
    return Image.network(
      u,
      fit: BoxFit.contain,
      loadingBuilder: (_, child, p) {
        if (p == null) return child;
        return const Center(
            child: CircularProgressIndicator(color: Colors.white54));
      },
      errorBuilder: (_, __, ___) => _fail(u),
    );
  }

  Widget _fail(String u) {
    final short = u.length > 48 ? '${u.substring(0, 48)}…' : u;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.broken_image_outlined,
            color: Colors.white38, size: 48),
        const SizedBox(height: 12),
        const Text('Не загрузилось',
            style: TextStyle(color: Colors.white54)),
        const SizedBox(height: 8),
        Text(short,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white30, fontSize: 11)),
      ]),
    );
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    super.dispose();
  }

  void _go(int next) {
    if (next < 0 || next >= widget.mediaUrls.length) return;
    setState(() => idx = next);
    _fadeCtrl
      ..value = 0
      ..forward();
  }

  @override
  Widget build(BuildContext context) {
    final urls = widget.mediaUrls;
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(children: [
          if (urls.isEmpty)
            Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                _Avatar(
                    name: widget.name,
                    color: SLineColors.accentA,
                    url: widget.avatar,
                    size: 80),
                const SizedBox(height: 16),
                Text(widget.name,
                    style:
                        const TextStyle(color: Colors.white, fontSize: 18)),
                const SizedBox(height: 8),
                const Text('Нет активных историй',
                    style: TextStyle(color: Colors.white54)),
              ]),
            )
          else
            GestureDetector(
              onTapUp: (d) {
                final w = MediaQuery.of(context).size.width;
                if (d.localPosition.dx > w / 2) {
                  _go(idx + 1);
                } else {
                  _go(idx - 1);
                }
              },
              child: FadeTransition(
                opacity: _fadeCtrl,
                child: Center(
                  child: _isVideo(urls[idx])
                      ? _NetVideo(url: urls[idx])
                      : _storyImage(urls[idx]),
                ),
              ),
            ),
          Positioned(
            top: 8,
            left: 0,
            right: 0,
            child: Row(children: [
              IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: () => Navigator.pop(context)),
              Expanded(
                  child: Text(widget.name,
                      style: const TextStyle(color: Colors.white))),
              if (urls.isNotEmpty)
                Text('${idx + 1}/${urls.length}',
                    style: const TextStyle(color: Colors.white54)),
              const SizedBox(width: 12),
            ]),
          ),
        ]),
      ),
    );
  }
}

// ── contacts ────────────────────────────────────────────────

class CallsPage extends StatelessWidget {
  final User user;
  final Profile? myProfile;
  const CallsPage({super.key, required this.user, this.myProfile});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Text('Звонки',
                  style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      color: isDark ? Colors.white : Colors.black)),
            ),
            Expanded(
              child: StreamBuilder<DatabaseEvent>(
                stream: FirebaseDatabase.instance
                    .ref('calls')
                    .orderByChild('ts')
                    .limitToLast(50)
                    .onValue,
                builder: (context, snap) {
                  final raw = snap.data?.snapshot.value;
                  final List<Map<String, dynamic>> items = [];
                  if (raw is Map) {
                    raw.forEach((k, v) {
                      if (v is Map) {
                        final m = Map<String, dynamic>.from(v);
                        m['_id'] = k.toString();
                        final a = m['from']?.toString() ?? '';
                        final b = m['to']?.toString() ?? '';
                        if (a == user.uid || b == user.uid) items.add(m);
                      }
                    });
                    items.sort((a, b) =>
                        ((b['ts'] as num?) ?? 0).compareTo((a['ts'] as num?) ?? 0));
                  }
                  if (items.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.phone_callback_rounded,
                              size: 56,
                              color: isDark
                                  ? Colors.white24
                                  : Colors.black26),
                          const SizedBox(height: 12),
                          Text('Пока нет звонков',
                              style: TextStyle(
                                  color: isDark
                                      ? Colors.white54
                                      : Colors.black45,
                                  fontSize: 16)),
                        ],
                      ),
                    );
                  }
                  return ListView.builder(
                    itemCount: items.length,
                    itemBuilder: (_, i) {
                      final m = items[i];
                      final peer = (m['from'] == user.uid)
                          ? (m['to']?.toString() ?? '')
                          : (m['from']?.toString() ?? '');
                      final video = m['video'] == true;
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: SLineColors.accentA.withOpacity(0.2),
                          child: Icon(
                              video
                                  ? Icons.videocam_rounded
                                  : Icons.phone_rounded,
                              color: SLineColors.accentA),
                        ),
                        title: Text(peer.isEmpty ? 'Звонок' : peer,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                        subtitle: Text(
                          video ? 'Видеозвонок' : 'Аудиозвонок',
                          style: const TextStyle(fontSize: 13),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ContactsPage extends StatefulWidget {
  final User user;
  final Profile? myProfile;
  const ContactsPage({super.key, required this.user, this.myProfile});
  @override
  State<ContactsPage> createState() => _ContactsPageState();
}

class _ContactsPageState extends State<ContactsPage> {
  List<Profile> contacts = [];
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final snap = await FirebaseDatabase.instance
          .ref('my_contacts/${widget.user.uid}')
          .get();
      final list = <Profile>[];
      if (snap.exists && snap.value is Map) {
        for (final id in (snap.value as Map).keys) {
          final p = await loadProfile(id.toString());
          if (p != null) list.add(p);
        }
      }
      if (mounted) setState(() => contacts = list);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 12, 8),
          child: Row(children: [
            Expanded(
                child: Text('Контакты',
                    style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                        color: themeCtrl.text))),
            IconButton(
                onPressed: () {
                  Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => SearchPage(
                          user: widget.user,
                          myProfile: widget.myProfile,
                          onOpenChat: (p) async {
                            await FirebaseDatabase.instance
                                .ref(
                                    'my_contacts/${widget.user.uid}/${p.id}')
                                .set(true);
                            if (context.mounted) Navigator.pop(context);
                            await _load();
                          })));
                },
                style: IconButton.styleFrom(
                    backgroundColor: SLineColors.accentA,
                    foregroundColor: Colors.white),
                icon: const Icon(Icons.person_add_alt_1, size: 18)),
          ]),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: contacts.length,
            itemBuilder: (_, i) {
              final p = contacts[i];
              return Dismissible(
                key: ValueKey('c_${p.id}'),
                direction: DismissDirection.endToStart,
                background: Container(
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: 20),
                  color: SLineColors.danger,
                  child: const Icon(Icons.delete, color: Colors.white),
                ),
                confirmDismiss: (_) async {
                  return await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('Удалить контакт?'),
                          content: Text('Убрать ${p.displayName} из контактов'),
                          actions: [
                            TextButton(
                                onPressed: () => Navigator.pop(ctx, false),
                                child: const Text('Отмена')),
                            TextButton(
                                onPressed: () => Navigator.pop(ctx, true),
                                child: const Text('Удалить')),
                          ],
                        ),
                      ) ??
                      false;
                },
                onDismissed: (_) async {
                  await FirebaseDatabase.instance
                      .ref('my_contacts/${widget.user.uid}/${p.id}')
                      .remove();
                  setState(() => contacts.removeWhere((x) => x.id == p.id));
                },
                child: ListTile(
                  leading: _Avatar(
                      name: p.displayName,
                      color: p.colorValue,
                      url: p.avatarUrl,
                      onTap: () {
                        Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) => ProfilePage(
                                user: widget.user,
                                profile: p,
                                isMe: false)));
                      }),
                  title: Text(p.displayName),
                  subtitle: Text('@${p.username}'),
                  trailing: IconButton(
                    icon: Icon(Icons.person_remove_outlined,
                        color: themeCtrl.muted),
                    onPressed: () async {
                      final ok = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('Удалить контакт?'),
                          content:
                              Text('Убрать ${p.displayName} из контактов'),
                          actions: [
                            TextButton(
                                onPressed: () => Navigator.pop(ctx, false),
                                child: const Text('Отмена')),
                            TextButton(
                                onPressed: () => Navigator.pop(ctx, true),
                                child: const Text('Удалить')),
                          ],
                        ),
                      );
                      if (ok == true) {
                        await FirebaseDatabase.instance
                            .ref('my_contacts/${widget.user.uid}/${p.id}')
                            .remove();
                        if (mounted) {
                          setState(() =>
                              contacts.removeWhere((x) => x.id == p.id));
                        }
                      }
                    },
                  ),
                  onTap: () {
                    final key = dmPairKey(widget.user.uid, p.id);
                    Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => ChatScreen(
                            user: widget.user,
                            peer: p,
                            chatKey: key,
                            myProfile: widget.myProfile)));
                  },
                ),
              );
            },
          ),
        ),
      ]),
    );
  }
}

// ── settings ────────────────────────────────────────────────
class SettingsPage extends StatelessWidget {
  final User user;
  final Profile? myProfile;
  final VoidCallback onRefresh;
  const SettingsPage(
      {super.key,
      required this.user,
      this.myProfile,
      required this.onRefresh});
  @override
  Widget build(BuildContext context) {
    final p = myProfile;
    return SafeArea(
      bottom: false,
      child: AnimatedBuilder(
        animation: themeCtrl,
        builder: (_, __) => ListView(padding: const EdgeInsets.all(16), children: [
          Text('Настройки',
              style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  color: themeCtrl.text)),
          const SizedBox(height: 16),
          ListTile(
            leading: _Avatar(
                name: p?.displayName ?? 'U',
                color: p?.colorValue ?? SLineColors.accentA,
                url: p?.avatarUrl,
                size: 56),
            title: Text(p?.displayName ?? 'User',
                style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text(p?.username.isNotEmpty == true
                ? '@${p!.username}'
                : (user.email ?? '')),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              if (p == null) return;
              Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) =>
                      ProfilePage(user: user, profile: p, isMe: true))).then((_) => onRefresh());
            },
          ),
          const Divider(),
          SwitchListTile(
            title: const Text('Светлая тема'),
            value: themeCtrl.light,
            onChanged: (_) => themeCtrl.toggle(),
          ),
          ListTile(
            leading: const Icon(Icons.vpn_key_outlined),
            title: const Text('Резервные коды'),
            subtitle: const Text('Вход без доступа к SLine'),
            onTap: () {
              Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => RecoveryCodesPage(user: user)));
            },
          ),
          ListTile(
            leading: const Icon(Icons.devices_other_outlined),
            title: const Text('Сеансы'),
            subtitle: const Text('Устройства, с которых выполнен вход'),
            onTap: () {
              Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => SessionsPage(user: user)));
            },
          ),
          ListTile(
            leading: const Icon(Icons.palette_outlined),
            title: const Text('Оформление'),
            subtitle: const Text('Цвет пузырьков и обои чата'),
            onTap: () {
              Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const AppearancePage()));
            },
          ),
          ListTile(
            leading: const Icon(Icons.dynamic_feed_outlined),
            title: const Text('Посты'),
            subtitle: const Text('Лента и публикация'),
            onTap: () {
              Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => PostsPage(user: user, myProfile: myProfile)));
            },
          ),
          ListTile(
            leading: const Icon(Icons.notifications_outlined),
            title: const Text('Уведомления'),
            subtitle: const Text('Разрешения и звук'),
            onTap: () async {
              await OneSignal.Notifications.requestPermission(true);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Разрешение запрошено')));
              }
            },
          ),
          ListTile(
            leading: const Icon(Icons.lock_outline),
            title: const Text('Конфиденциальность'),
            onTap: () {
              showDialog(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Конфиденциальность'),
                  content: const Text(
                      'Сообщения защищены правилами Firebase. Доступ только у авторизованных пользователей.'),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('OK')),
                  ],
                ),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.storage_outlined),
            title: const Text('Данные и память'),
            onTap: () async {
              try {
                final dir = await getTemporaryDirectory();
                int bytes = 0;
                if (await dir.exists()) {
                  await for (final f in dir.list(recursive: true)) {
                    if (f is File) bytes += await f.length();
                  }
                }
                final mb = (bytes / (1024 * 1024)).toStringAsFixed(1);
                if (context.mounted) {
                  showDialog(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Кэш'),
                      content: Text('Временные файлы: $mb МБ'),
                      actions: [
                        TextButton(
                            onPressed: () => Navigator.pop(ctx),
                            child: const Text('Закрыть')),
                        TextButton(
                            onPressed: () async {
                              try {
                                if (await dir.exists()) {
                                  await for (final f
                                      in dir.list(recursive: true)) {
                                    if (f is File) await f.delete();
                                  }
                                }
                              } catch (_) {}
                              if (ctx.mounted) Navigator.pop(ctx);
                            },
                            child: const Text('Очистить')),
                      ],
                    ),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context)
                      .showSnackBar(SnackBar(content: Text('$e')));
                }
              }
            },
          ),
          ListTile(
            leading: Icon(Icons.switch_account, color: themeCtrl.text),
            title: const Text('Аккаунты'),
            subtitle: const Text('Добавить и переключить'),
            onTap: () {
              Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => AccountsPage(user: user, myProfile: p),
              ));
            },
          ),
          ListTile(
            leading: Icon(Icons.pin_outlined, color: themeCtrl.text),
            title: const Text('Второй пароль'),
            subtitle: const Text('PIN вместо кода SLine / резервного'),
            onTap: () {
              Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => SecondPinSettingsPage(user: user),
              ));
            },
          ),
          ListTile(
            leading: const Icon(Icons.language),
            title: const Text('Посмотреть веб-версию'),
            onTap: () async {
              final url = Uri.parse('https://sigli.gleeze.com');
              if (await canLaunchUrl(url)) {
                await launchUrl(url, mode: LaunchMode.externalApplication);
              }
            },
          ),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('О SLine'),
            subtitle: const Text('Мессенджер SLine'),
            onTap: () {
              showAboutDialog(
                context: context,
                applicationName: 'SLine',
                applicationVersion: '1.0',
                children: const [
                  Text('Чаты, каналы, группы, истории.'),
                ],
              );
            },
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.logout, color: SLineColors.danger),
            title: const Text('Выйти',
                style: TextStyle(color: SLineColors.danger)),
            onTap: () => FirebaseAuth.instance.signOut(),
          ),
        ]),
      ),
    );
  }
}




/// Цифровая клавиатура PIN (как системная)
class SLinePinPadPage extends StatefulWidget {
  final String title;
  final String subtitle;
  final int minLen;
  final int maxLen;
  const SLinePinPadPage({
    super.key,
    this.title = 'PIN',
    this.subtitle = '',
    this.minLen = 4,
    this.maxLen = 8,
  });
  @override
  State<SLinePinPadPage> createState() => _SLinePinPadPageState();
}

class _SLinePinPadPageState extends State<SLinePinPadPage> {
  String _pin = '';

  void _tap(String d) {
    if (_pin.length >= widget.maxLen) return;
    setState(() => _pin += d);
    HapticFeedback.selectionClick();
  }

  void _back() {
    if (_pin.isEmpty) return;
    setState(() => _pin = _pin.substring(0, _pin.length - 1));
  }

  void _submit() {
    if (_pin.length < widget.minLen) return;
    Navigator.pop(context, _pin);
  }

  @override
  Widget build(BuildContext context) {
    final dark = !themeCtrl.light;
    final bg = dark ? const Color(0xFF0B1219) : const Color(0xFFF2F4F7);
    final keyBg = dark ? const Color(0xFF1A2733) : const Color(0xFFE8ECF0);
    final keyFg = dark ? Colors.white : const Color(0xFF0F1720);
    Widget key(String label, {VoidCallback? onTap, Widget? child}) {
      return Material(
        color: keyBg,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            width: 76,
            height: 76,
            child: Center(
              child: child ??
                  Text(label,
                      style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w500,
                          color: keyFg)),
            ),
          ),
        ),
      );
    }

    final dots = List.generate(widget.maxLen, (i) {
      final on = i < _pin.length;
      return Container(
        width: 12,
        height: 12,
        margin: const EdgeInsets.symmetric(horizontal: 6),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: on ? SLineColors.accentA : keyFg.withValues(alpha: 0.2),
        ),
      );
    });

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: bg,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.close, color: keyFg),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(widget.title, style: TextStyle(color: keyFg)),
      ),
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 24),
            if (widget.subtitle.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Text(widget.subtitle,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: keyFg.withValues(alpha: 0.6))),
              ),
            const SizedBox(height: 28),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: dots),
            const Spacer(),
            for (final row in [
              ['1', '2', '3'],
              ['4', '5', '6'],
              ['7', '8', '9'],
            ])
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: row.map((n) => key(n, onTap: () => _tap(n))).toList(),
                ),
              ),
            Padding(
              padding: const EdgeInsets.only(bottom: 24),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  key('', onTap: _back, child: Icon(Icons.backspace_outlined, color: keyFg)),
                  key('0', onTap: () => _tap('0')),
                  key('',
                      onTap: _pin.length >= widget.minLen ? _submit : null,
                      child: Icon(Icons.arrow_forward,
                          color: _pin.length >= widget.minLen
                              ? SLineColors.accentA
                              : keyFg.withValues(alpha: 0.3))),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}


class AccountsPage extends StatefulWidget {
  final User user;
  final Profile? myProfile;
  const AccountsPage({super.key, required this.user, this.myProfile});
  @override
  State<AccountsPage> createState() => _AccountsPageState();
}

class _AccountsPageState extends State<AccountsPage> {
  List<SLineSavedAccount> _list = [];
  bool _loading = true;
  String? _busyUid;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final list = await SLineAccounts.load();
    // гарантируем текущий в списке (без пароля не добавим — только если уже был)
    if (mounted) {
      setState(() {
        _list = list;
        _loading = false;
      });
    }
  }

  Future<void> _switch(SLineSavedAccount acc) async {
    if (acc.uid == widget.user.uid) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Уже этот аккаунт')),
      );
      return;
    }
    setState(() => _busyUid = acc.uid);
    final ok = await SLineAccounts.switchTo(acc);
    if (!mounted) return;
    setState(() => _busyUid = null);
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text(
                'Не удалось войти. Пароль изменился — войдите заново через «Добавить аккаунт».')),
      );
      return;
    }
    // AuthGate перестроит дерево
    if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
  }

  Future<void> _add() async {
    // выходим и открываем логин, текущий уже сохранён при прошлом входе
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Добавить аккаунт'),
        content: const Text(
          'Текущий аккаунт останется в списке. Вы выйдете на экран входа — войдите в другой аккаунт. Потом сможете переключаться в Настройках → Аккаунты.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Отмена')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Продолжить')),
        ],
      ),
    );
    if (ok != true) return;
    SLineAuthLock.pendingCode.value = false;
    SLineAuthLock.holdLogin.value = false;
    try {
      await FirebaseAuth.instance.signOut();
    } catch (_) {}
    if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
  }

  Future<void> _remove(SLineSavedAccount acc) async {
    if (acc.uid == widget.user.uid) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Нельзя удалить текущий. Сначала переключитесь.')),
      );
      return;
    }
    await SLineAccounts.removeUid(acc.uid);
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Аккаунты')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  'Переключение без повторного поиска логина. Пароли хранятся только на этом устройстве.',
                  style: TextStyle(color: themeCtrl.muted, fontSize: 13),
                ),
                const SizedBox(height: 12),
                ..._list.map((a) {
                  final current = a.uid == widget.user.uid;
                  return Card(
                    child: ListTile(
                      leading: CircleAvatar(
                        child: Text(
                          (a.label.isNotEmpty ? a.label[0] : '?').toUpperCase(),
                        ),
                      ),
                      title: Text(
                        a.label,
                        style: TextStyle(
                          fontWeight:
                              current ? FontWeight.w800 : FontWeight.w600,
                        ),
                      ),
                      subtitle: Text(
                        current ? '${a.login} · сейчас' : a.login,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: _busyUid == a.uid
                          ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (!current)
                                  IconButton(
                                    icon: const Icon(Icons.swap_horiz),
                                    tooltip: 'Переключить',
                                    onPressed: () => _switch(a),
                                  ),
                                if (!current)
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline,
                                        color: SLineColors.danger),
                                    onPressed: () => _remove(a),
                                  ),
                              ],
                            ),
                      onTap: current ? null : () => _switch(a),
                    ),
                  );
                }),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _add,
                  icon: const Icon(Icons.person_add_alt_1),
                  label: const Text('Добавить аккаунт'),
                ),
              ],
            ),
    );
  }
}


class SecondPinSettingsPage extends StatefulWidget {
  final User user;
  const SecondPinSettingsPage({super.key, required this.user});
  @override
  State<SecondPinSettingsPage> createState() => _SecondPinSettingsPageState();
}

class _SecondPinSettingsPageState extends State<SecondPinSettingsPage> {
  bool? _has;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final h = await hasSecondPin(widget.user.uid);
    if (mounted) setState(() { _has = h; _loading = false; });
  }

  Future<void> _setPin() async {
    final p1 = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => const SLinePinPadPage(
          title: 'Новый второй пароль',
          subtitle: 'Придумайте PIN (4–8 цифр)',
        ),
      ),
    );
    if (p1 == null || p1.length < 4) return;
    final p2 = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => const SLinePinPadPage(
          title: 'Повтор PIN',
          subtitle: 'Введите тот же PIN ещё раз',
        ),
      ),
    );
    if (p2 != p1) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('PIN не совпал')),
        );
      }
      return;
    }
    await saveSecondPin(widget.user.uid, p1);
    if (mounted) {
      setState(() => _has = true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Второй пароль сохранён')),
      );
    }
  }

  Future<void> _remove() async {
    final cur = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => const SLinePinPadPage(
          title: 'Текущий PIN',
          subtitle: 'Подтвердите, чтобы удалить',
        ),
      ),
    );
    if (cur == null) return;
    if (!await verifySecondPin(widget.user.uid, cur)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Неверный PIN')),
        );
      }
      return;
    }
    await clearSecondPin(widget.user.uid);
    if (mounted) setState(() => _has = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Второй пароль')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  'PIN можно ввести вместо кода из чата SLine или резервного кода при входе на новом устройстве.',
                  style: TextStyle(color: themeCtrl.muted),
                ),
                const SizedBox(height: 16),
                ListTile(
                  leading: const Icon(Icons.pin),
                  title: Text(_has == true ? 'Изменить PIN' : 'Установить PIN'),
                  onTap: _setPin,
                ),
                if (_has == true)
                  ListTile(
                    leading: const Icon(Icons.delete_outline, color: SLineColors.danger),
                    title: const Text('Удалить второй пароль',
                        style: TextStyle(color: SLineColors.danger)),
                    onTap: _remove,
                  ),
              ],
            ),
    );
  }
}

class BindEmailPage extends StatefulWidget {
  final User user;
  final Profile? profile;
  final VoidCallback? onDone;
  const BindEmailPage({super.key, required this.user, this.profile, this.onDone});
  @override
  State<BindEmailPage> createState() => _BindEmailPageState();
}

class _BindEmailPageState extends State<BindEmailPage> {
  final emailC = TextEditingController();
  final codeC = TextEditingController();
  String? _sentCode;
  bool _loading = false;
  String? _error;
  bool _codePhase = false;

  @override
  void dispose() {
    emailC.dispose();
    codeC.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final email = emailC.text.trim().toLowerCase();
    if (!email.contains('@') || email.endsWith('.local')) {
      setState(() => _error = 'Введите настоящий email');
      return;
    }
    setState(() { _loading = true; _error = null; });
    final code =
        (100000 + (DateTime.now().millisecondsSinceEpoch % 900000)).toString();
    final err = await slSendLoginEmailCode(email, code);
    if (err != null) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Ошибка, код не отправился. $err';
        });
      }
      return;
    }
    _sentCode = code;
    try {
      await FirebaseDatabase.instance
          .ref('email_bind_codes/${widget.user.uid}')
          .set({
        'email': email,
        'code': code,
        'expires': DateTime.now()
            .add(const Duration(minutes: 15))
            .millisecondsSinceEpoch,
      });
    } catch (_) {}
    if (mounted) {
      setState(() {
        _loading = false;
        _codePhase = true;
      });
    }
  }

  Future<void> _confirm() async {
    final entered = codeC.text.trim();
    if (entered.isEmpty) return;
    setState(() { _loading = true; _error = null; });
    var ok = _sentCode != null && entered == _sentCode;
    if (!ok) {
      try {
        final s = await FirebaseDatabase.instance
            .ref('email_bind_codes/${widget.user.uid}')
            .get();
        if (s.exists && s.value is Map) {
          final m = Map<String, dynamic>.from(s.value as Map);
          ok = (m['code'] ?? '').toString() == entered;
          if (ok) {
            emailC.text = (m['email'] ?? emailC.text).toString();
          }
        }
      } catch (_) {}
    }
    if (!ok) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Неверный код';
        });
      }
      return;
    }
    final email = emailC.text.trim().toLowerCase();
    try {
      await profilesRef().child(widget.user.uid).update({
        'email': email,
        'email_bound': true,
        'email_bound_at': DateTime.now().millisecondsSinceEpoch,
      });
      try {
        await FirebaseDatabase.instance
            .ref('email_bind_codes/${widget.user.uid}')
            .remove();
      } catch (_) {}
      widget.onDone?.call();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Почта привязана')),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Не удалось сохранить: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Привязать почту')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            'К номеру нужно привязать email — для восстановления без SMS.',
            style: TextStyle(color: themeCtrl.muted),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: emailC,
            enabled: !_codePhase,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(
              labelText: 'Email',
              border: OutlineInputBorder(),
            ),
          ),
          if (_codePhase) ...[
            const SizedBox(height: 12),
            TextField(
              controller: codeC,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Код из письма',
                border: OutlineInputBorder(),
              ),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: const TextStyle(color: SLineColors.danger)),
          ],
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _loading ? null : (_codePhase ? _confirm : _send),
            child: Text(_loading
                ? '…'
                : (_codePhase ? 'Подтвердить' : 'Отправить код')),
          ),
        ],
      ),
    );
  }
}


class RecoveryCodesPage extends StatefulWidget {
  final User user;
  const RecoveryCodesPage({super.key, required this.user});
  @override
  State<RecoveryCodesPage> createState() => _RecoveryCodesPageState();
}

class _RecoveryCodesPageState extends State<RecoveryCodesPage> {
  List<String>? freshCodes;
  bool loading = false;
  int unused = 0;

  @override
  void initState() {
    super.initState();
    _count();
  }

  Future<void> _count() async {
    try {
      final snap = await FirebaseDatabase.instance
          .ref('user_recovery_codes/${widget.user.uid}/hashes')
          .get();
      var n = 0;
      if (snap.exists && snap.value is Map) {
        for (final e in (snap.value as Map).entries) {
          if (e.value is Map && (e.value as Map)['used'] != true) n++;
        }
      }
      if (mounted) setState(() => unused = n);
    } catch (_) {}
  }

  Future<void> _regen() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Новые резервные коды?'),
        content: const Text(
          'Старые коды перестанут работать. Сохраните новые.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Отмена')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Сгенерировать')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => loading = true);
    try {
      final codes = generateRecoveryCodes();
      await saveRecoveryCodes(widget.user.uid, codes);
      if (mounted) {
        setState(() {
          freshCodes = codes;
          unused = codes.length;
          loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => loading = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Резервные коды')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            'Если потеряете устройство и не получите код в чате SLine — используйте резервный код при входе. Каждый код одноразовый.',
            style: TextStyle(color: themeCtrl.muted, height: 1.4),
          ),
          const SizedBox(height: 12),
          Text('Неиспользованных: $unused',
              style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 20),
          if (freshCodes != null) ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: themeCtrl.panel,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('Сохраните сейчас — больше не покажем:',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 10),
                  ...freshCodes!.map((c) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: SelectableText(
                          c,
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.5,
                          ),
                        ),
                      )),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],
          FilledButton.icon(
            onPressed: loading ? null : _regen,
            icon: loading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.refresh),
            label: Text(freshCodes == null
                ? 'Сгенерировать коды'
                : 'Сгенерировать заново'),
          ),
        ],
      ),
    );
  }
}

class SessionsPage extends StatefulWidget {
  final User user;
  const SessionsPage({super.key, required this.user});
  @override
  State<SessionsPage> createState() => _SessionsPageState();
}

class _SessionsPageState extends State<SessionsPage> {
  List<Map<String, dynamic>> sessions = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => loading = true);
    final list = <Map<String, dynamic>>[];
    try {
      final snap = await FirebaseDatabase.instance
          .ref('user_sessions/${widget.user.uid}')
          .get();
      if (snap.exists && snap.value is Map) {
        for (final e in (snap.value as Map).entries) {
          if (e.value is! Map) continue;
          final m = Map<String, dynamic>.from(e.value as Map);
          m['_id'] = e.key.toString();
          list.add(m);
        }
      }
    } catch (_) {}
    list.sort((a, b) {
      final la = int.tryParse((a['last_active'] ?? 0).toString()) ?? 0;
      final lb = int.tryParse((b['last_active'] ?? 0).toString()) ?? 0;
      return lb.compareTo(la);
    });
    if (mounted) setState(() { sessions = list; loading = false; });
  }

  Future<void> _terminate(String id) async {
    try {
      await FirebaseDatabase.instance
          .ref('user_sessions/${widget.user.uid}/$id')
          .remove();
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  String _fmt(int ms) {
    if (ms <= 0) return '—';
    final d = DateTime.fromMillisecondsSinceEpoch(ms);
    return '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year} '
        '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: themeCtrl.bg,
      appBar: AppBar(title: const Text('Сеансы')),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : sessions.isEmpty
              ? Center(
                  child: Text('Нет активных сеансов',
                      style: TextStyle(color: themeCtrl.muted)))
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: sessions.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final s = sessions[i];
                    final device = (s['device'] ?? s['platform'] ?? 'Устройство')
                        .toString();
                    final place = (s['place'] ?? s['country'] ?? s['ip'] ?? '—')
                        .toString();
                    final la = int.tryParse(
                            (s['last_active'] ?? 0).toString()) ??
                        0;
                    final id = (s['_id'] ?? '').toString();
                    return ListTile(
                      leading: Icon(
                        (s['platform']?.toString().toLowerCase() == 'web')
                            ? Icons.language
                            : Icons.phone_android,
                        color: SLineColors.accentA,
                      ),
                      title: Text(device,
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text('Место: $place\nАктивность: ${_fmt(la)}'),
                      isThreeLine: true,
                      trailing: IconButton(
                        icon: const Icon(Icons.logout, color: SLineColors.danger),
                        tooltip: 'Завершить сеанс',
                        onPressed: id.isEmpty ? null : () => _terminate(id),
                      ),
                    );
                  },
                ),
    );
  }
}


class AppearancePage extends StatelessWidget {
  const AppearancePage({super.key});
  static const bubblePresets = <(Color, Color, String)>[
    (Color(0xFF5B8CFF), Color(0xFF6D5DF6), 'Синий'),
    (Color(0xFF2ECC71), Color(0xFF27AE60), 'Зелёный'),
    (Color(0xFFE67E22), Color(0xFFD35400), 'Оранжевый'),
    (Color(0xFFE91E63), Color(0xFFC2185B), 'Розовый'),
    (Color(0xFF9B59B6), Color(0xFF8E44AD), 'Фиолетовый'),
    (Color(0xFF1ABC9C), Color(0xFF16A085), 'Бирюзовый'),
  ];
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: themeCtrl.bg,
      appBar: AppBar(title: const Text('Оформление')),
      body: AnimatedBuilder(
        animation: themeCtrl,
        builder: (_, __) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('Цвет пузырьков',
                style: TextStyle(
                    fontWeight: FontWeight.w700, color: themeCtrl.text)),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final (a, b, name) in bubblePresets)
                  GestureDetector(
                    onTap: () => themeCtrl.setBubbleColors(a, b),
                    child: Container(
                      width: 100,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(colors: [a, b]),
                        borderRadius: BorderRadius.circular(12),
                        border: themeCtrl.bubbleMeA == a
                            ? Border.all(color: themeCtrl.text, width: 2)
                            : null,
                      ),
                      child: Text(name,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600)),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 24),
            Text('Обои чата',
                style: TextStyle(
                    fontWeight: FontWeight.w700, color: themeCtrl.text)),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (var i = 0; i < ThemeController.wallpapers.length; i++)
                  GestureDetector(
                    onTap: () => themeCtrl.setWallpaper(i),
                    child: Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        color: ThemeController.wallpapers[i] ?? themeCtrl.bg,
                        gradient: ThemeController.wallpaperGrads[i] == null
                            ? null
                            : LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: ThemeController.wallpaperGrads[i]!,
                              ),
                        borderRadius: BorderRadius.circular(10),
                        border: themeCtrl.wallpaperIndex == i
                            ? Border.all(color: SLineColors.accentA, width: 3)
                            : Border.all(color: themeCtrl.line),
                      ),
                      child: i == 0
                          ? Icon(Icons.block, color: themeCtrl.muted)
                          : null,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── channel / group ──

class CreateChannelPage extends StatefulWidget {
  final User user;
  final Profile? myProfile;
  const CreateChannelPage({super.key, required this.user, this.myProfile});
  @override
  State<CreateChannelPage> createState() => _CreateChannelPageState();
}

class _CreateChannelPageState extends State<CreateChannelPage> {
  int step = 0;
  final nameC = TextEditingController();
  final descC = TextEditingController();
  final linkC = TextEditingController();
  String? avatarUrl;
  bool isPublic = true;
  bool loading = false;
  final selected = <String, Profile>{};
  List<Profile> contacts = [];

  @override
  void initState() {
    super.initState();
    _loadContacts();
  }

  Future<void> _loadContacts() async {
    try {
      final snap = await FirebaseDatabase.instance
          .ref('my_contacts/${widget.user.uid}')
          .get();
      final list = <Profile>[];
      if (snap.exists && snap.value is Map) {
        for (final id in (snap.value as Map).keys) {
          final p = await loadProfile(id.toString());
          if (p != null) list.add(p);
        }
      }
      if (mounted) setState(() => contacts = list);
    } catch (_) {}
  }

  Future<void> _pickAvatar() async {
    final x = await ImagePicker()
        .pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (x == null) return;
    setState(() => loading = true);
    try {
      final url = await B2Storage.uploadFile(
          File(x.path), 'channel_avatars', widget.user.uid);
      if (mounted) setState(() => avatarUrl = url);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _finish() async {
    final name = nameC.text.trim();
    if (name.isEmpty) return;
    setState(() => loading = true);
    try {
      final slug = (linkC.text.trim().isEmpty ? name : linkC.text.trim())
          .toLowerCase()
          .replaceAll(RegExp(r'[^a-z0-9_-]'), '-')
          .replaceAll(RegExp(r'-+'), '-');
      if (slug.length < 3) {
        if (mounted) {
          setState(() => loading = false);
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Username канала от 3 символов (a-z, 0-9)')));
        }
        return;
      }
      if (await isSlugTaken(slug) || await isUsernameTaken(slug)) {
        if (mounted) {
          setState(() => loading = false);
          ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Username @$slug уже занят')));
        }
        return;
      }
      final ref = FirebaseDatabase.instance.ref('channels').push();
      final id = ref.key!;
      final inviteCode = isPublic ? null : id;
      final payload = {
        'id': id,
        'name': name,
        'description': descC.text.trim(),
        'avatar_url': avatarUrl,
        'slug': slug,
        'username': slug,
        'public': isPublic,
        'is_public': isPublic,
        'admin_id': widget.user.uid,
        'owner_id': widget.user.uid,
        if (inviteCode != null) 'invite_code': inviteCode,
        'created_at': DateTime.now().toIso8601String(),
        'type': 'channel',
      };
      // Пишем в несколько путей — как на вебе (rules могут отличаться)
      Object? lastErr;
      for (final path in ['channels/$id', 'tables/channels/$id', 'groups/$id']) {
        try {
          await FirebaseDatabase.instance.ref(path).set({
            ...payload,
            if (path.startsWith('groups')) 'type': 'channel',
          });
          lastErr = null;
        } catch (e) {
          lastErr = e;
        }
      }
      try {
        await FirebaseDatabase.instance
            .ref('channel_members/$id/${widget.user.uid}')
            .set({'role': 'admin', 'muted': false});
      } catch (_) {}
      try {
        await FirebaseDatabase.instance
            .ref('group_members/$id/${widget.user.uid}')
            .set({'role': 'admin'});
      } catch (_) {}
      for (final uid in selected.keys) {
        try {
          await FirebaseDatabase.instance
              .ref('channel_members/$id/$uid')
              .set({'role': 'member', 'muted': false});
        } catch (_) {}
        try {
          await FirebaseDatabase.instance
              .ref('user_chat_index/$uid/c_$id')
              .set(true);
        } catch (_) {}
      }
      try {
        await FirebaseDatabase.instance
            .ref('user_chat_index/${widget.user.uid}/c_$id')
            .set(true);
      } catch (e) {
        lastErr = e;
      }
      if (!mounted) return;
      // Даже если второстепенные записи упали — открываем канал
      Navigator.of(context).pushReplacement(MaterialPageRoute(
        builder: (_) => ChannelScreen(
          user: widget.user,
          channelId: id,
          channelName: name,
          avatarUrl: avatarUrl,
          description: descC.text.trim(),
          isAdmin: true,
          isPublic: isPublic,
          slug: slug,
        ),
      ));
      if (inviteCode != null && mounted) {
        final link = 'https://sigli.gleeze.com/#/join/$inviteCode';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ссылка: $link')),
        );
      }
      if (lastErr != null) {
        // не блокируем — только лог
        // ignore: avoid_print
        print('channel secondary write: $lastErr');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(permissionHelp(e)),
            duration: const Duration(seconds: 8),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: themeCtrl.bg,
      appBar: AppBar(title: Text(step == 0
          ? 'Новый канал'
          : step == 1
              ? 'Ссылка и доступ'
              : 'Подписчики')),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : step == 0
              ? _step0()
              : step == 1
                  ? _step1()
                  : _step2(),
    );
  }

  Widget _step0() {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Center(
          child: GestureDetector(
            onTap: _pickAvatar,
            child: avatarUrl != null
                ? _Avatar(name: 'C', color: SLineColors.accentA, url: avatarUrl, size: 96)
                : Container(
                    width: 96,
                    height: 96,
                    decoration: BoxDecoration(
                        shape: BoxShape.circle, color: themeCtrl.input),
                    child: Icon(Icons.camera_alt, color: themeCtrl.muted),
                  ),
          ),
        ),
        const SizedBox(height: 20),
        TextField(
            controller: nameC,
            decoration: const InputDecoration(labelText: 'Название')),
        const SizedBox(height: 12),
        TextField(
            controller: descC,
            decoration: const InputDecoration(labelText: 'Описание'),
            maxLines: 3),
        const SizedBox(height: 24),
        ElevatedButton(
          onPressed: () {
            if (nameC.text.trim().isEmpty) return;
            setState(() => step = 1);
            if (linkC.text.isEmpty) {
              linkC.text = nameC.text
                  .trim()
                  .toLowerCase()
                  .replaceAll(RegExp(r'[^a-z0-9_-]'), '-');
            }
          },
          style: ElevatedButton.styleFrom(
              backgroundColor: SLineColors.accentA,
              foregroundColor: Colors.white),
          child: const Text('Продолжить'),
        ),
      ],
    );
  }

  Widget _step1() {
    final slug = linkC.text
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9_-]'), '-');
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        TextField(
          controller: linkC,
          decoration: const InputDecoration(
            labelText: 'Ссылка',
            prefixText: 'sigli.gleeze.com/#/channel/',
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 8),
        Text('https://sigli.gleeze.com/#/channel/$slug',
            style: TextStyle(fontSize: 12, color: themeCtrl.muted)),
        const SizedBox(height: 16),
        SwitchListTile(
          title: const Text('Публичный канал'),
          subtitle: Text(isPublic
              ? 'Любой может найти и подписаться'
              : 'Только по приглашению'),
          value: isPublic,
          onChanged: (v) => setState(() => isPublic = v),
        ),
        const SizedBox(height: 24),
        ElevatedButton(
          onPressed: () => setState(() => step = 2),
          style: ElevatedButton.styleFrom(
              backgroundColor: SLineColors.accentA,
              foregroundColor: Colors.white),
          child: const Text('Продолжить'),
        ),
      ],
    );
  }

  Widget _step2() {
    return Column(children: [
      Expanded(
        child: ListView.builder(
          itemCount: contacts.length,
          itemBuilder: (_, i) {
            final p = contacts[i];
            final on = selected.containsKey(p.id);
            return CheckboxListTile(
              value: on,
              onChanged: (v) {
                setState(() {
                  if (v == true) {
                    selected[p.id] = p;
                  } else {
                    selected.remove(p.id);
                  }
                });
              },
              secondary: _Avatar(
                  name: p.displayName, color: p.colorValue, url: p.avatarUrl),
              title: Text(p.displayName),
              subtitle: Text('@${p.username}'),
            );
          },
        ),
      ),
      Padding(
        padding: const EdgeInsets.all(16),
        child: SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _finish,
            style: ElevatedButton.styleFrom(
                backgroundColor: SLineColors.accentA,
                foregroundColor: Colors.white),
            child: const Text('Завершить'),
          ),
        ),
      ),
    ]);
  }
}

class CreateGroupPage extends StatefulWidget {
  final User user;
  final Profile? myProfile;
  const CreateGroupPage({super.key, required this.user, this.myProfile});
  @override
  State<CreateGroupPage> createState() => _CreateGroupPageState();
}

class _CreateGroupPageState extends State<CreateGroupPage> {
  int step = 0;
  final nameC = TextEditingController();
  final descC = TextEditingController();
  final linkC = TextEditingController();
  String? avatarUrl;
  bool loading = false;
  bool isPublic = true;
  final selected = <String, Profile>{};
  List<Profile> contacts = [];

  @override
  void initState() {
    super.initState();
    _loadContacts();
  }

  Future<void> _loadContacts() async {
    try {
      final snap = await FirebaseDatabase.instance
          .ref('my_contacts/${widget.user.uid}')
          .get();
      final list = <Profile>[];
      if (snap.exists && snap.value is Map) {
        for (final id in (snap.value as Map).keys) {
          final p = await loadProfile(id.toString());
          if (p != null) list.add(p);
        }
      }
      if (mounted) setState(() => contacts = list);
    } catch (_) {}
  }

  Future<void> _pickAvatar() async {
    final x = await ImagePicker()
        .pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (x == null) return;
    setState(() => loading = true);
    try {
      final url = await B2Storage.uploadFile(
          File(x.path), 'group_avatars', widget.user.uid);
      if (mounted) setState(() => avatarUrl = url);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _finish() async {
    final name = nameC.text.trim();
    if (name.isEmpty || selected.isEmpty) return;
    setState(() => loading = true);
    try {
      final ref = FirebaseDatabase.instance.ref('groups').push();
      final id = ref.key!;
      final key = 'g_$id';
      // username только латиница (a-z0-9_)
      var slug = linkC.text
          .trim()
          .toLowerCase()
          .replaceAll(RegExp(r'[^a-z0-9_]'), '');
      if (slug.isEmpty) {
        slug = name
            .toLowerCase()
            .replaceAll(RegExp(r'[^a-z0-9_]'), '');
      }
      if (slug.isEmpty) slug = id;
      if (slug.length >= 3 &&
          (await isSlugTaken(slug) || await isUsernameTaken(slug))) {
        if (mounted) {
          setState(() => loading = false);
          ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Username @$slug уже занят')));
        }
        return;
      }
      final inviteCode = isPublic ? null : id;
      final payload = {
        'id': id,
        'name': name,
        'description': descC.text.trim(),
        'avatar_url': avatarUrl,
        'username': slug,
        'slug': slug,
        'public': isPublic,
        'is_public': isPublic,
        if (inviteCode != null) 'invite_code': inviteCode,
        'admin_id': widget.user.uid,
        'owner_id': widget.user.uid,
        'created_at': DateTime.now().toIso8601String(),
        'type': 'group',
      };
      Object? lastErr;
      for (final path in ['groups/$id', 'tables/groups/$id']) {
        try {
          await FirebaseDatabase.instance.ref(path).set(payload);
          lastErr = null;
        } catch (e) {
          lastErr = e;
        }
      }
      final members = {widget.user.uid: true};
      for (final uid in selected.keys) {
        members[uid] = true;
        try {
          await FirebaseDatabase.instance
              .ref('user_chat_index/$uid/$key')
              .set(true);
        } catch (_) {}
      }
      try {
        await FirebaseDatabase.instance.ref('group_members/$id').set(members);
      } catch (_) {
        // fallback per-member
        for (final uid in members.keys) {
          try {
            await FirebaseDatabase.instance
                .ref('group_members/$id/$uid')
                .set({'role': uid == widget.user.uid ? 'admin' : 'member'});
          } catch (_) {}
        }
      }
      try {
        await FirebaseDatabase.instance
            .ref('user_chat_index/${widget.user.uid}/$key')
            .set(true);
      } catch (e) {
        lastErr = e;
      }
      if (!mounted) return;
      final peer = Profile(
        id: key,
        firstName: name,
        username: slug,
        avatarUrl: avatarUrl,
        color: '#6D5DF6',
        bio: widget.user.uid,
      );
      Navigator.of(context).pushReplacement(MaterialPageRoute(
        builder: (_) => ChatScreen(
          user: widget.user,
          peer: peer,
          chatKey: key,
          myProfile: widget.myProfile,
        ),
      ));
      if (inviteCode != null && mounted) {
        final link = 'https://sigli.gleeze.com/#/join/$inviteCode';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ссылка-приглашение: $link')),
        );
      }
      if (lastErr != null) {
        // ignore: avoid_print
        print('group secondary write: $lastErr');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(permissionHelp(e)),
            duration: const Duration(seconds: 8),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: themeCtrl.bg,
      appBar: AppBar(
          title: Text(step == 0 ? 'Новая группа' : 'Участники')),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : step == 0
              ? ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    Center(
                      child: GestureDetector(
                        onTap: _pickAvatar,
                        child: avatarUrl != null
                            ? _Avatar(
                                name: 'G',
                                color: SLineColors.accentB,
                                url: avatarUrl,
                                size: 96)
                            : Container(
                                width: 96,
                                height: 96,
                                decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: themeCtrl.input),
                                child: Icon(Icons.camera_alt,
                                    color: themeCtrl.muted),
                              ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    TextField(
                        controller: nameC,
                        decoration:
                            const InputDecoration(labelText: 'Название')),
                    const SizedBox(height: 12),
                    TextField(
                        controller: descC,
                        decoration:
                            const InputDecoration(labelText: 'Описание'),
                        maxLines: 3),
                    const SizedBox(height: 12),
                    TextField(
                      controller: linkC,
                      decoration: const InputDecoration(
                        labelText: 'Username (латиница)',
                        prefixText: '@',
                        helperText: 'Только a-z, 0-9, _',
                      ),
                      onChanged: (v) {
                        final clean = v
                            .toLowerCase()
                            .replaceAll(RegExp(r'[^a-z0-9_]'), '');
                        if (clean != v) {
                          linkC.value = TextEditingValue(
                            text: clean,
                            selection: TextSelection.collapsed(
                                offset: clean.length),
                          );
                        }
                      },
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Публичная группа'),
                      subtitle: Text(isPublic
                          ? 'Доступна в поиске'
                          : 'Только по ссылке'),
                      value: isPublic,
                      onChanged: (v) => setState(() => isPublic = v),
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton(
                      onPressed: () {
                        if (nameC.text.trim().isEmpty) return;
                        setState(() => step = 1);
                      },
                      style: ElevatedButton.styleFrom(
                          backgroundColor: SLineColors.accentA,
                          foregroundColor: Colors.white),
                      child: const Text('Продолжить'),
                    ),
                  ],
                )
              : Column(children: [
                  Expanded(
                    child: ListView.builder(
                      itemCount: contacts.length,
                      itemBuilder: (_, i) {
                        final p = contacts[i];
                        final on = selected.containsKey(p.id);
                        return CheckboxListTile(
                          value: on,
                          onChanged: (v) {
                            setState(() {
                              if (v == true) {
                                selected[p.id] = p;
                              } else {
                                selected.remove(p.id);
                              }
                            });
                          },
                          secondary: _Avatar(
                              name: p.displayName,
                              color: p.colorValue,
                              url: p.avatarUrl),
                          title: Text(p.displayName),
                          subtitle: Text('@${p.username}'),
                        );
                      },
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed:
                            selected.isEmpty ? null : _finish,
                        style: ElevatedButton.styleFrom(
                            backgroundColor: SLineColors.accentA,
                            foregroundColor: Colors.white),
                        child: const Text('Завершить'),
                      ),
                    ),
                  ),
                ]),
    );
  }
}

class ChannelScreen extends StatefulWidget {
  final User user;
  final String channelId;
  final String channelName;
  final String? avatarUrl;
  final String description;
  final bool isAdmin;
  final bool isPublic;
  final String slug;
  const ChannelScreen({
    super.key,
    required this.user,
    required this.channelId,
    required this.channelName,
    this.avatarUrl,
    this.description = '',
    this.isAdmin = false,
    this.isPublic = true,
    this.slug = '',
  });
  @override
  State<ChannelScreen> createState() => _ChannelScreenState();
}

class _ChannelScreenState extends State<ChannelScreen> {
  final msgCtrl = TextEditingController();
  final scrollCtrl = ScrollController();
  List<ChatMessage> messages = [];
  StreamSubscription? sub;
  bool subscribed = true;
  bool muted = false;
  bool sending = false;

  String get chatKey => 'c_${widget.channelId}';

  @override
  void initState() {
    super.initState();
    _loadMember();
    sub = chatMsgsRef(chatKey).limitToLast(200).onValue.listen((ev) {
      final list = <ChatMessage>[];
      if (ev.snapshot.exists && ev.snapshot.value is Map) {
        for (final e
            in Map<String, dynamic>.from(ev.snapshot.value as Map).entries) {
          if (e.value is Map) {
            list.add(ChatMessage.fromMap(
                e.key, Map<String, dynamic>.from(e.value as Map)));
          }
        }
      }
      list.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      if (mounted) {
        setState(() => messages = list);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (scrollCtrl.hasClients) {
            scrollCtrl.jumpTo(scrollCtrl.position.maxScrollExtent);
          }
        });
      }
    });
  }

  Future<void> _loadMember() async {
    try {
      final snap = await FirebaseDatabase.instance
          .ref('channel_members/${widget.channelId}/${widget.user.uid}')
          .get();
      if (snap.exists && snap.value is Map) {
        final m = Map<String, dynamic>.from(snap.value as Map);
        if (mounted) {
          setState(() {
            subscribed = true;
            muted = m['muted'] == true;
          });
        }
      } else {
        if (mounted) setState(() => subscribed = false);
      }
    } catch (_) {}
  }

  Future<void> _subscribe() async {
    await FirebaseDatabase.instance
        .ref('channel_members/${widget.channelId}/${widget.user.uid}')
        .set({'role': 'member', 'muted': false});
    await FirebaseDatabase.instance
        .ref('user_chat_index/${widget.user.uid}/$chatKey')
        .set(true);
    setState(() => subscribed = true);
  }

  Future<void> _toggleMute() async {
    final next = !muted;
    await FirebaseDatabase.instance
        .ref('channel_members/${widget.channelId}/${widget.user.uid}/muted')
        .set(next);
    setState(() => muted = next);
  }

  Future<void> _send() async {
    if (!widget.isAdmin || sending) return;
    final t = msgCtrl.text.trim();
    if (t.isEmpty) return;
    setState(() => sending = true);
    msgCtrl.clear();
    try {
      final ref = chatMsgsRef(chatKey).push();
      final now = DateTime.now();
      await ref.set({
        'id': ref.key,
        'sender_id': widget.user.uid,
        'content': t,
        'type': 'text',
        'created_at': now.toIso8601String(),
        'created_at_ms': now.millisecondsSinceEpoch,
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  @override
  void dispose() {
    sub?.cancel();
    msgCtrl.dispose();
    scrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: themeCtrl.bg,
      appBar: AppBar(
        titleSpacing: 0,
        title: InkWell(
          onTap: () {
            Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => ChannelInfoPage(
                channelId: widget.channelId,
                name: widget.channelName,
                avatarUrl: widget.avatarUrl,
                description: widget.description,
                isPublic: widget.isPublic,
                slug: widget.slug,
                isAdmin: widget.isAdmin,
                user: widget.user,
              ),
            ));
          },
          child: Row(children: [
            _Avatar(
                name: widget.channelName,
                color: SLineColors.accentB,
                url: widget.avatarUrl,
                size: 36),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.channelName,
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w700)),
                    const Text('канал',
                        style: TextStyle(
                            fontSize: 11, color: SLineColors.mint)),
                  ]),
            ),
          ]),
        ),
      ),
      body: Column(children: [
        Expanded(
          child: ListView.builder(
            controller: scrollCtrl,
            padding: const EdgeInsets.all(12),
            itemCount: messages.length,
            itemBuilder: (_, i) {
              final m = messages[i];
              return Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  margin: const EdgeInsets.only(bottom: 6),
                  constraints: BoxConstraints(
                      maxWidth: MediaQuery.of(context).size.width * 0.85),
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
                  decoration: BoxDecoration(
                    color: themeCtrl.bubbleThem,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(m.content,
                      style: TextStyle(color: themeCtrl.text)),
                ),
              );
            },
          ),
        ),
        if (!subscribed)
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: _subscribe,
                  style: ElevatedButton.styleFrom(
                      backgroundColor: SLineColors.accentA,
                      foregroundColor: Colors.white),
                  child: const Text('Подписаться'),
                ),
              ),
            ),
          )
        else if (widget.isAdmin)
          Container(
            padding: EdgeInsets.fromLTRB(
                8, 8, 8, 8 + MediaQuery.of(context).padding.bottom),
            decoration: BoxDecoration(
                color: themeCtrl.panel,
                border: Border(top: BorderSide(color: themeCtrl.line))),
            child: Row(children: [
              Expanded(
                child: TextField(
                  controller: msgCtrl,
                  decoration: InputDecoration(
                    hintText: 'Сообщение в канал',
                    filled: true,
                    fillColor: themeCtrl.input,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(22),
                        borderSide: BorderSide.none),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                  ),
                ),
              ),
              IconButton(
                  icon: const Icon(Icons.send, color: SLineColors.accentA),
                  onPressed: _send),
            ]),
          )
        else
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: SizedBox(
                width: double.infinity,
                height: 48,
                child: OutlinedButton.icon(
                  onPressed: _toggleMute,
                  icon: Icon(muted
                      ? Icons.notifications_active
                      : Icons.notifications_off),
                  label: Text(muted ? 'Вкл. звук' : 'Убр. звук'),
                ),
              ),
            ),
          ),
      ]),
    );
  }
}

class ChannelInfoPage extends StatelessWidget {
  final String channelId;
  final String name;
  final String? avatarUrl;
  final String description;
  final bool isPublic;
  final String slug;
  final bool isAdmin;
  final User? user;
  const ChannelInfoPage({
    super.key,
    required this.channelId,
    required this.name,
    this.avatarUrl,
    this.description = '',
    this.isPublic = true,
    this.slug = '',
    this.isAdmin = false,
    this.user,
  });
  @override
  Widget build(BuildContext context) {
    return GroupChannelInfoPage(
      user: user,
      chatKey: 'c_$channelId',
      entityId: channelId,
      name: name,
      avatarUrl: avatarUrl,
      description: description,
      isPublic: isPublic,
      slug: slug,
      isAdmin: isAdmin,
      isChannel: true,
    );
  }
}

/// Карточка группы / канала в стиле TG (без «В контакты»)
class GroupChannelInfoPage extends StatefulWidget {
  final User? user;
  final String chatKey;
  final String entityId;
  final String name;
  final String? avatarUrl;
  final String description;
  final bool isPublic;
  final String slug;
  final bool isAdmin;
  final bool isChannel;
  const GroupChannelInfoPage({
    super.key,
    this.user,
    required this.chatKey,
    required this.entityId,
    required this.name,
    this.avatarUrl,
    this.description = '',
    this.isPublic = true,
    this.slug = '',
    this.isAdmin = false,
    this.isChannel = false,
  });
  @override
  State<GroupChannelInfoPage> createState() => _GroupChannelInfoPageState();
}

class _GroupChannelInfoPageState extends State<GroupChannelInfoPage> {
  List<Profile> members = [];
  int memberCount = 0;
  bool loading = true;
  String? adminId;
  String link = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => loading = true);
    try {
      if (widget.isChannel) {
        final cs = await FirebaseDatabase.instance
            .ref('channels/${widget.entityId}')
            .get();
        if (cs.exists && cs.value is Map) {
          final d = Map<String, dynamic>.from(cs.value as Map);
          adminId = (d['admin_id'] ?? '').toString();
          final slug = (d['slug'] ?? d['username'] ?? widget.slug).toString();
          link = slug.isNotEmpty
              ? 'https://sigli.gleeze.com/#/channel/$slug'
              : 'https://sigli.gleeze.com/#/channel/${widget.entityId}';
        }
        final ms = await FirebaseDatabase.instance
            .ref('channel_members/${widget.entityId}')
            .get();
        final list = <Profile>[];
        if (ms.exists && ms.value is Map) {
          for (final e in (ms.value as Map).entries) {
            final p = await loadProfile(e.key.toString());
            if (p != null) list.add(p);
          }
        }
        if (mounted) {
          setState(() {
            members = list;
            memberCount = list.length;
            loading = false;
          });
        }
      } else {
        final gs = await FirebaseDatabase.instance
            .ref('groups/${widget.entityId}')
            .get();
        if (gs.exists && gs.value is Map) {
          final d = Map<String, dynamic>.from(gs.value as Map);
          adminId = (d['admin_id'] ?? '').toString();
          final slug = (d['slug'] ?? d['username'] ?? widget.slug).toString();
          final isPub = d['public'] != false;
          link = isPub && slug.isNotEmpty
              ? 'https://sigli.gleeze.com/#/g/$slug'
              : 'https://sigli.gleeze.com/#/g/${widget.entityId}';
        }
        final ms = await FirebaseDatabase.instance
            .ref('group_members/${widget.entityId}')
            .get();
        final list = <Profile>[];
        if (ms.exists && ms.value is Map) {
          for (final e in (ms.value as Map).entries) {
            final p = await loadProfile(e.key.toString());
            if (p != null) list.add(p);
          }
        }
        if (mounted) {
          setState(() {
            members = list;
            memberCount = list.length;
            loading = false;
          });
        }
      }
    } catch (_) {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _copyLink() async {
    if (link.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: link));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ссылка скопирована')));
    }
  }

  Future<void> _leave() async {
    final uid = widget.user?.uid;
    if (uid == null) return;
    final label = widget.isChannel ? 'канал' : 'группу';
    final ok = await showModalBottomSheet<bool>(
          context: context,
          backgroundColor: Colors.transparent,
          builder: (ctx) {
            final isLight = themeCtrl.light;
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: isLight
                            ? Colors.white
                            : const Color(0xFF2C2C2E),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Column(
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 18, 16, 12),
                            child: Text(
                              'Выйти из $label?',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 14,
                                color: isLight
                                    ? Colors.black54
                                    : Colors.white70,
                              ),
                            ),
                          ),
                          Divider(
                              height: 1,
                              color: isLight
                                  ? Colors.black12
                                  : Colors.white12),
                          SizedBox(
                            width: double.infinity,
                            height: 52,
                            child: TextButton(
                              onPressed: () => Navigator.pop(ctx, true),
                              child: const Text(
                                'Выйти',
                                style: TextStyle(
                                  color: Color(0xFFFF3B30),
                                  fontSize: 17,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      height: 52,
                      decoration: BoxDecoration(
                        color: isLight
                            ? Colors.white
                            : const Color(0xFF2C2C2E),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: Text(
                          'Отменить',
                          style: TextStyle(
                            color: SLineColors.accentA,
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ) ??
        false;
    if (!ok) return;
    try {
      if (widget.isChannel) {
        await FirebaseDatabase.instance
            .ref('channel_members/${widget.entityId}/$uid')
            .remove();
      } else {
        await FirebaseDatabase.instance
            .ref('group_members/${widget.entityId}/$uid')
            .remove();
      }
      await FirebaseDatabase.instance
          .ref('user_chat_index/$uid/${widget.chatKey}')
          .remove();
      if (mounted) {
        Navigator.of(context).popUntil((r) => r.isFirst);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.isChannel ? 'Канал' : 'Группа';
    final typeLabel = widget.isChannel
        ? (widget.isPublic ? 'Публичный канал' : 'Приватный канал')
        : (widget.isPublic ? 'Публичная группа' : 'Приватная группа');
    final isMeAdmin =
        widget.isAdmin || (adminId != null && adminId == widget.user?.uid);

    return Scaffold(
      backgroundColor: themeCtrl.bg,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 160,
            pinned: true,
            backgroundColor: themeCtrl.panel,
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      SLineColors.accentB.withValues(alpha: 0.95),
                      SLineColors.accentA.withValues(alpha: 0.8),
                    ],
                  ),
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Column(
              children: [
                const SizedBox(height: 16),
                Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: themeCtrl.bg, width: 4),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.12),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: _Avatar(
                    name: widget.name,
                    color: SLineColors.accentB,
                    url: widget.avatarUrl,
                    size: 104,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  widget.name,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: themeCtrl.text,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  typeLabel,
                  style: TextStyle(fontSize: 14, color: themeCtrl.muted),
                ),
                if (widget.slug.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      '@${widget.slug}',
                      style: TextStyle(
                        fontSize: 14,
                        color: SLineColors.accentA,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                const SizedBox(height: 16),
                // Действия: ссылка / выйти (без «В контакты»)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      Expanded(
                        child: _ProfileActionChip(
                          icon: Icons.link_rounded,
                          label: 'Ссылка',
                          onTap: _copyLink,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _ProfileActionChip(
                          icon: Icons.notifications_outlined,
                          label: 'Увед.',
                          onTap: () {},
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _ProfileActionChip(
                          icon: Icons.exit_to_app_rounded,
                          label: 'Выйти',
                          onTap: _leave,
                        ),
                      ),
                    ],
                  ),
                ),
                // Описание
                if (widget.description.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: themeCtrl.panel,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: themeCtrl.line),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Описание',
                            style: TextStyle(
                              fontSize: 12,
                              color: themeCtrl.muted,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            widget.description,
                            style: TextStyle(
                              fontSize: 15,
                              color: themeCtrl.text,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                // Ссылка
                if (link.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: InkWell(
                      onTap: _copyLink,
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: themeCtrl.panel,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: themeCtrl.line),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Ссылка-приглашение',
                              style: TextStyle(
                                fontSize: 12,
                                color: themeCtrl.muted,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              link,
                              style: TextStyle(
                                fontSize: 13,
                                color: SLineColors.accentA,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                // Участники
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
                  child: Row(
                    children: [
                      Text(
                        widget.isChannel ? 'Подписчики' : 'Участники',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: themeCtrl.text,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        '$memberCount',
                        style: TextStyle(
                          fontSize: 14,
                          color: themeCtrl.muted,
                        ),
                      ),
                    ],
                  ),
                ),
                if (loading)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (members.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'Пока никого нет',
                      style: TextStyle(color: themeCtrl.muted),
                    ),
                  )
                else
                  ...members.map((m) {
                    final isAdm = m.id == adminId;
                    return ListTile(
                      leading: _Avatar(
                        name: m.displayName,
                        color: m.colorValue,
                        url: m.avatarUrl,
                        size: 44,
                      ),
                      title: Text(m.displayName),
                      subtitle: Text(
                        isAdm
                            ? 'админ'
                            : (m.username.isNotEmpty
                                ? '@${m.username}'
                                : ''),
                        style: TextStyle(
                          color: isAdm
                              ? SLineColors.accentA
                              : themeCtrl.muted,
                          fontSize: 13,
                        ),
                      ),
                      onTap: () {
                        if (widget.user == null) return;
                        Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => ProfilePage(
                            user: widget.user!,
                            profile: m,
                            isMe: m.id == widget.user!.uid,
                          ),
                        ));
                      },
                    );
                  }),
                if (isMeAdmin)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                    child: Text(
                      'Вы администратор этого $title',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12,
                        color: themeCtrl.muted,
                      ),
                    ),
                  ),
                const SizedBox(height: 40),
              ],
            ),
          ),
        ],
      ),
    );
  }
}




// ── In-app WebRTC call (без внешних сайтов) ─────────────────

// ── Входящий звонок на весь экран ────────────────────────────
class IncomingCallScreen extends StatefulWidget {
  final String callId;
  final User user;
  final Profile peer;
  final bool audioOnly;
  const IncomingCallScreen({
    super.key,
    required this.callId,
    required this.user,
    required this.peer,
    required this.audioOnly,
  });
  @override
  State<IncomingCallScreen> createState() => _IncomingCallScreenState();
}

class _IncomingCallScreenState extends State<IncomingCallScreen> {
  StreamSubscription? _sub;

  @override
  void initState() {
    super.initState();
    _sub = FirebaseDatabase.instance
        .ref('calls/${widget.callId}/status')
        .onValue
        .listen((ev) {
      final st = (ev.snapshot.value ?? '').toString();
      if (st == 'ended' || st == 'rejected' || st == 'cancelled') {
        if (mounted) Navigator.of(context).maybePop();
      }
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _accept() async {
    try {
      await FirebaseDatabase.instance
          .ref('calls/${widget.callId}/status')
          .set('accepted');
    } catch (_) {}
    if (!mounted) return;
    Navigator.of(context).pushReplacement(MaterialPageRoute(
      builder: (_) => InAppCallScreen(
        callId: widget.callId,
        user: widget.user,
        peer: widget.peer,
        audioOnly: widget.audioOnly,
        isCaller: false,
      ),
    ));
  }

  Future<void> _reject() async {
    try {
      await FirebaseDatabase.instance
          .ref('calls/${widget.callId}/status')
          .set('rejected');
    } catch (_) {}
    if (mounted) Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final peer = widget.peer;
    return Scaffold(
      backgroundColor: const Color(0xFF0B1220),
      body: SafeArea(
        child: Column(
          children: [
            const Spacer(),
            Text(
              widget.audioOnly ? 'Входящий звонок' : 'Входящий видеозвонок',
              style: const TextStyle(color: Colors.white70, fontSize: 16),
            ),
            const SizedBox(height: 24),
            _Avatar(
              name: peer.displayName,
              color: peer.colorValue,
              url: peer.avatarUrl,
              size: 120,
            ),
            const SizedBox(height: 20),
            Text(
              peer.displayName,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text('@${peer.username}',
                style: const TextStyle(color: Colors.white54)),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.only(bottom: 48),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _roundBtn(
                    color: SLineColors.danger,
                    icon: Icons.call_end,
                    label: 'Отклонить',
                    onTap: _reject,
                  ),
                  _roundBtn(
                    color: const Color(0xFF22C55E),
                    icon: Icons.call,
                    label: 'Принять',
                    onTap: _accept,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _roundBtn({
    required Color color,
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return Column(
      children: [
        Material(
          color: color,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: SizedBox(
              width: 72,
              height: 72,
              child: Icon(icon, color: Colors.white, size: 32),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(label, style: const TextStyle(color: Colors.white70)),
      ],
    );
  }
}

class InAppCallScreen extends StatefulWidget {
  final String callId;
  final User user;
  final Profile peer;
  final bool audioOnly;
  final bool isCaller;
  const InAppCallScreen({
    super.key,
    required this.callId,
    required this.user,
    required this.peer,
    required this.audioOnly,
    required this.isCaller,
  });
  @override
  State<InAppCallScreen> createState() => _InAppCallScreenState();
}

class _InAppCallScreenState extends State<InAppCallScreen> {
  StreamSubscription? _sub;
  StreamSubscription? _iceSub;
  String status = 'ringing';
  bool muted = false;
  bool camOff = false;
  DateTime? connectedAt;
  Timer? _tick;
  String timerLabel = '00:00';

  final _localRenderer = RTCVideoRenderer();
  final _remoteRenderer = RTCVideoRenderer();
  RTCPeerConnection? _pc;
  MediaStream? _localStream;
  final List<RTCIceCandidate> _pendingIce = [];
  bool _remoteDescSet = false;

  DatabaseReference get _callRef =>
      FirebaseDatabase.instance.ref('calls/${widget.callId}');

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    await _localRenderer.initialize();
    await _remoteRenderer.initialize();
    await _initPeer();
    _sub = _callRef.onValue.listen(_onCallData);
    if (widget.isCaller) {
      await _createOffer();
    }
  }

  Future<void> _initPeer() async {
    final config = {
      'iceServers': [
        {'urls': 'stun:stun.l.google.com:19302'},
        {'urls': 'stun:stun1.l.google.com:19302'},
      ]
    };
    _pc = await createPeerConnection(config);
    _pc!.onIceCandidate = (c) {
      if (c.candidate == null) return;
      _callRef.child('ice/${widget.user.uid}').push().set({
        'candidate': c.candidate,
        'sdpMid': c.sdpMid,
        'sdpMLineIndex': c.sdpMLineIndex,
      });
    };
    _pc!.onTrack = (ev) {
      if (ev.streams.isNotEmpty) {
        _remoteRenderer.srcObject = ev.streams[0];
        if (mounted) {
          setState(() {
            status = 'connected';
            connectedAt ??= DateTime.now();
            _tick ??= Timer.periodic(const Duration(seconds: 1), (_) {
              if (!mounted || connectedAt == null) return;
              final s = DateTime.now().difference(connectedAt!).inSeconds;
              setState(() {
                timerLabel =
                    '${(s ~/ 60).toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}';
              });
            });
          });
        }
      }
    };
    _pc!.onConnectionState = (s) {
      if (s == RTCPeerConnectionState.RTCPeerConnectionStateConnected &&
          mounted) {
        setState(() => status = 'connected');
      }
    };

    final mediaConstraints = <String, dynamic>{
      'audio': true,
      'video': widget.audioOnly
          ? false
          : {
              'facingMode': 'user',
              'width': 640,
              'height': 480,
            },
    };
    try {
      _localStream =
          await navigator.mediaDevices.getUserMedia(mediaConstraints);
      _localRenderer.srcObject = _localStream;
      for (final t in _localStream!.getTracks()) {
        await _pc!.addTrack(t, _localStream!);
      }
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Медиа: $e')));
      }
    }

    _iceSub = _callRef.child('ice').onChildAdded.listen((ev) async {
      // listen to peer ice under peer uid
    });
    // Подписка на ICE собеседника
    final peerId = widget.peer.id;
    FirebaseDatabase.instance
        .ref('calls/${widget.callId}/ice/$peerId')
        .onChildAdded
        .listen((ev) async {
      if (ev.snapshot.value is! Map) return;
      final m = Map<String, dynamic>.from(ev.snapshot.value as Map);
      final c = RTCIceCandidate(
        m['candidate']?.toString(),
        m['sdpMid']?.toString(),
        m['sdpMLineIndex'] is int
            ? m['sdpMLineIndex'] as int
            : int.tryParse('${m['sdpMLineIndex']}') ?? 0,
      );
      if (_remoteDescSet) {
        try {
          await _pc?.addCandidate(c);
        } catch (_) {}
      } else {
        _pendingIce.add(c);
      }
    });
  }

  Future<void> _createOffer() async {
    final offer = await _pc!.createOffer({
      'offerToReceiveAudio': 1,
      'offerToReceiveVideo': widget.audioOnly ? 0 : 1,
    });
    await _pc!.setLocalDescription(offer);
    await _callRef.update({
      'offer': {'type': offer.type, 'sdp': offer.sdp},
      'status': 'ringing',
    });
  }

  Future<void> _createAnswer() async {
    final answer = await _pc!.createAnswer({
      'offerToReceiveAudio': 1,
      'offerToReceiveVideo': widget.audioOnly ? 0 : 1,
    });
    await _pc!.setLocalDescription(answer);
    await _callRef.update({
      'answer': {'type': answer.type, 'sdp': answer.sdp},
      'status': 'accepted',
    });
  }

  Future<void> _onCallData(DatabaseEvent e) async {
    if (!e.snapshot.exists || e.snapshot.value is! Map) return;
    final m = Map<String, dynamic>.from(e.snapshot.value as Map);
    final st = (m['status'] ?? '').toString();
    if (mounted && st.isNotEmpty) setState(() => status = st);
    if (st == 'ended' || st == 'rejected') {
      if (mounted) Navigator.of(context).maybePop();
      return;
    }
    if (!widget.isCaller && m['offer'] is Map && !_remoteDescSet) {
      final o = Map<String, dynamic>.from(m['offer'] as Map);
      await _pc!.setRemoteDescription(
          RTCSessionDescription(o['sdp']?.toString(), o['type']?.toString()));
      _remoteDescSet = true;
      for (final c in _pendingIce) {
        try {
          await _pc!.addCandidate(c);
        } catch (_) {}
      }
      _pendingIce.clear();
      await _createAnswer();
    }
    if (widget.isCaller && m['answer'] is Map && !_remoteDescSet) {
      final a = Map<String, dynamic>.from(m['answer'] as Map);
      await _pc!.setRemoteDescription(
          RTCSessionDescription(a['sdp']?.toString(), a['type']?.toString()));
      _remoteDescSet = true;
      for (final c in _pendingIce) {
        try {
          await _pc!.addCandidate(c);
        } catch (_) {}
      }
      _pendingIce.clear();
    }
  }

  Future<void> _hangup() async {
    try {
      await _callRef.child('status').set('ended');
    } catch (_) {}
    await _cleanup();
    if (mounted) Navigator.of(context).maybePop();
  }

  Future<void> _cleanup() async {
    await _localStream?.dispose();
    await _pc?.close();
    await _localRenderer.dispose();
    await _remoteRenderer.dispose();
  }

  Future<void> _toggleMute() async {
    setState(() => muted = !muted);
    _localStream?.getAudioTracks().forEach((t) => t.enabled = !muted);
  }

  Future<void> _toggleCam() async {
    setState(() => camOff = !camOff);
    _localStream?.getVideoTracks().forEach((t) => t.enabled = !camOff);
  }

  @override
  void dispose() {
    _sub?.cancel();
    _iceSub?.cancel();
    _tick?.cancel();
    _cleanup();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final peer = widget.peer;
    return Scaffold(
      backgroundColor: const Color(0xFF0B1220),
      body: SafeArea(
        child: Stack(children: [
          Positioned.fill(
            child: widget.audioOnly
                ? Container(
                    color: const Color(0xFF0B1220),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _Avatar(
                              name: peer.displayName,
                              color: peer.colorValue,
                              url: peer.avatarUrl,
                              size: 110),
                          const SizedBox(height: 16),
                          Text(peer.displayName,
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 22,
                                  fontWeight: FontWeight.w700)),
                        ],
                      ),
                    ),
                  )
                : RTCVideoView(_remoteRenderer,
                    objectFit:
                        RTCVideoViewObjectFit.RTCVideoViewObjectFitCover),
          ),
          if (!widget.audioOnly)
            Positioned(
              right: 14,
              top: 14,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  width: 110,
                  height: 160,
                  child: RTCVideoView(_localRenderer, mirror: true),
                ),
              ),
            ),
          Positioned(
            top: 12,
            left: 12,
            right: 12,
            child: Column(children: [
              Text(peer.displayName,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w700)),
              Text(
                status == 'ringing'
                    ? (widget.isCaller ? 'Вызов…' : 'Входящий…')
                    : status == 'connected'
                        ? timerLabel
                        : status,
                style: const TextStyle(color: Colors.white70),
              ),
              const Text('SLine WebRTC',
                  style: TextStyle(color: Colors.white38, fontSize: 11)),
            ]),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 36,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _cBtn(
                    icon: muted ? Icons.mic_off : Icons.mic,
                    onTap: _toggleMute),
                _cBtn(
                    icon: Icons.call_end,
                    color: SLineColors.danger,
                    onTap: _hangup,
                    big: true),
                if (!widget.audioOnly)
                  _cBtn(
                      icon: camOff ? Icons.videocam_off : Icons.videocam,
                      onTap: _toggleCam)
                else
                  _cBtn(icon: Icons.volume_up, onTap: () {}),
              ],
            ),
          ),
        ]),
      ),
    );
  }

  Widget _cBtn({
    required IconData icon,
    required VoidCallback onTap,
    Color? color,
    bool big = false,
  }) {
    final sz = big ? 72.0 : 56.0;
    return Material(
      color: color ?? Colors.white24,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: sz,
          height: sz,
          child: Icon(icon, color: Colors.white, size: big ? 34 : 26),
        ),
      ),
    );
  }
}

// ── Галерея внутри мессенджера (как в TG) ───────────────────
class InAppGalleryPicker extends StatefulWidget {
  final RequestType requestType;
  const InAppGalleryPicker({super.key, this.requestType = RequestType.image});
  @override
  State<InAppGalleryPicker> createState() => _InAppGalleryPickerState();
}

class _InAppGalleryPickerState extends State<InAppGalleryPicker> {
  List<AssetEntity> assets = [];
  bool loading = true;
  String? error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final perm = await PhotoManager.requestPermissionExtend();
      if (!perm.isAuth && !perm.hasAccess) {
        setState(() {
          loading = false;
          error = 'Нет доступа к галерее';
        });
        return;
      }
      final filter = FilterOptionGroup(
        orders: [
          const OrderOption(type: OrderOptionType.createDate, asc: false),
        ],
      );
      final paths = await PhotoManager.getAssetPathList(
        type: widget.requestType,
        onlyAll: true,
        filterOption: filter,
      );
      if (paths.isEmpty) {
        setState(() {
          loading = false;
          assets = [];
        });
        return;
      }
      List<AssetEntity> list = [];
      try {
        list = await paths.first.getAssetListRange(start: 0, end: 120);
      } catch (_) {
        try {
          list = await paths.first.getAssetListPaged(page: 0, size: 60);
        } catch (e2) {
          if (mounted) {
            setState(() {
              loading = false;
              error = null;
              assets = [];
            });
          }
          return;
        }
      }
      if (mounted) {
        setState(() {
          assets = list;
          loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          loading = false;
          error = null;
          assets = [];
        });
      }
    }
  }

  Future<void> _pick(AssetEntity a) async {
    final f = await a.file;
    if (f == null) return;
    if (mounted) Navigator.pop(context, f.path);
  }

  @override
  Widget build(BuildContext context) {
    final h = MediaQuery.of(context).size.height * 0.72;
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: Container(
          height: h,
          color: themeCtrl.light
              ? Colors.white.withValues(alpha: 0.92)
              : const Color(0xFF12181F).withValues(alpha: 0.95),
          child: Column(
            children: [
              const SizedBox(height: 8),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: themeCtrl.muted.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
                child: Row(
                  children: [
                    Text(
                      widget.requestType == RequestType.video
                          ? 'Видео'
                          : 'Галерея',
                      style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: themeCtrl.text),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Закрыть'),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: loading
                    ? const Center(child: CircularProgressIndicator())
                    : error != null
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(error!,
                                      textAlign: TextAlign.center,
                                      style: TextStyle(color: themeCtrl.muted)),
                                  const SizedBox(height: 12),
                                  TextButton(
                                    onPressed: () =>
                                        PhotoManager.openSetting(),
                                    child: const Text('Открыть настройки'),
                                  ),
                                ],
                              ),
                            ),
                          )
                        : assets.isEmpty
                            ? Center(
                                child: Text('Пусто',
                                    style: TextStyle(color: themeCtrl.muted)))
                            : GridView.builder(
                                padding: const EdgeInsets.all(6),
                                gridDelegate:
                                    const SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: 3,
                                  crossAxisSpacing: 4,
                                  mainAxisSpacing: 4,
                                ),
                                itemCount: assets.length,
                                itemBuilder: (_, i) {
                                  final a = assets[i];
                                  return FutureBuilder<Uint8List?>(
                                    future: a.thumbnailDataWithSize(
                                        const ThumbnailSize(300, 300)),
                                    builder: (_, s) {
                                      return GestureDetector(
                                        onTap: () => _pick(a),
                                        child: ClipRRect(
                                          borderRadius:
                                              BorderRadius.circular(10),
                                          child: s.data != null
                                              ? Image.memory(s.data!,
                                                  fit: BoxFit.cover)
                                              : Container(
                                                  color: themeCtrl.input),
                                        ),
                                      );
                                    },
                                  );
                                },
                              ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}


class _ChatDoodlePainter extends CustomPainter {
  final Color base;
  final bool light;
  _ChatDoodlePainter({required this.base, required this.light});

  @override
  void paint(Canvas canvas, Size size) {
    // Тёмная тема — почти чёрный фон с тонкими светлыми контурами (как TG dark)
    final bg = light ? base : const Color(0xFF0E0E0E);
    canvas.drawRect(Offset.zero & size, Paint()..color = bg);
    final paint = Paint()
      ..color = light
          ? Colors.black.withValues(alpha: 0.08)
          : const Color(0xFF3A3A3A).withValues(alpha: 0.55)
      ..style = PaintingStyle.stroke
      ..strokeWidth = light ? 1.1 : 1.0;
    const step = 48.0;
    for (double y = 8; y < size.height; y += step) {
      for (double x = 8; x < size.width; x += step) {
        final i = ((x / step).floor() * 7 + (y / step).floor() * 3) % 10;
        final o = Offset(x + ((y / step).floor() % 2) * 8, y);
        switch (i) {
          case 0: // cake
            canvas.drawRRect(
                RRect.fromRectAndRadius(
                    Rect.fromCenter(center: o, width: 12, height: 10),
                    const Radius.circular(2)),
                paint);
            canvas.drawLine(o.translate(-3, -7), o.translate(-3, -3), paint);
            canvas.drawLine(o.translate(3, -7), o.translate(3, -3), paint);
            break;
          case 1: // house
            final path = Path()
              ..moveTo(o.dx, o.dy - 7)
              ..lineTo(o.dx + 7, o.dy)
              ..lineTo(o.dx + 7, o.dy + 6)
              ..lineTo(o.dx - 7, o.dy + 6)
              ..lineTo(o.dx - 7, o.dy)
              ..close();
            canvas.drawPath(path, paint);
            break;
          case 2: // star
            canvas.drawCircle(o, 2, paint);
            canvas.drawLine(o.translate(0, -6), o.translate(0, 6), paint);
            canvas.drawLine(o.translate(-6, 0), o.translate(6, 0), paint);
            break;
          case 3: // gift
            canvas.drawRect(
                Rect.fromCenter(center: o, width: 12, height: 10), paint);
            canvas.drawLine(o.translate(0, -5), o.translate(0, 5), paint);
            canvas.drawLine(o.translate(-6, -1), o.translate(6, -1), paint);
            break;
          case 4: // heart-ish
            canvas.drawOval(
                Rect.fromCenter(center: o.translate(-3, -1), width: 6, height: 6),
                paint);
            canvas.drawOval(
                Rect.fromCenter(center: o.translate(3, -1), width: 6, height: 6),
                paint);
            break;
          case 5: // cupcake
            canvas.drawOval(
                Rect.fromCenter(center: o.translate(0, -3), width: 10, height: 6),
                paint);
            canvas.drawRRect(
                RRect.fromRectAndRadius(
                    Rect.fromCenter(center: o.translate(0, 3), width: 12, height: 6),
                    const Radius.circular(2)),
                paint);
            break;
          case 6: // pizza
            final p2 = Path()
              ..moveTo(o.dx, o.dy - 7)
              ..lineTo(o.dx + 7, o.dy + 5)
              ..lineTo(o.dx - 7, o.dy + 5)
              ..close();
            canvas.drawPath(p2, paint);
            break;
          case 7: // ice cream
            canvas.drawCircle(o.translate(0, -3), 5, paint);
            final cone = Path()
              ..moveTo(o.dx - 4, o.dy)
              ..lineTo(o.dx + 4, o.dy)
              ..lineTo(o.dx, o.dy + 8)
              ..close();
            canvas.drawPath(cone, paint);
            break;
          case 8: // balloon
            canvas.drawOval(
                Rect.fromCenter(center: o.translate(0, -3), width: 10, height: 12),
                paint);
            canvas.drawLine(o.translate(0, 3), o.translate(0, 8), paint);
            break;
          default: // book
            canvas.drawRRect(
                RRect.fromRectAndRadius(
                    Rect.fromCenter(center: o, width: 10, height: 12),
                    const Radius.circular(1)),
                paint);
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _ChatDoodlePainter old) =>
      old.base != base || old.light != light;
}



// ── «Начать общение» как в TG ────────────────────────────────
class StartChatPage extends StatefulWidget {
  final User user;
  final Profile? myProfile;
  const StartChatPage({super.key, required this.user, this.myProfile});
  @override
  State<StartChatPage> createState() => _StartChatPageState();
}

class _StartChatPageState extends State<StartChatPage> {
  final qCtrl = TextEditingController();
  List<Profile> recent = [];
  List<Profile> found = [];
  bool searching = false;

  @override
  void initState() {
    super.initState();
    _loadRecent();
  }

  Future<void> _loadRecent() async {
    try {
      final snap = await FirebaseDatabase.instance
          .ref('my_contacts/${widget.user.uid}')
          .get();
      final list = <Profile>[];
      if (snap.exists && snap.value is Map) {
        for (final id in (snap.value as Map).keys) {
          final p = await loadProfile(id.toString());
          if (p != null) list.add(p);
        }
      }
      if (mounted) setState(() => recent = list);
    } catch (_) {}
  }

  Future<void> _search(String q) async {
    q = q.trim().toLowerCase();
    if (q.isEmpty) {
      setState(() {
        found = [];
        searching = false;
      });
      return;
    }
    setState(() => searching = true);
    try {
      final snap =
          await FirebaseDatabase.instance.ref('tables/profiles').get();
      final list = <Profile>[];
      if (snap.exists && snap.value is Map) {
        for (final e in (snap.value as Map).entries) {
          if (e.value is! Map) continue;
          final p = Profile.fromMap(
              e.key.toString(), Map<String, dynamic>.from(e.value as Map));
          final hay =
              '${p.displayName} ${p.username} ${p.email ?? ''}'.toLowerCase();
          if (hay.contains(q) || '@${p.username}'.contains(q)) {
            list.add(p);
          }
        }
      }
      if (mounted) {
        setState(() {
          found = list;
          searching = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => searching = false);
    }
  }

  void _open(Profile p) {
    final key = dmPairKey(widget.user.uid, p.id);
    Navigator.of(context).pushReplacement(MaterialPageRoute(
      builder: (_) => ChatScreen(
        user: widget.user,
        peer: p,
        chatKey: key,
        myProfile: widget.myProfile,
      ),
    ));
  }

  Widget _action(IconData icon, String title, VoidCallback onTap) {
    return ListTile(
      leading: Icon(icon, color: SLineColors.accentA),
      title: Text(title,
          style: const TextStyle(
              color: SLineColors.accentA, fontWeight: FontWeight.w600)),
      onTap: onTap,
    );
  }

  @override
  Widget build(BuildContext context) {
    final showSearch = qCtrl.text.trim().isNotEmpty;
    return Scaffold(
      backgroundColor: themeCtrl.bg,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Начать общение'),
        centerTitle: true,
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: TextField(
            controller: qCtrl,
            onChanged: _search,
            decoration: InputDecoration(
              hintText: 'Имя, @username, email или @bot',
              filled: true,
              fillColor: themeCtrl.input,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            ),
          ),
        ),
        Expanded(
          child: ListView(
            children: [
              if (!showSearch) ...[
                _action(Icons.person_add_alt_1, 'Добавить контакт', () {
                  Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => SearchPage(
                      user: widget.user,
                      myProfile: widget.myProfile,
                      onOpenChat: (p) async {
                        await FirebaseDatabase.instance
                            .ref('my_contacts/${widget.user.uid}/${p.id}')
                            .set(true);
                        if (context.mounted) _open(p);
                      },
                    ),
                  ));
                }),
                _action(Icons.group_add_outlined, 'Создать группу', () {
                  Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => CreateGroupPage(
                        user: widget.user, myProfile: widget.myProfile),
                  ));
                }),
                _action(Icons.call_outlined, 'Создать групповой звонок', () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text('Групповые звонки — скоро')),
                  );
                }),
                _action(Icons.campaign_outlined, 'Создать канал', () {
                  Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => CreateChannelPage(
                        user: widget.user, myProfile: widget.myProfile),
                  ));
                }),
                _action(Icons.smart_toy_outlined, 'Создать бота', () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Боты — в разработке')),
                  );
                }),
                _action(Icons.search, 'Найти бота по @username', () {
                  FocusScope.of(context).requestFocus(FocusNode());
                  qCtrl.text = '@';
                  setState(() {});
                }),
                _action(Icons.phone_outlined, 'Найти по номеру', () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text('Поиск по номеру — введите в поле')),
                  );
                }),
                _action(Icons.email_outlined, 'Найти по email', () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text('Введите email в поле поиска')),
                  );
                }),
                _action(Icons.link, 'Пригласить по ссылке', () {
                  final link =
                      'https://sigli.gleeze.com/#/u/${widget.myProfile?.username ?? widget.user.uid}';
                  Clipboard.setData(ClipboardData(text: link));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Ссылка скопирована')),
                  );
                }),
                const Divider(),
              ],
              if (searching)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (showSearch)
                for (final p in found)
                  ListTile(
                    leading: _Avatar(
                        name: p.displayName,
                        color: p.colorValue,
                        url: p.avatarUrl),
                    title: Text(p.displayName),
                    subtitle: Text('@${p.username}'),
                    onTap: () => _open(p),
                  )
              else
                for (final p in recent)
                  ListTile(
                    leading: _Avatar(
                        name: p.displayName,
                        color: p.colorValue,
                        url: p.avatarUrl),
                    title: Text(p.displayName),
                    subtitle: Text('@${p.username}'),
                    onTap: () => _open(p),
                  ),
            ],
          ),
        ),
      ]),
    );
  }
}

// ── TG-style панель вложений ─────────────────────────────────
class _TgAttachPanel extends StatefulWidget {
  final VoidCallback onPhoto;
  final VoidCallback onVideo;
  final VoidCallback onFile;
  final VoidCallback onGif;
  final VoidCallback onSticker;
  final VoidCallback onPoll;
  final void Function(String giftId) onGiftId;
  final VoidCallback onLocation;
  final void Function(String path, bool isVideo) onPickAsset;
  final VoidCallback? onWallet;
  const _TgAttachPanel({
    required this.onPhoto,
    required this.onVideo,
    required this.onFile,
    required this.onGif,
    required this.onSticker,
    required this.onPoll,
    required this.onGiftId,
    required this.onLocation,
    required this.onPickAsset,
    this.onWallet,
  });
  @override
  State<_TgAttachPanel> createState() => _TgAttachPanelState();
}

class _TgAttachPanelState extends State<_TgAttachPanel> {
  int tab = 0; // 0 gallery 1 gift 2 file 3 location
  List<AssetEntity> assets = [];
  bool loading = true;
  int scoinBal = 0;

  @override
  void initState() {
    super.initState();
    _load();
    _loadScoin();
  }

  Future<void> _loadScoin() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      await SCoin.ensureStarter(uid);
      final b = await SCoin.balance(uid);
      if (mounted) setState(() => scoinBal = b);
    } catch (_) {}
  }

  Future<void> _load() async {
    try {
      final perm = await PhotoManager.requestPermissionExtend();
      if (!perm.isAuth && !perm.hasAccess) {
        setState(() => loading = false);
        return;
      }
      final filter = FilterOptionGroup(
        orders: [
          const OrderOption(type: OrderOptionType.createDate, asc: false),
        ],
      );
      final paths = await PhotoManager.getAssetPathList(
        type: RequestType.common,
        onlyAll: true,
        filterOption: filter,
      );
      if (paths.isEmpty) {
        setState(() => loading = false);
        return;
      }
      List<AssetEntity> list = [];
      try {
        list = await paths.first.getAssetListRange(start: 0, end: 80);
      } catch (_) {
        try {
          list = await paths.first.getAssetListPaged(page: 0, size: 40);
        } catch (_) {}
      }
      if (mounted) {
        setState(() {
          assets = list;
          loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final h = MediaQuery.of(context).size.height * 0.55;
    return Container(
      height: h,
      decoration: BoxDecoration(
        color: themeCtrl.light ? Colors.white : const Color(0xFF1C1C1E),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Column(children: [
        const SizedBox(height: 8),
        Container(
          width: 36,
          height: 4,
          decoration: BoxDecoration(
            color: themeCtrl.muted.withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        Expanded(
          child: tab == 0
              ? (loading
                  ? const Center(child: CircularProgressIndicator())
                  : assets.isEmpty
                      ? Center(
                          child: TextButton.icon(
                            onPressed: () async {
                              try {
                                final x = await ImagePicker().pickImage(
                                    source: ImageSource.gallery);
                                if (x == null) return;
                                widget.onPickAsset(x.path, false);
                              } catch (_) {
                                widget.onPhoto();
                              }
                            },
                            icon: const Icon(Icons.photo_library),
                            label: const Text('Выбрать фото'),
                          ),
                        )
                      : GridView.builder(
                          padding: const EdgeInsets.all(4),
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3,
                            crossAxisSpacing: 2,
                            mainAxisSpacing: 2,
                          ),
                          itemCount: assets.length,
                          itemBuilder: (_, i) {
                            final a = assets[i];
                            return FutureBuilder<Uint8List?>(
                              future: a.thumbnailDataWithSize(
                                  const ThumbnailSize(280, 280)),
                              builder: (_, s) {
                                return GestureDetector(
                                  onTap: () async {
                                    final f = await a.file;
                                    if (f == null) return;
                                    widget.onPickAsset(
                                        f.path, a.type == AssetType.video);
                                  },
                                  child: Stack(fit: StackFit.expand, children: [
                                    if (s.data != null)
                                      Image.memory(s.data!, fit: BoxFit.cover)
                                    else
                                      Container(color: themeCtrl.input),
                                    if (a.type == AssetType.video)
                                      const Align(
                                        alignment: Alignment.bottomRight,
                                        child: Padding(
                                          padding: EdgeInsets.all(4),
                                          child: Icon(Icons.play_circle_fill,
                                              color: Colors.white, size: 20),
                                        ),
                                      ),
                                  ]),
                                );
                              },
                            );
                          },
                        ))
              : tab == 1
                  ? Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                          child: Row(
                            children: [
                              Text('Подарки',
                                  style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 16,
                                      color: themeCtrl.text)),
                              const Spacer(),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  color: SLineColors.accentA
                                      .withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Text('SL',
                                        style: TextStyle(
                                            fontWeight: FontWeight.w900,
                                            fontSize: 11,
                                            color: SLineColors.accentA)),
                                    const SizedBox(width: 6),
                                    Text('$scoinBal',
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w800,
                                            fontSize: 14,
                                            color: SLineColors.accentA)),
                                  ],
                                ),
                              ),
                              if (widget.onWallet != null) ...[
                                const SizedBox(width: 8),
                                IconButton(
                                  tooltip: 'Кошелёк',
                                  onPressed: widget.onWallet,
                                  icon: const Icon(
                                      Icons.account_balance_wallet_outlined,
                                      color: SLineColors.accentA),
                                ),
                              ],
                            ],
                          ),
                        ),
                        Expanded(
                          child: GridView.count(
                            padding: const EdgeInsets.all(12),
                            crossAxisCount: 4,
                            mainAxisSpacing: 10,
                            crossAxisSpacing: 10,
                            children: [
                              for (final g in SLineGifts.items)
                                InkWell(
                                  onTap: () => widget.onGiftId(g.$1),
                                  borderRadius: BorderRadius.circular(14),
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: themeCtrl.input,
                                      borderRadius: BorderRadius.circular(14),
                                      border:
                                          Border.all(color: themeCtrl.line),
                                    ),
                                    child: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Text(g.$2,
                                            style: const TextStyle(
                                                fontSize: 28)),
                                        const SizedBox(height: 2),
                                        Text(g.$3,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                                fontSize: 10,
                                                color: themeCtrl.muted)),
                                        Text('${g.$4} SL',
                                            style: TextStyle(
                                                fontSize: 10,
                                                fontWeight: FontWeight.w700,
                                                color: scoinBal >= g.$4
                                                    ? SLineColors.accentA
                                                    : themeCtrl.muted)),
                                      ],
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    )
                  : tab == 2
                      ? ListView(children: [
                          if (widget.onWallet != null)
                            ListTile(
                              leading: const Icon(Icons.account_balance_wallet,
                                  color: SLineColors.accentA),
                              title: const Text('Кошелёк'),
                              subtitle: const Text('Баланс SCoin и переводы'),
                              onTap: widget.onWallet,
                            ),
                          ListTile(
                            leading: const Icon(Icons.insert_drive_file),
                            title: const Text('Файл (APK, PDF, ZIP…)'),
                            onTap: widget.onFile,
                          ),
                          ListTile(
                            leading: const Icon(Icons.gif_box),
                            title: const Text('GIF'),
                            onTap: widget.onGif,
                          ),
                          ListTile(
                            leading: const Icon(Icons.emoji_emotions),
                            title: const Text('Стикеры'),
                            onTap: widget.onSticker,
                          ),
                          ListTile(
                            leading: const Icon(Icons.poll),
                            title: const Text('Опрос'),
                            onTap: widget.onPoll,
                          ),
                        ])
                      : ListView(
                          padding: const EdgeInsets.all(16),
                          children: [
                            ListTile(
                              leading: const Icon(Icons.my_location,
                                  color: SLineColors.accentA),
                              title: const Text('Отправить мою геопозицию'),
                              subtitle: const Text('Текущее местоположение'),
                              onTap: widget.onLocation,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Будет отправлена точка на карте. Нужен доступ к геолокации.',
                              style: TextStyle(
                                  fontSize: 12, color: themeCtrl.muted),
                            ),
                          ],
                        ),
        ),
        SafeArea(
          top: false,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _tab(Icons.photo_library, 'Галерея', 0),
              _tab(Icons.card_giftcard, 'Подарок', 1),
              _tab(Icons.insert_drive_file, 'Файл', 2),
              _tab(Icons.location_on_outlined, 'Гео', 3),
            ],
          ),
        ),
      ]),
    );
  }

  Widget _tab(IconData icon, String label, int i) {
    final on = tab == i;
    return InkWell(
      onTap: () => setState(() => tab = i),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                color: on ? SLineColors.accentA : themeCtrl.muted, size: 22),
            const SizedBox(height: 2),
            Text(label,
                style: TextStyle(
                    fontSize: 11,
                    color: on ? SLineColors.accentA : themeCtrl.muted)),
          ],
        ),
      ),
    );
  }
}


// ── Посты ────────────────────────────────────────────────────
class PostsPage extends StatefulWidget {
  final User user;
  final Profile? myProfile;
  const PostsPage({super.key, required this.user, this.myProfile});
  @override
  State<PostsPage> createState() => _PostsPageState();
}

class _PostsPageState extends State<PostsPage> {
  final List<Map<String, dynamic>> posts = [];
  StreamSubscription? sub;
  bool loading = true;

  @override
  void initState() {
    super.initState();
    sub = FirebaseDatabase.instance
        .ref('tables/posts')
        .orderByChild('created_at')
        .limitToLast(50)
        .onValue
        .listen((ev) {
      final list = <Map<String, dynamic>>[];
      if (ev.snapshot.exists && ev.snapshot.value is Map) {
        final m = Map<String, dynamic>.from(ev.snapshot.value as Map);
        for (final e in m.entries) {
          if (e.value is Map) {
            final item = Map<String, dynamic>.from(e.value as Map);
            item['id'] = e.key;
            list.add(item);
          }
        }
        list.sort((a, b) {
          final aa = (a['created_at'] ?? '').toString();
          final bb = (b['created_at'] ?? '').toString();
          return bb.compareTo(aa);
        });
      }
      if (mounted) {
        setState(() {
          posts
            ..clear()
            ..addAll(list);
          loading = false;
        });
      }
    }, onError: (e) {
      if (mounted) {
        setState(() => loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(permissionHelp(e))));
      }
    });
  }

  @override
  void dispose() {
    sub?.cancel();
    super.dispose();
  }

  Future<void> _createPost() async {
    final textC = TextEditingController();
    String? imagePath;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Новый пост'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: textC,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    hintText: 'Что нового?',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                if (imagePath != null)
                  Text('Фото выбрано',
                      style: TextStyle(color: themeCtrl.muted, fontSize: 12)),
                TextButton.icon(
                  onPressed: () async {
                    final x = await ImagePicker().pickImage(
                        source: ImageSource.gallery, imageQuality: 85);
                    if (x != null) setLocal(() => imagePath = x.path);
                  },
                  icon: const Icon(Icons.image_outlined),
                  label: const Text('Добавить фото'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Отмена')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Опубликовать')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final text = textC.text.trim();
    if (text.isEmpty && (imagePath == null || imagePath!.isEmpty)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Добавьте текст или фото')));
      }
      return;
    }
    try {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Публикация…')));
      }
      String? mediaUrl;
      if (imagePath != null && imagePath!.isNotEmpty) {
        mediaUrl = await B2Storage.uploadFile(
            File(imagePath!), 'posts', widget.user.uid);
      }
      final ref = FirebaseDatabase.instance.ref('tables/posts').push();
      final now = DateTime.now();
      await ref.set({
        'id': ref.key,
        'user_id': widget.user.uid,
        'author_name': widget.myProfile?.displayName ?? 'User',
        'author_avatar': widget.myProfile?.avatarUrl,
        'text': text,
        'media_url': mediaUrl,
        'created_at': now.toIso8601String(),
        'created_at_ms': now.millisecondsSinceEpoch,
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Пост опубликован')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(permissionHelp(e))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: themeCtrl.bg,
      appBar: AppBar(
        title: const Text('Посты'),
        backgroundColor: themeCtrl.panel,
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: _createPost,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _createPost,
        backgroundColor: SLineColors.accentA,
        child: const Icon(Icons.edit, color: Colors.white),
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : posts.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.dynamic_feed,
                          size: 48, color: themeCtrl.muted),
                      const SizedBox(height: 12),
                      Text('Пока нет постов',
                          style: TextStyle(color: themeCtrl.muted)),
                      const SizedBox(height: 12),
                      FilledButton(
                          onPressed: _createPost,
                          child: const Text('Создать пост')),
                    ],
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: posts.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (_, i) {
                    final post = posts[i];
                    final name = (post['author_name'] ?? 'User').toString();
                    final text = (post['text'] ?? '').toString();
                    final media = (post['media_url'] ?? '').toString();
                    final av = post['author_avatar']?.toString();
                    final at = (post['created_at'] ?? '').toString();
                    final authorId = (post['author_id'] ?? post['user_id'] ?? '')
                        .toString();
                    final postId = (post['id'] ?? '').toString();
                    final likesMap = post['likes'] is Map
                        ? Map<String, dynamic>.from(post['likes'] as Map)
                        : <String, dynamic>{};
                    final likeCount = likesMap.length;
                    final liked = likesMap.containsKey(widget.user.uid);
                    final comments = post['comments'] is Map
                        ? Map<String, dynamic>.from(post['comments'] as Map)
                        : <String, dynamic>{};
                    return Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: themeCtrl.panel,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: themeCtrl.line),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            GestureDetector(
                              onTap: authorId.isEmpty
                                  ? null
                                  : () async {
                                      final p = await loadProfile(authorId);
                                      if (p != null && mounted) {
                                        Navigator.of(context).push(
                                          MaterialPageRoute(
                                            builder: (_) => ProfilePage(
                                              user: widget.user,
                                              profile: p,
                                              isMe: authorId == widget.user.uid,
                                            ),
                                          ),
                                        );
                                      }
                                    },
                              child: _Avatar(
                                name: name,
                                color: SLineColors.accentA,
                                url: av,
                                size: 40,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(name,
                                      style: TextStyle(
                                          fontWeight: FontWeight.w700,
                                          color: themeCtrl.text)),
                                  if (at.isNotEmpty)
                                    Text(
                                        at.length > 16
                                            ? at.substring(0, 16)
                                            : at,
                                        style: TextStyle(
                                            fontSize: 11,
                                            color: themeCtrl.muted)),
                                ],
                              ),
                            ),
                          ]),
                          if (text.isNotEmpty) ...[
                            const SizedBox(height: 10),
                            Text(text,
                                style: TextStyle(
                                    fontSize: 15, color: themeCtrl.text)),
                          ],
                          if (media.isNotEmpty) ...[
                            const SizedBox(height: 10),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Image.network(
                                media,
                                width: double.infinity,
                                fit: BoxFit.cover,
                                headers: kMediaHeaders,
                                errorBuilder: (_, __, ___) => Container(
                                  height: 120,
                                  color: themeCtrl.input,
                                  alignment: Alignment.center,
                                  child: const Text('Фото недоступно'),
                                ),
                              ),
                            ),
                          ],
                          const SizedBox(height: 8),
                          Row(children: [
                            IconButton(
                              visualDensity: VisualDensity.compact,
                              onPressed: postId.isEmpty
                                  ? null
                                  : () async {
                                      final ref = FirebaseDatabase.instance
                                          .ref(
                                              'tables/posts/$postId/likes/${widget.user.uid}');
                                      if (liked) {
                                        await ref.remove();
                                      } else {
                                        await ref.set(true);
                                      }
                                    },
                              icon: Icon(
                                liked
                                    ? Icons.favorite
                                    : Icons.favorite_border,
                                color: liked
                                    ? SLineColors.danger
                                    : themeCtrl.muted,
                              ),
                            ),
                            Text('$likeCount',
                                style: TextStyle(color: themeCtrl.muted)),
                            const SizedBox(width: 12),
                            IconButton(
                              visualDensity: VisualDensity.compact,
                              onPressed: postId.isEmpty
                                  ? null
                                  : () => _commentPost(postId, comments),
                              icon: Icon(Icons.chat_bubble_outline,
                                  color: themeCtrl.muted),
                            ),
                            Text('${comments.length}',
                                style: TextStyle(color: themeCtrl.muted)),
                          ]),
                          // Комментарии только по кнопке, не в ленте
                        ],
                      ),
                    );
                  },
                ),
    );
  }

  Future<void> _commentPost(
      String postId, Map<String, dynamic> existing) async {
    final ctrl = TextEditingController();
    final sorted = existing.entries.toList()
      ..sort((a, b) {
        final at = (a.value is Map
                ? (a.value as Map)['created_at']
                : 0) as int? ??
            0;
        final bt = (b.value is Map
                ? (b.value as Map)['created_at']
                : 0) as int? ??
            0;
        return at.compareTo(bt);
      });
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: themeCtrl.panel,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 12,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: themeCtrl.muted.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Text('Комментарии (${existing.length})',
                  style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                      color: themeCtrl.text)),
              const SizedBox(height: 12),
              if (sorted.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Text('Пока нет комментариев',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: themeCtrl.muted)),
                )
              else
                ConstrainedBox(
                  constraints: BoxConstraints(
                      maxHeight: MediaQuery.of(ctx).size.height * 0.4),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: sorted.length,
                    separatorBuilder: (_, __) => const Divider(height: 12),
                    itemBuilder: (_, i) {
                      final c = sorted[i].value is Map
                          ? Map<String, dynamic>.from(
                              sorted[i].value as Map)
                          : <String, dynamic>{};
                      final cText = (c['text'] ?? '').toString();
                      final cUid = (c['user_id'] ?? '').toString();
                      final isMeC = cUid == widget.user.uid;
                      return ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: CircleAvatar(
                          radius: 16,
                          backgroundColor: SLineColors.accentA
                              .withValues(alpha: 0.2),
                          child: Text(
                            isMeC
                                ? 'Я'
                                : (cUid.isNotEmpty
                                    ? cUid[0].toUpperCase()
                                    : '?'),
                            style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700),
                          ),
                        ),
                        title: Text(cText,
                            style: TextStyle(color: themeCtrl.text)),
                        subtitle: Text(
                          isMeC
                              ? 'Вы'
                              : (cUid.length > 8
                                  ? cUid.substring(0, 8)
                                  : cUid),
                          style: TextStyle(
                              fontSize: 11, color: themeCtrl.muted),
                        ),
                      );
                    },
                  ),
                ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: ctrl,
                      maxLines: 2,
                      decoration: InputDecoration(
                        hintText: 'Написать комментарий…',
                        filled: true,
                        fillColor: themeCtrl.input,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: () async {
                      final t = ctrl.text.trim();
                      if (t.isEmpty) return;
                      try {
                        await FirebaseDatabase.instance
                            .ref('tables/posts/$postId/comments')
                            .push()
                            .set({
                          'user_id': widget.user.uid,
                          'text': t,
                          'created_at':
                              DateTime.now().millisecondsSinceEpoch,
                        });
                        if (ctx.mounted) Navigator.pop(ctx);
                      } catch (e) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(permissionHelp(e))));
                        }
                      }
                    },
                    icon: const Icon(Icons.send_rounded),
                    style: IconButton.styleFrom(
                        backgroundColor: SLineColors.accentA),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}
