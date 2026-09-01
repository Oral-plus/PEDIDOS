import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../utils/theme.dart';
import '../widgets/app_header.dart';

enum TipoPregunta { sino, opciones, rating, texto }

class Pregunta {
  final String id;
  final String texto;
  final TipoPregunta tipo;
  final List<String> opciones;
  final bool requerida;
  const Pregunta({
    required this.id,
    required this.texto,
    required this.tipo,
    this.opciones = const [],
    this.requerida = true,
  });
}

class Encuesta {
  final String id;
  final String nombre;
  final String descripcion;
  final IconData icono;
  final Color color;
  final List<Pregunta> preguntas;
  const Encuesta({
    required this.id,
    required this.nombre,
    required this.descripcion,
    required this.icono,
    required this.color,
    required this.preguntas,
  });
}

const List<Encuesta> kEncuestasVisita = [
  Encuesta(
    id: 'gestion_comercial',
    nombre: 'Gestión comercial',
    descripcion: 'Registra la gestión realizada en el punto de venta',
    icono: Icons.storefront_rounded,
    color: AppTheme.primaryBlue,
    preguntas: [
      Pregunta(id: 'exhibicion', texto: '¿Realizó exhibición de productos en el punto?', tipo: TipoPregunta.sino),
      Pregunta(id: 'tomo_pedido', texto: '¿El cliente tomó pedido?', tipo: TipoPregunta.sino),
      Pregunta(id: 'promociones', texto: '¿Se socializaron las promociones vigentes?', tipo: TipoPregunta.sino),
      Pregunta(
        id: 'interes',
        texto: 'Nivel de interés del cliente',
        tipo: TipoPregunta.opciones,
        opciones: ['Alto', 'Medio', 'Bajo'],
      ),
      Pregunta(id: 'obs_gestion', texto: 'Observación de la gestión', tipo: TipoPregunta.texto, requerida: false),
    ],
  ),
  Encuesta(
    id: 'satisfaccion',
    nombre: 'Satisfacción del cliente',
    descripcion: 'Mide la percepción y satisfacción del cliente',
    icono: Icons.sentiment_satisfied_alt_rounded,
    color: AppTheme.successColor,
    preguntas: [
      Pregunta(id: 'calificacion', texto: '¿Cómo califica la atención de Oral-Plus?', tipo: TipoPregunta.rating),
      Pregunta(id: 'recomienda', texto: '¿Recomendaría nuestros productos?', tipo: TipoPregunta.sino),
      Pregunta(id: 'quejas', texto: '¿El cliente tiene quejas o reclamos?', tipo: TipoPregunta.sino),
      Pregunta(id: 'sugerencias', texto: 'Sugerencias del cliente', tipo: TipoPregunta.texto, requerida: false),
    ],
  ),
];

class EncuestaVisitaScreen extends StatefulWidget {
  final String nombreCliente;
  const EncuestaVisitaScreen({super.key, required this.nombreCliente});

  @override
  State<EncuestaVisitaScreen> createState() => _EncuestaVisitaScreenState();
}

class _EncuestaVisitaScreenState extends State<EncuestaVisitaScreen> {
  Encuesta? _sel;
  final Map<String, dynamic> _resp = {};
  final Map<String, TextEditingController> _controllers = {};
  bool _mostrarErrores = false;

  static Color get _bg => AppTheme.backgroundColor;
  static Color get _border => AppTheme.borderColor;
  static Color get _textDark => AppTheme.darkBlue;
  static Color get _textMuted => AppTheme.textSecondary;

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _seleccionar(Encuesta e) {
    HapticFeedback.selectionClick();
    setState(() {
      _sel = e;
      _resp.clear();
      _mostrarErrores = false;
    });
  }

  bool get _completa {
    final e = _sel;
    if (e == null) return false;
    for (final p in e.preguntas) {
      if (!p.requerida) continue;
      final v = _resp[p.id];
      if (v == null || (v is String && v.trim().isEmpty)) return false;
    }
    return true;
  }

  void _finalizar() {
    for (final entry in _controllers.entries) {
      _resp[entry.key] = entry.value.text.trim();
    }
    if (!_completa) {
      setState(() => _mostrarErrores = true);
      HapticFeedback.heavyImpact();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Responde todas las preguntas obligatorias para finalizar'),
          backgroundColor: AppTheme.errorColor,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    HapticFeedback.mediumImpact();
    Navigator.of(context).pop({
      'tipo': _sel!.id,
      'nombre': _sel!.nombre,
      'respuestas': Map<String, dynamic>.from(_resp),
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        surfaceTintColor: Colors.white,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded, color: _textDark),
          onPressed: () {
            if (_sel != null) {
              setState(() => _sel = null);
            } else {
              Navigator.of(context).pop();
            }
          },
        ),
        titleSpacing: 0,
        title: AppBarTitle(_sel == null ? 'Encuesta de visita' : _sel!.nombre),
      ),
      body: _sel == null ? _seleccion() : _formulario(_sel!),
      bottomNavigationBar: _sel == null ? null : _barraFinalizar(),
    );
  }

  Widget _seleccion() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 28),
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppTheme.accentColor.withOpacity(0.1),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppTheme.accentColor.withOpacity(0.25)),
          ),
          child: Row(children: [
            const Icon(Icons.assignment_turned_in_rounded, color: AppTheme.accentColor),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Para finalizar la visita debes completar una encuesta. Selecciona cuál deseas responder:',
                style: TextStyle(color: _textDark, fontSize: 13, fontWeight: FontWeight.w600, height: 1.3),
              ),
            ),
          ]),
        ),
        const SizedBox(height: 18),
        ...kEncuestasVisita.map(_cardEncuesta),
      ],
    );
  }

  Widget _cardEncuesta(Encuesta e) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => _seleccionar(e),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: _border),
            ),
            child: Row(children: [
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [e.color, Color.lerp(e.color, Colors.black, 0.12)!],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(15),
                  boxShadow: [BoxShadow(color: e.color.withOpacity(0.3), blurRadius: 10, offset: const Offset(0, 4))],
                ),
                child: Icon(e.icono, color: Colors.white, size: 27),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(e.nombre, style: TextStyle(color: _textDark, fontSize: 16, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 3),
                  Text(e.descripcion,
                      style: TextStyle(color: _textMuted, fontSize: 12.5, fontWeight: FontWeight.w500, height: 1.25)),
                  const SizedBox(height: 6),
                  Text('${e.preguntas.length} preguntas',
                      style: TextStyle(color: e.color, fontSize: 11.5, fontWeight: FontWeight.w700)),
                ]),
              ),
              Icon(Icons.chevron_right_rounded, color: _textMuted),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _formulario(Encuesta e) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      itemCount: e.preguntas.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (_, i) => _cardPregunta(e, e.preguntas[i], i + 1),
    );
  }

  Widget _cardPregunta(Encuesta e, Pregunta p, int num) {
    final falta = _mostrarErrores &&
        p.requerida &&
        (_resp[p.id] == null || (_resp[p.id] is String && (_resp[p.id] as String).trim().isEmpty));
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: falta ? AppTheme.errorColor : _border, width: falta ? 1.5 : 1),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 24, height: 24, alignment: Alignment.center,
            decoration: BoxDecoration(color: e.color.withOpacity(0.12), borderRadius: BorderRadius.circular(8)),
            child: Text('$num', style: TextStyle(color: e.color, fontSize: 12, fontWeight: FontWeight.w800)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text.rich(TextSpan(children: [
              TextSpan(text: p.texto, style: TextStyle(color: _textDark, fontSize: 14.5, fontWeight: FontWeight.w700, height: 1.3)),
              if (p.requerida)
                const TextSpan(text: '  *', style: TextStyle(color: AppTheme.errorColor, fontWeight: FontWeight.w900)),
            ])),
          ),
        ]),
        const SizedBox(height: 12),
        _control(e, p),
      ]),
    );
  }

  Widget _control(Encuesta e, Pregunta p) {
    switch (p.tipo) {
      case TipoPregunta.sino:
        return Row(children: [
          _opcionPill(p, 'Sí', e.color, Icons.check_rounded),
          const SizedBox(width: 10),
          _opcionPill(p, 'No', AppTheme.errorColor, Icons.close_rounded),
        ]);
      case TipoPregunta.opciones:
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: p.opciones.map((o) => _opcionChip(p, o, e.color)).toList(),
        );
      case TipoPregunta.rating:
        return Row(
          children: List.generate(5, (i) {
            final val = i + 1;
            final activa = (_resp[p.id] as int? ?? 0) >= val;
            return GestureDetector(
              onTap: () {
                HapticFeedback.selectionClick();
                setState(() => _resp[p.id] = val);
              },
              child: Padding(
                padding: const EdgeInsets.only(right: 6),
                child: Icon(
                  activa ? Icons.star_rounded : Icons.star_outline_rounded,
                  color: activa ? AppTheme.accentColor : _textMuted,
                  size: 34,
                ),
              ),
            );
          }),
        );
      case TipoPregunta.texto:
        final ctrl = _controllers.putIfAbsent(p.id, () => TextEditingController());
        return TextField(
          controller: ctrl,
          maxLines: 2,
          textCapitalization: TextCapitalization.sentences,
          style: TextStyle(fontSize: 14, color: _textDark),
          onChanged: (v) => _resp[p.id] = v,
          decoration: InputDecoration(
            hintText: 'Escribe aquí…',
            hintStyle: TextStyle(color: AppTheme.textTertiaryColor, fontSize: 14),
            filled: true,
            fillColor: _bg,
            contentPadding: const EdgeInsets.all(12),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: _border)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: _border)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: e.color, width: 1.5)),
          ),
        );
    }
  }

  Widget _opcionPill(Pregunta p, String valor, Color color, IconData icon) {
    final sel = _resp[p.id] == valor;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          setState(() => _resp[p.id] = valor);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: sel ? color.withOpacity(0.12) : _bg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: sel ? color : _border, width: sel ? 1.6 : 1),
          ),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(icon, size: 18, color: sel ? color : _textMuted),
            const SizedBox(width: 6),
            Text(valor,
                style: TextStyle(color: sel ? color : _textDark, fontSize: 14, fontWeight: FontWeight.w700)),
          ]),
        ),
      ),
    );
  }

  Widget _opcionChip(Pregunta p, String valor, Color color) {
    final sel = _resp[p.id] == valor;
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() => _resp[p.id] = valor);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: sel ? color.withOpacity(0.12) : _bg,
          borderRadius: BorderRadius.circular(11),
          border: Border.all(color: sel ? color : _border, width: sel ? 1.6 : 1),
        ),
        child: Text(valor,
            style: TextStyle(color: sel ? color : _textDark, fontSize: 13.5, fontWeight: FontWeight.w700)),
      ),
    );
  }

  Widget _barraFinalizar() {
    final color = _sel?.color ?? AppTheme.successColor;
    return Container(
      padding: EdgeInsets.fromLTRB(16, 12, 16, 16 + MediaQuery.of(context).padding.bottom),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: _border.withOpacity(0.6))),
      ),
      child: SizedBox(
        width: double.infinity,
        height: 54,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: _finalizar,
            child: Container(
              alignment: Alignment.center,
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [color, Color.lerp(color, Colors.black, 0.12)!]),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [BoxShadow(color: color.withOpacity(0.35), blurRadius: 14, offset: const Offset(0, 5))],
              ),
              child: const Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.flag_rounded, color: Colors.white, size: 20),
                SizedBox(width: 8),
                Text('Finalizar visita',
                    style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800)),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
