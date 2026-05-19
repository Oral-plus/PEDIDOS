import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';
import '../models/cart_item.dart';
import '../services/api_easy_service.dart';
import '../services/order_db_service.dart';
import '../services/Datos_service.dart';
import '../services/order_receipt_service.dart';
import '../utils/theme.dart';
import '../utils/price_utils.dart';
import '../providers/session_provider.dart';
import 'loading_overlay.dart';

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

  List<CartItem> get _validItems =>
      widget.cartItems.where((i) => i.price > 0).toList();

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
          : context.read<SessionProvider>().codigoCliente;
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
        if (!silent) _snack('Cliente verificado', AppTheme.successColor);
      } else {
        setState(() => _clientFoundInSAP = false);
        if (!silent) _snack('Cliente no encontrado', AppTheme.errorColor);
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
      _snack('Acepta los términos para continuar', AppTheme.errorColor);
      return;
    }
    if (_validItems.isEmpty) {
      _snack('No hay productos válidos', AppTheme.errorColor);
      return;
    }

    setState(() => _isProcessingOrder = true);
    try {
      final session = context.read<SessionProvider>();
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
        direccion: _direccionController.text.trim().isEmpty ? null : _direccionController.text.trim(),
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
        _snack(e.toString().replaceAll('Exception: ', ''), AppTheme.errorColor);
      }
    } finally {
      if (mounted) setState(() => _isProcessingOrder = false);
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
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

  Widget _loading() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 42, height: 42,
            child: CircularProgressIndicator(strokeWidth: 3, color: AppTheme.primaryBlue),
          ),
          const SizedBox(height: 16),
          const Text('Preparando checkout...', style: TextStyle(color: AppTheme.textSecondary, fontSize: 14)),
        ],
      ),
    );
  }

  Widget _appBar() {
    return Container(
      color: Colors.white,
      child: SafeArea(
        bottom: false,
        child: Container(
          decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppTheme.borderColor, width: 1))),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.arrow_back_ios_new, size: 18, color: AppTheme.darkBlue),
                style: IconButton.styleFrom(
                  backgroundColor: AppTheme.elegantGray,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Finalizar Pedido', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppTheme.darkBlue, letterSpacing: -0.5)),
                    Text('${_validItems.length} items seleccionados', style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(color: AppTheme.primaryBlue.withOpacity(0.08), borderRadius: BorderRadius.circular(12)),
                child: Text(PriceUtils.formatPriceDisplay(_total), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppTheme.primaryBlue)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _productsCard() {
    return Container(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppTheme.borderColor)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 18, 20, 12),
            child: Row(
              children: [
                Icon(Icons.receipt_long_rounded, size: 20, color: AppTheme.primaryBlue),
                SizedBox(width: 10),
                Text('Resumen del pedido', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppTheme.darkBlue)),
              ],
            ),
          ),
          const Divider(height: 1, color: AppTheme.borderColor),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: _validItems.length,
            separatorBuilder: (_, __) => const Divider(height: 1, indent: 20, endIndent: 20, color: AppTheme.borderColor),
            itemBuilder: (_, i) => _productRow(_validItems[i]),
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
              width: 52, height: 52, color: AppTheme.elegantGray,
              child: Image.asset(item.image, fit: BoxFit.contain, errorBuilder: (_, __, ___) => const Icon(Icons.shopping_bag_outlined, color: AppTheme.textSecondary, size: 24)),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.darkBlue), maxLines: 2, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 4),
                Row(
                  children: [
                    _badge('x${item.quantity}', AppTheme.primaryBlue),
                    const SizedBox(width: 6),
                    _badge(item.codigoSap, AppTheme.textSecondary),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(PriceUtils.formatPriceDisplay(item.totalPrice), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppTheme.darkBlue)),
        ],
      ),
    );
  }

  Widget _badge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: color.withOpacity(0.08), borderRadius: BorderRadius.circular(8)),
      child: Text(text, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color)),
    );
  }

  Widget _clientCard() {
    return Container(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppTheme.borderColor)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
            child: Row(
              children: [
                Icon(_clientFoundInSAP ? Icons.verified_rounded : Icons.person_outline_rounded, size: 20, color: _clientFoundInSAP ? AppTheme.successColor : AppTheme.primaryBlue),
                const SizedBox(width: 10),
                const Expanded(child: Text('Datos del cliente', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppTheme.darkBlue))),
                if (_isSearchingUser) const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primaryBlue)),
              ],
            ),
          ),
          const Divider(height: 1, color: AppTheme.borderColor),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                _field(_cedulaController, 'Código de cliente', Icons.credit_card_rounded,
                  readOnly: false,
                  suffix: IconButton(icon: const Icon(Icons.search_rounded, color: AppTheme.primaryBlue, size: 20), onPressed: () => _searchUser(_cedulaController.text.trim())),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Requerido' : null,
                  onSubmitted: (v) => _searchUser(v.trim()),
                ),
                const SizedBox(height: 14),
                _field(_nombreController, 'Nombre completo', Icons.person_outline_rounded, validator: (v) => (v == null || v.trim().isEmpty) ? 'Requerido' : null),
                const SizedBox(height: 14),
                _field(_emailController, 'Correo electrónico', Icons.email_outlined, keyboard: TextInputType.emailAddress,
                  validator: (v) => (v == null || !v.contains('@')) ? 'Correo inválido' : null),
                const SizedBox(height: 14),
                _field(_telefonoController, 'Teléfono', Icons.phone_outlined, keyboard: TextInputType.phone),
                const SizedBox(height: 14),
                _field(_direccionController, 'Ubicación (GPS)', Icons.location_on_outlined, readOnly: false,
                  suffix: _isGettingLocation ? const Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primaryBlue)))
                  : IconButton(icon: const Icon(Icons.my_location_rounded, color: AppTheme.primaryBlue, size: 20), onPressed: _getDeviceLocation)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _field(TextEditingController controller, String label, IconData icon, {bool readOnly = true, TextInputType? keyboard, String? Function(String?)? validator, Widget? suffix, void Function(String)? onSubmitted}) {
    return TextFormField(
      controller: controller, readOnly: readOnly, keyboardType: keyboard, validator: validator, onFieldSubmitted: onSubmitted,
      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: AppTheme.darkBlue),
      decoration: InputDecoration(
        labelText: label, labelStyle: const TextStyle(color: AppTheme.textSecondary, fontSize: 13),
        prefixIcon: Icon(icon, color: AppTheme.primaryBlue.withOpacity(0.5), size: 18),
        suffixIcon: suffix, filled: true, fillColor: readOnly ? AppTheme.elegantGray : Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppTheme.borderColor)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppTheme.borderColor)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppTheme.primaryBlue, width: 1.5)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
    );
  }

  Widget _termsRow() {
    return GestureDetector(
      onTap: () => setState(() => _acceptTerms = !_acceptTerms),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: _acceptTerms ? AppTheme.primaryBlue.withOpacity(0.3) : AppTheme.borderColor)),
        child: Row(
          children: [
            Checkbox(value: _acceptTerms, onChanged: (v) => setState(() => _acceptTerms = v ?? false), activeColor: AppTheme.primaryBlue),
            const SizedBox(width: 10),
            const Expanded(child: Text('Confirmo que los datos son correctos y autorizo el procesamiento.', style: TextStyle(fontSize: 13, color: AppTheme.textSecondary, height: 1.4))),
          ],
        ),
      ),
    );
  }

  Widget _totalBar() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: AppTheme.primaryBlue.withOpacity(0.05), borderRadius: BorderRadius.circular(14), border: Border.all(color: AppTheme.primaryBlue.withOpacity(0.15))),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text('Total a pagar', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppTheme.darkBlue)),
          Text(PriceUtils.formatPriceDisplay(_total), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: AppTheme.primaryBlue)),
        ],
      ),
    );
  }

  Widget _confirmButton() {
    return SizedBox(
      height: 56, width: double.infinity,
      child: ElevatedButton(
        onPressed: _canProcess ? _processOrder : null,
        style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryBlue, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)), elevation: 0),
        child: _isProcessingOrder ? const CircularProgressIndicator(color: Colors.white)
        : const Text('Confirmar Pedido', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
      ),
    );
  }

  void _showSuccessDialog(Map<String, dynamic> result) {
    showDialog(
      context: context, barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle_rounded, color: AppTheme.successColor, size: 64),
            const SizedBox(height: 16),
            const Text('¡Pedido Exitoso!', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Text('Nº Documento: ${result['docNum'] ?? '—'}', style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _actionIcon(Icons.picture_as_pdf_rounded, 'PDF', () => _downloadPdf(result)),
                _actionIcon(Icons.table_view_rounded, 'Excel', () => _downloadExcel(result)),
              ],
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () { Navigator.pop(ctx); Navigator.pop(context); },
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.darkBlue, minimumSize: const Size(double.infinity, 50)),
              child: const Text('Volver al inicio'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _actionIcon(IconData icon, String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Column(
        children: [
          Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: AppTheme.elegantGray, borderRadius: BorderRadius.circular(12)), child: Icon(icon, color: AppTheme.primaryBlue)),
          const SizedBox(height: 4),
          Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Future<void> _downloadPdf(Map<String, dynamic> result) async {
    try {
      await OrderReceiptService.generateAndSavePdf(clientName: _nombreController.text, cedula: _cedulaController.text, email: _emailController.text, telefono: _telefonoController.text, items: _validItems, total: _total, docNum: result['docNum']?.toString(), docEntry: result['docEntry']?.toString());
      _snack('PDF generado', AppTheme.successColor);
    } catch (_) { _snack('Error al generar PDF', AppTheme.errorColor); }
  }

  Future<void> _downloadExcel(Map<String, dynamic> result) async {
    try {
      await OrderReceiptService.generateAndSaveCsv(clientName: _nombreController.text, cedula: _cedulaController.text, email: _emailController.text, telefono: _telefonoController.text, items: _validItems, total: _total, docNum: result['docNum']?.toString(), docEntry: result['docEntry']?.toString());
      _snack('Excel generado', AppTheme.successColor);
    } catch (_) { _snack('Error al generar Excel', AppTheme.errorColor); }
  }
}
