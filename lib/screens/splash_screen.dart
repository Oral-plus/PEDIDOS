import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/api_easy_service.dart';
import '../utils/app_assets.dart';
import 'login_screen.dart';
import 'client_menu_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  // Paleta monocromática (blanco / negro / gris)
  static const Color _ink = Color(0xFF1F2937);
  static const Color _inkDeep = Color(0xFF0B1220);
  static const Color _gray = Color(0xFF6B7280);
  static const Color _track = Color(0xFFECECEE);

  late final AnimationController _intro; // entrada del logo (fade + scale)
  late final AnimationController _pulse; // halo que "respira" detrás del logo
  late final AnimationController _progress; // progreso determinado 0 → 1

  late final Animation<double> _fade;
  late final Animation<double> _scale;

  // Módulos que se "preparan" mientras carga (experiencia profesional de arranque).
  static const List<String> _modulos = [
    'Iniciando aplicación',
    'Conectando con el servidor',
    'Cargando catálogo de productos',
    'Sincronizando rutas y clientes',
    'Preparando tu portal',
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) precacheImage(AssetImage(AppAssets.logo), context);
    });

    _intro = AnimationController(
      duration: const Duration(milliseconds: 900),
      vsync: this,
    );
    _pulse = AnimationController(
      duration: const Duration(milliseconds: 1800),
      vsync: this,
    )..repeat(reverse: true);
    _progress = AnimationController(
      duration: const Duration(milliseconds: 2600),
      vsync: this,
    );

    _fade = CurvedAnimation(
        parent: _intro, curve: const Interval(0.0, 0.6, curve: Curves.easeOut));
    _scale = Tween<double>(begin: 0.90, end: 1.0).animate(CurvedAnimation(
        parent: _intro, curve: const Interval(0.05, 0.7, curve: Curves.easeOutBack)));

    _intro.forward();
    _initApp();
  }

  @override
  void dispose() {
    _intro.dispose();
    _pulse.dispose();
    _progress.dispose();
    super.dispose();
  }

  Future<void> _initApp() async {
    final api = ApiEasyService();
    // La barra avanza mientras se restaura la sesión y se preparan los módulos.
    await Future.wait([
      api.restoreSession(),
      _progress.forward().orCancel.catchError((_) {}),
    ]);
    if (!mounted) return;
    _goTo(api.hasSession ? const ClientMenuScreen() : const LoginScreen());
  }

  void _goTo(Widget screen) {
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => screen,
        transitionsBuilder: (_, a, __, c) =>
            FadeTransition(opacity: a, child: c),
        transitionDuration: const Duration(milliseconds: 450),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        systemNavigationBarColor: Colors.white,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
    );

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 36),
          child: Column(
            children: [
              const Spacer(flex: 5),
              // ---- Logo con halo que respira ----
              FadeTransition(
                opacity: _fade,
                child: ScaleTransition(
                  scale: _scale,
                  child: SizedBox(
                    width: 200,
                    height: 200,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        AnimatedBuilder(
                          animation: _pulse,
                          builder: (context, _) {
                            final t = Curves.easeInOut.transform(_pulse.value);
                            return Container(
                              width: 150 + 30 * t,
                              height: 150 + 30 * t,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: _ink.withOpacity(0.04 * (1 - t) + 0.02),
                              ),
                            );
                          },
                        ),
                        Container(
                          width: 132,
                          height: 132,
                          alignment: Alignment.center,
                          child: Image.asset(
                            AppAssets.logo,
                            width: 128,
                            height: 128,
                            fit: BoxFit.contain,
                            errorBuilder: (_, __, ___) => Icon(
                                Icons.medical_services_outlined,
                                size: 72,
                                color: _ink.withOpacity(0.6)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              FadeTransition(
                opacity: _fade,
                child: Text(
                  'Portal de Pedidos',
                  style: TextStyle(
                    color: _ink,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.2,
                  ),
                ),
              ),
              const Spacer(flex: 4),
              // ---- Progreso + módulo actual ----
              FadeTransition(
                opacity: _fade,
                child: AnimatedBuilder(
                  animation: _progress,
                  builder: (context, _) {
                    final v = _progress.value;
                    final idx = (v * _modulos.length)
                        .floor()
                        .clamp(0, _modulos.length - 1);
                    final pct = (v * 100).round();
                    return Column(
                      children: [
                        // Módulo actual (con check si ya se completó todo)
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            SizedBox(
                              width: 14,
                              height: 14,
                              child: v >= 1.0
                                  ? Icon(Icons.check_circle_rounded,
                                      size: 14, color: _ink)
                                  : CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor:
                                          AlwaysStoppedAnimation(_gray),
                                    ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              v >= 1.0 ? '¡Listo!' : _modulos[idx],
                              style: TextStyle(
                                color: _gray,
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0.1,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        // Barra de progreso determinada
                        ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: Container(
                            height: 6,
                            width: double.infinity,
                            color: _track,
                            alignment: Alignment.centerLeft,
                            child: FractionallySizedBox(
                              widthFactor: v.clamp(0.0, 1.0),
                              child: Container(
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(
                                    colors: [_ink, _inkDeep],
                                  ),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '$pct%',
                          style: TextStyle(
                            color: _gray.withOpacity(0.8),
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
              const Spacer(flex: 2),
              // ---- Pie de marca ----
              FadeTransition(
                opacity: _fade,
                child: Text(
                  'ORAL-PLUS  ·  SALUD Y BELLEZA EN TU SONRISA',
                  style: TextStyle(
                    color: _gray.withOpacity(0.6),
                    fontSize: 9.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.0,
                  ),
                ),
              ),
              const SizedBox(height: 18),
            ],
          ),
        ),
      ),
    );
  }
}
