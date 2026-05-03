import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/app_config.dart';
import '../store/admin_store.dart';

int _parseHex(String s) {
  var t = s.trim().toLowerCase();
  if (t.startsWith('0x')) t = t.substring(2);
  return int.tryParse(t, radix: 16) ?? 0xFF0ea5e9;
}

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
    builder: (ctx) => _MalipoPlanBody(store: store, existing: existing),
  );
}

class _MalipoPlanBody extends StatefulWidget {
  const _MalipoPlanBody({required this.store, this.existing});

  final AdminStore store;
  final MalipoPlanDto? existing;

  @override
  State<_MalipoPlanBody> createState() => _MalipoPlanBodyState();
}

class _MalipoPlanBodyState extends State<_MalipoPlanBody> {
  late final TextEditingController _idCtrl;
  late final TextEditingController _labelCtrl;
  late final TextEditingController _priceLinesCtrl;
  late final TextEditingController _amountCtrl;
  late final TextEditingController _periodCtrl;
  late final TextEditingController _accent1Ctrl;
  late final TextEditingController _accent2Ctrl;
  late final TextEditingController _badgeCtrl;
  late final FocusNode _amountFocus;
  bool _popular = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _idCtrl = TextEditingController(text: e?.id ?? '');
    _labelCtrl = TextEditingController(text: e?.label ?? '');
    _priceLinesCtrl = TextEditingController(text: e?.priceLines ?? '');
    _amountCtrl = TextEditingController(text: e?.amount ?? '');
    _periodCtrl = TextEditingController(text: e?.period ?? '');
    _accent1Ctrl = TextEditingController(text: '0x${(e?.accent1 ?? 0xFF0ea5e9).toRadixString(16)}');
    _accent2Ctrl = TextEditingController(text: '0x${(e?.accent2 ?? 0xFF6366f1).toRadixString(16)}');
    _badgeCtrl = TextEditingController(text: e?.badge ?? '');
    _popular = e?.popular ?? false;
    _amountFocus = FocusNode();

    for (final c in [_accent1Ctrl, _accent2Ctrl]) {
      c.addListener(() => setState(() {}));
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.existing != null && _amountFocus.canRequestFocus) {
        _amountFocus.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    _idCtrl.dispose();
    _labelCtrl.dispose();
    _priceLinesCtrl.dispose();
    _amountCtrl.dispose();
    _periodCtrl.dispose();
    _accent1Ctrl.dispose();
    _accent2Ctrl.dispose();
    _badgeCtrl.dispose();
    _amountFocus.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final id = _idCtrl.text.trim();
    if (id.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Weka kitambulisho cha mpango.')),
        );
      }
      return;
    }
    HapticFeedback.mediumImpact();
    final dto = MalipoPlanDto(
      id: id,
      label: _labelCtrl.text.trim(),
      priceLines: _priceLinesCtrl.text.trim(),
      amount: _amountCtrl.text.trim(),
      period: _periodCtrl.text.trim(),
      popular: _popular,
      accent1: _parseHex(_accent1Ctrl.text),
      accent2: _parseHex(_accent2Ctrl.text),
      badge: _badgeCtrl.text.trim(),
    );
    await widget.store.upsertMalipo(dto);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bottom = MediaQuery.paddingOf(context).bottom;
    final isNew = widget.existing == null;
    final c1 = Color(_parseHex(_accent1Ctrl.text));
    final c2 = Color(_parseHex(_accent2Ctrl.text));

    final saving = context.watch<AdminStore>().syncingToServer;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.92,
        ),
        decoration: BoxDecoration(
          color: const Color(0xFF0e1118),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.45),
              blurRadius: 28,
              offset: const Offset(0, -8),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(99),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 16, 8),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      gradient: LinearGradient(
                        colors: [
                          cs.primary.withValues(alpha: 0.35),
                          cs.tertiary.withValues(alpha: 0.22),
                        ],
                      ),
                    ),
                    child: Icon(
                      isNew ? Icons.add_card_rounded : Icons.payments_rounded,
                      color: Colors.white,
                      size: 26,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isNew ? 'Mpango mpya wa Malipo' : 'Hariri mpango wa Malipo',
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.w900,
                                letterSpacing: -0.3,
                              ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Weka bei, maandishi, na rangi za kadi katika programu.',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.5),
                            fontSize: 12.5,
                            height: 1.35,
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
                padding: EdgeInsets.fromLTRB(20, 0, 20, 16 + bottom),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _MalipoSectionLabel(icon: Icons.price_change_rounded, title: 'Bei na maonyesho'),
                    const SizedBox(height: 12),
                    TextField(spellCheckConfiguration: SpellCheckConfiguration.disabled(),
                      controller: _amountCtrl,
                      focusNode: _amountFocus,
                      decoration: const InputDecoration(
                        labelText: 'Kiasi kinachoonekana',
                        hintText: 'TSh 5,000',
                        prefixIcon: Icon(Icons.payments_rounded),
                      ),
                      textInputAction: TextInputAction.next,
                    ),
                    const SizedBox(height: 16),
                    TextField(spellCheckConfiguration: SpellCheckConfiguration.disabled(),
                      controller: _priceLinesCtrl,
                      minLines: 2,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        labelText: 'Mistari ya bei (mkusanyiko)',
                        hintText: 'TSh kwenye mstari wa kwanza, kiasi mstari wa pili',
                        alignLabelWithHint: true,
                        prefixIcon: Icon(Icons.view_agenda_rounded),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(spellCheckConfiguration: SpellCheckConfiguration.disabled(),
                      controller: _periodCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Kipindi',
                        hintText: 'Wiki Moja · Mwezi Moja',
                        prefixIcon: Icon(Icons.schedule_rounded),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(spellCheckConfiguration: SpellCheckConfiguration.disabled(),
                      controller: _badgeCtrl,
                      textCapitalization: TextCapitalization.characters,
                      decoration: const InputDecoration(
                        labelText: 'Beji ya bei (hiari)',
                        hintText: 'MPYA · BORA · PUNGUZO',
                        prefixIcon: Icon(Icons.label_outline_rounded),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Inaonekana juu ya bei kwenye programu. Acha tupu kama hutaki beji.',
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 11.5, height: 1.35),
                    ),
                    const SizedBox(height: 24),
                    _MalipoSectionLabel(icon: Icons.layers_rounded, title: 'Taarifa za mpango'),
                    const SizedBox(height: 12),
                    TextField(spellCheckConfiguration: SpellCheckConfiguration.disabled(),
                      controller: _idCtrl,
                      enabled: isNew,
                      decoration: const InputDecoration(
                        labelText: 'Kitambulisho',
                        hintText: 'mfano: weekly',
                        prefixIcon: Icon(Icons.tag_rounded),
                      ),
                      textCapitalization: TextCapitalization.none,
                    ),
                    const SizedBox(height: 16),
                    TextField(spellCheckConfiguration: SpellCheckConfiguration.disabled(),
                      controller: _labelCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Jina fupi',
                        hintText: 'Jina linaonekana kwenye kadi',
                        prefixIcon: Icon(Icons.label_rounded),
                      ),
                    ),
                    const SizedBox(height: 16),
                    _PopularToggleCard(
                      value: _popular,
                      onChanged: (v) => setState(() => _popular = v),
                    ),
                    const SizedBox(height: 24),
                    _MalipoSectionLabel(icon: Icons.palette_rounded, title: 'Rangi za msingi'),
                    const SizedBox(height: 8),
                    Text(
                      'Hex (mfano 0xFF0ea5e9). Hakuna uwezekano wa rangi mbaya — tutatumia chaguo-msingi.',
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.45), fontSize: 12, height: 1.35),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        _ColorDot(color: c1),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextField(spellCheckConfiguration: SpellCheckConfiguration.disabled(),
                            controller: _accent1Ctrl,
                            decoration: const InputDecoration(
                              labelText: 'Rangi ya kwanza',
                              hintText: '0xFF0ea5e9',
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        _ColorDot(color: c2),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextField(spellCheckConfiguration: SpellCheckConfiguration.disabled(),
                            controller: _accent2Ctrl,
                            decoration: const InputDecoration(
                              labelText: 'Rangi ya pili',
                              hintText: '0xFF6366f1',
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 28),
                    FilledButton(
                      onPressed: saving ? null : _save,
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      child: saving
                          ? const SizedBox(
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : Text(
                              isNew ? 'Ongeza mpango' : 'Hifadhi mabadiliko',
                              style: const TextStyle(fontWeight: FontWeight.w800),
                            ),
                    ),
                    const SizedBox(height: 8),
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

class _ColorDot extends StatelessWidget {
  const _ColorDot({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
        border: Border.all(color: Colors.white.withValues(alpha: 0.25), width: 2),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.45),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
    );
  }
}

class _PopularToggleCard extends StatelessWidget {
  const _PopularToggleCard({
    required this.value,
    required this.onChanged,
  });

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: const Color(0xFF161c28),
        border: Border.all(
          color: value ? cs.tertiary.withValues(alpha: 0.45) : Colors.white.withValues(alpha: 0.08),
          width: value ? 1.5 : 1,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: cs.tertiary.withValues(alpha: value ? 0.22 : 0.08),
            ),
            child: Icon(Icons.star_rounded, color: value ? cs.tertiary : Colors.white54, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Mpango maarufu',
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, letterSpacing: 0.2),
                ),
                const SizedBox(height: 2),
                Text(
                  value
                      ? 'Utaangaziwa kama chaguo la kupendeza zaidi'
                      : 'Zima kuonyesha kama kawaida',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 12.5),
                ),
              ],
            ),
          ),
          Switch.adaptive(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}

class _MalipoSectionLabel extends StatelessWidget {
  const _MalipoSectionLabel({required this.icon, required this.title});

  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(icon, size: 18, color: cs.primary),
        const SizedBox(width: 8),
        Text(
          title.toUpperCase(),
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.2,
            color: cs.primary.withValues(alpha: 0.95),
          ),
        ),
      ],
    );
  }
}
