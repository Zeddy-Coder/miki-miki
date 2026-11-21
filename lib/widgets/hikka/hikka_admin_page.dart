import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../models/hikka_models.dart';
import '../../services/admin_api.dart';
import '../../services/hikka_nav.dart';
import '../../services/ui_theme_service.dart';
import '../../utils/app_clock.dart';
import '../app_animation_kit.dart';
import '../app_tones.dart';
import '../app_ui_kit.dart';
import '../design_kit.dart';
import '../line_icons.dart';
import 'hikka_common.dart';
import 'hikka_page_kit.dart';
import 'hikka_watch_dialogs.dart' show QuietAction;

/// The admin panel (only for the accounts the server knows as admins, now ZEDDY). The first tool: a notification to
/// everybody who uses Miki Miki, or to those who follow one title — an announcement, "a new version is out" (the tap
/// opens the update window) or a test "new episode". Before sending it shows how the notification looks and how many
/// devices get it; below are the last sent ones. The server decides who may send (see `tools/backend/admin.ts`).
class HikkaAdminPage extends StatefulWidget {
  final HikkaRoute route;
  final double scale;
  final double bottomInset;

  /// For tests: own requests
  final AdminApi? api;

  const HikkaAdminPage({super.key, required this.route, required this.scale, this.bottomInset = 0, this.api});

  /// Under the history rows: what, to whom, how many got it, when
  static String footer(AdminLogEntry e, DateTime now) {
    final to = e.target.startsWith('slug:') ? 'хто стежить за ${e.target.substring(5)}' : 'усім';
    final got = e.failed > 0 ? '${e.sent} з ${e.devices}' : '${e.sent}';
    final hm = '${e.at.hour.toString().padLeft(2, '0')}:${e.at.minute.toString().padLeft(2, '0')}';
    return '${typeLabel(e.type)} · $to · отримали $got · ${HikkaText.dayMonth(e.at, now: now)}, $hm';
  }

  static String typeLabel(String wire) => AdminPushType.values.where((t) => t.wire == wire).firstOrNull?.label ?? wire;

  static String devices(int n) => '$n ${HikkaText.plural(n, 'пристрій', 'пристрої', 'пристроїв')}';

  @override
  State<HikkaAdminPage> createState() => _HikkaAdminPageState();
}

class _HikkaAdminPageState extends State<HikkaAdminPage> {
  late final AdminApi _api = widget.api ?? AdminApi.instance;
  final ScrollController _scroll = AppSmoothScrollController();
  final TextEditingController _title = TextEditingController();
  final TextEditingController _body = TextEditingController();
  final TextEditingController _slug = TextEditingController();
  final TextEditingController _image = TextEditingController();

  AdminPushType _type = AdminPushType.news;

  /// "Кому": only those who follow the title (otherwise everybody)
  bool _followers = false;

  // Access: who the server sees
  bool _checking = true;
  String? _accessError;
  String _who = '';
  int _devices = 0;

  // "Скільки отримають?"
  int? _count;
  bool _counting = false;

  // Sending
  bool _sending = false;
  String? _sendError;
  AdminSendResult? _result;

  // The last sent
  List<AdminLogEntry>? _history;
  String? _historyError;

  double get _scale => widget.scale;

  @override
  void initState() {
    super.initState();
    for (final c in [_title, _body, _slug, _image]) {
      c.addListener(_onEdit);
    }
    unawaited(_load());
  }

  @override
  void dispose() {
    for (final c in [_title, _body, _slug, _image]) {
      c.dispose();
    }
    _scroll.dispose();
    super.dispose();
  }

  /// Any edit: the preview follows, the old count and result no longer apply
  void _onEdit() {
    if (!mounted) return;
    setState(() {
      _count = null;
      _sendError = null;
    });
  }

  Future<void> _load() async {
    setState(() {
      _checking = true;
      _accessError = null;
    });
    try {
      final (who, devices) = await _api.whoami();
      if (!mounted) return;
      setState(() {
        _who = who;
        _devices = devices;
        _checking = false;
      });
      unawaited(_loadHistory());
    } on AdminException catch (e) {
      if (!mounted) return;
      setState(() {
        _accessError = e.message;
        _checking = false;
      });
    }
  }

  Future<void> _loadHistory() async {
    try {
      final items = await _api.history();
      if (mounted) {
        setState(() {
          _history = items;
          _historyError = null;
        });
      }
    } on AdminException catch (e) {
      if (mounted) setState(() => _historyError = e.message);
    }
  }

  // ── The form ───────────────────────────────────────────────────────────────

  bool get _hasTitleField => _type != AdminPushType.update;

  /// The title from the field (a slug or a hikka.io address); null when the field is empty or wrong
  String? get _slugValue => _slug.text.trim().isEmpty ? null : AdminApi.slugOf(_slug.text);

  String? get _slugError => _hasTitleField && _slug.text.trim().isNotEmpty && _slugValue == null
      ? 'Не схоже на тайтл Hikka: вставте slug (sousou-no-frieren-…) або посилання hikka.io/anime/…'
      : null;

  String? get _imageError {
    final s = _image.text.trim();
    return _hasTitleField && s.isNotEmpty && !s.startsWith('https://') ? 'Картинка має бути посиланням https://' : null;
  }

  bool get _toFollowers => _hasTitleField && _followers && _slugValue != null;

  AdminPush get _push => AdminPush(
        type: _type,
        title: _title.text,
        body: _body.text,
        slug: _hasTitleField ? (_slugValue ?? '') : '',
        audienceSlug: _toFollowers ? _slugValue! : '',
        image: _hasTitleField ? _image.text.trim() : '',
      );

  /// What stops sending, in words; null when everything is in place
  String? get _problem {
    if (_title.text.trim().isEmpty) return 'Напишіть заголовок.';
    if (_body.text.trim().isEmpty) return 'Напишіть текст сповіщення.';
    if (_slugError != null) return _slugError;
    if (_imageError != null) return _imageError;
    if (_type == AdminPushType.episode && _slugValue == null) return 'Для «Нової серії» потрібен тайтл: вставте його slug чи посилання.';
    if (_hasTitleField && _followers && _slugValue == null) return 'Щоб надіслати тим, хто стежить за тайтлом, вкажіть тайтл.';
    return null;
  }

  Future<void> _countDevices() async {
    setState(() {
      _counting = true;
      _sendError = null;
    });
    try {
      final n = await _api.count(audienceSlug: _push.audienceSlug);
      if (mounted) setState(() => _count = n);
    } on AdminException catch (e) {
      if (mounted) setState(() => _sendError = e.message);
    } finally {
      if (mounted) setState(() => _counting = false);
    }
  }

  Future<void> _send() async {
    final problem = _problem;
    if (problem != null) {
      setState(() => _sendError = problem);
      return;
    }
    final push = _push;
    setState(() {
      _counting = true;
      _sendError = null;
      _result = null;
    });
    int n;
    try {
      n = await _api.count(audienceSlug: push.audienceSlug);
    } on AdminException catch (e) {
      if (mounted) {
        setState(() {
          _sendError = e.message;
          _counting = false;
        });
      }
      return;
    }
    if (!mounted) return;
    setState(() {
      _count = n;
      _counting = false;
    });
    if (n == 0) {
      setState(() => _sendError = push.audienceSlug.isEmpty
          ? 'Жоден пристрій ще не отримує сповіщень.'
          : 'За цим тайтлом зараз не стежить жоден пристрій зі сповіщеннями.');
      return;
    }
    final ok = await showAppConfirm(
      context,
      scale: _scale,
      title: 'Надіслати сповіщення?',
      message: '«${push.title.trim()}» отримають ${HikkaAdminPage.devices(n)}. Скасувати надіслане вже не вийде.',
      action: 'Надіслати',
    );
    if (!ok || !mounted) return;
    setState(() => _sending = true);
    try {
      final r = await _api.send(push);
      if (!mounted) return;
      setState(() {
        _result = r;
        _sending = false;
        _count = null;
      });
      // The text goes, so the same message is not sent twice by accident; the type and the title stay
      _title.clear();
      _body.clear();
      unawaited(_loadHistory());
    } on AdminException catch (e) {
      if (mounted) {
        setState(() {
          _sendError = e.message;
          _sending = false;
        });
      }
    }
  }

  // ── Pieces ─────────────────────────────────────────────────────────────────

  Widget _label(String text) => Padding(
        padding: EdgeInsets.only(bottom: 6 * _scale),
        child: Text(text, style: hikkaStyle(12.5 * _scale, color: AppTones.caption, weight: FontWeight.w700)),
      );

  Widget _spinnerLine(String text) => Row(
        children: [
          SizedBox(width: 16 * _scale, height: 16 * _scale, child: CircularProgressIndicator(strokeWidth: 2, color: uiTheme.accentColor)),
          SizedBox(width: 10 * _scale),
          Expanded(child: Text(text, style: hikkaStyle(13 * _scale, color: uiTheme.textMuted))),
        ],
      );

  /// A highlighted note: a result (accent) or an error (red)
  Widget _note(IconData icon, String text, {bool error = false, Key? key}) {
    final scale = _scale;
    final color = error ? AppTones.danger : uiTheme.accentColor;
    return Container(
      key: key,
      padding: EdgeInsets.all(12 * scale),
      decoration: BoxDecoration(
        color: color.withValues(alpha: uiTheme.isLight ? 0.08 : 0.12),
        borderRadius: uiTheme.borderRadius(12 * scale),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18 * scale, color: color),
          SizedBox(width: 10 * scale),
          Expanded(child: Text(text, style: hikkaStyle(13 * scale, color: uiTheme.textPrimary, height: 1.45))),
        ],
      ),
    );
  }

  /// Who the server sees: the name and how many devices get notifications at all
  Widget _access() {
    final scale = _scale;
    if (_checking) return _spinnerLine('Перевіряємо доступ…');
    final error = _accessError;
    if (error != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _note(Symbols.error_rounded, error, error: true),
          SizedBox(height: 12 * scale),
          AppSecondaryButton(scale: scale, label: 'Спробувати ще', icon: Symbols.refresh_rounded, expand: false, onTap: _load),
        ],
      );
    }
    return Row(
      children: [
        LineIconView(LineIcon.shield, size: 20 * scale, color: uiTheme.accentColor),
        SizedBox(width: 10 * scale),
        Expanded(
          child: Text.rich(
            TextSpan(children: [
              TextSpan(text: _who, style: hikkaStyle(13.5 * scale, weight: FontWeight.bold)),
              TextSpan(text: ' · сповіщення отримують ${HikkaAdminPage.devices(_devices)}', style: hikkaStyle(13 * scale, color: uiTheme.textMuted)),
            ]),
          ),
        ),
      ],
    );
  }

  /// How the notification looks on a phone, and what the tap opens
  Widget _preview() {
    final scale = _scale;
    final title = _title.text.trim();
    final body = _body.text.trim();
    final slug = _slugValue;
    final tap = switch (_type) {
      AdminPushType.update => 'Дотик відкриє вікно оновлення',
      _ when slug != null => 'Дотик відкриє тайтл $slug',
      AdminPushType.episode => 'Дотик відкриє тайтл',
      _ => 'Дотик відкриє «Сповіщення» в застосунку',
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          key: const ValueKey('admin-preview'),
          padding: EdgeInsets.fromLTRB(14 * scale, 12 * scale, 14 * scale, 14 * scale),
          decoration: BoxDecoration(
            color: uiTheme.bgElevated,
            borderRadius: uiTheme.borderRadius(18 * scale),
            border: Border.all(color: uiTheme.borderSubtle),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 20 * scale,
                    height: 20 * scale,
                    decoration: BoxDecoration(color: uiTheme.accentColor, shape: BoxShape.circle),
                    alignment: Alignment.center,
                    child: LineIconView(
                      _type == AdminPushType.update ? LineIcon.download : (_type == AdminPushType.episode ? LineIcon.play : LineIcon.megaphone),
                      size: 12 * scale,
                      color: onAccent(uiTheme.accentColor),
                    ),
                  ),
                  SizedBox(width: 8 * scale),
                  Text('Miki Miki · зараз', style: hikkaStyle(11.5 * scale, color: uiTheme.textMuted)),
                ],
              ),
              SizedBox(height: 8 * scale),
              Text(
                title.isEmpty ? 'Заголовок' : title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: hikkaStyle(14 * scale, weight: FontWeight.bold, color: title.isEmpty ? uiTheme.textDarkMuted : uiTheme.textPrimary),
              ),
              SizedBox(height: 3 * scale),
              Text(
                body.isEmpty ? 'Текст сповіщення' : body,
                maxLines: 6,
                overflow: TextOverflow.ellipsis,
                style: hikkaStyle(13 * scale, color: body.isEmpty ? uiTheme.textDarkMuted : uiTheme.textMuted, height: 1.4),
              ),
            ],
          ),
        ),
        SizedBox(height: 6 * scale),
        Text(tap, style: hikkaStyle(12 * scale, color: uiTheme.textMuted)),
      ],
    );
  }

  Widget _form(double pad) {
    final scale = _scale;
    final gap = SizedBox(height: 16 * scale);
    final slug = _slugValue;
    final problem = _sendError;
    final result = _result;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: pad),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 8 * scale,
            runSpacing: 8 * scale,
            children: [
              for (final t in AdminPushType.values)
                HikkaChip(
                  key: ValueKey('admin-type-${t.wire}'),
                  label: t.label,
                  scale: scale,
                  selected: _type == t,
                  onTap: () => setState(() {
                    _type = t;
                    _count = null;
                    _sendError = null;
                  }),
                ),
            ],
          ),
          gap,
          _AdminField(
            key: const ValueKey('admin-title'),
            scale: scale,
            label: 'Заголовок',
            hint: _type == AdminPushType.update ? 'Вийшла версія 1.2' : 'Коротко, про що це',
            controller: _title,
            max: AdminApi.maxTitle,
          ),
          gap,
          _AdminField(
            key: const ValueKey('admin-body'),
            scale: scale,
            label: 'Текст',
            hint: _type == AdminPushType.update ? 'Що нового: торкніться, щоб оновити' : 'Що людина прочитає у сповіщенні',
            controller: _body,
            max: AdminApi.maxBody,
            minLines: 3,
            maxLines: 6,
          ),
          if (_hasTitleField) ...[
            gap,
            _AdminField(
              key: const ValueKey('admin-slug'),
              scale: scale,
              label: _type == AdminPushType.episode ? 'Тайтл' : 'Тайтл (необовʼязково)',
              hint: 'slug або посилання hikka.io/anime/…',
              controller: _slug,
              error: _slugError,
              keyboard: TextInputType.url,
            ),
            gap,
            _label('Кому'),
            Wrap(
              spacing: 8 * scale,
              runSpacing: 8 * scale,
              children: [
                HikkaChip(
                  key: const ValueKey('admin-to-all'),
                  label: 'Усім',
                  scale: scale,
                  selected: !_toFollowers,
                  onTap: () => setState(() {
                    _followers = false;
                    _count = null;
                  }),
                ),
                HikkaChip(
                  key: const ValueKey('admin-to-followers'),
                  label: 'Хто стежить за тайтлом',
                  scale: scale,
                  selected: _toFollowers,
                  onTap: slug == null
                      ? null
                      : () => setState(() {
                            _followers = true;
                            _count = null;
                          }),
                ),
              ],
            ),
            gap,
            _AdminField(
              key: const ValueKey('admin-image'),
              scale: scale,
              label: 'Картинка (необовʼязково)',
              hint: 'https://…',
              controller: _image,
              error: _imageError,
              keyboard: TextInputType.url,
            ),
          ],
          SizedBox(height: 20 * scale),
          _label('Як виглядатиме'),
          _preview(),
          SizedBox(height: 18 * scale),
          if (problem != null) ...[
            _note(Symbols.error_rounded, problem, error: true, key: const ValueKey('admin-error')),
            SizedBox(height: 12 * scale),
          ] else if (result != null) ...[
            _note(
              Symbols.check_circle_rounded,
              result.failed > 0
                  ? 'Надіслано: ${result.sent} з ${result.devices}. Не дійшло ${result.failed} (застосунок видалили чи пристрій давно не заходив).'
                  : 'Надіслано на ${HikkaAdminPage.devices(result.sent)}.',
              key: const ValueKey('admin-result'),
            ),
            SizedBox(height: 12 * scale),
          ],
          Wrap(
            spacing: 18 * scale,
            runSpacing: 10 * scale,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              AppAccentButton(
                key: const ValueKey('admin-send'),
                scale: scale,
                icon: Symbols.send_rounded,
                label: _sending ? 'Надсилаю…' : 'Надіслати',
                onTap: () {
                  if (!_sending && !_counting) unawaited(_send());
                },
              ),
              // How many get it: a quiet link next to the button, the answer in its place
              QuietAction(
                key: const ValueKey('admin-count'),
                scale: scale,
                label: _counting ? 'Рахую…' : (_count == null ? 'Скільки отримають?' : 'Отримають ${HikkaAdminPage.devices(_count!)}'),
                onTap: () {
                  if (!_counting) unawaited(_countDevices());
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _historyRow(AdminLogEntry e, DateTime now, double pad) {
    final scale = _scale;
    final icon = switch (e.type) {
      'update' => LineIcon.download,
      'episode' => LineIcon.play,
      _ => LineIcon.megaphone,
    };
    return Padding(
      padding: EdgeInsets.fromLTRB(pad, 8 * scale, pad, 8 * scale),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40 * scale,
            height: 40 * scale,
            decoration: BoxDecoration(color: AppTones.plate, borderRadius: uiTheme.borderRadius(10 * scale)),
            alignment: Alignment.center,
            child: LineIconView(icon, size: 20 * scale, color: AppTones.rowIcon),
          ),
          SizedBox(width: 12 * scale),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(e.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: hikkaStyle(13.5 * scale, weight: FontWeight.bold)),
                SizedBox(height: 2 * scale),
                Text(e.body, maxLines: 2, overflow: TextOverflow.ellipsis, style: hikkaStyle(12.5 * scale, color: uiTheme.textMuted, height: 1.35)),
                SizedBox(height: 4 * scale),
                Text(HikkaAdminPage.footer(e, now), style: hikkaStyle(11.5 * scale, color: AppTones.caption)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _historyPart(double pad, double inset) {
    final scale = _scale;
    final items = _history;
    final error = _historyError;
    final now = AppClock.now();
    return [
      AppGroupCaption(scale: scale, text: 'Надіслані', inset: inset, top: 26),
      if (error != null)
        Padding(padding: EdgeInsets.symmetric(horizontal: pad), child: _note(Symbols.error_rounded, error, error: true))
      else if (items == null)
        Padding(padding: EdgeInsets.fromLTRB(pad, 6 * scale, pad, 0), child: _spinnerLine('Завантажуємо…'))
      else if (items.isEmpty)
        Padding(
          padding: EdgeInsets.fromLTRB(pad, 6 * scale, pad, 0),
          child: Text('Ще нічого не надсилали з панелі.', style: hikkaStyle(13 * scale, color: uiTheme.textMuted)),
        )
      else
        for (final e in items) _historyRow(e, now, pad),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final scale = _scale;
    final pad = HikkaLayout.sidePad(context, scale);
    final inset = pad + 2 * scale;
    return HikkaPageFrame(
      scale: scale,
      controller: _scroll,
      bottomInset: widget.bottomInset,
      children: [
        Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: hikkaReadableWidth(scale) + pad * 2),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(padding: EdgeInsets.fromLTRB(pad, 4 * scale, pad, 0), child: _access()),
                if (_who.isNotEmpty) ...[
                  AppGroupCaption(scale: scale, text: 'Нове сповіщення', inset: inset, top: 22),
                  _form(pad),
                  ..._historyPart(pad, inset),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// A labelled text field of the panel: the length counter on the right, the accent edge while typing, an error under it
class _AdminField extends StatefulWidget {
  final double scale;
  final String label;
  final String hint;
  final TextEditingController controller;
  final int? max;
  final int minLines;
  final int maxLines;
  final String? error;
  final TextInputType? keyboard;

  const _AdminField({
    super.key,
    required this.scale,
    required this.label,
    required this.hint,
    required this.controller,
    this.max,
    this.minLines = 1,
    this.maxLines = 1,
    this.error,
    this.keyboard,
  });

  @override
  State<_AdminField> createState() => _AdminFieldState();
}

class _AdminFieldState extends State<_AdminField> {
  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(_refresh);
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final scale = widget.scale;
    final max = widget.max;
    final length = widget.controller.text.characters.length;
    final focused = _focus.hasFocus;
    final error = widget.error;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.only(bottom: 6 * scale),
          child: Row(
            children: [
              Expanded(child: Text(widget.label, style: hikkaStyle(12.5 * scale, color: AppTones.caption, weight: FontWeight.w700))),
              if (max != null)
                Text('$length/$max', style: hikkaStyle(11.5 * scale, color: length >= max ? AppTones.danger : uiTheme.textDarkMuted)),
            ],
          ),
        ),
        AppAnimatedContainer(
          duration: AppAnim.fast,
          curve: AppAnim.easeOut,
          padding: EdgeInsets.symmetric(horizontal: 12 * scale),
          decoration: BoxDecoration(
            color: uiTheme.bgElevated,
            borderRadius: uiTheme.borderRadius(12 * scale),
            border: Border.all(color: error != null ? AppTones.danger : (focused ? uiTheme.accentBorder : uiTheme.borderSubtle)),
          ),
          child: TextField(
            controller: widget.controller,
            focusNode: _focus,
            minLines: widget.minLines,
            maxLines: widget.maxLines,
            keyboardType: widget.keyboard ?? (widget.maxLines > 1 ? TextInputType.multiline : TextInputType.text),
            textCapitalization: widget.keyboard == null ? TextCapitalization.sentences : TextCapitalization.none,
            inputFormatters: [if (max != null) LengthLimitingTextInputFormatter(max)],
            cursorColor: uiTheme.accentColor,
            style: hikkaStyle(14 * scale, color: uiTheme.textPrimary, height: 1.4),
            decoration: InputDecoration(
              hintText: widget.hint,
              hintStyle: hikkaStyle(14 * scale, color: uiTheme.textDarkMuted, height: 1.4),
              border: InputBorder.none,
              isDense: true,
              contentPadding: EdgeInsets.symmetric(vertical: 11 * scale),
            ),
          ),
        ),
        if (error != null)
          Padding(
            padding: EdgeInsets.only(top: 6 * scale),
            child: Text(error, style: hikkaStyle(12 * scale, color: AppTones.danger, height: 1.35)),
          ),
      ],
    );
  }
}
