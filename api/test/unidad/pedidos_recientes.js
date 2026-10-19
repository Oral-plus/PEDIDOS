const path = require("path")
const { evaluar, ventanaMinutos, textoEspera, MINUTOS_POR_DEFECTO } = require(
  path.join(process.cwd(), "modules", "pedidos_recientes"),
)

const out = []
const ok = (nombre, condicion, extra) => out.push([nombre + (extra ? `  [${extra}]` : ""), !!condicion])

const AHORA = new Date("2026-10-15T10:00:00Z")
const haceSegundos = (s) => new Date(AHORA.getTime() - s * 1000)
const ultimo = (s, extra = {}) => ({ fecha: haceSegundos(s), numeroPedido: "PED-77", total: 150000, ...extra })

const r1 = evaluar({ ultimo: ultimo(60), ahora: AHORA, minutos: 5 })
ok("un pedido al mismo cliente hace un minuto se bloquea",
  r1.bloquea === true && r1.codigo === "PEDIDO_RECIENTE" && r1.segundosRestantes === 240,
  `faltan ${r1.segundosRestantes}s`)

const r2 = evaluar({ ultimo: ultimo(300), ahora: AHORA, minutos: 5 })
ok("justo al cumplirse la ventana ya deja pedir", r2.bloquea === false)

const r3 = evaluar({ ultimo: ultimo(301), ahora: AHORA, minutos: 5 })
ok("pasada la ventana deja pedir", r3.bloquea === false)

const r4 = evaluar({ ultimo: ultimo(1), ahora: AHORA, minutos: 5 })
ok("el doble toque, a un segundo, se bloquea con casi toda la ventana por delante",
  r4.bloquea === true && r4.segundosRestantes === 299)

ok("sin pedidos previos no se bloquea nada",
  evaluar({ ultimo: null, ahora: AHORA, minutos: 5 }).bloquea === false)

ok("un pedido sin fecha no bloquea: ante la duda, se deja trabajar",
  evaluar({ ultimo: { numeroPedido: "X" }, ahora: AHORA, minutos: 5 }).bloquea === false)

ok("una fecha ilegible tampoco bloquea",
  evaluar({ ultimo: { fecha: "no es fecha" }, ahora: AHORA, minutos: 5 }).bloquea === false)

ok("un reloj adelantado no deja al gestor sin trabajar",
  evaluar({ ultimo: ultimo(-120), ahora: AHORA, minutos: 5 }).bloquea === false)

const r5 = evaluar({ ultimo: ultimo(30), ahora: AHORA, minutos: 5 })
ok("el aviso dice el numero del pedido anterior y cuanto falta",
  /PED-77/.test(r5.message) && /4 minuto/.test(r5.message),
  r5.message)

ok("el pedido previo viaja para que el gestor lo reconozca",
  r5.pedidoPrevio.numeroPedido === "PED-77" && r5.pedidoPrevio.total === 150000)

const r6 = evaluar({ ultimo: ultimo(30, { numeroPedido: "  " }), ahora: AHORA, minutos: 5 })
ok("si el pedido previo no tiene numero, el aviso sigue teniendo sentido",
  r6.bloquea === true && r6.pedidoPrevio.numeroPedido === null && !/\(\)/.test(r6.message),
  r6.message)

const r7 = evaluar({ ultimo: ultimo(30), ahora: AHORA, minutos: 0.5 })
ok("una ventana corta se respeta igual", r7.bloquea === false, `${r7.bloquea}`)

ok("sin configurar, la ventana es de 5 minutos", ventanaMinutos({}) === MINUTOS_POR_DEFECTO)
ok("la ventana se puede configurar por entorno", ventanaMinutos({ PEDIDO_VENTANA_MIN: "10" }) === 10)
ok("un valor absurdo no rompe la configuracion",
  ventanaMinutos({ PEDIDO_VENTANA_MIN: "abc" }) === 5 &&
    ventanaMinutos({ PEDIDO_VENTANA_MIN: "-3" }) === 5 &&
    ventanaMinutos({ PEDIDO_VENTANA_MIN: "99999" }) === 120)

ok("el tiempo se dice como lo diria una persona",
  textoEspera(45) === "45 segundo(s)" &&
    textoEspera(120) === "2 minuto(s)" &&
    textoEspera(135) === "2 minuto(s) y 15 segundo(s)")

for (const [nombre, bien] of out) process.stdout.write((bien ? "OK    " : "FALLA ") + nombre + "\n")
const todo = out.every(([, bien]) => bien)
process.stdout.write("\n" + (todo ? "PEDIDOS RECIENTES (UNIDAD) OK\n" : "HAY FALLOS EN PEDIDOS RECIENTES\n"))
process.exit(todo ? 0 : 1)
