import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'screens/splash_screen.dart';
import 'screens/informacion_visita_screen.dart';
import 'utils/app_assets.dart';
import 'utils/theme.dart';
import 'providers/session_provider.dart';
import 'providers/cart_provider.dart';
import 'providers/visita_activa_provider.dart';
// © 2025 Autor: SKY - Todos los derechos reservados.

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  rootBundle.load(AppAssets.logo).ignore();
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => SessionProvider()),
        ChangeNotifierProvider(create: (_) => CartProvider()),
        ChangeNotifierProvider(create: (_) => VisitaActivaProvider()),
      ],
      child: const SkyPagosApp(),
    ),
  );
}

class SkyPagosApp extends StatelessWidget {
  const SkyPagosApp({super.key});

  @override
  Widget build(BuildContext context) {
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarIconBrightness: Brightness.dark,
        systemNavigationBarDividerColor: Colors.transparent,
      ),
    );
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

    return MaterialApp(
      title: 'ORAL-PLUS Pedidos',
      theme: AppTheme.lightTheme,
      debugShowCheckedModeBanner: false,
      navigatorKey: navigatorKey,
      home: const SplashScreen(),
      builder: (context, child) {
        // Superpone el cronómetro flotante de la visita en curso sobre
        // cualquier pantalla, para recordar que hay una visita abierta.
        return Stack(
          textDirection: TextDirection.ltr,
          children: [
            if (child != null) child,
            const _CronometroFlotante(),
          ],
        );
      },
    );
  }
}

/// Píldora flotante con el cronómetro de la visita en curso.
class _CronometroFlotante extends StatelessWidget {
  const _CronometroFlotante();

  @override
  Widget build(BuildContext context) {
    final v = context.watch<VisitaActivaProvider>();
    // Se oculta cuando no hay visita o cuando el usuario ya está en la pantalla
    // de la visita (allí se ve el cronómetro grande).
    if (!v.activa || v.enPantallaVisita) return const SizedBox.shrink();

    final topInset = MediaQuery.of(context).padding.top;

    return Positioned(
      top: topInset + 8,
      left: 0,
      right: 0,
      child: SafeArea(
        bottom: false,
        child: Center(
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(24),
              onTap: () {
                if (v.cliente == null || v.ruta == null) return;
                navigatorKey.currentState?.push(
                  MaterialPageRoute(
                    builder: (_) => InformacionVisitaScreen(
                      cliente: v.cliente!,
                      ruta: v.ruta!,
                    ),
                  ),
                );
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF374151), Color(0xFF111827)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.35),
                      blurRadius: 16,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.timer_rounded, color: Colors.white, size: 18),
                  const SizedBox(width: 8),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(mainAxisSize: MainAxisSize.min, children: [
                        const Text('Visita en curso',
                            style: TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.w700, letterSpacing: 0.2)),
                        const SizedBox(width: 8),
                        Text(v.textoTiempo,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w900,
                              fontFeatures: [FontFeature.tabularFigures()],
                            )),
                      ]),
                      SizedBox(
                        width: 180,
                        child: Text(
                          v.nombreCliente,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.9),
                            fontSize: 10.5,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 6),
                  const Icon(Icons.chevron_right_rounded, color: Colors.white, size: 18),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
