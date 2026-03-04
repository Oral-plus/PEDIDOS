import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:geolocator/geolocator.dart';
import '../models/cart_item.dart';
import '../services/api_easy_service.dart';
import '../services/order_db_service.dart';
import '../services/Datos_service.dart';
import '../services/order_receipt_service.dart';
import '../utils/app_assets.dart';
import 'loading_overlay.dart';
import 'login_screen.dart';

class CheckoutScreen extends StatefulWidget {
  final List<CartItem> cartItems;
  final String codigoCliente;

  const CheckoutScreen({
    super.key,
    required this.cartItems,
    required this.codigoCliente,
  });

  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends State<CheckoutScreen> {
  final _formKey = GlobalKey<FormState>();

  final _cedulaController = TextEditingController();
  final _nombreController = TextEditingController();
  final _emailController = TextEditingController();
  final _telefonoController = TextEditingController();
  final _direccionController = TextEditingController();

  bool _isProcessingOrder = false;
  bool _isSearchingUser = false;
  bool _acceptTerms = false;
  bool _isLoadingUserData = true;
  bool _clientFoundInSAP = false;
  bool _isGettingLocation = false;
  String? _locationError;

  static const _blue = Color(0xFF1A56DB);
  // ignore: unused_field
  static const _blueLight = Color(0xFF3B82F6);
  static const _bg = Color(0xFFF8FAFC);
  static const _textDark = Color(0xFF111827);
  static const _textMuted = Color(0xFF6B7280);
  static const _success = Color(0xFF059669);
  static const _error = Color(0xFFDC2626);
  static const _border = Color(0xFFE5E7EB);

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  @override
  void dispose() {
    _cedulaController.dispose();
    _nombreController.dispose();
    _emailController.dispose();
    _telefonoController.dispose();
    _direccionController.dispose();
    super.dispose();
  }

  String _fmt(num price) => NumberFormat('#,##0', 'es_CO').format(price);

  List<CartItem> get _validItems =>
      widget.cartItems.where((i) => i.numericPrice > 0).toList();

  double get _total =>
      _validItems.fold(0.0, (s, i) => s + i.totalPrice);

  bool get _canProcess =>
      _nombreController.text.trim().isNotEmpty &&
      _emailController.text.trim().isNotEmpty &&
      _cedulaController.text.trim().isNotEmpty &&
      _validItems.isNotEmpty &&
      _acceptTerms &&
      !_isProcessingOrder;

  // ── Data loading ──

  Future<void> _loadUserData() async {
    if (!mounted) return;
    setState(() => _isLoadingUserData = true);
    try {
      final code = widget.codigoCliente.isNotEmpty
          ? widget.codigoCliente
          : ClientSession().codigoCliente;
      if (code.isNotEmpty && mounted) {
        _cedulaController.text = code;
        await _searchUser(code, silent: true);
      }
    } catch (_) {}
    if (mounted) setState(() => _isLoadingUserData = false);
  }

  Future<void> _searchUser(String cedula, {bool silent = false}) async {
    if (cedula.isEmpty || !mounted) return;
    setState(() => _isSearchingUser = true);
    try {
      final data = await InvoiceService1.getClientDataWithFilters(cedula);
      if (!mounted) return;
      if (data != null) {
        _nombreController.text = data['cardName']?.toString() ?? '';
        _emailController.text = data['email']?.toString() ?? '';
        _telefonoController.text = data['phone']?.toString() ?? '';
        _direccionController.text = data['address']?.toString() ?? '';
        setState(() => _clientFoundInSAP = true);
        if (!silent) _snack('Cliente verificado', _success);
      } else {
        setState(() => _clientFoundInSAP = false);
        if (!silent) _snack('Cliente no encontrado', _error);
      }
    } catch (_) {
      if (mounted) setState(() => _clientFoundInSAP = false);
    } finally {
      if (mounted) setState(() => _isSearchingUser = false);
    }
  }

  // ── Geolocation ──

  Future<void> _getDeviceLocation() async {
    if (!mounted) return;
    setState(() { _isGettingLocation = true; _locationError = null; });

    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          setState(() { _isGettingLocation = false; _locationError = 'Permiso de ubicación denegado'; });
          return;
        }
      }
      if (permission == LocationPermission.deniedForever) {
        setState(() { _isGettingLocation = false; _locationError = 'Ubicación deshabilitada permanentemente'; });
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 15)),
      );

      // Guardar solo coordenadas (lat, lng). No usar reverse-geocode: la dirección
      // del dispositivo sería la del vendedor, no del cliente.
      final coords = '${position.latitude.toStringAsFixed(6)}, ${position.longitude.toStringAsFixed(6)}';

      if (mounted) {
        _direccionController.text = coords;
        setState(() => _isGettingLocation = false);
      }
    } catch (e) {
      if (mounted) {
        setState(() { _isGettingLocation = false; _locationError = 'No se pudo obtener ubicación'; });
      }
    }
  }

  // ── Order processing ──

  Future<void> _processOrder() async {
    if (!_formKey.currentState!.validate()) return;
    if (!_acceptTerms) {
      _snack('Acepta los términos para continuar', _error);
      return;
    }
    if (_validItems.isEmpty) {
      _snack('No hay productos válidos', _error);
      return;
    }

    setState(() => _isProcessingOrder = true);
    try {
      // No auto-rellenar con GPS: la ubicación del dispositivo es del vendedor, no del cliente.
      // La dirección debe venir de SAP o ingresarse manualmente.

      final session = ClientSession();
      final vendedorNombre = ApiEasyService().usuario?['nombre']?.toString().trim() ?? '';
      final vendedor = vendedorNombre.isNotEmpty
          ? vendedorNombre
          : (session.vendedor.trim().isNotEmpty ? session.vendedor.trim() : 'Vendedor');

      final result = await OrderDbService.saveOrder(
        cartItems: _validItems,
        cedula: _cedulaController.text.trim(),
        nombre: _nombreController.text.trim(),
        correo: _emailController.text.trim(),
        telefono: _telefonoController.text.trim(),
        direccion: _direccionController.text.trim().isEmpty
            ? null
            : _direccionController.text.trim(),
        observaciones: '',
        codigoCliente: widget.codigoCliente,
        vendedor: vendedor,
        ciudad: session.ciudad.isNotEmpty ? session.ciudad : null,
      );

      if (result['success'] == true && mounted) {
        HapticFeedback.mediumImpact();
        _showSuccessDialog(result);
      } else {
        throw Exception(result['message'] ?? 'Error desconocido');
      }
    } catch (e) {
      if (mounted) {
        _snack(e.toString().replaceAll('Exception: ', ''), _error);
      }
    } finally {
      if (mounted) setState(() => _isProcessingOrder = false);
    }
  }

  // ── Receipts ──

  Future<void> _downloadPdf(Map<String, dynamic> result) async {
    try {
      await OrderReceiptService.generateAndSavePdf(
        clientName: _nombreController.text.trim(),
        cedula: _cedulaController.text.trim(),
        email: _emailController.text.trim(),
        telefono: _telefonoController.text.trim(),
        items: _validItems,
        total: _total,
        docNum: result['docNum']?.toString(),
        docEntry: result['docEntry']?.toString(),
      );
      if (mounted) _snack('PDF descargado', _success);
    } catch (e, st) {
      debugPrint('Error al generar PDF: $e\n$st');
      if (mounted) _snack('Error al generar PDF', _error);
    }
  }

  Future<void> _downloadExcel(Map<String, dynamic> result) async {
    try {
      await OrderReceiptService.generateAndSaveCsv(
        clientName: _nombreController.text.trim(),
        cedula: _cedulaController.text.trim(),
        email: _emailController.text.trim(),
        telefono: _telefonoController.text.trim(),
        items: _validItems,
        total: _total,
        docNum: result['docNum']?.toString(),
        docEntry: result['docEntry']?.toString(),
      );
      if (mounted) _snack('Excel descargado', _success);
    } catch (e) {
      if (mounted) _snack('Error al generar Excel', _error);
    }
  }

  void _snack(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
      backgroundColor: color,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.all(16),
    ));
  }

  // ══════════════════════════════════════
  //  BUILD
  // ══════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: _isLoadingUserData
          ? _loading()
          : LoadingOverlay(
              isLoading: _isProcessingOrder,
              message: 'Procesando pedido',
              subtitle: 'Registrando en base de datos...',
              child: Column(
                children: [
                  _appBar(),
                  Expanded(
                    child: SingleChildScrollView(
                      physics: const BouncingScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _productsCard(),
                            const SizedBox(height: 20),
                            _clientCard(),
                            const SizedBox(height: 20),
                            _termsRow(),
                            const SizedBox(height: 24),
                            _totalBar(),
                            const SizedBox(height: 16),
                            _confirmButton(),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  // ── Loading splash ──

  Widget _loading() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppAssets.logoImage(width: 100, height: 40),
          const SizedBox(height: 24),
          const SizedBox(
            width: 36, height: 36,
            child: CircularProgressIndicator(strokeWidth: 3, color: _blue),
          ),
          const SizedBox(height: 16),
          const Text('Cargando datos del cliente...', style: TextStyle(color: _textMuted, fontSize: 14)),
        ],
      ),
    );
  }

  // ── App Bar ──

  Widget _appBar() {
    return Container(
      color: Colors.white,
      child: SafeArea(
        bottom: false,
        child: Container(
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: _border, width: 1)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  width: 40, height: 40,
                  decoration: BoxDecoration(
                    color: _bg,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _border),
                  ),
                  child: const Icon(Icons.arrow_back_ios_new, size: 18, color: _textDark),
                ),
              ),
              const SizedBox(width: 14),
              AppAssets.logoImage(width: 100, height: 32),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Checkout', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: _textDark, letterSpacing: -0.5)),
                    Text(
                      '${_validItems.length} producto${_validItems.length == 1 ? '' : 's'}',
                      style: const TextStyle(fontSize: 12, color: _textMuted),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: _blue.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '\$${_fmt(_total)}',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: _blue),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Products card ──

  Widget _productsCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
            child: Row(
              children: [
                Icon(Icons.receipt_long_rounded, size: 20, color: _blue.withOpacity(0.7)),
                const SizedBox(width: 10),
                const Text('Resumen del pedido', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: _textDark)),
              ],
            ),
          ),
          const Divider(height: 1, color: _border),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: _validItems.length,
            separatorBuilder: (_, __) => const Divider(height: 1, indent: 20, endIndent: 20, color: _border),
            itemBuilder: (_, i) => _productRow(_validItems[i]),
          ),
          const Divider(height: 1, color: _border),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Subtotal', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: _textMuted)),
                Text('\$${_fmt(_total)}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: _textDark)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _productRow(CartItem item) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Container(
              width: 52, height: 52,
              color: _bg,
              child: Image.asset(item.image, fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => const Icon(Icons.shopping_bag_outlined, color: _textMuted, size: 24)),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: _textDark), maxLines: 2, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 4),
                Row(
                  children: [
                    _badge('x${item.quantity}', _blue),
                    const SizedBox(width: 6),
                    _badge(item.codigoSap, _textMuted),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text('\$${_fmt(item.totalPrice)}', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: _textDark)),
        ],
      ),
    );
  }

  Widget _badge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(text, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color)),
    );
  }

  // ── Client card ──

  Widget _clientCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
            child: Row(
              children: [
                Icon(
                  _clientFoundInSAP ? Icons.verified_rounded : Icons.person_outline_rounded,
                  size: 20,
                  color: _clientFoundInSAP ? _success : _blue.withOpacity(0.7),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text('Datos del cliente', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: _textDark)),
                ),
                if (_clientFoundInSAP)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(color: _success.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                    child: const Text('Verificado', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: _success)),
                  ),
                if (_isSearchingUser)
                  const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: _blue)),
              ],
            ),
          ),
          const Divider(height: 1, color: _border),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            child: Column(
              children: [
                _field(_cedulaController, 'Código de cliente', Icons.credit_card_rounded,
                  readOnly: false,
                  suffix: IconButton(
                    icon: const Icon(Icons.search_rounded, color: _blue, size: 20),
                    onPressed: () => _searchUser(_cedulaController.text.trim()),
                  ),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return 'Requerido';
                    if (v.trim().length < 5) return 'Código inválido';
                    return null;
                  },
                  onSubmitted: (v) => _searchUser(v.trim()),
                ),
                const SizedBox(height: 14),
                _field(_nombreController, 'Nombre completo', Icons.person_outline_rounded,
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Requerido' : null),
                const SizedBox(height: 14),
                _field(_emailController, 'Correo electrónico', Icons.email_outlined,
                  keyboard: TextInputType.emailAddress,
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return 'Requerido';
                    if (!RegExp(r'^[\w\-.]+@([\w\-]+\.)+[\w\-]{2,4}$').hasMatch(v)) return 'Correo inválido';
                    return null;
                  }),
                const SizedBox(height: 14),
                _field(_telefonoController, 'Teléfono', Icons.phone_outlined, keyboard: TextInputType.phone),
                const SizedBox(height: 14),
                _field(
                  _direccionController, 'Dirección del cliente o coordenadas (GPS)', Icons.location_on_outlined,
                  readOnly: false,
                  suffix: _isGettingLocation
                      ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: _blue)),
                        )
                      : IconButton(
                          icon: const Icon(Icons.my_location_rounded, color: _blue, size: 20),
                          onPressed: _getDeviceLocation,
                          tooltip: 'Obtener ubicación GPS',
                        ),
                ),
                if (_locationError != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 6, left: 4),
                    child: Text(_locationError!, style: const TextStyle(fontSize: 12, color: _error)),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _field(
    TextEditingController controller,
    String label,
    IconData icon, {
    bool readOnly = true,
    TextInputType? keyboard,
    String? Function(String?)? validator,
    Widget? suffix,
    void Function(String)? onSubmitted,
  }) {
    return TextFormField(
      controller: controller,
      readOnly: readOnly,
      keyboardType: keyboard,
      validator: validator,
      onFieldSubmitted: onSubmitted,
      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: _textDark),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: _textMuted, fontSize: 14),
        prefixIcon: Icon(icon, color: _blue.withOpacity(0.6), size: 20),
        suffixIcon: suffix,
        filled: true,
        fillColor: readOnly ? const Color(0xFFF9FAFB) : Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: _border)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: _border)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: _blue, width: 1.5)),
        errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: _error)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
    );
  }

  // ── Terms ──

  Widget _termsRow() {
    return GestureDetector(
      onTap: () => setState(() => _acceptTerms = !_acceptTerms),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _acceptTerms ? _blue.withOpacity(0.3) : _border),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 24, height: 24,
              child: Checkbox(
                value: _acceptTerms,
                onChanged: (v) => setState(() => _acceptTerms = v ?? false),
                activeColor: _blue,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
              ),
            ),
            const SizedBox(width: 14),
            const Expanded(
              child: Text(
                'Confirmo que los datos son correctos y autorizo el procesamiento del pedido.',
                style: TextStyle(fontSize: 13, color: _textMuted, height: 1.4),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Total bar ──

  Widget _totalBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      decoration: BoxDecoration(
        color: _blue.withOpacity(0.05),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _blue.withOpacity(0.15)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text('Total a pagar', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: _textDark)),
          Text('\$${_fmt(_total)}', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: _blue)),
        ],
      ),
    );
  }

  // ── Confirm button ──

  Widget _confirmButton() {
    return SizedBox(
      height: 56,
      child: ElevatedButton(
        onPressed: _canProcess ? _processOrder : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: _blue,
          disabledBackgroundColor: Colors.grey.shade300,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        child: _isProcessingOrder
            ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(_canProcess ? Icons.shopping_cart_checkout_rounded : Icons.info_outline_rounded, size: 22),
                  const SizedBox(width: 10),
                  Text(
                    _canProcess ? 'Confirmar pedido' : 'Completa los datos',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
      ),
    );
  }

  // ── Success dialog ──

  void _showSuccessDialog(Map<String, dynamic> result) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 72, height: 72,
                  decoration: BoxDecoration(color: _success.withOpacity(0.1), shape: BoxShape.circle),
                  child: const Icon(Icons.check_rounded, color: _success, size: 38),
                ),
                const SizedBox(height: 20),
                const Text('Pedido registrado', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: _textDark)),
                const SizedBox(height: 8),
                Text(
                  result['message']?.toString() ?? 'Tu pedido ha sido procesado correctamente.',
                  style: const TextStyle(fontSize: 14, color: _textMuted, height: 1.4),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                _infoCard(result),
                const SizedBox(height: 20),
                _receiptButtons(result),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity, height: 50,
                  child: ElevatedButton(
                    onPressed: () {
                      final nav = Navigator.of(ctx, rootNavigator: true);
                      nav.pop();
                      if (mounted) {
                        Navigator.of(context).popUntil((route) => route.isFirst);
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _blue,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    child: const Text('Continuar comprando', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _infoCard(Map<String, dynamic> result) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _bg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _border),
      ),
      child: Column(
        children: [
          if (result['docNum'] != null) _infoRow('Nº Documento', '${result['docNum']}'),
          if (result['docEntry'] != null) ...[const SizedBox(height: 10), _infoRow('ID Transacción', '${result['docEntry']}')],
          const SizedBox(height: 10),
          _infoRow('Total', '\$${_fmt(_total)}'),
          const SizedBox(height: 10),
          _infoRow('Email', result['emailSent'] == true ? 'Enviado' : 'No enviado'),
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(fontSize: 13, color: _textMuted, fontWeight: FontWeight.w500)),
        Flexible(child: Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: _textDark), textAlign: TextAlign.end)),
      ],
    );
  }

  Widget _receiptButtons(Map<String, dynamic> result) {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () => _downloadPdf(result),
            icon: const Icon(Icons.picture_as_pdf_rounded, size: 18),
            label: const Text('PDF', style: TextStyle(fontWeight: FontWeight.w700)),
            style: OutlinedButton.styleFrom(
              foregroundColor: _blue,
              side: const BorderSide(color: _blue),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () => _downloadExcel(result),
            icon: const Icon(Icons.table_chart_rounded, size: 18),
            label: const Text('Excel', style: TextStyle(fontWeight: FontWeight.w700)),
            style: OutlinedButton.styleFrom(
              foregroundColor: _success,
              side: const BorderSide(color: _success),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ),
      ],
    );
  }
}
