import 'package:flutter_test/flutter_test.dart';
import 'package:miki_miki/services/deep_links.dart';
import 'package:miki_miki/services/hikka_auth.dart';
import 'package:miki_miki/services/hikka_nav.dart';

void main() {
  test('miki://open/anime/<slug> відкриває сторінку тайтлу', () {
    final nav = HikkaNav();
    expect(DeepLinks.handle('miki://open/anime/sousou-no-frieren-abc123', nav: nav), isTrue);
    expect(nav.top?.kind, HikkaRouteKind.anime);
    expect(nav.top?.slug, 'sousou-no-frieren-abc123');
  });

  test('інші сторінки й просте відкриття', () {
    final nav = HikkaNav();
    expect(DeepLinks.handle('miki://open', nav: nav), isTrue);
    expect(nav.top, isNull);
    expect(DeepLinks.handle('miki://open/character/frieren', nav: nav), isTrue);
    expect(nav.top?.kind, HikkaRouteKind.character);
  });

  test('чужі та підозрілі посилання ігноруються', () {
    final nav = HikkaNav();
    expect(DeepLinks.handle('https://example.com/anime/x', nav: nav), isFalse);
    expect(DeepLinks.handle('miki://other/anime/x', nav: nav), isFalse);
    expect(DeepLinks.handle('miki://open/anime/../../etc', nav: nav), isFalse);
    expect(DeepLinks.handle('miki://open/anime/a b', nav: nav), isFalse);
    expect(DeepLinks.handle('miki://open/невідомо/x', nav: nav), isFalse);
    expect(nav.top, isNull);
  });

  test('код входу за посиланням приймається лише коли вхід триває', () {
    final auth = HikkaAuth(load: () => {}, save: (_) {});
    expect(auth.phase, HikkaAuthPhase.signedOut);
    expect(DeepLinks.handle('miki://open/auth?reference=00000000-0000-4000-8000-000000000003', auth: auth, nav: HikkaNav()), isFalse);
    expect(auth.phase, HikkaAuthPhase.signedOut, reason: 'чужий код не логінить без початого входу');
  });
}
