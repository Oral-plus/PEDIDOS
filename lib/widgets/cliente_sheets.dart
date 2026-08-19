import 'package:flutter/material.dart';
import '../services/api_easy_service.dart';
import '../utils/theme.dart';

// Paleta monocromática (blanco / negro / gris) compartida por los sheets.
const Color _mInk = Color(0xFF1F2937); // negro-gris principal
const Color _mGray = Color(0xFF6B7280); // gris medio

/// Reusable bottom-sheet wrapper for client-related actions.
class SheetWrapper extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color color;
  final Widget child;

  const SheetWrapper({
    super.key,
    required this.title,
    required this.icon,
    required this.color,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final maxH = media.size.height * 0.85;
    return SafeArea(
      top: false,
      child: Container(
        constraints: BoxConstraints(maxHeight: maxH),
        decoration: BoxDecoration(
          color: AppTheme.backgroundColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 10),
          Container(
            width: 44, height: 5,
            decoration: BoxDecoration(
              color: AppTheme.borderColor,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 10),
            child: Row(children: [
              Container(
                width: 40, height: 40,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(title,
                    style: TextStyle(color: AppTheme.darkBlue, fontSize: 18, fontWeight: FontWeight.w800)),
              ),
              IconButton(
                onPressed: () => Navigator.of(context).maybePop(),
                icon: const Icon(Icons.close_rounded),
                color: AppTheme.textSecondary,
              ),
            ]),
          ),
          Flexible(child: child),
        ]),
      ),
    );
  }
}

/// Cartera (open invoices + balance) bottom sheet.
class CarteraSheet extends StatefulWidget {
  final String codigo;
  final ApiEasyService api;
  final Map<String, dynamic>? initialData;
  final Color color;

  const CarteraSheet({
    super.key,
    required this.codigo,
    required this.api,
    required this.initialData,
    required this.color,
  });

  @override
  State<CarteraSheet> createState() => _CarteraSheetState();
}

class _CarteraSheetState extends State<CarteraSheet> {
  Map<String, dynamic>? _data;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _data = widget.initialData;
    if (_data == null) _cargar();
  }

  Future<void> _cargar() async {
    setState(() => _loading = true);
    final res = await widget.api.getCarteraCliente(widget.codigo);
    if (mounted) setState(() { _data = res; _loading = false; });
  }

  String _formatMoney(dynamic v) {
    final n = (double.tryParse(v.toString()) ?? 0);
    final parts = n.toStringAsFixed(0).split('');
    final buffer = StringBuffer();
    int count = 0;
    for (int i = parts.length - 1; i >= 0; i--) {
      buffer.write(parts[i]); count++;
      if (count % 3 == 0 && i > 0 && parts[i] != '-') buffer.write('.');
    }
    return '\$${buffer.toString().split('').reversed.join()}';
  }

  String _formatDate(dynamic v) {
    if (v == null) return '—';
    try {
      final d = DateTime.parse(v.toString()).toLocal();
      return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
    } catch (_) { return v.toString().split('T').first; }
  }

  @override
  Widget build(BuildContext context) {
    final d = _data;
    final facturas = (d?['facturas'] as List<dynamic>?) ?? [];
    final balance = d?['balance'] ?? 0;
    final saldo = d?['saldoFacturas'] ?? 0;
    final totalAbiertas = d?['totalFacturasAbiertas'] ?? 0;
    final vencidas = d?['facturasVencidas'] ?? 0;

    return SheetWrapper(
      title: 'Cartera',
      icon: Icons.account_balance_wallet_rounded,
      color: widget.color,
      child: _loading
          ? const Center(child: Padding(padding: EdgeInsets.all(40), child: CircularProgressIndicator()))
          : (d == null
              ? Padding(
                  padding: const EdgeInsets.all(40),
                  child: Column(children: [
                    Icon(Icons.error_outline_rounded, color: AppTheme.textSecondary, size: 40),
                    const SizedBox(height: 10),
                    Text('No se pudo cargar la cartera',
                        style: TextStyle(color: AppTheme.textSecondary, fontWeight: FontWeight.w500)),
                    const SizedBox(height: 12),
                    ElevatedButton(
                      onPressed: _cargar,
                      style: ElevatedButton.styleFrom(backgroundColor: _mInk, foregroundColor: Colors.white),
                      child: const Text('Reintentar'),
                    ),
                  ]),
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Expanded(child: _stat('Saldo SAP', _formatMoney(balance), _mInk, Icons.account_balance_rounded)),
                      const SizedBox(width: 10),
                      Expanded(child: _stat('Saldo facturas', _formatMoney(saldo), _mGray, Icons.receipt_long_rounded)),
                    ]),
                    const SizedBox(height: 10),
                    Row(children: [
                      Expanded(child: _stat('Abiertas', '$totalAbiertas', _mInk, Icons.folder_open_rounded)),
                      const SizedBox(width: 10),
                      Expanded(child: _stat('Vencidas', '$vencidas',
                          vencidas is int && vencidas > 0 ? _mInk : _mGray,
                          Icons.warning_amber_rounded)),
                    ]),
                    const SizedBox(height: 18),
                    Text('Facturas pendientes',
                        style: TextStyle(color: AppTheme.darkBlue, fontWeight: FontWeight.w800, fontSize: 15)),
                    const SizedBox(height: 10),
                    if (facturas.isEmpty)
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: AppTheme.borderColor),
                        ),
                        child: Row(children: [
                          Icon(Icons.check_circle_rounded, color: _mInk),
                          const SizedBox(width: 10),
                          Expanded(child: Text('Sin facturas pendientes',
                              style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w600))),
                        ]),
                      )
                    else
                      ...facturas.map((raw) {
                        final f = Map<String, dynamic>.from(raw as Map);
                        final venc = f['vencida'] == true;
                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: venc ? _mInk.withOpacity(0.3) : AppTheme.borderColor,
                            ),
                          ),
                          child: Row(children: [
                            Container(
                              width: 38, height: 38,
                              decoration: BoxDecoration(
                                color: (venc ? _mInk : _mGray).withOpacity(0.1),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(
                                venc ? Icons.warning_amber_rounded : Icons.receipt_rounded,
                                color: venc ? _mInk : _mGray,
                                size: 18,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text('#${f['numero'] ?? '—'}',
                                  style: TextStyle(color: AppTheme.darkBlue, fontWeight: FontWeight.w700, fontSize: 14)),
                              const SizedBox(height: 2),
                              Text('Vence: ${_formatDate(f['vencimiento'])}',
                                  style: TextStyle(
                                    color: venc ? _mInk : AppTheme.textSecondary,
                                    fontWeight: FontWeight.w500, fontSize: 12,
                                  )),
                            ])),
                            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                              Text(_formatMoney(f['saldo']),
                                  style: TextStyle(color: AppTheme.darkBlue, fontWeight: FontWeight.w800, fontSize: 14)),
                              const SizedBox(height: 2),
                              Text('Total: ${_formatMoney(f['total'])}',
                                  style: TextStyle(color: AppTheme.textSecondary, fontSize: 11)),
                            ]),
                          ]),
                        );
                      }),
                  ]),
                )),
    );
  }

  Widget _stat(String label, String value, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withOpacity(0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.12)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, color: color.withOpacity(0.7), size: 14),
          const SizedBox(width: 6),
          Expanded(
            child: Text(label.toUpperCase(),
                style: TextStyle(color: color.withOpacity(0.7), fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.6),
                maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
        ]),
        const SizedBox(height: 6),
        Text(value,
            style: TextStyle(color: color, fontSize: 16, fontWeight: FontWeight.w800),
            maxLines: 1, overflow: TextOverflow.ellipsis),
      ]),
    );
  }
}

/// Comments + SAP Free_Text bottom sheet.
class ComentariosSheet extends StatefulWidget {
  final String codigo;
  final String nombreCliente;
  final ApiEasyService api;
  final Color color;

  const ComentariosSheet({
    super.key,
    required this.codigo,
    required this.nombreCliente,
    required this.api,
    required this.color,
  });

  @override
  State<ComentariosSheet> createState() => _ComentariosSheetState();
}

class _ComentariosSheetState extends State<ComentariosSheet> {
  final TextEditingController _ctrl = TextEditingController();
  List<Map<String, dynamic>> _items = [];
  String _freeText = '';
  bool _loading = true;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    setState(() => _loading = true);
    final data = await widget.api.getComentariosCliente(widget.codigo);
    if (mounted) {
      setState(() {
        _items = (data['comentarios'] as List).cast<Map<String, dynamic>>();
        _freeText = (data['freeText'] ?? '').toString();
        _loading = false;
      });
    }
  }

  Future<void> _enviar() async {
    final txt = _ctrl.text.trim();
    if (txt.isEmpty || _sending) return;
    setState(() => _sending = true);
    final nuevo = await widget.api.crearComentarioCliente(widget.codigo, txt);
    if (!mounted) return;
    if (nuevo != null) {
      _ctrl.clear();
      setState(() {
        _items = [nuevo, ..._items];
        if (nuevo['freeText'] != null) _freeText = nuevo['freeText'].toString();
        _sending = false;
      });
    } else {
      setState(() => _sending = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo guardar el comentario')),
      );
    }
  }

  Future<void> _editarFreeText() async {
    final editCtrl = TextEditingController(text: _freeText);
    final guardado = await showDialog<String?>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Texto SAP (Free_Text)', style: TextStyle(fontWeight: FontWeight.w700)),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 320, minWidth: 320),
          child: TextField(
            controller: editCtrl,
            minLines: 6, maxLines: 12, maxLength: 2000,
            decoration: InputDecoration(
              hintText: 'Editar texto que se guarda en OCRD.Free_Text...',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, null), child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, editCtrl.text),
            style: ElevatedButton.styleFrom(
              backgroundColor: _mInk, foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );

    if (guardado == null || !mounted) return;
    final res = await widget.api.actualizarFreeTextCliente(widget.codigo, guardado);
    if (!mounted) return;
    if (res != null) {
      setState(() => _freeText = res);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Texto SAP actualizado')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo actualizar el texto SAP')),
      );
    }
  }

  String _formatFecha(dynamic v) {
    if (v == null) return '';
    try {
      final d = DateTime.parse(v.toString()).toLocal();
      final hh = d.hour.toString().padLeft(2, '0');
      final mm = d.minute.toString().padLeft(2, '0');
      return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year} $hh:$mm';
    } catch (_) { return v.toString(); }
  }

  Widget _buildFreeTextCard() {
    final vacio = _freeText.trim().isEmpty;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.borderColor),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10, offset: const Offset(0, 3)),
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 32, height: 32,
            decoration: BoxDecoration(
              color: _mInk.withOpacity(0.12),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(Icons.sticky_note_2_rounded, color: _mInk, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Texto SAP (OCRD.Free_Text)',
                  style: TextStyle(color: AppTheme.darkBlue, fontSize: 13, fontWeight: FontWeight.w800)),
              Text('Historial guardado en SAP',
                  style: TextStyle(color: AppTheme.textSecondary, fontSize: 11)),
            ]),
          ),
          TextButton.icon(
            onPressed: _editarFreeText,
            icon: Icon(Icons.edit_rounded, size: 16, color: _mInk),
            label: Text('Editar',
                style: TextStyle(color: _mInk, fontWeight: FontWeight.w700, fontSize: 12)),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              minimumSize: const Size(0, 30),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              backgroundColor: _mInk.withOpacity(0.08),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ]),
        const SizedBox(height: 10),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppTheme.backgroundColor,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppTheme.borderColor.withOpacity(0.6)),
          ),
          child: Text(
            vacio ? 'Sin texto en SAP. Toca "Editar" para agregar.' : _freeText,
            style: TextStyle(
              color: vacio ? AppTheme.textSecondary : AppTheme.textPrimary,
              fontStyle: vacio ? FontStyle.italic : FontStyle.normal,
              fontSize: 13, height: 1.4,
            ),
          ),
        ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SheetWrapper(
        title: 'Comentarios',
        icon: Icons.chat_bubble_rounded,
        color: widget.color,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Expanded(
            child: _loading
                ? const Center(child: Padding(padding: EdgeInsets.all(30), child: CircularProgressIndicator()))
                : ListView(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                    children: [
                      _buildFreeTextCard(),
                      const SizedBox(height: 14),
                      Row(children: [
                        Text('Historial de comentarios',
                            style: TextStyle(color: AppTheme.darkBlue, fontWeight: FontWeight.w800, fontSize: 13)),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: widget.color.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text('${_items.length}',
                              style: TextStyle(color: widget.color, fontSize: 11, fontWeight: FontWeight.w700)),
                        ),
                      ]),
                      const SizedBox(height: 8),
                      if (_items.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 20),
                          child: Column(children: [
                            Icon(Icons.chat_bubble_outline_rounded, size: 36,
                                color: AppTheme.textSecondary.withOpacity(0.5)),
                            const SizedBox(height: 8),
                            Text('Sin comentarios aún',
                                style: TextStyle(color: AppTheme.textSecondary, fontWeight: FontWeight.w500)),
                          ]),
                        )
                      else
                        ..._items.map((c) {
                          final autor = (c['usuarioNombre'] ?? '').toString();
                          return Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: AppTheme.borderColor),
                            ),
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Row(children: [
                                Container(
                                  width: 32, height: 32,
                                  decoration: BoxDecoration(
                                    color: widget.color.withOpacity(0.12),
                                    borderRadius: BorderRadius.circular(9),
                                  ),
                                  child: Icon(Icons.person_rounded, color: widget.color, size: 18),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    autor.isEmpty ? 'Vendedor' : autor,
                                    style: TextStyle(color: AppTheme.darkBlue, fontSize: 13, fontWeight: FontWeight.w700),
                                  ),
                                ),
                                Text(_formatFecha(c['fechaCreacion']),
                                    style: TextStyle(color: AppTheme.textSecondary, fontSize: 11)),
                              ]),
                              const SizedBox(height: 8),
                              Text(c['comentario']?.toString() ?? '',
                                  style: TextStyle(color: AppTheme.textPrimary, fontSize: 14, height: 1.4)),
                            ]),
                          );
                        }),
                    ],
                  ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(top: BorderSide(color: AppTheme.borderColor)),
            ),
            child: Row(children: [
              Expanded(
                child: TextField(
                  controller: _ctrl,
                  minLines: 1, maxLines: 4,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    hintText: 'Escribe un comentario...',
                    hintStyle: TextStyle(color: AppTheme.textSecondary),
                    filled: true, fillColor: AppTheme.backgroundColor,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(color: AppTheme.borderColor),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(color: widget.color, width: 1.5),
                    ),
                  ),
                  onSubmitted: (_) => _enviar(),
                ),
              ),
              const SizedBox(width: 10),
              GestureDetector(
                onTap: _sending ? null : _enviar,
                child: Container(
                  width: 48, height: 48,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: [widget.color, _mInk]),
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(color: widget.color.withOpacity(0.3), blurRadius: 8, offset: const Offset(0, 3)),
                    ],
                  ),
                  child: _sending
                      ? const Padding(
                          padding: EdgeInsets.all(14),
                          child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                        )
                      : const Icon(Icons.send_rounded, color: Colors.white, size: 20),
                ),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}
