// Ventana de seguridad contra pedidos dobles.
//
// Un gestor que toca dos veces, o que no ve la confirmacion y vuelve a enviar,
// termina metiendo el mismo pedido dos veces. La regla: tras registrar un
// pedido a un cliente, ese mismo gestor no puede registrarle otro hasta que
// pase la ventana.
//
// Esto es el nucleo y no habla con la base: recibe el ultimo pedido y decide.
// Quien lo consulta es server.js y quien lo muestra es la app.

const MINUTOS_POR_DEFECTO = 5
const CODIGO = "PEDIDO_RECIENTE"

/// Minutos de espera configurados, con tope sensato.
function ventanaMinutos(env = {}) {
  const n = Number.parseFloat(env.PEDIDO_VENTANA_MIN)
  if (!Number.isFinite(n) || n <= 0) return MINUTOS_POR_DEFECTO
  return Math.min(n, 120)
}

/// Como se le dice al gestor cuanto falta, sin segundos sueltos que confundan.
function textoEspera(segundos) {
  if (segundos <= 60) return `${Math.max(1, segundos)} segundo(s)`
  const min = Math.floor(segundos / 60)
  const resto = segundos % 60
  if (resto === 0) return `${min} minuto(s)`
  return `${min} minuto(s) y ${resto} segundo(s)`
}

/// Decide si el pedido nuevo se bloquea.
///
/// [ultimo] es el ultimo pedido de ese gestor a ese cliente (o null si no hay),
/// con su `fecha`. [ahora] y [minutos] se inyectan para poder probarlo.
function evaluar({ ultimo, ahora = new Date(), minutos = MINUTOS_POR_DEFECTO } = {}) {
  if (!ultimo || !ultimo.fecha) return { bloquea: false }

  const fecha = ultimo.fecha instanceof Date ? ultimo.fecha : new Date(ultimo.fecha)
  if (Number.isNaN(fecha.getTime())) return { bloquea: false }

  const transcurridos = Math.floor((ahora.getTime() - fecha.getTime()) / 1000)
  const ventana = Math.round(minutos * 60)

  // Un reloj desfasado no puede dejar al gestor sin trabajar.
  if (transcurridos < 0 || transcurridos >= ventana) return { bloquea: false }

  const restantes = ventana - transcurridos
  const numero = (ultimo.numeroPedido || "").toString().trim()
  return {
    bloquea: true,
    codigo: CODIGO,
    segundosRestantes: restantes,
    ventanaMinutos: minutos,
    pedidoPrevio: {
      numeroPedido: numero || null,
      fecha: ultimo.fechaTexto || null,
      total: ultimo.total == null ? null : Number(ultimo.total),
    },
    message:
      `Ya le registraste un pedido a este cliente${numero ? ` (${numero})` : ""} hace menos de ` +
      `${minutos} minuto(s). Espera ${textoEspera(restantes)} antes de registrarle otro.`,
  }
}

module.exports = { evaluar, ventanaMinutos, textoEspera, CODIGO, MINUTOS_POR_DEFECTO }
