import 'dart:math' show Random;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/app_config.dart';
import '../store/admin_store.dart';

int? _digitsAsInt(String s) {
  final digits = s.replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.isEmpty) return null;
  return int.tryParse(digits);
}

String _commaInt(int v) {
  final s = v.toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
    b.write(s[i]);
  }
  return b.toString();
}

const _kAccent1 = 0xFF0ea5e9;
const _kAccent2 = 0xFF6366f1;

/// Bottom sheet ya kuhariri / kuongeza mpango wa Malipo — lugha ya Kiswahili.
Future<void> showMalipoPlanSheet(
  BuildContext context,
  AdminStore store,
  MalipoPlanDto? existing,
) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => _MalipoPlanBody(
      key: ValueKey(existing?.id ?? 'malipo_new'),
      store: store,
      existing: existing,
    ),
  );
}

class _MalipoPlanBody extends StatefulWidget {
  const _MalipoPlanBody({super.key, required this.store, this.existing});

  final AdminStore store;
  final MalipoPlanDto? existing;

  @override
  State<_MalipoPlanBody> createState() => _MalipoPlanBodyState();
}

class _MalipoPlanBodyState extends State<_MalipoPlanBody> {
  /// Nullable + lazy init so Flutter web hot reload cannot leave fields as JS `undefined`
  /// (which throws on `.text`).
  TextEditingController? _priceCtrl;
  TextEditingController? _periodCtrl;
  TextEditingController? _badgeCtrl;
  FocusNode? _priceFocus;
  bool _requestedEditFocus = false;

  void _ensureControllers() {
    final e = widget.existing;
    final existingDigits = e == null ? '' : (_digitsAsInt(e.amount)?.toString() ?? '');
    _priceCtrl ??= TextEditingController(text: existingDigits);
    _periodCtrl ??= TextEditingController(text: e?.period ?? '');
    _badgeCtrl ??= TextEditingController(text: e?.badge ?? '');
    _priceFocus ??= FocusNode();

    if (!_requestedEditFocus && widget.existing != null) {
      _requestedEditFocus = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final n = _priceFocus;
        if (n != null && n.canRequestFocus) n.requestFocus();
      });
    }
  }

  @override
  void initState() {
    super.initState();
    _ensureControllers();
  }

  @override
  void dispose() {
    _priceCtrl?.dispose();
    _periodCtrl?.dispose();
    _badgeCtrl?.dispose();
    _priceFocus?.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    _ensureControllers();
    final price = _priceCtrl!;
    final periodC = _periodCtrl!;
    final badgeC = _badgeCtrl!;
    final tzs = _digitsAsInt(price.text);
    if (tzs == null || tzs < 1) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Weka kiasi halali cha TZS (nambari tu).')),
        );
      }
      return;
    }
    final period = periodC.text.trim();
    if (period.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Weka kipindi cha mpango.')),
        );
      }
      return;
    }

    HapticFeedback.mediumImpact();

    final id = widget.existing?.id ??
        'malipo_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(8999) + 1000}';

    final comma = _commaInt(tzs);
    final amountDisplay = 'TSh $comma/=';
    final priceLines = 'TSh\n$comma';

    final dto = MalipoPlanDto(
      id: id,
      label: period,
      priceLines: priceLines,
      amount: amountDisplay,
      period: period,
      popular: widget.existing?.popular ?? false,
      accent1: widget.existing?.accent1 ?? _kAccent1,
      accent2: widget.existing?.accent2 ?? _kAccent2,
      badge: badgeC.text.trim(),
    );

    await widget.store.upsertMalipo(dto);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    _ensureControllers();
    final cs = Theme.of(context).colorScheme;
    final bottom = MediaQuery.paddingOf(context).bottom;
    final isNew = widget.existing == null;
    final inset = MediaQuery.viewInsetsOf(context).bottom;

    final saving = context.watch<AdminStore>().syncingToServer;
    return Padding(
      padding: EdgeInsets.only(bottom: inset),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.88,
        ),
        decoration: BoxDecoration(
          color: const Color(0xFF0a0d14),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.5),
              blurRadius: 32,
              offset: const Offset(0, -10),
            ),
          ],
        ),
        child: Column(
          children: [
            const SizedBox(height: 10),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(99),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 20, 12, 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(18),
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          cs.primary.withValues(alpha: 0.5),
                          cs.tertiary.withValues(alpha: 0.25),
                        ],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: cs.primary.withValues(alpha: 0.25),
                          blurRadius: 16,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Icon(
                        isNew ? Icons.add_card_rounded : Icons.edit_calendar_rounded,
                        color: Colors.white,
                        size: 26,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isNew ? 'Mpango mpya wa Malipo' : 'Hariri mpango wa Malipo',
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.w900,
                                letterSpacing: -0.4,
                              ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Bei kwa TZS, kipindi kinachoonekana kwenye kadi, na beji ya hiari.',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.48),
                            fontSize: 13,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                    style: IconButton.styleFrom(backgroundColor: Colors.white.withValues(alpha: 0.06)),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(22, 8, 22, 20 + bottom),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'TAARIFA',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 2,
                        color: cs.primary.withValues(alpha: 0.9),
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      spellCheckConfiguration: SpellCheckConfiguration.disabled(),
                      controller: _priceCtrl!,
                      focusNode: _priceFocus!,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: InputDecoration(
                        labelText: 'Bei (TZS)',
                        hintText: '5000',
                        prefixIcon: const Icon(Icons.currency_exchange_rounded),
                        suffixText: 'TZS',
                        suffixStyle: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: Colors.white.withValues(alpha: 0.35),
                        ),
                        filled: true,
                        fillColor: const Color(0xFF121722),
                      ),
                      textInputAction: TextInputAction.next,
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, letterSpacing: 0.2),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Mfano 5000 → TSh 5,000/= kwenye programu.',
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.38), fontSize: 11.5, height: 1.35),
                    ),
                    const SizedBox(height: 20),
                    TextField(
                      spellCheckConfiguration: SpellCheckConfiguration.disabled(),
                      controller: _periodCtrl!,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: const InputDecoration(
                        labelText: 'Kipindi',
                        hintText: 'Wiki 1 · Mwezi 1',
                        prefixIcon: Icon(Icons.schedule_rounded),
                        filled: true,
                        fillColor: Color(0xFF121722),
                      ),
                      textInputAction: TextInputAction.next,
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                    ),
                    const SizedBox(height: 20),
                    TextField(
                      spellCheckConfiguration: SpellCheckConfiguration.disabled(),
                      controller: _badgeCtrl!,
                      textCapitalization: TextCapitalization.characters,
                      decoration: const InputDecoration(
                        labelText: 'Beji (hiari)',
                        hintText: 'BORA · MPYA',
                        prefixIcon: Icon(Icons.label_outline_rounded),
                        filled: true,
                        fillColor: Color(0xFF121722),
                      ),
                      style: const TextStyle(fontWeight: FontWeight.w800, letterSpacing: 0.6),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Inaonekana juu ya kadi ukiacha neno. Acha tupu kuificha.',
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.38), fontSize: 11.5, height: 1.35),
                    ),
                    if (!isNew && widget.existing != null) ...[
                      const SizedBox(height: 18),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          color: Colors.white.withValues(alpha: 0.04),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.fingerprint_rounded, size: 18, color: cs.tertiary.withValues(alpha: 0.85)),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'Kitambulisho: ${widget.existing!.id}',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white.withValues(alpha: 0.45),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 28),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(18),
                        gradient: LinearGradient(
                          colors: [
                            cs.primary,
                            Color.lerp(cs.primary, cs.tertiary, 0.35)!,
                          ],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: cs.primary.withValues(alpha: 0.35),
                            blurRadius: 20,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      child: FilledButton(
                        onPressed: saving ? null : _save,
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          backgroundColor: Colors.transparent,
                          shadowColor: Colors.transparent,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                        ),
                        child: saving
                            ? const SizedBox(
                                height: 22,
                                width: 22,
                                child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white),
                              )
                            : Text(
                                isNew ? 'Hifadhi mpango' : 'Hifadhi mabadiliko',
                                style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, letterSpacing: 0.3),
                              ),
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
