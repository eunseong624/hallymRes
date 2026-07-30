import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' as latlong;
import 'package:shared_preferences/shared_preferences.dart';
import 'firebase_options.dart';

const String kSchoolDomain = 'hallym.ac.kr';
const String kAppName = '먹자골목';

// ===== EmailJS 설정 (인증코드 메일 발송용) =====
const String kEmailJsServiceId = 'service_7gp8yju';
const String kEmailJsTemplateId = 'template_1ioktv8';
const String kEmailJsPublicKey = 'O9uobK20cRJZnWZHV';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const SlipperApp());
}

/// ============================================================
/// 디자인 토큰
/// ============================================================
List<BoxShadow> softShadow(Color tint,
        {double opacity = 0.12, double blur = 18, double dy = 8}) =>
    [
      BoxShadow(
          color: tint.withOpacity(opacity),
          blurRadius: blur,
          offset: Offset(0, dy)),
    ];

class AppColors {
  AppColors._();

  static const Color coral = Color(0xFFFF3B5C);
  static const Color gradientStart = coral;
  static const Color gradientEnd = coral;
  static const Color dark = Color(0xFF16161C);

  static const Color background = Colors.white;
  static const Color surface = Colors.white;
  static const Color surfaceMuted = Color(0xFFF4F4F6);

  static const Color ink = Color(0xFF1A1A1E);
  static const Color inkFaint = Color(0xFF8E8E93);
  static const Color divider = Color(0xFFECECEF);

  static const Color gold = Color(0xFFFFB300);
  static const Color stamp = Color(0xFFE5484D);

  static const gradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [coral, coral],
  );
}

class T {
  T._();

  static TextStyle heading(
          {double size = 20,
          Color color = AppColors.ink,
          FontWeight w = FontWeight.w800}) =>
      GoogleFonts.notoSansKr(
          fontSize: size,
          color: color,
          fontWeight: w,
          height: 1.25,
          letterSpacing: -0.3);

  static TextStyle body(
          {double size = 14,
          Color color = AppColors.ink,
          FontWeight w = FontWeight.w400}) =>
      GoogleFonts.notoSansKr(
          fontSize: size, color: color, fontWeight: w, height: 1.4);
}

ThemeData buildTheme() {
  return ThemeData(
    useMaterial3: true,
    scaffoldBackgroundColor: AppColors.background,
    colorScheme: const ColorScheme.light(
      primary: AppColors.gradientEnd,
      secondary: AppColors.gold,
      surface: AppColors.surface,
      error: AppColors.stamp,
    ),
    fontFamily: GoogleFonts.notoSansKr().fontFamily,
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.gradientEnd,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 22),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: T.body(size: 15, color: Colors.white, w: FontWeight.w800),
        elevation: 0,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.surfaceMuted,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
      focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide:
              const BorderSide(color: AppColors.gradientEnd, width: 1.5)),
      hintStyle: T.body(color: AppColors.inkFaint),
    ),
    dividerColor: AppColors.divider,
  );
}

/// 학생 인증 도장
class StampBadge extends StatelessWidget {
  final double size;
  const StampBadge({super.key, this.size = 30});

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: -0.15,
      child: CustomPaint(size: Size(size, size), painter: _StampPainter()),
    );
  }
}

class _StampPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 2;
    final ring = Paint()
      ..color = AppColors.stamp
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.08;
    canvas.drawCircle(center, radius, ring);
    final tp = TextPainter(
      text: TextSpan(
          text: '인증',
          style: TextStyle(
              color: AppColors.stamp,
              fontSize: size.width * 0.28,
              fontWeight: FontWeight.w900)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(
        canvas, Offset(center.dx - tp.width / 2, center.dy - tp.height / 2));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// ============================================================
/// 이메일 인증코드 서비스
/// ============================================================
class EmailCodeService {
  static final _firestore = FirebaseFirestore.instance;

  static String _generateCode() =>
      List.generate(6, (_) => Random.secure().nextInt(10)).join();

  static Future<void> sendCode(String email) async {
    final code = _generateCode();
    await _firestore.collection('email_codes').doc(email).set({
      'code': code,
      'createdAt': FieldValue.serverTimestamp(),
    });
    final res = await http.post(
      Uri.parse('https://api.emailjs.com/api/v1.0/email/send'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'service_id': kEmailJsServiceId,
        'template_id': kEmailJsTemplateId,
        'user_id': kEmailJsPublicKey,
        'template_params': {'to_email': email, 'code': code},
      }),
    );
    if (res.statusCode != 200) {
      throw Exception('메일 발송 실패 (${res.statusCode}): ${res.body}');
    }
  }

  static Future<bool> verifyCode(String email, String inputCode) async {
    final doc = await _firestore.collection('email_codes').doc(email).get();
    if (!doc.exists) return false;
    final data = doc.data()!;
    final savedCode = data['code'] as String?;
    final createdAt = (data['createdAt'] as Timestamp?)?.toDate();
    if (savedCode == null || createdAt == null) return false;
    if (savedCode != inputCode) return false;
    if (DateTime.now().difference(createdAt) > const Duration(minutes: 10))
      return false;
    return true;
  }

  static Future<void> clearCode(String email) =>
      _firestore.collection('email_codes').doc(email).delete();
}

/// ============================================================
/// 앱 루트
/// ============================================================
class SlipperApp extends StatelessWidget {
  const SlipperApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: kAppName,
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: const RootGate(),
    );
  }
}

class RootGate extends StatefulWidget {
  const RootGate({super.key});

  @override
  State<RootGate> createState() => _RootGateState();
}

class _RootGateState extends State<RootGate> {
  bool _guestMode = false;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
              backgroundColor: AppColors.background,
              body: Center(
                  child:
                      CircularProgressIndicator(color: AppColors.gradientEnd)));
        }
        final loggedIn = snapshot.data != null;
        if (loggedIn || _guestMode) return const MainShell();
        return AuthScreen(onGuest: () => setState(() => _guestMode = true));
      },
    );
  }
}

/// ============================================================
/// 데이터 모델
/// ============================================================
class Place {
  final String id;
  final String name;
  final String category;
  final double tasteSum;
  final int tasteCount;
  final double valueSum;
  final int valueCount;
  final List<String> tags;
  final String? naverMapUrl;
  final String? address;
  final double? latitude;
  final double? longitude;
  final String? createdBy;

  Place({
    required this.id,
    required this.name,
    required this.category,
    required this.tasteSum,
    required this.tasteCount,
    required this.valueSum,
    required this.valueCount,
    required this.tags,
    this.naverMapUrl,
    this.address,
    this.latitude,
    this.longitude,
    this.createdBy,
  });

  double get tasteAvg => tasteCount == 0 ? 0 : tasteSum / tasteCount;
  double get valueAvg => valueCount == 0 ? 0 : valueSum / valueCount;
  int get reviewCount => tasteCount;

  factory Place.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data()!;
    return Place(
      id: doc.id,
      name: d['name'] ?? '',
      category: d['category'] ?? '한식',
      tasteSum: (d['tasteSum'] ?? 0).toDouble(),
      tasteCount: (d['tasteCount'] ?? 0),
      valueSum: (d['valueSum'] ?? 0).toDouble(),
      valueCount: (d['valueCount'] ?? 0),
      tags: List<String>.from(d['tags'] ?? []),
      naverMapUrl: d['naverMapUrl'],
      address: d['address'],
      latitude: (d['latitude'] as num?)?.toDouble(),
      longitude: (d['longitude'] as num?)?.toDouble(),
      createdBy: d['createdBy'],
    );
  }
}

/// 주소 문자열을 좌표로 변환 (OpenStreetMap Nominatim, 무료·키 불필요)
Future<latlong.LatLng?> geocodeAddress(String address) async {
  final query = Uri.encodeComponent('$address, 대한민국');
  final uri = Uri.parse(
      'https://nominatim.openstreetmap.org/search?q=$query&format=json&limit=1&countrycodes=kr');
  try {
    final res =
        await http.get(uri, headers: {'User-Agent': 'hallym-meokjagolmok-app'});
    if (res.statusCode != 200) return null;
    final list = jsonDecode(res.body) as List;
    if (list.isEmpty) return null;
    final lat = double.tryParse(list.first['lat']?.toString() ?? '');
    final lon = double.tryParse(list.first['lon']?.toString() ?? '');
    if (lat == null || lon == null) return null;
    return latlong.LatLng(lat, lon);
  } catch (_) {
    return null;
  }
}

/// 현재 로그인한 유저가 관리자인지 확인 (users/{uid}.isAdmin 필드 기준)
Future<bool> isAdminUser() async {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return false;
  final doc =
      await FirebaseFirestore.instance.collection('users').doc(uid).get();
  return doc.data()?['isAdmin'] == true;
}

/// 한림대 학교 이메일 인증을 거친 계정인지 확인 (등록 권한 판별용)
Future<bool> isVerifiedStudentAccount() async {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return false;
  final doc =
      await FirebaseFirestore.instance.collection('users').doc(uid).get();
  return doc.data()?['verified'] == true;
}

/// 비회원용 즐겨찾기 — 기기 로컬 저장소에만 저장 (앱 삭제 시 사라짐)
class GuestFavoritesService {
  GuestFavoritesService._();
  static const _key = 'guest_favorites_v1';
  static final ValueNotifier<int> revision = ValueNotifier(0);

  static Future<List<Map<String, dynamic>>> getAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return [];
    final list = jsonDecode(raw) as List;
    return list.cast<Map<String, dynamic>>();
  }

  static Future<bool> isFavorite(String placeId) async {
    final all = await getAll();
    return all.any((e) => e['placeId'] == placeId);
  }

  static Future<void> toggle(Place place) async {
    final prefs = await SharedPreferences.getInstance();
    final all = await getAll();
    final idx = all.indexWhere((e) => e['placeId'] == place.id);
    if (idx >= 0) {
      all.removeAt(idx);
    } else {
      all.add({
        'placeId': place.id,
        'name': place.name,
        'category': place.category
      });
    }
    await prefs.setString(_key, jsonEncode(all));
    revision.value++;
  }
}

const kCategories = [
  '한식',
  '일식',
  '중식',
  '양식',
  '카페/디저트',
  '술집',
  '갓성비',
  '과팅/소개팅',
  '제휴업체'
];

/// 띄어쓰기·특수문자·대소문자를 무시하고 이름을 비교하기 위한 정규화
String normalizeName(String s) =>
    s.replaceAll(RegExp(r'[\s·\-_.,]'), '').toLowerCase();

class CategoryStyle {
  final Color bg;
  final Color iconColor;
  final IconData icon;
  final String subtitle;
  const CategoryStyle(this.bg, this.iconColor, this.icon, this.subtitle);
}

const Map<String, CategoryStyle> kCategoryStyles = {
  '한식': CategoryStyle(Color(0xFFFDE1E6), Color(0xFFE5484D),
      Icons.soup_kitchen_outlined, '국밥·한정식·찌개'),
  '일식': CategoryStyle(Color(0xFFE3EEFC), Color(0xFF3B82F6),
      Icons.set_meal_outlined, '라멘·초밥·돈카츠'),
  '중식': CategoryStyle(Color(0xFFFCEEDC), Color(0xFFB5651D),
      Icons.ramen_dining_outlined, '짜장·마라탕·딤섬'),
  '양식': CategoryStyle(Color(0xFFE1F5EA), Color(0xFFE5484D),
      Icons.lunch_dining_outlined, '파스타·피자·버거'),
  '카페/디저트': CategoryStyle(Color(0xFFF1E7FB), Color(0xFF8B5E3C),
      Icons.local_cafe_outlined, '커피·케이크·빙수'),
  '술집': CategoryStyle(Color(0xFFFCF6DC), Color(0xFF3B82F6),
      Icons.sports_bar_outlined, '호프·포차·이자카야'),
  '갓성비': CategoryStyle(Color(0xFFFFF3D6), Color(0xFFC98A2C),
      Icons.lightbulb_outline, '착한가격 맛집 모음'),
  '과팅/소개팅': CategoryStyle(Color(0xFFFCE3EC), Color(0xFFE5487D),
      Icons.favorite_border, '분위기 좋은 데이트'),
  '제휴업체': CategoryStyle(Color(0xFFFFF4CC), Color(0xFFC98A2C),
      Icons.card_membership_outlined, '학생할인·멤버십'),
};

/// ============================================================
/// 메인 셸 — 하단 탭바(홈/검색/등록/즐겨찾기/마이페이지)
/// ============================================================
class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _index = 0;

  Future<void> _onRegisterTap() async {
    if (FirebaseAuth.instance.currentUser == null) {
      await Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => const AuthScreen()));
      return;
    }
    final verified = await isVerifiedStudentAccount();
    if (!verified) {
      if (!mounted) return;
      await showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('한림대 학생만 등록할 수 있어요'),
          content: Text(
              '새 장소 등록은 학교 이메일(@$kSchoolDomain) 인증을 마친 학생만 가능해요.\n리뷰 작성과 수정 요청은 계속 이용할 수 있어요.',
              style: T.body(size: 13)),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('확인'))
          ],
        ),
      );
      return;
    }
    if (!mounted) return;
    final category = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.background,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => const _CategoryPickerSheet(),
    );
    if (category == null || !mounted) return;
    Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => AddPlaceScreen(category: category)));
  }

  void _goToTab(int i) => setState(() => _index = i);

  @override
  Widget build(BuildContext context) {
    final pages = [
      _HomeBody(
          onSearchTap: () => _goToTab(1), onProfileTap: () => _goToTab(3)),
      const SearchScreen(),
      const FavoritesScreen(),
      const AccountScreen(),
    ];
    // pages: 0=홈 1=검색 2=즐겨찾기 3=마이페이지 (등록은 별도 액션이라 페이지 아님)
    // 네비게이션 아이콘 5개 순서: 0홈 1검색 2등록 3즐겨찾기 4마이페이지
    final navHighlightIndex = _index < 2 ? _index : _index + 1;
    return Scaffold(
      body: IndexedStack(index: _index, children: pages),
      bottomNavigationBar: _BottomBar(
        currentIndex: navHighlightIndex,
        onTap: (navIndex) {
          if (navIndex == 2) {
            _onRegisterTap();
            return;
          }
          final pageIndex = navIndex < 2 ? navIndex : navIndex - 1;
          _goToTab(pageIndex);
        },
      ),
    );
  }
}

class _NavItem {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  const _NavItem(this.icon, this.activeIcon, this.label);
}

const _navItems = [
  _NavItem(Icons.home_outlined, Icons.home, '홈'),
  _NavItem(Icons.search, Icons.search, '검색'),
  _NavItem(Icons.add, Icons.add, '등록'),
  _NavItem(Icons.bookmark_border, Icons.bookmark, '즐겨찾기'),
  _NavItem(Icons.person_outline, Icons.person, '마이페이지'),
];

class _BottomBar extends StatelessWidget {
  final int
      currentIndex; // 0홈 1검색 2등록(액션) 3즐겨찾기 4마이페이지 — 실제 활성표시는 _goToTab 기준(등록 제외)
  final void Function(int) onTap;
  const _BottomBar({required this.currentIndex, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(color: Colors.white, boxShadow: [
        BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 12,
            offset: const Offset(0, -2))
      ]),
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).padding.bottom + 6, top: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: List.generate(5, (i) {
          if (i == 2) {
            return GestureDetector(
              onTap: () => onTap(i),
              child: Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  gradient: AppColors.gradient,
                  shape: BoxShape.circle,
                  boxShadow: softShadow(AppColors.gradientEnd,
                      opacity: 0.35, blur: 14, dy: 4),
                ),
                child: const Icon(Icons.add, color: Colors.white, size: 24),
              ),
            );
          }
          final item = _navItems[i];
          final selected = currentIndex == i;
          return InkWell(
            onTap: () => onTap(i),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(selected ? item.activeIcon : item.icon,
                    color:
                        selected ? AppColors.gradientEnd : AppColors.inkFaint,
                    size: 22),
                const SizedBox(height: 2),
                Text(item.label,
                    style: T.body(
                        size: 10,
                        color: selected
                            ? AppColors.gradientEnd
                            : AppColors.inkFaint,
                        w: FontWeight.w700)),
              ],
            ),
          );
        }),
      ),
    );
  }
}

class _CategoryPickerSheet extends StatelessWidget {
  const _CategoryPickerSheet();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('어떤 카테고리에 등록할까요?', style: T.heading(size: 16)),
            const SizedBox(height: 16),
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 3,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 0.95,
              children: kCategories.map((c) {
                final style = kCategoryStyles[c]!;
                return InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () => Navigator.of(context).pop(c),
                  child: Container(
                    decoration: BoxDecoration(
                        color: style.bg,
                        borderRadius: BorderRadius.circular(14)),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(style.icon, color: style.iconColor, size: 22),
                        const SizedBox(height: 6),
                        Text(c,
                            style: T.heading(size: 11),
                            textAlign: TextAlign.center),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }
}

/// ============================================================
/// 홈 탭 콘텐츠
/// ============================================================
class _HomeBody extends StatelessWidget {
  final VoidCallback onSearchTap;
  final VoidCallback onProfileTap;
  const _HomeBody({required this.onSearchTap, required this.onProfileTap});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        const Icon(Icons.location_on,
                            size: 14, color: AppColors.inkFaint),
                        const SizedBox(width: 3),
                        Text('한림대학교',
                            style: T.body(
                                size: 12,
                                color: AppColors.inkFaint,
                                w: FontWeight.w600)),
                      ]),
                      const SizedBox(height: 2),
                      Text(kAppName, style: T.heading(size: 23)),
                    ],
                  ),
                ),
                const _NotificationBellButton(),
                const SizedBox(width: 8),
                _RoundIconButton(
                    icon: Icons.person_outline_rounded, onTap: onProfileTap),
              ],
            ),
            const SizedBox(height: 16),
            InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: onSearchTap,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                    color: AppColors.surfaceMuted,
                    borderRadius: BorderRadius.circular(14)),
                child: Row(
                  children: [
                    const Icon(Icons.search,
                        color: AppColors.inkFaint, size: 20),
                    const SizedBox(width: 10),
                    Text('음식점 이름으로 검색',
                        style: T.body(size: 14, color: AppColors.inkFaint)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            const _TodayPickBanner(),
            const SizedBox(height: 26),
            Text('지도로 보기', style: T.heading(size: 17)),
            const SizedBox(height: 4),
            Text('등록된 곳을 한눈에 확인해보세요',
                style: T.body(size: 12, color: AppColors.inkFaint)),
            const SizedBox(height: 12),
            const _PlacesMapCard(),
            const SizedBox(height: 26),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('카테고리', style: T.heading(size: 17)),
                Text('${kCategories.length}개',
                    style: T.body(size: 12, color: AppColors.inkFaint)),
              ],
            ),
            const SizedBox(height: 14),
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 3,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 1.05,
              children:
                  kCategories.map((c) => _CategoryButton(category: c)).toList(),
            ),
          ],
        ),
      ),
    );
  }
}

class _NotificationBellButton extends StatelessWidget {
  const _NotificationBellButton();

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return _RoundIconButton(
          icon: Icons.notifications_none_rounded,
          onTap: () => Navigator.of(context)
              .push(MaterialPageRoute(builder: (_) => const NoticeScreen())));
    }
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('notifications')
          .where('toUid', isEqualTo: uid)
          .where('read', isEqualTo: false)
          .snapshots(),
      builder: (context, snapshot) {
        final count = snapshot.data?.docs.length ?? 0;
        return Stack(
          clipBehavior: Clip.none,
          children: [
            _RoundIconButton(
                icon: Icons.notifications_none_rounded,
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => const NotificationsScreen()))),
            if (count > 0)
              Positioned(
                right: -2,
                top: -2,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                      color: AppColors.coral,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.white, width: 1.5)),
                  child: Text('$count',
                      style: T.body(
                          size: 9, color: Colors.white, w: FontWeight.w800)),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _RoundIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _RoundIconButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        width: 38,
        height: 38,
        decoration: const BoxDecoration(
            color: AppColors.surfaceMuted, shape: BoxShape.circle),
        child: Icon(icon, size: 19, color: AppColors.ink),
      ),
    );
  }
}

/// 한림대학교 좌표 (출처: Wikidata) — 등록된 곳이 없을 때 기본 중심점
const latlong.LatLng kDefaultMapCenter = latlong.LatLng(37.8861, 127.7383);

class _PlacesMapCard extends StatelessWidget {
  const _PlacesMapCard();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection('places').snapshots(),
      builder: (context, snapshot) {
        final docs = snapshot.data?.docs ?? [];
        final places = docs
            .map(Place.fromDoc)
            .where((p) => p.latitude != null && p.longitude != null)
            .toList();

        final markers = places.map((place) {
          final style =
              kCategoryStyles[place.category] ?? kCategoryStyles['한식']!;
          return Marker(
            point: latlong.LatLng(place.latitude!, place.longitude!),
            width: 34,
            height: 34,
            child: GestureDetector(
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => PlaceDetailScreen(place: place))),
              child: Container(
                decoration: BoxDecoration(
                  color: style.iconColor,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                  boxShadow:
                      softShadow(AppColors.ink, opacity: 0.25, blur: 6, dy: 2),
                ),
                child: Icon(style.icon, color: Colors.white, size: 15),
              ),
            ),
          );
        }).toList();

        return ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: SizedBox(
            height: 200,
            child: Stack(
              children: [
                FlutterMap(
                  options: const MapOptions(
                    initialCenter: kDefaultMapCenter,
                    initialZoom: 15,
                    interactionOptions:
                        InteractionOptions(flags: InteractiveFlag.none),
                  ),
                  children: [
                    TileLayer(
                      urlTemplate:
                          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.hallym.meokjagolmok',
                    ),
                    MarkerLayer(markers: markers),
                  ],
                ),
                if (markers.isEmpty)
                  Container(
                    color: Colors.black.withOpacity(0.35),
                    alignment: Alignment.center,
                    child: Text('위치가 등록된 곳이 아직 없어요',
                        style: T.body(
                            size: 13, color: Colors.white, w: FontWeight.w700)),
                  ),
                Positioned(
                  right: 10,
                  bottom: 10,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => const FullMapScreen())),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: softShadow(AppColors.ink,
                              opacity: 0.15, blur: 8, dy: 2)),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.open_in_full,
                              size: 13, color: AppColors.ink),
                          const SizedBox(width: 5),
                          Text('크게 보기',
                              style: T.body(size: 12, w: FontWeight.w700)),
                        ],
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
  }
}

class _TodayPickBanner extends StatelessWidget {
  const _TodayPickBanner();

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: () => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => const CategoryScreen(category: '갓성비'))),
      child: Container(
        height: 128,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
            color: AppColors.dark, borderRadius: BorderRadius.circular(20)),
        child: Stack(
          children: [
            Positioned(
              right: -6,
              top: 8,
              child: Opacity(
                  opacity: 0.12,
                  child: Icon(Icons.restaurant, size: 92, color: Colors.white)),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                      color: AppColors.coral,
                      borderRadius: BorderRadius.circular(20)),
                  child: Text('이번 주 인기',
                      style: T.body(
                          size: 11, color: Colors.white, w: FontWeight.w800)),
                ),
                const SizedBox(height: 10),
                Text('갓성비 점심\n모음집',
                    style: T.heading(size: 19, color: Colors.white)),
              ],
            ),
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.15),
                    shape: BoxShape.circle),
                child: const Icon(Icons.chevron_right,
                    color: Colors.white, size: 18),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CategoryButton extends StatelessWidget {
  final String category;
  const _CategoryButton({required this.category});

  @override
  Widget build(BuildContext context) {
    final style = kCategoryStyles[category]!;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => CategoryScreen(category: category))),
      child: Container(
        padding: const EdgeInsets.all(9),
        decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            boxShadow:
                softShadow(AppColors.ink, opacity: 0.05, blur: 10, dy: 4)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 30,
              height: 30,
              decoration:
                  BoxDecoration(color: style.bg, shape: BoxShape.circle),
              child: Icon(style.icon, size: 15, color: style.iconColor),
            ),
            const SizedBox(height: 6),
            Text(category,
                style: T.heading(size: 11),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
            const SizedBox(height: 1),
            Text(style.subtitle,
                style: T.body(size: 9, color: AppColors.inkFaint),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    );
  }
}

/// ============================================================
/// 검색 화면 (하단 탭)
/// ============================================================
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _controller = TextEditingController();
  List<Place> _all = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final snap = await FirebaseFirestore.instance.collection('places').get();
    setState(() {
      _all = snap.docs.map(Place.fromDoc).toList();
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final query = _controller.text.trim();
    final results = query.isEmpty
        ? <Place>[]
        : _all
            .where((p) => p.name.toLowerCase().contains(query.toLowerCase()))
            .toList();

    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        foregroundColor: AppColors.ink,
        title: TextField(
          controller: _controller,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(
              hintText: '맛집 이름으로 검색', border: InputBorder.none),
        ),
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.gradientEnd))
          : query.isEmpty
              ? Center(
                  child: Text('가게 이름을 입력해보세요',
                      style: T.body(color: AppColors.inkFaint)))
              : results.isEmpty
                  ? Center(
                      child: Text('검색 결과가 없어요',
                          style: T.body(color: AppColors.inkFaint)))
                  : ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: results.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, i) => ListTile(
                        title: Text(results[i].name,
                            style: T.body(w: FontWeight.w700)),
                        subtitle: Text(results[i].category,
                            style: T.body(size: 12, color: AppColors.inkFaint)),
                        onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                                builder: (_) =>
                                    PlaceDetailScreen(place: results[i]))),
                      ),
                    ),
    );
  }
}

/// ============================================================
/// 카테고리 화면
/// ============================================================
enum SortType { all, near, rating, reviews, price }

const _sortLabels = {
  SortType.all: '전체',
  SortType.near: '가까운순',
  SortType.rating: '별점순',
  SortType.reviews: '리뷰순',
  SortType.price: '가격순',
};

class CategoryScreen extends StatefulWidget {
  final String category;
  const CategoryScreen({super.key, required this.category});

  @override
  State<CategoryScreen> createState() => _CategoryScreenState();
}

class _CategoryScreenState extends State<CategoryScreen> {
  SortType _sort = SortType.all;

  Future<void> _onAddPressed() async {
    if (FirebaseAuth.instance.currentUser == null) {
      await Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => const AuthScreen()));
      return;
    }
    final verified = await isVerifiedStudentAccount();
    if (!verified) {
      if (!mounted) return;
      await showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('한림대 학생만 등록할 수 있어요'),
          content: Text(
              '새 장소 등록은 학교 이메일(@$kSchoolDomain) 인증을 마친 학생만 가능해요.\n리뷰 작성과 수정 요청은 계속 이용할 수 있어요.',
              style: T.body(size: 13)),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('확인'))
          ],
        ),
      );
      return;
    }
    if (!mounted) return;
    Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => AddPlaceScreen(category: widget.category)));
  }

  List<Place> _applySort(List<Place> places) {
    final list = [...places];
    switch (_sort) {
      case SortType.all:
      case SortType.near:
        break;
      case SortType.rating:
        list.sort((a, b) => b.tasteAvg.compareTo(a.tasteAvg));
        break;
      case SortType.reviews:
        list.sort((a, b) => b.reviewCount.compareTo(a.reviewCount));
        break;
      case SortType.price:
        list.sort((a, b) => b.valueAvg.compareTo(a.valueAvg));
        break;
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final style = kCategoryStyles[widget.category]!;
    final query = FirebaseFirestore.instance
        .collection('places')
        .where('category', isEqualTo: widget.category);

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Container(
              color: Colors.white,
              padding: EdgeInsets.fromLTRB(
                  16, MediaQuery.of(context).padding.top + 8, 16, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  InkWell(
                    onTap: () => Navigator.of(context).pop(),
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                        width: 36,
                        height: 36,
                        decoration: const BoxDecoration(
                            color: AppColors.surfaceMuted,
                            shape: BoxShape.circle),
                        child: const Icon(Icons.arrow_back,
                            color: AppColors.ink, size: 18)),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                              color: style.bg, shape: BoxShape.circle),
                          child: Icon(style.icon, color: style.iconColor)),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(widget.category, style: T.heading(size: 19)),
                          Text(style.subtitle,
                              style:
                                  T.body(size: 12, color: AppColors.inkFaint)),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Container(
              color: AppColors.background,
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: SizedBox(
                height: 36,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: SortType.values.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (context, i) {
                    final type = SortType.values[i];
                    final selected = type == _sort;
                    return ChoiceChip(
                      label: Text(_sortLabels[type]!),
                      selected: selected,
                      onSelected: (_) => setState(() => _sort = type),
                      selectedColor: AppColors.gradientEnd,
                      backgroundColor: AppColors.surfaceMuted,
                      labelStyle: T.body(
                          size: 13,
                          color: selected ? Colors.white : AppColors.ink,
                          w: FontWeight.w700),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                          side: BorderSide.none),
                    );
                  },
                ),
              ),
            ),
          ),
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: query.snapshots(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const SliverFillRemaining(
                    child: Center(
                        child: CircularProgressIndicator(
                            color: AppColors.gradientEnd)));
              }
              if (snapshot.hasError) {
                return SliverFillRemaining(
                    child: Center(
                        child: Text('불러오는 중 문제가 생겼어요', style: T.body())));
              }
              final docs = snapshot.data?.docs ?? [];
              if (docs.isEmpty) {
                return SliverFillRemaining(
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(style.icon, size: 40, color: AppColors.inkFaint),
                          const SizedBox(height: 14),
                          Text('아직 등록된 곳이 없어요', style: T.heading(size: 15)),
                          const SizedBox(height: 6),
                          Text('학교 웹메일 인증하고\n첫 번째로 등록해 보세요.',
                              textAlign: TextAlign.center,
                              style: T.body(color: AppColors.inkFaint)),
                        ],
                      ),
                    ),
                  ),
                );
              }
              final places = _applySort(docs.map(Place.fromDoc).toList());
              return SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 90),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, i) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _PlaceCard(place: places[i])),
                    childCount: places.length,
                  ),
                ),
              );
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _onAddPressed,
        backgroundColor: AppColors.gradientEnd,
        icon: const Icon(Icons.add, color: Colors.white),
        label: Text('등록하기',
            style: T.body(color: Colors.white, w: FontWeight.w700)),
      ),
    );
  }
}

String? _badgeFor(Place p) {
  if (p.reviewCount <= 1) return '신규';
  if (p.reviewCount >= 5) return '인기';
  if (p.tasteAvg >= 4.5) return '추천';
  return null;
}

class _PlaceCard extends StatelessWidget {
  final Place place;
  const _PlaceCard({required this.place});

  @override
  Widget build(BuildContext context) {
    final style = kCategoryStyles[place.category] ?? kCategoryStyles['한식']!;
    final badge = _badgeFor(place);
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => PlaceDetailScreen(place: place))),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(18),
          boxShadow: softShadow(AppColors.ink, opacity: 0.06, blur: 16, dy: 6),
        ),
        child: Row(
          children: [
            Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      style.bg,
                      Color.lerp(style.bg, Colors.white, 0.5)!
                    ]),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(style.icon, color: style.iconColor),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                          child: Text(place.name,
                              style: T.heading(size: 15),
                              overflow: TextOverflow.ellipsis)),
                      if (badge != null) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                              color: AppColors.gradientEnd.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(8)),
                          child: Text(badge,
                              style: T.body(
                                  size: 10,
                                  color: AppColors.gradientEnd,
                                  w: FontWeight.w800)),
                        ),
                      ],
                      if (place.reviewCount > 0) ...[
                        const SizedBox(width: 6),
                        const StampBadge(size: 18)
                      ],
                    ],
                  ),
                  const SizedBox(height: 5),
                  Row(
                    children: [
                      const Icon(Icons.star, size: 14, color: AppColors.gold),
                      const SizedBox(width: 3),
                      Text(place.tasteAvg.toStringAsFixed(1),
                          style: T.body(size: 13, w: FontWeight.w700)),
                      Text(' (${place.reviewCount})',
                          style: T.body(size: 12, color: AppColors.inkFaint)),
                      const SizedBox(width: 10),
                      Text('가성비 ${place.valueAvg.toStringAsFixed(1)}',
                          style: T.body(size: 12, color: AppColors.inkFaint)),
                    ],
                  ),
                  if (place.tags.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: place.tags
                          .map((t) => Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 7, vertical: 2),
                                decoration: BoxDecoration(
                                    color: AppColors.surfaceMuted,
                                    borderRadius: BorderRadius.circular(8)),
                                child: Text(t,
                                    style: T.body(
                                        size: 10, color: AppColors.inkFaint)),
                              ))
                          .toList(),
                    ),
                  ],
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: AppColors.inkFaint),
          ],
        ),
      ),
    );
  }
}

/// ============================================================
/// 장소 상세 화면
/// ============================================================
class PlaceDetailScreen extends StatelessWidget {
  final Place place;
  const PlaceDetailScreen({super.key, required this.place});

  Future<void> _onReviewPressed(BuildContext context) async {
    if (FirebaseAuth.instance.currentUser == null) {
      await Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => const AuthScreen()));
      return;
    }
    if (!context.mounted) return;
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => AddReviewScreen(place: place)));
  }

  @override
  Widget build(BuildContext context) {
    final style = kCategoryStyles[place.category] ?? kCategoryStyles['한식']!;
    final currentUser = FirebaseAuth.instance.currentUser;
    final reviewsQuery = FirebaseFirestore.instance
        .collection('places')
        .doc(place.id)
        .collection('reviews')
        .orderBy('createdAt', descending: true);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        foregroundColor: AppColors.ink,
        title: Text(place.name, style: T.heading(size: 17)),
        actions: [
          _FavoriteButton(place: place),
          if (currentUser != null)
            FutureBuilder<bool>(
              future: isAdminUser(),
              builder: (context, snap) {
                final admin = snap.data ?? false;
                final owner = currentUser.uid == place.createdBy;
                if (!owner && !admin) return const SizedBox.shrink();
                return IconButton(
                  icon: const Icon(Icons.edit_outlined),
                  tooltip: '수정하기',
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => EditPlaceScreen(place: place))),
                );
              },
            ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
            child: Row(
              children: [
                CircleAvatar(
                    radius: 24,
                    backgroundColor: style.bg,
                    child: Icon(style.icon, color: style.iconColor)),
                const SizedBox(width: 14),
                Expanded(
                    child: Row(children: [
                  Expanded(
                      child: _StatBlock(label: '맛', value: place.tasteAvg)),
                  Expanded(
                      child: _StatBlock(label: '가성비', value: place.valueAvg))
                ])),
                ElevatedButton(
                    onPressed: () => _onReviewPressed(context),
                    child: const Text('리뷰 남기기')),
              ],
            ),
          ),
          if (place.address != null && place.address!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Row(
                children: [
                  const Icon(Icons.place_outlined,
                      size: 16, color: AppColors.inkFaint),
                  const SizedBox(width: 6),
                  Expanded(
                      child: Text(place.address!,
                          style: T.body(size: 13, color: AppColors.inkFaint))),
                ],
              ),
            ),
          if (place.naverMapUrl != null && place.naverMapUrl!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () async {
                  final uri = Uri.tryParse(place.naverMapUrl!);
                  if (uri != null) {
                    await launchUrl(uri, mode: LaunchMode.externalApplication);
                  }
                },
                child: Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                      color: AppColors.surfaceMuted,
                      borderRadius: BorderRadius.circular(12)),
                  child: Row(
                    children: [
                      const Icon(Icons.map_outlined,
                          size: 18, color: AppColors.coral),
                      const SizedBox(width: 8),
                      Text('네이버지도에서 위치 보기',
                          style: T.body(
                              size: 13,
                              w: FontWeight.w700,
                              color: AppColors.ink)),
                      const Spacer(),
                      const Icon(Icons.open_in_new,
                          size: 15, color: AppColors.inkFaint),
                    ],
                  ),
                ),
              ),
            ),
          if (currentUser != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
              child: Row(
                children: [
                  TextButton.icon(
                    onPressed: () => _showReportDialog(context, place),
                    icon: const Icon(Icons.flag_outlined,
                        size: 16, color: AppColors.inkFaint),
                    label: Text('정보가 잘못됐나요? 수정 요청하기',
                        style: T.body(
                            size: 12,
                            color: AppColors.inkFaint,
                            w: FontWeight.w600)),
                  ),
                  const Spacer(),
                  FutureBuilder<bool>(
                    future: isAdminUser(),
                    builder: (context, snap) {
                      final admin = snap.data ?? false;
                      final owner = currentUser.uid == place.createdBy;
                      if (!owner && !admin) return const SizedBox.shrink();
                      return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                        stream: FirebaseFirestore.instance
                            .collection('places')
                            .doc(place.id)
                            .collection('reports')
                            .where('resolved', isEqualTo: false)
                            .snapshots(),
                        builder: (context, reportSnap) {
                          final count = reportSnap.data?.docs.length ?? 0;
                          return TextButton(
                            onPressed: () => Navigator.of(context).push(
                                MaterialPageRoute(
                                    builder: (_) =>
                                        ReportsScreen(place: place))),
                            child: Text('수정 요청 $count건',
                                style: T.body(
                                    size: 12,
                                    color: count > 0
                                        ? AppColors.coral
                                        : AppColors.inkFaint,
                                    w: FontWeight.w700)),
                          );
                        },
                      );
                    },
                  ),
                ],
              ),
            ),
          const Divider(height: 1),
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: reviewsQuery.snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData)
                  return const Center(
                      child: CircularProgressIndicator(
                          color: AppColors.gradientEnd));
                final docs = snapshot.data!.docs;
                if (docs.isEmpty)
                  return Center(
                      child: Text('아직 리뷰가 없어요',
                          style: T.body(color: AppColors.inkFaint)));
                return ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: docs.length,
                  separatorBuilder: (_, __) => const Divider(height: 24),
                  itemBuilder: (context, i) {
                    final d = docs[i].data();
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const StampBadge(size: 26),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(children: [
                                const Icon(Icons.star,
                                    size: 13, color: AppColors.gold),
                                Text(' ${d['taste']}',
                                    style:
                                        T.body(size: 12, w: FontWeight.w700)),
                                const SizedBox(width: 10),
                                Text('가성비 ${d['value']}',
                                    style: T.body(
                                        size: 12, color: AppColors.inkFaint)),
                              ]),
                              const SizedBox(height: 4),
                              Text(d['comment'] ?? '', style: T.body()),
                            ],
                          ),
                        ),
                      ],
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

Future<void> _showReportDialog(BuildContext context, Place place) async {
  final controller = TextEditingController();
  final submitted = await showDialog<bool>(
    context: context,
    builder: (_) => AlertDialog(
      title: const Text('수정 요청하기'),
      content: TextField(
        controller: controller,
        maxLines: 3,
        decoration:
            const InputDecoration(hintText: '예: 위치가 실제와 달라요 / 가게가 없어졌어요'),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소')),
        TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('보내기')),
      ],
    ),
  );
  if (submitted != true || controller.text.trim().isEmpty) return;
  final reporterUid = FirebaseAuth.instance.currentUser?.uid;
  await FirebaseFirestore.instance
      .collection('places')
      .doc(place.id)
      .collection('reports')
      .add({
    'uid': reporterUid,
    'message': controller.text.trim(),
    'createdAt': FieldValue.serverTimestamp(),
    'resolved': false,
  });

  // 등록자 + 관리자에게 알림 생성 (실패해도 수정요청 저장 자체는 이미 됐으니 아래 완료 메시지는 항상 뜨게 분리)
  try {
    final recipients = <String>{};
    if (place.createdBy != null && place.createdBy != reporterUid)
      recipients.add(place.createdBy!);
    final admins = await FirebaseFirestore.instance
        .collection('users')
        .where('isAdmin', isEqualTo: true)
        .get();
    for (final doc in admins.docs) {
      if (doc.id != reporterUid) recipients.add(doc.id);
    }
    for (final toUid in recipients) {
      await FirebaseFirestore.instance.collection('notifications').add({
        'toUid': toUid,
        'type': 'report',
        'placeId': place.id,
        'placeName': place.name,
        'message': controller.text.trim(),
        'createdAt': FieldValue.serverTimestamp(),
        'read': false,
      });
    }
  } catch (e) {
    // 알림 생성 실패는 조용히 넘어감 (수정요청 저장 자체는 이미 성공했으므로)
  }

  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.white, size: 20),
            const SizedBox(width: 10),
            Expanded(
                child: Text('수정 요청을 보냈어요. 확인해주셔서 감사해요!',
                    style: T.body(
                        size: 13, color: Colors.white, w: FontWeight.w700))),
          ],
        ),
        backgroundColor: AppColors.ink,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      ),
    );
  }
}

class _StatBlock extends StatelessWidget {
  final String label;
  final double value;
  const _StatBlock({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: T.body(size: 11, color: AppColors.inkFaint)),
        Row(children: [
          const Icon(Icons.star, size: 14, color: AppColors.gold),
          const SizedBox(width: 2),
          Text(value.toStringAsFixed(1), style: T.heading(size: 15))
        ]),
      ],
    );
  }
}

class _FavoriteButton extends StatefulWidget {
  final Place place;
  const _FavoriteButton({required this.place});

  @override
  State<_FavoriteButton> createState() => _FavoriteButtonState();
}

class _FavoriteButtonState extends State<_FavoriteButton> {
  bool _guestFav = false;

  @override
  void initState() {
    super.initState();
    if (FirebaseAuth.instance.currentUser == null) {
      GuestFavoritesService.isFavorite(widget.place.id).then((v) {
        if (mounted) setState(() => _guestFav = v);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;

    if (uid == null) {
      return IconButton(
        icon: Icon(_guestFav ? Icons.bookmark : Icons.bookmark_border,
            color: _guestFav ? AppColors.coral : AppColors.ink),
        onPressed: () async {
          await GuestFavoritesService.toggle(widget.place);
          final updated =
              await GuestFavoritesService.isFavorite(widget.place.id);
          if (mounted) setState(() => _guestFav = updated);
        },
      );
    }

    final favRef = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('favorites')
        .doc(widget.place.id);
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: favRef.snapshots(),
      builder: (context, snapshot) {
        final isFav = snapshot.data?.exists ?? false;
        return IconButton(
          icon: Icon(isFav ? Icons.bookmark : Icons.bookmark_border,
              color: isFav ? AppColors.coral : AppColors.ink),
          onPressed: () async {
            if (isFav) {
              await favRef.delete();
            } else {
              await favRef.set({
                'placeId': widget.place.id,
                'name': widget.place.name,
                'category': widget.place.category,
                'addedAt': FieldValue.serverTimestamp()
              });
            }
          },
        );
      },
    );
  }
}

/// ============================================================
/// 즐겨찾기 탭
/// ============================================================
class FavoritesScreen extends StatelessWidget {
  const FavoritesScreen({super.key});

  Future<void> _openPlace(BuildContext context, String placeId) async {
    final doc = await FirebaseFirestore.instance
        .collection('places')
        .doc(placeId)
        .get();
    if (!doc.exists) {
      if (context.mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('삭제된 장소예요')));
      return;
    }
    final place = Place.fromDoc(doc);
    if (context.mounted)
      Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => PlaceDetailScreen(place: place)));
  }

  Widget _buildList(BuildContext context, List<Map<String, dynamic>> items) {
    if (items.isEmpty)
      return Center(
          child:
              Text('즐겨찾기한 곳이 없어요', style: T.body(color: AppColors.inkFaint)));
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: items.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final d = items[i];
        final style = kCategoryStyles[d['category']] ?? kCategoryStyles['한식']!;
        return ListTile(
          leading: CircleAvatar(
              backgroundColor: style.bg,
              child: Icon(style.icon, color: style.iconColor, size: 18)),
          title: Text(d['name'] ?? '', style: T.heading(size: 15)),
          subtitle: Text(d['category'] ?? '',
              style: T.body(size: 12, color: AppColors.inkFaint)),
          trailing: const Icon(Icons.chevron_right, color: AppColors.inkFaint),
          onTap: () => _openPlace(context, d['placeId']),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    return Scaffold(
      appBar: AppBar(
          title: const Text('즐겨찾기'),
          backgroundColor: AppColors.background,
          elevation: 0,
          foregroundColor: AppColors.ink),
      body: uid == null
          ? Column(
              children: [
                Container(
                  width: double.infinity,
                  color: AppColors.surfaceMuted,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  child: Text('비회원 즐겨찾기는 이 기기에만 저장돼요. 앱을 삭제하면 사라져요.',
                      style: T.body(size: 11, color: AppColors.inkFaint)),
                ),
                Expanded(
                  child: ValueListenableBuilder<int>(
                    valueListenable: GuestFavoritesService.revision,
                    builder: (context, _, __) {
                      return FutureBuilder<List<Map<String, dynamic>>>(
                        future: GuestFavoritesService.getAll(),
                        builder: (context, snapshot) {
                          if (!snapshot.hasData)
                            return const Center(
                                child: CircularProgressIndicator(
                                    color: AppColors.coral));
                          return _buildList(context, snapshot.data!);
                        },
                      );
                    },
                  ),
                ),
              ],
            )
          : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('users')
                  .doc(uid)
                  .collection('favorites')
                  .orderBy('addedAt', descending: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData)
                  return const Center(
                      child: CircularProgressIndicator(color: AppColors.coral));
                return _buildList(
                    context, snapshot.data!.docs.map((d) => d.data()).toList());
              },
            ),
    );
  }
}

/// ============================================================
/// 전체화면 지도 — 드래그/줌 가능
/// ============================================================
class FullMapScreen extends StatefulWidget {
  const FullMapScreen({super.key});

  @override
  State<FullMapScreen> createState() => _FullMapScreenState();
}

class _FullMapScreenState extends State<FullMapScreen> {
  final MapController _mapController = MapController();

  void _zoom(double delta) {
    final camera = _mapController.camera;
    _mapController.move(camera.center, (camera.zoom + delta).clamp(3, 19));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
          title: const Text('지도로 보기'),
          backgroundColor: Colors.white,
          elevation: 0,
          foregroundColor: AppColors.ink),
      body: Stack(
        children: [
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance.collection('places').snapshots(),
            builder: (context, snapshot) {
              final docs = snapshot.data?.docs ?? [];
              final places = docs
                  .map(Place.fromDoc)
                  .where((p) => p.latitude != null && p.longitude != null)
                  .toList();

              final markers = places.map((place) {
                final style =
                    kCategoryStyles[place.category] ?? kCategoryStyles['한식']!;
                return Marker(
                  point: latlong.LatLng(place.latitude!, place.longitude!),
                  width: 40,
                  height: 40,
                  child: GestureDetector(
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => PlaceDetailScreen(place: place))),
                    child: Container(
                      decoration: BoxDecoration(
                        color: style.iconColor,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                        boxShadow: softShadow(AppColors.ink,
                            opacity: 0.25, blur: 6, dy: 2),
                      ),
                      child: Icon(style.icon, color: Colors.white, size: 18),
                    ),
                  ),
                );
              }).toList();

              return FlutterMap(
                mapController: _mapController,
                options: MapOptions(
                  initialCenter: kDefaultMapCenter,
                  initialZoom: 15,
                  interactionOptions:
                      const InteractionOptions(flags: InteractiveFlag.all),
                ),
                children: [
                  TileLayer(
                    urlTemplate:
                        'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'com.hallym.meokjagolmok',
                  ),
                  MarkerLayer(markers: markers),
                ],
              );
            },
          ),
          Positioned(
            right: 16,
            bottom: 24,
            child: Column(
              children: [
                _ZoomButton(icon: Icons.add, onTap: () => _zoom(1)),
                const SizedBox(height: 8),
                _ZoomButton(icon: Icons.remove, onTap: () => _zoom(-1)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ZoomButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _ZoomButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            boxShadow:
                softShadow(AppColors.ink, opacity: 0.15, blur: 8, dy: 2)),
        child: Icon(icon, color: AppColors.ink, size: 20),
      ),
    );
  }
}

/// ============================================================
/// 장소 정보 수정 (등록자 본인 또는 관리자만 접근 가능)
/// ============================================================
class EditPlaceScreen extends StatefulWidget {
  final Place place;
  const EditPlaceScreen({super.key, required this.place});

  @override
  State<EditPlaceScreen> createState() => _EditPlaceScreenState();
}

class _EditPlaceScreenState extends State<EditPlaceScreen> {
  late final _nameController = TextEditingController(text: widget.place.name);
  late final _mapUrlController =
      TextEditingController(text: widget.place.naverMapUrl ?? '');
  late final _addressController =
      TextEditingController(text: widget.place.address ?? '');
  late String _category = widget.place.category;
  late double? _lat = widget.place.latitude;
  late double? _lng = widget.place.longitude;
  late Set<String> _selectedTags = {...widget.place.tags};
  bool _saving = false;
  bool _locating = false;
  bool _geocoding = false;

  static const _allTags = [
    '혼밥 가능',
    '단체 가능',
    '술자리 적합',
    '시험기간 늦은영업',
    '배달 가능',
    '포장 가능',
    '예약 가능',
    '주차 가능',
    '24시간',
    '분위기 좋음',
    '데이트 코스',
    '사진 맛집',
    '가성비',
    '매운맛 주의',
    '채식 옵션',
    '반려동물 동반',
    '콘센트 많음',
    '웨이팅 있음',
  ];

  Future<void> _findByAddress() async {
    final address = _addressController.text.trim();
    if (address.isEmpty) return;
    setState(() => _geocoding = true);
    try {
      final result = await geocodeAddress(address);
      if (result == null) {
        if (mounted)
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('주소로 위치를 찾지 못했어요. 도로명 주소를 다시 확인해주세요')));
        return;
      }
      setState(() {
        _lat = result.latitude;
        _lng = result.longitude;
      });
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('주소로 위치를 찾았어요')));
    } finally {
      if (mounted) setState(() => _geocoding = false);
    }
  }

  Future<void> _recaptureLocation() async {
    setState(() => _locating = true);
    try {
      final serviceOn = await Geolocator.isLocationServiceEnabled();
      if (!serviceOn) return;
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        if (mounted)
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('위치 권한을 확인해주세요')));
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high);
      setState(() {
        _lat = pos.latitude;
        _lng = pos.longitude;
      });
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('위치를 가져오지 못했어요: $e')));
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  Future<void> _save() async {
    if (_nameController.text.trim().isEmpty) return;
    setState(() => _saving = true);
    try {
      await FirebaseFirestore.instance
          .collection('places')
          .doc(widget.place.id)
          .update({
        'name': _nameController.text.trim(),
        'nameNormalized': normalizeName(_nameController.text.trim()),
        'category': _category,
        'tags': _selectedTags.toList(),
        'naverMapUrl': _mapUrlController.text.trim().isEmpty
            ? null
            : _mapUrlController.text.trim(),
        'address': _addressController.text.trim().isEmpty
            ? null
            : _addressController.text.trim(),
        'latitude': _lat,
        'longitude': _lng,
      });
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('수정 실패: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('장소 정보 수정')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          DropdownButtonFormField<String>(
            initialValue: _category,
            items: kCategories
                .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                .toList(),
            onChanged: (v) => setState(() => _category = v!),
            decoration: const InputDecoration(labelText: '카테고리'),
          ),
          const SizedBox(height: 14),
          TextField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: '가게 이름')),
          const SizedBox(height: 14),
          TextField(
              controller: _mapUrlController,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(labelText: '네이버지도 링크 (선택)')),
          const SizedBox(height: 14),
          Text('위치 등록', style: T.body(w: FontWeight.w700)),
          const SizedBox(height: 6),
          Text('도로명 주소를 적으면 GPS보다 정확한 위치를 잡을 수 있어요',
              style: T.body(size: 11, color: AppColors.inkFaint)),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                  child: TextField(
                      controller: _addressController,
                      decoration:
                          const InputDecoration(hintText: '예: 한림대학길 1'))),
              const SizedBox(width: 8),
              SizedBox(
                height: 48,
                child: ElevatedButton(
                  onPressed: _geocoding ? null : _findByAddress,
                  style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 16)),
                  child: _geocoding
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Text('찾기'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(children: [
            const Expanded(child: Divider()),
            Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text('또는',
                    style: T.body(size: 11, color: AppColors.inkFaint))),
            const Expanded(child: Divider())
          ]),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _locating ? null : _recaptureLocation,
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.coral,
              side: const BorderSide(color: AppColors.coral),
              padding: const EdgeInsets.symmetric(vertical: 13),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            icon: const Icon(Icons.my_location, size: 18),
            label: Text(_locating
                ? '위치 확인 중...'
                : (_lat != null ? '지금 위치로 다시 등록하기' : '위치 등록하기')),
          ),
          if (_lat != null) ...[
            const SizedBox(height: 6),
            Text(
                '현재 저장된 위치: ${_lat!.toStringAsFixed(5)}, ${_lng!.toStringAsFixed(5)}',
                style: T.body(size: 11, color: AppColors.inkFaint)),
          ],
          const SizedBox(height: 20),
          Text('상황 태그', style: T.body(w: FontWeight.w700)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _allTags.map((tag) {
              final selected = _selectedTags.contains(tag);
              return FilterChip(
                label: Text(tag),
                selected: selected,
                onSelected: (v) => setState(() =>
                    v ? _selectedTags.add(tag) : _selectedTags.remove(tag)),
                selectedColor: AppColors.coral.withOpacity(0.15),
                checkmarkColor: AppColors.coral,
              );
            }).toList(),
          ),
          const SizedBox(height: 24),
          ElevatedButton(
              onPressed: _saving ? null : _save,
              child: Text(_saving ? '저장 중...' : '수정 완료')),
        ],
      ),
    );
  }
}

/// ============================================================
/// 이 장소에 대한 수정 요청 목록 (등록자/관리자용)
/// ============================================================
class ReportsScreen extends StatelessWidget {
  final Place place;
  const ReportsScreen({super.key, required this.place});

  @override
  Widget build(BuildContext context) {
    final query = FirebaseFirestore.instance
        .collection('places')
        .doc(place.id)
        .collection('reports')
        .orderBy('createdAt', descending: true);
    return Scaffold(
      appBar: AppBar(title: Text('${place.name} · 수정 요청')),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: query.snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData)
            return const Center(
                child: CircularProgressIndicator(color: AppColors.coral));
          final docs = snapshot.data!.docs;
          if (docs.isEmpty)
            return Center(
                child: Text('접수된 수정 요청이 없어요',
                    style: T.body(color: AppColors.inkFaint)));
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: docs.length,
            separatorBuilder: (_, __) => const Divider(height: 24),
            itemBuilder: (context, i) {
              final doc = docs[i];
              final d = doc.data();
              final resolved = d['resolved'] == true;
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(resolved ? Icons.check_circle : Icons.flag,
                      size: 18,
                      color: resolved ? AppColors.inkFaint : AppColors.coral),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(d['message'] ?? '',
                            style: T.body(size: 14, w: FontWeight.w600)),
                        if (resolved)
                          Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text('처리 완료',
                                  style: T.body(
                                      size: 11, color: AppColors.inkFaint))),
                      ],
                    ),
                  ),
                  if (!resolved)
                    TextButton(
                      onPressed: () => doc.reference.update({'resolved': true}),
                      child: const Text('처리 완료로 표시'),
                    ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

/// ============================================================
/// 새 장소 등록
/// ============================================================
class AddPlaceScreen extends StatefulWidget {
  final String category;
  const AddPlaceScreen({super.key, required this.category});

  @override
  State<AddPlaceScreen> createState() => _AddPlaceScreenState();
}

class _AddPlaceScreenState extends State<AddPlaceScreen> {
  final _nameController = TextEditingController();
  final _commentController = TextEditingController();
  final _mapUrlController = TextEditingController();
  final _addressController = TextEditingController();
  late String _category = widget.category;
  double _taste = 4;
  double _value = 4;
  final Set<String> _selectedTags = {};
  bool _saving = false;
  double? _lat;
  double? _lng;
  bool _locating = false;
  bool _geocoding = false;

  Future<void> _findByAddress() async {
    final address = _addressController.text.trim();
    if (address.isEmpty) return;
    setState(() => _geocoding = true);
    try {
      final result = await geocodeAddress(address);
      if (result == null) {
        if (mounted)
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('주소로 위치를 찾지 못했어요. 도로명 주소를 다시 확인해주세요')));
        return;
      }
      setState(() {
        _lat = result.latitude;
        _lng = result.longitude;
      });
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('주소로 위치를 찾았어요')));
    } finally {
      if (mounted) setState(() => _geocoding = false);
    }
  }

  Future<Position?> _resolvePosition() async {
    final serviceOn = await Geolocator.isLocationServiceEnabled();
    if (!serviceOn) return null;
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) return null;
    return Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high);
  }

  Future<void> _captureLocation() async {
    setState(() => _locating = true);
    try {
      final pos = await _resolvePosition();
      if (pos == null) {
        if (mounted)
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('위치 권한을 확인해주세요')));
        return;
      }
      setState(() {
        _lat = pos.latitude;
        _lng = pos.longitude;
      });
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('위치를 가져오지 못했어요: $e')));
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  static const _allTags = [
    '혼밥 가능',
    '단체 가능',
    '술자리 적합',
    '시험기간 늦은영업',
    '배달 가능',
    '포장 가능',
    '예약 가능',
    '주차 가능',
    '24시간',
    '분위기 좋음',
    '데이트 코스',
    '사진 맛집',
    '가성비',
    '매운맛 주의',
    '채식 옵션',
    '반려동물 동반',
    '콘센트 많음',
    '웨이팅 있음',
  ];

  Future<void> _save() async {
    if (_nameController.text.trim().isEmpty) return;
    final trimmedName = _nameController.text.trim();

    setState(() => _saving = true);

    try {
      // 같은 카테고리에 같은 이름(띄어쓰기/기호 무시)이 이미 등록되어 있는지 확인
      final normalized = normalizeName(trimmedName);
      final existing = await FirebaseFirestore.instance
          .collection('places')
          .where('category', isEqualTo: _category)
          .where('nameNormalized', isEqualTo: normalized)
          .limit(1)
          .get();

      if (existing.docs.isNotEmpty) {
        setState(() => _saving = false);
        if (!mounted) return;
        final existingPlace = Place.fromDoc(existing.docs.first);
        final wantsReview = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('이미 등록된 곳이에요'),
            content: Text('"$trimmedName"은(는) 이미 등록되어 있어요.\n리뷰만 추가할까요?',
                style: T.body(size: 13)),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('취소')),
              TextButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('리뷰 추가하기')),
            ],
          ),
        );
        if (wantsReview == true && mounted) {
          Navigator.of(context).pushReplacement(MaterialPageRoute(
              builder: (_) => AddReviewScreen(place: existingPlace)));
        }
        return;
      }

      final placeRef = FirebaseFirestore.instance.collection('places').doc();
      await placeRef.set({
        'name': trimmedName,
        'nameNormalized': normalized,
        'category': _category,
        'tags': _selectedTags.toList(),
        'tasteSum': _taste,
        'tasteCount': 1,
        'valueSum': _value,
        'valueCount': 1,
        'naverMapUrl': _mapUrlController.text.trim().isEmpty
            ? null
            : _mapUrlController.text.trim(),
        'address': _addressController.text.trim().isEmpty
            ? null
            : _addressController.text.trim(),
        'latitude': _lat,
        'longitude': _lng,
        'createdAt': FieldValue.serverTimestamp(),
        'createdBy': FirebaseAuth.instance.currentUser?.uid,
      });
      await placeRef.collection('reviews').add({
        'taste': _taste,
        'value': _value,
        'comment': _commentController.text.trim(),
        'createdAt': FieldValue.serverTimestamp(),
        'uid': FirebaseAuth.instance.currentUser?.uid,
        'placeId': placeRef.id,
        'placeName': _nameController.text.trim(),
      });
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('등록 실패: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('새 장소 등록')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          DropdownButtonFormField<String>(
            initialValue: _category,
            items: kCategories
                .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                .toList(),
            onChanged: (v) => setState(() => _category = v!),
            decoration: const InputDecoration(labelText: '카테고리'),
          ),
          const SizedBox(height: 14),
          TextField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: '가게 이름')),
          const SizedBox(height: 14),
          TextField(
            controller: _mapUrlController,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(
              labelText: '네이버지도 링크 (선택)',
              hintText: '네이버지도 앱 > 공유 > 링크 복사해서 붙여넣기',
            ),
          ),
          const SizedBox(height: 14),
          Text('위치 등록', style: T.body(w: FontWeight.w700)),
          const SizedBox(height: 6),
          Text('도로명 주소를 적으면 GPS보다 정확한 위치를 잡을 수 있어요',
              style: T.body(size: 11, color: AppColors.inkFaint)),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextField(
                  controller: _addressController,
                  decoration: const InputDecoration(hintText: '예: 한림대학길 1'),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                height: 48,
                child: ElevatedButton(
                  onPressed: _geocoding ? null : _findByAddress,
                  style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 16)),
                  child: _geocoding
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Text('찾기'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(children: [
            const Expanded(child: Divider()),
            Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text('또는',
                    style: T.body(size: 11, color: AppColors.inkFaint))),
            const Expanded(child: Divider())
          ]),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _locating ? null : _captureLocation,
            style: OutlinedButton.styleFrom(
              foregroundColor: _lat != null ? AppColors.coral : AppColors.ink,
              side: BorderSide(
                  color: _lat != null ? AppColors.coral : AppColors.divider),
              padding: const EdgeInsets.symmetric(vertical: 13),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            icon: Icon(
                _lat != null ? Icons.check_circle : Icons.location_on_outlined,
                size: 18),
            label: Text(_locating
                ? '위치 확인 중...'
                : (_lat != null
                    ? '위치 등록됨 (다시 잡으려면 탭)'
                    : '지금 여기 위치(GPS)로 등록하기')),
          ),
          if (_lat == null) ...[
            const SizedBox(height: 6),
            Text('위치를 등록하면 홈 지도에 표시돼요 (선택사항)',
                style: T.body(size: 11, color: AppColors.inkFaint)),
          ],
          const SizedBox(height: 20),
          Text('맛 (${_taste.toStringAsFixed(1)})',
              style: T.body(w: FontWeight.w700)),
          Slider(
              value: _taste,
              min: 1,
              max: 5,
              divisions: 8,
              activeColor: AppColors.gradientEnd,
              onChanged: (v) => setState(() => _taste = v)),
          Text('가성비 (${_value.toStringAsFixed(1)})',
              style: T.body(w: FontWeight.w700)),
          Slider(
              value: _value,
              min: 1,
              max: 5,
              divisions: 8,
              activeColor: AppColors.gradientEnd,
              onChanged: (v) => setState(() => _value = v)),
          const SizedBox(height: 10),
          Text('상황 태그', style: T.body(w: FontWeight.w700)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _allTags.map((tag) {
              final selected = _selectedTags.contains(tag);
              return FilterChip(
                label: Text(tag),
                selected: selected,
                onSelected: (v) => setState(() =>
                    v ? _selectedTags.add(tag) : _selectedTags.remove(tag)),
                selectedColor: AppColors.gradientEnd.withOpacity(0.15),
                checkmarkColor: AppColors.gradientEnd,
              );
            }).toList(),
          ),
          const SizedBox(height: 20),
          TextField(
              controller: _commentController,
              maxLines: 3,
              decoration: const InputDecoration(labelText: '한줄 코멘트 (선택)')),
          const SizedBox(height: 24),
          ElevatedButton(
              onPressed: _saving ? null : _save,
              child: Text(_saving ? '등록 중...' : '등록하기')),
        ],
      ),
    );
  }
}

/// ============================================================
/// 기존 장소에 리뷰 추가
/// ============================================================
class AddReviewScreen extends StatefulWidget {
  final Place place;
  const AddReviewScreen({super.key, required this.place});

  @override
  State<AddReviewScreen> createState() => _AddReviewScreenState();
}

class _AddReviewScreenState extends State<AddReviewScreen> {
  final _commentController = TextEditingController();
  double _taste = 4;
  double _value = 4;
  bool _saving = false;

  Future<void> _save() async {
    setState(() => _saving = true);
    final placeRef =
        FirebaseFirestore.instance.collection('places').doc(widget.place.id);
    try {
      await FirebaseFirestore.instance.runTransaction((tx) async {
        tx.update(placeRef, {
          'tasteSum': FieldValue.increment(_taste),
          'tasteCount': FieldValue.increment(1),
          'valueSum': FieldValue.increment(_value),
          'valueCount': FieldValue.increment(1),
        });
        tx.set(placeRef.collection('reviews').doc(), {
          'taste': _taste,
          'value': _value,
          'comment': _commentController.text.trim(),
          'createdAt': FieldValue.serverTimestamp(),
          'uid': FirebaseAuth.instance.currentUser?.uid,
          'placeId': widget.place.id,
          'placeName': widget.place.name,
        });
      });
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('등록 실패: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('${widget.place.name} 리뷰')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text('맛 (${_taste.toStringAsFixed(1)})',
              style: T.body(w: FontWeight.w700)),
          Slider(
              value: _taste,
              min: 1,
              max: 5,
              divisions: 8,
              activeColor: AppColors.gradientEnd,
              onChanged: (v) => setState(() => _taste = v)),
          Text('가성비 (${_value.toStringAsFixed(1)})',
              style: T.body(w: FontWeight.w700)),
          Slider(
              value: _value,
              min: 1,
              max: 5,
              divisions: 8,
              activeColor: AppColors.gradientEnd,
              onChanged: (v) => setState(() => _value = v)),
          const SizedBox(height: 14),
          TextField(
              controller: _commentController,
              maxLines: 3,
              decoration: const InputDecoration(labelText: '한줄 코멘트')),
          const SizedBox(height: 20),
          ElevatedButton(
              onPressed: _saving ? null : _save,
              child: Text(_saving ? '등록 중...' : '리뷰 등록')),
        ],
      ),
    );
  }
}

/// ============================================================
/// 인증 화면
/// ============================================================
/// Firebase 인증 에러를 한국어 안내 문구로 변환
String friendlyAuthError(FirebaseAuthException e) {
  switch (e.code) {
    case 'invalid-credential':
    case 'wrong-password':
      return '이메일 또는 비밀번호를 확인해주세요';
    case 'user-not-found':
      return '가입되지 않은 이메일이에요';
    case 'invalid-email':
      return '이메일 형식을 확인해주세요';
    case 'email-already-in-use':
      return '이미 가입된 이메일이에요';
    case 'weak-password':
      return '비밀번호가 너무 간단해요';
    case 'too-many-requests':
      return '시도가 너무 많아요. 잠시 후 다시 시도해주세요';
    case 'network-request-failed':
      return '네트워크 연결을 확인해주세요';
    case 'requires-recent-login':
      return '보안을 위해 재로그인 후 다시 시도해주세요';
    default:
      return '문제가 발생했어요. 다시 시도해주세요';
  }
}

enum _AuthStep { email, code, password }

class AuthScreen extends StatefulWidget {
  final VoidCallback? onGuest;
  const AuthScreen({super.key, this.onGuest});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  _AuthStep _step = _AuthStep.email;
  bool _isLoginMode = true;

  final _emailController = TextEditingController();
  final _codeController = TextEditingController();
  final _pwController = TextEditingController();
  final _pwConfirmController = TextEditingController();

  bool _loading = false;
  String? _message;

  Future<void> _proceedFromEmail() async {
    final email = _emailController.text.trim().toLowerCase();
    if (!email.contains('@') || !email.contains('.')) {
      setState(() => _message = '올바른 이메일 형식을 입력해주세요');
      return;
    }
    await _sendCode();
  }

  Future<void> _sendCode() async {
    final email = _emailController.text.trim().toLowerCase();
    setState(() {
      _loading = true;
      _message = null;
    });
    try {
      await EmailCodeService.sendCode(email);
      setState(() => _step = _AuthStep.code);
    } catch (e) {
      setState(() => _message = '메일 발송에 실패했어요: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _verifyCode() async {
    final email = _emailController.text.trim().toLowerCase();
    final code = _codeController.text.trim();
    if (code.length != 6) {
      setState(() => _message = '6자리 코드를 입력해주세요');
      return;
    }
    setState(() {
      _loading = true;
      _message = null;
    });
    final ok = await EmailCodeService.verifyCode(email, code);
    setState(() => _loading = false);
    if (!ok) {
      setState(() => _message = '코드가 일치하지 않거나 만료됐어요');
      return;
    }
    setState(() => _step = _AuthStep.password);
  }

  Future<void> _createAccount() async {
    final email = _emailController.text.trim().toLowerCase();
    final pw = _pwController.text;
    final pwConfirm = _pwConfirmController.text;
    if (pw.length < 6) {
      setState(() => _message = '비밀번호는 6자 이상이어야 해요');
      return;
    }
    if (pw != pwConfirm) {
      setState(() => _message = '비밀번호가 서로 달라요. 다시 확인해주세요');
      return;
    }
    setState(() {
      _loading = true;
      _message = null;
    });
    try {
      final isSchoolEmail = email.endsWith('@$kSchoolDomain');
      final cred = await FirebaseAuth.instance
          .createUserWithEmailAndPassword(email: email, password: pw);
      await FirebaseFirestore.instance
          .collection('users')
          .doc(cred.user!.uid)
          .set({
        'email': email,
        'verified': isSchoolEmail,
        'createdAt': FieldValue.serverTimestamp()
      });
      if (isSchoolEmail) await EmailCodeService.clearCode(email);
      if (!mounted) return;
      Navigator.of(context).maybePop();
    } on FirebaseAuthException catch (e) {
      setState(() => _message = friendlyAuthError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _login() async {
    final email = _emailController.text.trim().toLowerCase();
    final pw = _pwController.text;
    setState(() {
      _loading = true;
      _message = null;
    });
    try {
      await FirebaseAuth.instance
          .signInWithEmailAndPassword(email: email, password: pw);
      if (!mounted) return;
      Navigator.of(context).maybePop();
    } on FirebaseAuthException catch (e) {
      setState(() => _message = friendlyAuthError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _handleGuest() {
    if (widget.onGuest != null) {
      widget.onGuest!();
    } else {
      Navigator.of(context).maybePop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: const BoxDecoration(
                        color: AppColors.coral, shape: BoxShape.circle),
                    child: const Icon(Icons.storefront_rounded,
                        color: Colors.white, size: 18),
                  ),
                  const SizedBox(width: 10),
                  Text('한림대 $kAppName', style: T.heading(size: 15)),
                ],
              ),
              const SizedBox(height: 28),
              RichText(
                text: TextSpan(
                  style: T.heading(size: 27),
                  children: [
                    const TextSpan(text: '먹고 싶다면\n'),
                    TextSpan(
                        text: '여기서 찾아요',
                        style: T.heading(size: 27, color: AppColors.coral)),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Text('한림대 주변 맛집 정보를 한눈에',
                  style: T.body(size: 13, color: AppColors.inkFaint)),
              const SizedBox(height: 28),
              Row(
                children: [
                  _TabUnderline(
                      label: '로그인',
                      selected: _isLoginMode,
                      onTap: () => setState(() {
                            _isLoginMode = true;
                            _step = _AuthStep.email;
                            _message = null;
                          })),
                  const SizedBox(width: 22),
                  _TabUnderline(
                      label: '회원가입',
                      selected: !_isLoginMode,
                      onTap: () => setState(() {
                            _isLoginMode = false;
                            _step = _AuthStep.email;
                            _message = null;
                          })),
                ],
              ),
              const Divider(height: 24, color: AppColors.divider),
              if (_isLoginMode) ..._buildLoginForm() else ..._buildSignupForm(),
              if (_message != null) ...[
                const SizedBox(height: 12),
                Text(_message!,
                    style: T.body(size: 13, color: AppColors.stamp)),
              ],
              const SizedBox(height: 20),
              Row(
                children: [
                  const Expanded(child: Divider(color: AppColors.divider)),
                  Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      child: Text('또는',
                          style: T.body(size: 12, color: AppColors.inkFaint))),
                  const Expanded(child: Divider(color: AppColors.divider)),
                ],
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.ink,
                      side: const BorderSide(color: AppColors.divider),
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14))),
                  onPressed: _handleGuest,
                  child: Text('비회원으로 둘러보기',
                      style: T.body(size: 14, w: FontWeight.w700)),
                ),
              ),
              const SizedBox(height: 20),
              Text('계속 진행하면 이용약관 및 개인정보처리방침에 동의합니다',
                  textAlign: TextAlign.center,
                  style: T.body(size: 11, color: AppColors.inkFaint)),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildLoginForm() {
    return [
      Text('이메일',
          style:
              T.body(size: 12, color: AppColors.inkFaint, w: FontWeight.w700)),
      const SizedBox(height: 6),
      TextField(
          controller: _emailController,
          keyboardType: TextInputType.emailAddress,
          inputFormatters: [FilteringTextInputFormatter.deny(RegExp(r'\s'))],
          decoration: const InputDecoration(hintText: '이메일 주소')),
      const SizedBox(height: 16),
      Text('비밀번호',
          style:
              T.body(size: 12, color: AppColors.inkFaint, w: FontWeight.w700)),
      const SizedBox(height: 6),
      TextField(
          controller: _pwController,
          obscureText: true,
          decoration: const InputDecoration(hintText: '비밀번호 8자 이상')),
      const SizedBox(height: 18),
      SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: _loading ? null : _login,
          child: _loading
              ? const Text('처리 중...')
              : Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  const Text('로그인'),
                  const SizedBox(width: 6),
                  const Icon(Icons.arrow_forward, size: 16, color: Colors.white)
                ]),
        ),
      ),
      const SizedBox(height: 12),
      Center(
        child: TextButton(
          onPressed: () => ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('준비 중인 기능이에요'))),
          child: RichText(
              text: TextSpan(
                  style: T.body(size: 12, color: AppColors.inkFaint),
                  children: const [
                TextSpan(text: '비밀번호를 잊으셨나요? '),
                TextSpan(
                    text: '재설정',
                    style: TextStyle(
                        color: AppColors.coral, fontWeight: FontWeight.w700))
              ])),
        ),
      ),
    ];
  }

  List<Widget> _buildSignupForm() {
    switch (_step) {
      case _AuthStep.email:
        return [
          Text('이메일 인증이 필요해요', style: T.heading(size: 14)),
          const SizedBox(height: 4),
          Text(
              '입력한 이메일로 인증코드를 보내드려요.\n한림대 웹메일(@$kSchoolDomain)이면 학생 인증까지 완료돼요.',
              style: T.body(size: 12, color: AppColors.inkFaint)),
          const SizedBox(height: 12),
          Text('이메일',
              style: T.body(
                  size: 12, color: AppColors.inkFaint, w: FontWeight.w700)),
          const SizedBox(height: 6),
          TextField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              inputFormatters: [
                FilteringTextInputFormatter.deny(RegExp(r'\s'))
              ],
              decoration: const InputDecoration(
                  hintText: 'example@hallym.ac.kr 또는 일반 이메일')),
          const SizedBox(height: 18),
          SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                  onPressed: _loading ? null : _proceedFromEmail,
                  child: Text(_loading ? '확인 중...' : '다음'))),
        ];
      case _AuthStep.code:
        return [
          TextButton(
            onPressed: () => setState(() {
              _step = _AuthStep.email;
              _codeController.clear();
              _message = null;
            }),
            style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                alignment: Alignment.centerLeft,
                minimumSize: const Size(0, 0)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.arrow_back, size: 14, color: AppColors.inkFaint),
              const SizedBox(width: 4),
              Text('이메일 다시 입력',
                  style: T.body(
                      size: 12, color: AppColors.inkFaint, w: FontWeight.w700))
            ]),
          ),
          const SizedBox(height: 10),
          Text('${_emailController.text.trim()}(으)로\n인증코드를 보냈어요',
              style: T.heading(size: 14)),
          const SizedBox(height: 14),
          TextField(
            controller: _codeController,
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            maxLength: 6,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            style: T
                .heading(size: 22, color: AppColors.coral)
                .copyWith(letterSpacing: 8),
            decoration:
                const InputDecoration(counterText: '', hintText: '000000'),
          ),
          SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                  onPressed: _loading ? null : _verifyCode,
                  child: Text(_loading ? '확인 중...' : '확인'))),
          Center(
              child: TextButton(
                  onPressed: _loading ? null : _sendCode,
                  child: const Text('코드 다시 받기'))),
        ];
      case _AuthStep.password:
        return [
          TextButton(
            onPressed: () => setState(() {
              _step = _AuthStep.email;
              _pwController.clear();
              _pwConfirmController.clear();
              _message = null;
            }),
            style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                alignment: Alignment.centerLeft,
                minimumSize: const Size(0, 0)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.arrow_back, size: 14, color: AppColors.inkFaint),
              const SizedBox(width: 4),
              Text('처음부터 다시',
                  style: T.body(
                      size: 12, color: AppColors.inkFaint, w: FontWeight.w700))
            ]),
          ),
          const SizedBox(height: 10),
          Text('비밀번호를 설정해주세요', style: T.heading(size: 14)),
          const SizedBox(height: 12),
          TextField(
              controller: _pwController,
              obscureText: true,
              decoration: const InputDecoration(hintText: '비밀번호 (6자 이상)')),
          const SizedBox(height: 10),
          TextField(
              controller: _pwConfirmController,
              obscureText: true,
              decoration: const InputDecoration(hintText: '비밀번호 확인')),
          const SizedBox(height: 18),
          SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                  onPressed: _loading ? null : _createAccount,
                  child: Text(_loading ? '처리 중...' : '가입 완료'))),
        ];
    }
  }
}

class _TabUnderline extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _TabUnderline(
      {required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label,
              style: T.body(
                  size: 15,
                  w: FontWeight.w800,
                  color: selected ? AppColors.ink : AppColors.inkFaint)),
          const SizedBox(height: 8),
          Container(
              width: 40,
              height: 2.5,
              color: selected ? AppColors.coral : Colors.transparent),
        ],
      ),
    );
  }
}

/// ============================================================
/// 마이페이지 탭 — 계정 정보 + 메뉴 목록
/// ============================================================
class AccountScreen extends StatelessWidget {
  const AccountScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    return Scaffold(
      appBar: AppBar(
          title: const Text('마이페이지'),
          backgroundColor: AppColors.background,
          elevation: 0,
          foregroundColor: AppColors.ink),
      body: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.all(20),
            child: user == null
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                          '가입하면 리뷰를 남기고 수정 요청을 할 수 있어요.\n한림대 웹메일로 가입하면 등록 권한까지 생겨요.',
                          style: T.body(color: AppColors.inkFaint)),
                      const SizedBox(height: 14),
                      ElevatedButton(
                          onPressed: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                  builder: (_) => const AuthScreen())),
                          child: const Text('로그인 / 학교 인증하기')),
                    ],
                  )
                : FutureBuilder<bool>(
                    future: isVerifiedStudentAccount(),
                    builder: (context, snap) {
                      final verified = snap.data ?? false;
                      return Row(
                        children: [
                          if (verified)
                            const StampBadge(size: 34)
                          else
                            const CircleAvatar(
                                radius: 17,
                                backgroundColor: AppColors.surfaceMuted,
                                child: Icon(Icons.person,
                                    size: 18, color: AppColors.inkFaint)),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(user.email ?? '',
                                    style: T.heading(size: 15),
                                    overflow: TextOverflow.ellipsis),
                                Text(verified ? '인증된 학생' : '일반 회원',
                                    style: T.body(
                                        size: 12, color: AppColors.inkFaint)),
                              ],
                            ),
                          ),
                        ],
                      );
                    },
                  ),
          ),
          const Divider(height: 1),
          if (user != null)
            ListTile(
              leading: const Icon(Icons.rate_review_outlined,
                  color: AppColors.gradientEnd),
              title: Text('내 리뷰', style: T.body(w: FontWeight.w600)),
              trailing:
                  const Icon(Icons.chevron_right, color: AppColors.inkFaint),
              onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const MyReviewsScreen())),
            ),
          if (user != null)
            ListTile(
              leading: const Icon(Icons.storefront_outlined,
                  color: AppColors.gradientEnd),
              title: Text('내가 등록한 곳', style: T.body(w: FontWeight.w600)),
              trailing:
                  const Icon(Icons.chevron_right, color: AppColors.inkFaint),
              onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const MyPlacesScreen())),
            ),
          ListTile(
            leading: const Icon(Icons.campaign_outlined,
                color: AppColors.gradientEnd),
            title: Text('공지사항', style: T.body(w: FontWeight.w600)),
            trailing:
                const Icon(Icons.chevron_right, color: AppColors.inkFaint),
            onTap: () => Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => const NoticeScreen())),
          ),
          ListTile(
            leading:
                const Icon(Icons.mail_outline, color: AppColors.gradientEnd),
            title: Text('문의', style: T.body(w: FontWeight.w600)),
            trailing:
                const Icon(Icons.chevron_right, color: AppColors.inkFaint),
            onTap: () => Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => const ContactScreen())),
          ),
          ListTile(
            leading: Icon(user == null ? Icons.login : Icons.logout,
                color: user == null ? AppColors.gradientEnd : AppColors.stamp),
            title: Text(user == null ? '로그인' : '로그아웃',
                style: T.body(
                    w: FontWeight.w600,
                    color: user == null ? AppColors.ink : AppColors.stamp)),
            onTap: () async {
              if (user == null) {
                Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const AuthScreen()));
              } else {
                await FirebaseAuth.instance.signOut();
              }
            },
          ),
          if (user != null)
            ListTile(
              leading: const Icon(Icons.person_remove_outlined,
                  color: AppColors.stamp),
              title: Text('탈퇴',
                  style: T.body(w: FontWeight.w600, color: AppColors.stamp)),
              onTap: () => _confirmAndDeleteAccount(context),
            ),
        ],
      ),
    );
  }

  Future<void> _confirmAndDeleteAccount(BuildContext context) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final myPlaces = await FirebaseFirestore.instance
        .collection('places')
        .where('createdBy', isEqualTo: user.uid)
        .get();
    final placeCount = myPlaces.docs.length;

    final message = placeCount > 0
        ? '내가 등록한 곳이 $placeCount곳 있어요.\n\n탈퇴해도 등록한 곳과 리뷰는 삭제되지 않고 그대로 남아요.\n다만 탈퇴 후에는 본인이 직접 수정할 수 없고, 관리자만 수정할 수 있게 돼요.\n\n그래도 탈퇴할까요?'
        : '탈퇴하면 계정 정보가 삭제되고 되돌릴 수 없어요.\n작성한 리뷰는 남아있을 수 있어요.';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('정말 탈퇴할까요?'),
        content: Text(message, style: T.body(size: 13)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('취소')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text('탈퇴', style: TextStyle(color: AppColors.stamp))),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .delete();
      await user.delete();
    } on FirebaseAuthException catch (e) {
      if (!context.mounted) return;
      if (e.code == 'requires-recent-login') {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('보안을 위해 재로그인 후 다시 시도해주세요')));
      } else {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('탈퇴 실패: ${e.message}')));
      }
    }
  }
}

class MyReviewsScreen extends StatelessWidget {
  const MyReviewsScreen({super.key});

  Future<void> _openPlace(BuildContext context, String placeId) async {
    final doc = await FirebaseFirestore.instance
        .collection('places')
        .doc(placeId)
        .get();
    if (!doc.exists) {
      if (context.mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('삭제된 장소예요')));
      return;
    }
    final place = Place.fromDoc(doc);
    if (context.mounted)
      Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => PlaceDetailScreen(place: place)));
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final query = FirebaseFirestore.instance
        .collectionGroup('reviews')
        .where('uid', isEqualTo: uid)
        .orderBy('createdAt', descending: true);
    return Scaffold(
      appBar: AppBar(title: const Text('내 리뷰')),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: query.snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
                child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Text(
                        '색인 설정이 필요해요.\nFirestore 콘솔 에러 메시지의 링크를 눌러\n색인을 생성한 뒤 다시 시도해주세요.',
                        textAlign: TextAlign.center,
                        style: T.body(color: AppColors.inkFaint))));
          }
          if (!snapshot.hasData)
            return const Center(
                child: CircularProgressIndicator(color: AppColors.gradientEnd));
          final docs = snapshot.data!.docs;
          if (docs.isEmpty)
            return Center(
                child: Text('아직 남긴 리뷰가 없어요',
                    style: T.body(color: AppColors.inkFaint)));
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: docs.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final d = docs[i].data();
              return ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(d['placeName'] ?? '', style: T.heading(size: 15)),
                subtitle: Text(d['comment'] ?? '',
                    style: T.body(size: 12, color: AppColors.inkFaint),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                trailing: Text('★${d['taste']} · 가성비 ${d['value']}',
                    style: T.body(
                        size: 11, color: AppColors.gold, w: FontWeight.w700)),
                onTap: () => _openPlace(context, d['placeId']),
              );
            },
          );
        },
      ),
    );
  }
}

/// ============================================================
/// 내가 등록한 곳
/// ============================================================
class MyPlacesScreen extends StatelessWidget {
  const MyPlacesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final query = FirebaseFirestore.instance
        .collection('places')
        .where('createdBy', isEqualTo: uid)
        .orderBy('createdAt', descending: true);
    return Scaffold(
      appBar: AppBar(title: const Text('내가 등록한 곳')),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: query.snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
                child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Text(
                        '색인 설정이 필요해요.\nFirestore 콘솔 에러 메시지의 링크를 눌러\n색인을 생성한 뒤 다시 시도해주세요.',
                        textAlign: TextAlign.center,
                        style: T.body(color: AppColors.inkFaint))));
          }
          if (!snapshot.hasData)
            return const Center(
                child: CircularProgressIndicator(color: AppColors.coral));
          final docs = snapshot.data!.docs;
          if (docs.isEmpty)
            return Center(
                child: Text('아직 등록한 곳이 없어요',
                    style: T.body(color: AppColors.inkFaint)));
          final places = docs.map(Place.fromDoc).toList();
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: places.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final place = places[i];
              final style =
                  kCategoryStyles[place.category] ?? kCategoryStyles['한식']!;
              return ListTile(
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(
                    backgroundColor: style.bg,
                    child: Icon(style.icon, color: style.iconColor, size: 18)),
                title: Text(place.name, style: T.heading(size: 15)),
                subtitle: Text('${place.category} · 리뷰 ${place.reviewCount}',
                    style: T.body(size: 12, color: AppColors.inkFaint)),
                trailing: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: FirebaseFirestore.instance
                      .collection('places')
                      .doc(place.id)
                      .collection('reports')
                      .where('resolved', isEqualTo: false)
                      .snapshots(),
                  builder: (context, reportSnap) {
                    final count = reportSnap.data?.docs.length ?? 0;
                    if (count == 0)
                      return const Icon(Icons.chevron_right,
                          color: AppColors.inkFaint);
                    return Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                          color: AppColors.coral,
                          borderRadius: BorderRadius.circular(10)),
                      child: Text('요청 $count',
                          style: T.body(
                              size: 11,
                              color: Colors.white,
                              w: FontWeight.w700)),
                    );
                  },
                ),
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => PlaceDetailScreen(place: place))),
              );
            },
          );
        },
      ),
    );
  }
}

/// ============================================================
/// 알림함 — 내 게시물에 온 수정 요청 등
/// ============================================================
class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final query = FirebaseFirestore.instance
        .collection('notifications')
        .where('toUid', isEqualTo: uid)
        .orderBy('createdAt', descending: true);
    return Scaffold(
      appBar: AppBar(title: const Text('알림')),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: query.snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
                child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Text(
                        '색인 설정이 필요해요.\nFirestore 콘솔 에러 메시지의 링크를 눌러\n색인을 생성한 뒤 다시 시도해주세요.',
                        textAlign: TextAlign.center,
                        style: T.body(color: AppColors.inkFaint))));
          }
          if (!snapshot.hasData)
            return const Center(
                child: CircularProgressIndicator(color: AppColors.coral));
          final docs = snapshot.data!.docs;
          if (docs.isEmpty)
            return Center(
                child: Text('아직 알림이 없어요',
                    style: T.body(color: AppColors.inkFaint)));
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: docs.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final doc = docs[i];
              final d = doc.data();
              final read = d['read'] == true;
              return ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.flag,
                    color: read ? AppColors.inkFaint : AppColors.coral),
                title: Text('"${d['placeName']}" 수정 요청',
                    style: T.body(
                        size: 14, w: read ? FontWeight.w500 : FontWeight.w800)),
                subtitle: Text(d['message'] ?? '',
                    style: T.body(size: 12, color: AppColors.inkFaint),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis),
                onTap: () async {
                  await doc.reference.update({'read': true});
                  if (!context.mounted) return;
                  final placeDoc = await FirebaseFirestore.instance
                      .collection('places')
                      .doc(d['placeId'])
                      .get();
                  if (!placeDoc.exists) {
                    if (context.mounted)
                      ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('삭제된 장소예요')));
                    return;
                  }
                  final place = Place.fromDoc(placeDoc);
                  if (context.mounted)
                    Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => PlaceDetailScreen(place: place)));
                },
              );
            },
          );
        },
      ),
    );
  }
}

/// ============================================================
/// 공지사항 / 문의
/// ============================================================
class NoticeScreen extends StatelessWidget {
  const NoticeScreen({super.key});

  static const _notices = [
    {
      'title': '한림먹자골목 오픈했어요',
      'date': '2026.07',
      'body': '학교 웹메일 인증한 학생이라면 누구나 등록·리뷰를 남길 수 있어요. 광고성 게시물은 발견 즉시 삭제합니다.'
    },
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('공지사항')),
      body: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _notices.length,
        separatorBuilder: (_, __) => const Divider(height: 24),
        itemBuilder: (context, i) {
          final n = _notices[i];
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(n['title']!, style: T.heading(size: 16)),
              const SizedBox(height: 4),
              Text(n['date']!,
                  style: T.body(size: 12, color: AppColors.inkFaint)),
              const SizedBox(height: 8),
              Text(n['body']!, style: T.body()),
            ],
          );
        },
      ),
    );
  }
}

class ContactScreen extends StatelessWidget {
  const ContactScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('문의')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('버그 제보나 건의사항, 광고성 게시물 신고는\n아래로 연락해주세요.', style: T.body()),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                  color: AppColors.surface,
                  border: Border.all(color: AppColors.divider),
                  borderRadius: BorderRadius.circular(12)),
              child: Text('이메일: 20225131@hallym.ac.kr',
                  style: T.body(
                      size: 13,
                      color: AppColors.gradientEnd,
                      w: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
  }
}
