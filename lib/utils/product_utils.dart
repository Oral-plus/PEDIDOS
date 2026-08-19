class ProductUtils {
  static String getTextureDescription(String texture, String? category) {
    switch (category?.toLowerCase()) {
      case 'cepillos':
        return texture == 'Media'
            ? 'Limpieza efectiva para uso diario'
            : 'Cuidado delicado para encías sensibles';
      case 'cremas':
        return texture == 'Estándar'
            ? 'Fórmula balanceada para uso diario'
            : texture == 'Concentrado'
                ? 'Fórmula concentrada de acción intensiva'
                : 'Fórmula premium con ingredientes selectos';
      case 'enjuagues':
        return texture == 'Regular'
            ? 'Protección estándar para uso diario'
            : 'Fórmula de acción intensiva';
      case 'sedas':
        return texture == 'Estándar'
            ? 'Grosor ideal para la mayoría de espacios'
            : 'Diseño ultra delgado para espacios reducidos';
      case 'universo niños':
        return texture.contains('3-6')
            ? 'Diseñado especialmente para niños pequeños'
            : 'Ideal para niños en edad escolar';
      case 'kits':
        return texture == 'Básico'
            ? 'Productos esenciales para higiene completa'
            : 'Kit completo con productos premium';
      default:
        return 'Opción especializada para tus necesidades';
    }
  }
}
