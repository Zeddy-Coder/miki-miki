import '../utils/platform_info.dart';
import '../widgets/app_ui_kit.dart';

class AppConstants {
  static const List<double> speeds = [0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0, 2.5];

  // Словники декодерів
  static final Map<String, String> hwdecOptions = AppPlatform.isMobile
      ? {
          "mediacodec-copy": "MediaCodec (Універсальний)",
          "mediacodec": "MediaCodec (без копіювання кадру)",
          "auto-safe": "Автоматичний вибір (Auto Safe)",
          "no": "Вимкнено (Програмний CPU)",
        }
      : {
          "nvdec-copy": "NVIDIA NVDEC (CUDA — Максимальна швидкість)",
          "d3d11va-copy": "Direct3D 11 (Універсальний)",
          "auto-safe": "Автоматичний вибір (Auto Safe)",
          "no": "Вимкнено (Програмний CPU)",
        };

  static const Map<String, String> hwdecShortNames = {
    "nvdec-copy": "NVDEC (CUDA)",
    "d3d11va-copy": "Direct3D 11",
    "mediacodec-copy": "MediaCodec",
    "mediacodec": "MediaCodec",
    "auto-safe": "Авто",
    "no": "Вимкнено",
  };

  // Словник мов
  static const Map<String, String> langMap = {
    "en": "Англійська", "eng": "Англійська",
    "uk": "Українська", "ukr": "Українська",
    "ja": "Японська", "jpn": "Японська",
    "ko": "Корейська", "kor": "Корейська",
    "pl": "Польська", "pol": "Польська",
    "de": "Німецька", "ger": "Німецька", "deu": "Німецька",
    "fr": "Французька", "fre": "Французька", "fra": "Французька",
    "es": "Іспанська", "spa": "Іспанська",
    "it": "Італійська", "ita": "Італійська",
    "pt": "Португальська", "por": "Португальська",
    "zh": "Китайська", "chi": "Китайська", "zho": "Китайська",
    "tr": "Турецька", "tur": "Турецька",
    "ar": "Арабська", "ara": "Арабська",
    "hi": "Хінді", "hin": "Хінді",
    "cs": "Чеська", "cze": "Чеська", "ces": "Чеська",
    "da": "Данська", "dan": "Данська",
    "el": "Грецька", "gre": "Грецька", "ell": "Грецька",
    "et": "Естонська", "est": "Естонська",
    "fi": "Фінська", "fin": "Фінська",
    "he": "Іврит", "heb": "Іврит",
    "hu": "Угорська", "hun": "Угорська",
    "id": "Індонезійська", "ind": "Індонезійська",
    "lt": "Литовська", "lit": "Литовська",
    "lv": "Латиська", "lav": "Латиська",
    "ms": "Малайська", "may": "Малайська", "msa": "Малайська",
    "nl": "Нідерландська", "dut": "Нідерландська", "nld": "Нідерландська",
    "no": "Норвезька", "nor": "Норвезька",
    "ro": "Румунська", "rum": "Румунська", "ron": "Румунська",
    "sk": "Словацька", "slo": "Словацька", "slk": "Словацька",
    "sl": "Словенська", "slv": "Словенська",
    "sv": "Шведська", "swe": "Шведська",
    "th": "Тайська", "tha": "Тайська",
    "vi": "В'єтнамська", "vie": "В'єтнамська",
    "hr": "Хорватська", "hrv": "Хорватська",
    "sr": "Сербська", "srp": "Сербська",
    "bg": "Болгарська", "bul": "Болгарська",
    "ka": "Грузинська", "kat": "Грузинська",
    "hy": "Вірменська", "arm": "Вірменська",
    "az": "Азербайджанська", "aze": "Азербайджанська",
    "kk": "Казахська", "kaz": "Казахська",
    "uz": "Узбецька", "uzb": "Узбецька",
    "fa": "Перська", "per": "Перська",
    "ur": "Урду", "urd": "Урду",
    "bn": "Бенгальська", "ben": "Бенгальська",
    "is": "Ісландська", "isl": "Ісландська",
    "fil": "Філіппінська", "tgl": "Тагальська",
    "mk": "Македонська", "mac": "Македонська",
    "sq": "Албанська", "alb": "Албанська",
    "be": "Білоруська", "bel": "Білоруська",
  };

  static List<AppDropdownOption<String>> getLanguageDropdownOptions({bool includeAuto = true}) {
    final List<AppDropdownOption<String>> result = [];
    if (includeAuto) {
      result.add(const AppDropdownOption(value: 'auto', label: 'Автоматичний вибір файлу'));
    }
    final priorityCodes = ['uk', 'ja', 'en', 'ko', 'pl', 'de', 'fr', 'es', 'it', 'zh'];
    for (final code in priorityCodes) {
      final name = langMap[code];
      if (name != null) result.add(AppDropdownOption(value: code, label: '$name ($code)'));
    }
    final Set<String> processedNames = priorityCodes.map((c) => langMap[c]!).toSet();
    final remaining = <MapEntry<String, String>>[];
    langMap.forEach((code, name) {
      if (code.length == 2 && !processedNames.contains(name)) {
        processedNames.add(name);
        remaining.add(MapEntry(code, name));
      }
    });
    remaining.sort((a, b) => a.value.compareTo(b.value));
    for (final e in remaining) {
      result.add(AppDropdownOption(value: e.key, label: '${e.value} (${e.key})'));
    }
    return result;
  }
}