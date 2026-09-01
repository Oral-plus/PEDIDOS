import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../utils/app_assets.dart';


const Color _ink = Color(0xFF0F172A);
const Color _inkSoft = Color(0xFF1E293B);
const Color _gray = Color(0xFF64748B);
const Color _grayLight = Color(0xFF94A3B8);
const Color _line = Color(0xFFE2E8F0);

Future<T?> showAppDialog<T>(
  BuildContext context, {
  required Widget child,
  bool barrierDismissible = true,
}) {
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    barrierLabel: 'dialog',
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 320),
    pageBuilder: (_, __, ___) => child,
    transitionBuilder: (ctx, anim, __, c) {
      final t = Curves.easeOutCubic.transform(anim.value);
      return Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              onTap: barrierDismissible ? () => Navigator.of(ctx).pop() : null,
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 10 * t, sigmaY: 10 * t),
                child: Container(color: Colors.black.withOpacity(0.34 * t)),
              ),
            ),
          ),
          Center(
            child: Opacity(
              opacity: t,
              child: Transform.translate(
                offset: Offset(0, (1 - t) * 22),
                child: Transform.scale(scale: 0.95 + 0.05 * t, child: c),
              ),
            ),
          ),
        ],
      );
    },
  );
}

class AppDialogShell extends StatelessWidget {
  final IconData? icon;
  final String title;
  final Widget content;
  final List<Widget> actions;

  final Color? accent;

  const AppDialogShell({
    super.key,
    this.icon,
    this.accent,
    required this.title,
    required this.content,
    required this.actions,
  });

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 380),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(26),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.86),
                borderRadius: BorderRadius.circular(26),
                border: Border.all(color: Colors.white.withOpacity(0.7), width: 1),
                boxShadow: [
                  BoxShadow(color: Colors.black.withOpacity(0.22), blurRadius: 34, offset: const Offset(0, 14)),
                ],
              ),
              child: Material(
                type: MaterialType.transparency,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 24, 20, 2),
                      child: Center(child: AppAssets.logoImage(height: 46)),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(26, 16, 26, 6),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (icon != null) ...[
                            Container(
                              width: 58,
                              height: 58,
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: [_inkSoft, _ink],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(color: _ink.withOpacity(0.28), blurRadius: 16, offset: const Offset(0, 6)),
                                ],
                              ),
                              child: Icon(icon, color: Colors.white, size: 28),
                            ),
                            const SizedBox(height: 16),
                          ],
                          Text(
                            title,
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: _ink, fontSize: 19, fontWeight: FontWeight.w800, letterSpacing: -0.2),
                          ),
                          const SizedBox(height: 10),
                          content,
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(22, 10, 22, 22),
                      child: Row(children: actions),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

Widget appDialogCancel(BuildContext context, {String text = 'Cancelar'}) {
  return Expanded(
    child: SizedBox(
      height: 50,
      child: OutlinedButton(
        onPressed: () => Navigator.of(context).pop(),
        style: OutlinedButton.styleFrom(
          foregroundColor: _gray,
          backgroundColor: Colors.white.withOpacity(0.5),
          side: const BorderSide(color: _line),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        ),
        child: Text(text, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
      ),
    ),
  );
}

Widget appDialogAction(
  BuildContext context, {
  required String text,
  Color? color,
  required VoidCallback? onPressed,
}) {
  final habilitado = onPressed != null;
  return Expanded(
    child: SizedBox(
      height: 50,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(15),
          onTap: onPressed,
          child: Ink(
            decoration: BoxDecoration(
              gradient: habilitado ? const LinearGradient(colors: [_inkSoft, _ink]) : null,
              color: habilitado ? null : _line,
              borderRadius: BorderRadius.circular(15),
            ),
            child: Center(
              child: Text(text,
                  style: TextStyle(
                    color: habilitado ? Colors.white : _grayLight,
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  )),
            ),
          ),
        ),
      ),
    ),
  );
}

Future<bool> showAppConfirm(
  BuildContext context, {
  required String title,
  required String message,
  String confirmText = 'Aceptar',
  String cancelText = 'Cancelar',
  IconData? icon,
  Color? accent,
  bool danger = false,
}) async {
  final res = await showAppDialog<bool>(
    context,
    child: AppDialogShell(
      icon: icon ?? (danger ? Icons.warning_amber_rounded : Icons.help_outline_rounded),
      title: title,
      content: Text(
        message,
        textAlign: TextAlign.center,
        style: const TextStyle(color: _gray, fontSize: 14.5, height: 1.4, fontWeight: FontWeight.w500),
      ),
      actions: [
        appDialogCancel(context, text: cancelText),
        const SizedBox(width: 12),
        appDialogAction(
          context,
          text: confirmText,
          onPressed: () {
            HapticFeedback.mediumImpact();
            Navigator.of(context).pop(true);
          },
        ),
      ],
    ),
  );
  return res ?? false;
}

Future<String?> showAppInput(
  BuildContext context, {
  required String title,
  String? subtitle,
  String hint = '',
  String initialValue = '',
  IconData? icon,
  Color? accent,
  String confirmText = 'Guardar',
  TextInputType keyboardType = TextInputType.text,
  int minLength = 1,
  bool numeric = false,
}) {
  return showAppDialog<String>(
    context,
    child: _AppInputDialog(
      title: title,
      subtitle: subtitle,
      hint: hint,
      initialValue: initialValue,
      icon: icon,
      confirmText: confirmText,
      keyboardType: keyboardType,
      minLength: minLength,
      numeric: numeric,
    ),
  );
}

class _AppInputDialog extends StatefulWidget {
  final String title;
  final String? subtitle;
  final String hint;
  final String initialValue;
  final IconData? icon;
  final String confirmText;
  final TextInputType keyboardType;
  final int minLength;
  final bool numeric;

  const _AppInputDialog({
    required this.title,
    this.subtitle,
    required this.hint,
    required this.initialValue,
    this.icon,
    required this.confirmText,
    required this.keyboardType,
    required this.minLength,
    required this.numeric,
  });

  @override
  State<_AppInputDialog> createState() => _AppInputDialogState();
}

class _AppInputDialogState extends State<_AppInputDialog> {
  late final TextEditingController _ctrl;
  bool _valido = false;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.initialValue);
    _valido = _ctrl.text.trim().length >= widget.minLength;
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppDialogShell(
      icon: widget.icon,
      title: widget.title,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.subtitle != null) ...[
            Text(widget.subtitle!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: _gray, fontSize: 13.5, height: 1.35, fontWeight: FontWeight.w500)),
            const SizedBox(height: 14),
          ],
          TextField(
            controller: _ctrl,
            autofocus: true,
            keyboardType: widget.keyboardType,
            textAlign: widget.numeric ? TextAlign.center : TextAlign.start,
            textCapitalization: widget.numeric ? TextCapitalization.none : TextCapitalization.sentences,
            maxLines: widget.numeric ? 1 : 2,
            minLines: 1,
            style: TextStyle(
              fontSize: widget.numeric ? 24 : 15,
              fontWeight: widget.numeric ? FontWeight.w800 : FontWeight.w600,
              color: _ink,
            ),
            onChanged: (v) => setState(() => _valido = v.trim().length >= widget.minLength),
            onSubmitted: (_) {
              if (_valido) Navigator.of(context).pop(_ctrl.text.trim());
            },
            decoration: InputDecoration(
              hintText: widget.hint,
              hintStyle: const TextStyle(color: _grayLight, fontSize: 14),
              filled: true,
              fillColor: Colors.white.withOpacity(0.7),
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: const BorderSide(color: _line)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: const BorderSide(color: _line)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: const BorderSide(color: _ink, width: 1.6)),
            ),
          ),
        ],
      ),
      actions: [
        appDialogCancel(context),
        const SizedBox(width: 12),
        appDialogAction(
          context,
          text: widget.confirmText,
          onPressed: _valido
              ? () {
                  HapticFeedback.selectionClick();
                  Navigator.of(context).pop(_ctrl.text.trim());
                }
              : null,
        ),
      ],
    );
  }
}
