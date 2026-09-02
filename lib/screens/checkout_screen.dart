import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';
import '../models/cart_item.dart';
import '../services/api_easy_service.dart';
import '../services/order_db_service.dart';
import '../services/order_receipt_service.dart';
import '../utils/theme.dart';
import '../utils/app_assets.dart';
import '../utils/price_utils.dart';
import '../widgets/producto_imagen.dart';
import '../providers/session_provider.dart';
import '../providers/cart_provider.dart';
import '../widgets/app_dialog.dart';
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

  List<CartItem> get _validItems {
    List<CartItem> fuente;
    try {
      fuente = context.read<CartProvider>().items;
    } catch (_) {
      fuente = widget.cartItems;
    }
    return fuente.where((i) => i.price > 0).toList();
  }

  double get _total =>
      _validItems.fold(0.0, (s, i) => s + i.totalPrice);

  bool get _canProcess =>
      _nombreController.text.trim().isNotEmpty &&
      _emailController.text.trim().isNotEmpty &&
      _cedulaController.text.trim().isNotEmpty &&
      _validItems.isNotEmpty &&
      _acceptTerms &&
      !_isProcessingOrder;


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
      final data = await ApiEasyService().getClientePorCodigo(cedula.trim());
      if (!mounted) return;
      if (data != null && (data['nombre']?.toString().trim().isNotEmpty ?? false)) {
        _nombreController.text = data['nombre']?.toString() ?? '';
        _emailController.text = data['correo']?.toString() ?? '';
        _telefonoController.text = data['telefono']?.toString() ?? '';
        _direccionController.text = data['direccion']?.toString() ?? '';
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
    context.watch<CartProvider>();
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
    final n = _validItems.length;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 12, offset: const Offset(0, 4)),
        ],
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
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
              const SizedBox(width: 10),
              Image.asset(AppAssets.logo, height: 28, fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => const Icon(Icons.medical_services_rounded, size: 26, color: AppTheme.primaryBlue)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text('Finalizar pedido',
                          maxLines: 1,
                          softWrap: false,
                          style: TextStyle(fontSize: 16.5, fontWeight: FontWeight.w800, color: AppTheme.darkBlue, letterSpacing: -0.4)),
                    ),
                    const SizedBox(height: 1),
                    Text('$n ${n == 1 ? 'producto' : 'productos'} seleccionado${n == 1 ? '' : 's'}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11.5, color: AppTheme.textSecondary, fontWeight: FontWeight.w500)),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [AppTheme.primaryBlue, AppTheme.secondaryBlue]),
                  borderRadius: BorderRadius.circular(13),
                  boxShadow: [
                    BoxShadow(color: AppTheme.primaryBlue.withOpacity(0.28), blurRadius: 12, offset: const Offset(0, 5)),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('TOTAL', style: TextStyle(fontSize: 8, fontWeight: FontWeight.w800, color: Colors.white70, letterSpacing: 1)),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 250),
                      transitionBuilder: (c, a) => FadeTransition(opacity: a, child: c),
                      child: Text(
                        PriceUtils.formatPriceDisplay(_total),
                        key: ValueKey<double>(_total),
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: -0.3),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  BoxDecoration get _cardDecoration => BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.borderColor),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 16, offset: const Offset(0, 6)),
        ],
      );

  Widget _sectionHeader(IconData icon, String title, Color color, {Widget? trailing}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      child: Row(
        children: [
          Container(
            width: 34, height: 34,
            decoration: BoxDecoration(color: color.withOpacity(0.10), borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, size: 18, color: color),
          ),
          const SizedBox(width: 11),
          Expanded(child: Text(title, style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800, color: AppTheme.darkBlue, letterSpacing: -0.2))),
          if (trailing != null) trailing,
        ],
      ),
    );
  }

  Widget _productsCard() {
    return Container(
      decoration: _cardDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader(
            Icons.receipt_long_rounded,
            'Resumen del pedido',
            AppTheme.primaryBlue,
            trailing: _validItems.isEmpty
                ? null
                : Container(
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                    decoration: BoxDecoration(color: AppTheme.primaryBlue.withOpacity(0.08), borderRadius: BorderRadius.circular(20)),
                    child: Text('${_validItems.length}',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AppTheme.primaryBlue)),
                  ),
          ),
          const Divider(height: 1, color: AppTheme.borderColor),
          if (_validItems.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 28),
              child: Center(
                child: Column(children: [
                  Icon(Icons.remove_shopping_cart_rounded, color: AppTheme.textSecondary, size: 34),
                  SizedBox(height: 8),
                  Text('No hay productos en el pedido',
                      style: TextStyle(color: AppTheme.textSecondary, fontWeight: FontWeight.w600)),
                ]),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(
                children: [
                  for (var i = 0; i < _validItems.length; i++) ...[
                    if (i > 0)
                      const Divider(height: 1, indent: 20, endIndent: 20, color: AppTheme.borderColor),
                    _productRow(_validItems[i]),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _productRow(CartItem item) {
    final cart = context.read<CartProvider>();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Container(
              width: 52, height: 52, color: AppTheme.elegantGray,
              child: ProductoImagen(url: item.image, cacheWidth: 160, iconSize: 24, iconColor: AppTheme.textSecondary),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.darkBlue), maxLines: 2, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 6),
                _badge(item.codigoSap, AppTheme.textSecondary),
                const SizedBox(height: 10),
                Container(
                  decoration: BoxDecoration(
                    color: AppTheme.elegantGray,
                    borderRadius: BorderRadius.circular(11),
                    border: Border.all(color: AppTheme.borderColor),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    _stepBtn(Icons.remove_rounded, () => cart.updateQuantity(item.id, item.quantity - 1)),
                    GestureDetector(
                      onTap: () => _editarCantidad(cart, item),
                      child: Container(
                        constraints: const BoxConstraints(minWidth: 42),
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                        alignment: Alignment.center,
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 220),
                          transitionBuilder: (c, a) => ScaleTransition(
                            scale: Tween<double>(begin: 0.6, end: 1).animate(a),
                            child: FadeTransition(opacity: a, child: c),
                          ),
                          child: Text('${item.quantity}',
                              key: ValueKey<int>(item.quantity),
                              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppTheme.darkBlue)),
                        ),
                      ),
                    ),
                    _stepBtn(Icons.add_rounded, () => cart.updateQuantity(item.id, item.quantity + 1)),
                  ]),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(PriceUtils.formatPriceDisplay(item.totalPrice),
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppTheme.darkBlue)),
              const SizedBox(height: 8),
              InkWell(
                borderRadius: BorderRadius.circular(9),
                onTap: () => _confirmarBorrar(cart, item),
                child: Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: AppTheme.errorColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: const Icon(Icons.delete_outline_rounded, color: AppTheme.errorColor, size: 19),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _stepBtn(IconData icon, VoidCallback onTap) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(11),
      child: InkWell(
        borderRadius: BorderRadius.circular(11),
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: Container(
          width: 34, height: 34,
          alignment: Alignment.center,
          child: Icon(icon, color: AppTheme.primaryBlue, size: 18),
        ),
      ),
    );
  }

  Future<void> _confirmarBorrar(CartProvider cart, CartItem item) async {
    HapticFeedback.mediumImpact();
    final ok = await showAppConfirm(
      context,
      title: 'Eliminar producto',
      message: '¿Quitar "${item.title}" del pedido?',
      confirmText: 'Eliminar',
      icon: Icons.delete_outline_rounded,
      danger: true,
    );
    if (ok) {
      cart.removeItem(item.id);
      if (mounted) _snack('Producto eliminado', AppTheme.errorColor);
    }
  }

  Future<void> _editarCantidad(CartProvider cart, CartItem item) async {
    final val = await showAppInput(
      context,
      title: 'Editar cantidad',
      subtitle: item.title,
      initialValue: '${item.quantity}',
      icon: Icons.edit_rounded,
      numeric: true,
      keyboardType: TextInputType.number,
      confirmText: 'Guardar',
    );
    if (val != null) {
      cart.updateQuantity(item.id, int.tryParse(val) ?? item.quantity);
    }
  }

  Widget _badge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: color.withOpacity(0.08), borderRadius: BorderRadius.circular(8)),
      child: Text(text, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color)),
    );
  }

  Widget _clientCard() {
    Widget? trailing;
    if (_isSearchingUser) {
      trailing = const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primaryBlue));
    } else if (_clientFoundInSAP) {
      trailing = Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(color: AppTheme.successColor.withOpacity(0.10), borderRadius: BorderRadius.circular(20)),
        child: const Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.verified_rounded, size: 13, color: AppTheme.successColor),
          SizedBox(width: 4),
          Text('Verificado', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppTheme.successColor)),
        ]),
      );
    }
    return Container(
      decoration: _cardDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader(
            _clientFoundInSAP ? Icons.verified_user_rounded : Icons.person_outline_rounded,
            'Datos del cliente',
            _clientFoundInSAP ? AppTheme.successColor : AppTheme.primaryBlue,
            trailing: trailing,
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
                if (_locationError != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8, left: 4),
                    child: Row(children: [
                      const Icon(Icons.error_outline_rounded, size: 14, color: AppTheme.errorColor),
                      const SizedBox(width: 6),
                      Expanded(child: Text(_locationError!, style: const TextStyle(fontSize: 11.5, color: AppTheme.errorColor, fontWeight: FontWeight.w600))),
                    ]),
                  ),
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
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() => _acceptTerms = !_acceptTerms);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _acceptTerms ? AppTheme.primaryBlue.withOpacity(0.04) : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: _acceptTerms ? AppTheme.primaryBlue.withOpacity(0.45) : AppTheme.borderColor,
            width: _acceptTerms ? 1.4 : 1,
          ),
        ),
        child: Row(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: 24, height: 24,
              decoration: BoxDecoration(
                color: _acceptTerms ? AppTheme.primaryBlue : Colors.white,
                borderRadius: BorderRadius.circular(7),
                border: Border.all(color: _acceptTerms ? AppTheme.primaryBlue : AppTheme.borderColor, width: 1.6),
              ),
              child: _acceptTerms ? const Icon(Icons.check_rounded, color: Colors.white, size: 16) : null,
            ),
            const SizedBox(width: 12),
            const Expanded(child: Text('Confirmo que los datos son correctos y autorizo el procesamiento del pedido.', style: TextStyle(fontSize: 13, color: AppTheme.textSecondary, height: 1.4, fontWeight: FontWeight.w500))),
          ],
        ),
      ),
    );
  }

  Widget _totalBar() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: AppTheme.primaryBlue.withOpacity(0.05), borderRadius: BorderRadius.circular(14), border: Border.all(color: AppTheme.primaryBlue.withOpacity(0.15))),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Total a pagar', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppTheme.darkBlue)),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 260),
                transitionBuilder: (c, a) => FadeTransition(
                  opacity: a,
                  child: SizeTransition(sizeFactor: a, axis: Axis.horizontal, axisAlignment: 1, child: c),
                ),
                child: Text(PriceUtils.formatPriceDisplay(_total),
                    key: ValueKey<double>(_total),
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: AppTheme.primaryBlue, letterSpacing: -0.5)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _confirmButton() {
    final on = _canProcess;
    return SizedBox(
      height: 56, width: double.infinity,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(15),
          onTap: on ? _processOrder : null,
          child: Ink(
            decoration: BoxDecoration(
              gradient: on
                  ? const LinearGradient(colors: [AppTheme.primaryBlue, AppTheme.secondaryBlue])
                  : null,
              color: on ? null : const Color(0xFFE5E7EB),
              borderRadius: BorderRadius.circular(15),
              boxShadow: on
                  ? [BoxShadow(color: AppTheme.primaryBlue.withOpacity(0.30), blurRadius: 16, offset: const Offset(0, 7))]
                  : null,
            ),
            child: Center(
              child: _isProcessingOrder
                  ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.6))
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.check_circle_rounded, color: on ? Colors.white : AppTheme.textSecondary, size: 20),
                        const SizedBox(width: 9),
                        Text('Confirmar pedido',
                            style: TextStyle(fontSize: 16.5, fontWeight: FontWeight.w800, color: on ? Colors.white : AppTheme.textSecondary, letterSpacing: 0.2)),
                      ],
                    ),
            ),
          ),
        ),
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
