import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../models/cart_item.dart';
import '../utils/app_assets.dart';

import '../utils/pdf_save_io.dart' if (dart.library.html) '../utils/pdf_save_web.dart' as pdf_save;
import '../utils/csv_save_io.dart' if (dart.library.html) '../utils/csv_save_web.dart' as csv_save;

/// Genera comprobantes de pedido: PDF (con logo) y CSV (para Excel).
class OrderReceiptService {
  /// Genera un PDF con el logo ORAL-PLUS y el detalle del pedido.
  static Future<void> generateAndSavePdf({
    required String clientName,
    required String cedula,
    required String email,
    required String telefono,
    required List<CartItem> items,
    required double total,
    String? docNum,
    String? docEntry,
  }) async {
    final pdf = pw.Document();
    final dateStr = DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now());
    final formatter = NumberFormat('#,##0', 'es_CO');

    pw.Widget logoWidget = pw.SizedBox.shrink();
    try {
      final data = await rootBundle.load(AppAssets.logo);
      final bytes = data.buffer.asUint8List();
      logoWidget = pw.Image(pw.MemoryImage(bytes), width: 120, height: 48, fit: pw.BoxFit.contain);
    } catch (_) {}

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(24),
        build: (pw.Context context) => [
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  logoWidget,
                  pw.Text('COMPROBANTE DE PEDIDO', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
                ],
              ),
              pw.SizedBox(height: 8),
              pw.Text('ORAL-PLUS — Salud y belleza en tu sonrisa', style: pw.TextStyle(fontSize: 10)),
              pw.SizedBox(height: 20),
              pw.Divider(),
              pw.SizedBox(height: 12),
              pw.Text('Fecha: $dateStr', style: const pw.TextStyle(fontSize: 10)),
              if (docNum != null) pw.Text('Nº Documento: $docNum', style: const pw.TextStyle(fontSize: 10)),
              if (docEntry != null) pw.Text('ID Transacción: $docEntry', style: const pw.TextStyle(fontSize: 10)),
              pw.SizedBox(height: 16),
              pw.Text('Datos del cliente', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 4),
              pw.Text('Nombre: $clientName', style: const pw.TextStyle(fontSize: 10)),
              pw.Text('Cédula: $cedula', style: const pw.TextStyle(fontSize: 10)),
              pw.Text('Correo: $email', style: const pw.TextStyle(fontSize: 10)),
              pw.Text('Teléfono: $telefono', style: const pw.TextStyle(fontSize: 10)),
              pw.SizedBox(height: 20),
              pw.Text('Detalle del pedido', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 8),
              pw.Table(
                border: pw.TableBorder.all(width: 0.5),
                columnWidths: {
                  0: const pw.FlexColumnWidth(3),
                  1: const pw.FlexColumnWidth(1),
                  2: const pw.FlexColumnWidth(1.5),
                  3: const pw.FlexColumnWidth(1.5),
                },
                children: [
                  pw.TableRow(
                    decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                    children: [
                      _cell('Producto', bold: true),
                      _cell('Cant.', bold: true),
                      _cell('P. unit.', bold: true),
                      _cell('Total', bold: true),
                    ],
                  ),
                  ...items.map((item) => pw.TableRow(
                    children: [
                      pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text(item.title.isNotEmpty ? item.title : 'Producto', style: const pw.TextStyle(fontSize: 9), maxLines: 2)),
                      pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('${item.quantity}', style: const pw.TextStyle(fontSize: 9))),
                      pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('\$${formatter.format(item.numericPrice.round())}', style: const pw.TextStyle(fontSize: 9))),
                      pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('\$${formatter.format(item.totalPrice.round())}', style: const pw.TextStyle(fontSize: 9))),
                    ],
                  )),
                ],
              ),
              pw.SizedBox(height: 12),
              pw.Align(
                alignment: pw.Alignment.centerRight,
                child: pw.Text('TOTAL: \$${formatter.format(total.round())}', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
              ),
              pw.SizedBox(height: 24),
              pw.Center(child: pw.Text('Gracias por su compra', style: const pw.TextStyle(fontSize: 11))),
            ],
          ),
        ],
      ),
    );

    final bytes = await pdf.save();
    final fileName = 'Comprobante_ORAL-PLUS_${DateFormat('yyyyMMdd_HHmm').format(DateTime.now())}.pdf';
    await pdf_save.savePdfBytes(fileName, bytes);
  }

  static pw.Widget _cell(String text, {bool bold = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(6),
      child: pw.Text(text, style: pw.TextStyle(fontSize: 9, fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal)),
    );
  }

  /// Genera PDF tipo factura desde datos de un pedido existente.
  static Future<void> generateAndSavePdfFactura({
    required Map<String, dynamic> pedido,
    required List<Map<String, dynamic>> productos,
  }) async {
    final pdf = pw.Document();
    final formatter = NumberFormat('#,##0', 'es_CO');
    final numeroPedido = pedido['numeroPedido']?.toString() ?? '—';
    final fechaCreacion = pedido['fechaCreacion'];
    String dateStr = '—';
    if (fechaCreacion != null) {
      try {
        dateStr = DateFormat('dd/MM/yyyy HH:mm').format(DateTime.parse(fechaCreacion.toString()));
      } catch (_) {}
    }

    pw.Widget logoWidget = pw.SizedBox.shrink();
    try {
      final data = await rootBundle.load(AppAssets.logo);
      final bytes = data.buffer.asUint8List();
      logoWidget = pw.Image(pw.MemoryImage(bytes), width: 120, height: 48, fit: pw.BoxFit.contain);
    } catch (_) {}

    final clientName = pedido['nombreCliente']?.toString() ?? '—';
    final cedula = pedido['cedulaCliente']?.toString() ?? pedido['codigoCliente']?.toString() ?? '—';
    final email = pedido['correo']?.toString() ?? '—';
    final telefono = pedido['telefono']?.toString() ?? '—';
    final direccion = pedido['direccion']?.toString() ?? '—';
    final vendedor = pedido['vendedor']?.toString() ?? '—';
    final estado = pedido['estado']?.toString() ?? 'PENDIENTE';
    final total = (pedido['total'] as num?)?.toDouble() ?? 0;
    final subtotal = (pedido['subtotal'] as num?)?.toDouble() ?? 0;
    final iva = (pedido['iva'] as num?)?.toDouble() ?? 0;
    final observaciones = pedido['observaciones']?.toString() ?? '';

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(24),
        build: (pw.Context context) => [
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  logoWidget,
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text('FACTURA / PEDIDO', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
                      pw.Text('ORAL-PLUS', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
                    ],
                  ),
                ],
              ),
              pw.SizedBox(height: 8),
              pw.Text('Salud y belleza en tu sonrisa', style: pw.TextStyle(fontSize: 10)),
              pw.SizedBox(height: 20),
              pw.Divider(),
              pw.SizedBox(height: 12),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text('Nº Pedido: $numeroPedido', style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
                      pw.Text('Fecha: $dateStr', style: const pw.TextStyle(fontSize: 10)),
                      pw.Text('Estado: $estado', style: const pw.TextStyle(fontSize: 10)),
                      pw.Text('Vendedor: $vendedor', style: const pw.TextStyle(fontSize: 10)),
                    ],
                  ),
                ],
              ),
              pw.SizedBox(height: 20),
              pw.Text('Datos del cliente', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 6),
              pw.Container(
                padding: const pw.EdgeInsets.all(12),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(width: 0.5),
                  borderRadius: pw.BorderRadius.circular(4),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('Nombre: $clientName', style: const pw.TextStyle(fontSize: 10)),
                    pw.Text('Cédula/Código: $cedula', style: const pw.TextStyle(fontSize: 10)),
                    pw.Text('Correo: $email', style: const pw.TextStyle(fontSize: 10)),
                    pw.Text('Teléfono: $telefono', style: const pw.TextStyle(fontSize: 10)),
                    pw.Text('Dirección: $direccion', style: const pw.TextStyle(fontSize: 10)),
                  ],
                ),
              ),
              if (observaciones.isNotEmpty) ...[
                pw.SizedBox(height: 12),
                pw.Text('Observaciones: $observaciones', style: const pw.TextStyle(fontSize: 10)),
              ],
              pw.SizedBox(height: 20),
              pw.Text('Detalle del pedido', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 8),
              pw.Table(
                border: pw.TableBorder.all(width: 0.5),
                columnWidths: {
                  0: const pw.FlexColumnWidth(3),
                  1: const pw.FlexColumnWidth(1),
                  2: const pw.FlexColumnWidth(1.5),
                  3: const pw.FlexColumnWidth(1.5),
                },
                children: [
                  pw.TableRow(
                    decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                    children: [
                      _cell('Producto', bold: true),
                      _cell('Cant.', bold: true),
                      _cell('P. unit.', bold: true),
                      _cell('Total', bold: true),
                    ],
                  ),
                  ...productos.map((item) {
                    final nombre = item['nombre']?.toString() ?? '—';
                    final cant = (item['cantidad'] as num?)?.toInt() ?? 0;
                    final precio = (item['precioUnitario'] as num?)?.toDouble() ?? 0;
                    final totalLinea = (item['totalLinea'] as num?)?.toDouble() ?? 0;
                    return pw.TableRow(
                      children: [
                        pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text(nombre, style: const pw.TextStyle(fontSize: 9), maxLines: 2)),
                        pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('$cant', style: const pw.TextStyle(fontSize: 9))),
                        pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('\$${formatter.format(precio.round())}', style: const pw.TextStyle(fontSize: 9))),
                        pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('\$${formatter.format(totalLinea.round())}', style: const pw.TextStyle(fontSize: 9))),
                      ],
                    );
                  }),
                ],
              ),
              pw.SizedBox(height: 16),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.end,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      if (iva > 0) pw.Text('Subtotal: \$${formatter.format(subtotal.round())}', style: const pw.TextStyle(fontSize: 10)),
                      if (iva > 0) pw.Text('IVA: \$${formatter.format(iva.round())}', style: const pw.TextStyle(fontSize: 10)),
                      pw.SizedBox(height: 4),
                      pw.Text('TOTAL: \$${formatter.format(total.round())}', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
                    ],
                  ),
                ],
              ),
              pw.SizedBox(height: 24),
              pw.Center(child: pw.Text('Gracias por su compra - ORAL-PLUS', style: const pw.TextStyle(fontSize: 11))),
            ],
          ),
        ],
      ),
    );

    final bytes = await pdf.save();
    final fileName = 'Factura_${numeroPedido.replaceAll(RegExp(r'[^a-zA-Z0-9\-]'), '_')}_${DateFormat('yyyyMMdd').format(DateTime.now())}.pdf';
    await pdf_save.savePdfBytes(fileName, bytes);
  }

  /// Genera un CSV con el comprobante (ORAL-PLUS, productos, total). Se abre en Excel.
  static Future<void> generateAndSaveCsv({
    required String clientName,
    required String cedula,
    required String email,
    required String telefono,
    required List<CartItem> items,
    required double total,
    String? docNum,
    String? docEntry,
  }) async {
    final dateStr = DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now());
    final formatter = NumberFormat('#,##0', 'es_CO');
    final sb = StringBuffer();
    sb.writeln('ORAL-PLUS - COMPROBANTE DE PEDIDO');
    sb.writeln('Salud y belleza en tu sonrisa');
    sb.writeln('');
    sb.writeln('Fecha;$dateStr');
    if (docNum != null) sb.writeln('Nº Documento;$docNum');
    if (docEntry != null) sb.writeln('ID Transacción;$docEntry');
    sb.writeln('');
    sb.writeln('Cliente;$clientName');
    sb.writeln('Cédula;$cedula');
    sb.writeln('Correo;$email');
    sb.writeln('Teléfono;$telefono');
    sb.writeln('');
    sb.writeln('Producto;Cantidad;Precio unit;Total');
    for (final item in items) {
      sb.writeln('"${item.title.replaceAll('"', '""')}";${item.quantity};\$${formatter.format(item.numericPrice.round())};\$${formatter.format(item.totalPrice.round())}');
    }
    sb.writeln('');
    sb.writeln('TOTAL;\$${formatter.format(total.round())}');

    final fileName = 'Comprobante_ORAL-PLUS_${DateFormat('yyyyMMdd_HHmm').format(DateTime.now())}.csv';
    await csv_save.saveCsvBytes(fileName, sb.toString());
  }
}
