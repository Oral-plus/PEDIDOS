const path = require("path")
const { netear } = require(path.join(process.cwd(), "modules", "cartera"))

const out = []
const ok = (nombre, condicion, extra) => out.push([nombre + (extra ? `  [${extra}]` : ""), !!condicion])

const doc = (docEntry, saldo, extra = {}) => ({
  docEntry,
  docNum: 1000 + docEntry,
  numFactura: `F-${docEntry}`,
  saldo,
  total: saldo,
  ...extra,
})
const abono = (docEntry, valor, saldoAlRegistrar, extra = {}) => ({
  numeroRecaudo: `REC-${docEntry}`,
  fecha: "2026-09-25 10:00:00",
  dias: 0,
  docEntry,
  abono: valor,
  saldoAlRegistrar,
  ...extra,
})

const r1 = netear([doc(1, 4000000)], [abono(1, 1000000, 4000000)])
ok("pago de 1 millon sobre una cartera de 4: la cartera queda en 3",
  r1.saldoSap === 4000000 && r1.pendientePorAplicar === 1000000 && r1.saldoNeto === 3000000 &&
  r1.documentos[0].saldoNeto === 3000000,
  `sap ${r1.saldoSap} neto ${r1.saldoNeto}`)

const r2 = netear([doc(1, 3000000)], [abono(1, 1000000, 4000000)])
ok("cuando SAP ya aplico el pago, deja de descontarse (no se resta dos veces)",
  r2.pendientePorAplicar === 0 && r2.saldoNeto === 3000000 && r2.pendientes.length === 0,
  `neto ${r2.saldoNeto}`)

const r3 = netear([doc(1, 200000)], [abono(1, 493660, 493660)])
ok("aplicacion parcial: SAP aplico 293.660 de 493.660, solo se descuenta lo que falta",
  r3.pendientePorAplicar === 200000 && r3.saldoNeto === 0,
  `pendiente ${r3.pendientePorAplicar}`)

const r4 = netear([doc(1, 138684)], [abono(1, 6601368, 6601368), abono(1, 6601368, 6601368)])
ok("dos recaudos sobre la misma factura: nunca deja la cartera en negativo",
  r4.pendientePorAplicar === 138684 && r4.saldoNeto === 0,
  `pendiente ${r4.pendientePorAplicar} neto ${r4.saldoNeto}`)

const r5 = netear([doc(1, 500000)], [abono(1, 900000, 500000)])
ok("un abono mayor que el saldo se topa en el saldo de la factura",
  r5.pendientePorAplicar === 500000 && r5.saldoNeto === 0)

const r6 = netear([doc(1, 400000)], [abono(99, 100000, 100000)])
ok("un abono de una factura que ya no esta abierta se ignora",
  r6.pendientePorAplicar === 0 && r6.saldoNeto === 400000 && r6.pendientes.length === 0)

const r7 = netear([doc(1, 667373)], [abono(1, 200000, 887373)])
ok("si SAP aplico mas de lo que registro el gestor, no queda pendiente",
  r7.pendientePorAplicar === 0 && r7.saldoNeto === 667373)

const r8 = netear([doc(1, 300010)], [abono(1, 200000, 500000)])
ok("si SAP aplico unos pesos de menos, el residuo no se muestra como pendiente",
  r8.pendientePorAplicar === 0 && r8.saldoNeto === 300010,
  `residuo ignorado, neto ${r8.saldoNeto}`)

const r8b = netear([doc(1, 802591)], [abono(1, 802591, 802592)])
ok("si la factura no se movio, el pago sigue pendiente aunque la foto difiera en un peso",
  r8b.pendientePorAplicar === 802590 && r8b.saldoNeto === 1)

const r9 = netear([doc(1, 1000000), doc(2, 500000)], [abono(1, 300000, 1000000), abono(2, 500000, 500000)])
ok("varias facturas: cada una se netea por separado y el total cuadra",
  r9.saldoSap === 1500000 && r9.pendientePorAplicar === 800000 && r9.saldoNeto === 700000 &&
  r9.documentos[0].saldoNeto === 700000 && r9.documentos[1].saldoNeto === 0,
  `neto ${r9.saldoNeto}`)

const r10 = netear([doc(1, 100000)], [abono(1, 100000, 100000, { dias: 9 })], { diasAviso: 5 })
const r11 = netear([doc(1, 100000)], [abono(1, 100000, 100000, { dias: 2 })], { diasAviso: 5 })
ok("un pago que lleva demasiados dias sin llegar a SAP queda marcado",
  r10.pendientes[0].demorado === true && r11.pendientes[0].demorado === false)

const r12 = netear([], [abono(1, 100000, 100000)])
const r13 = netear([doc(1, 100000)], [])
ok("sin facturas o sin recaudos no se rompe",
  r12.saldoNeto === 0 && r12.pendientePorAplicar === 0 && r13.saldoNeto === 100000)

const r14 = netear([doc(1, 1000000)], [abono(1, 1000000, 1000000)])
ok("el detalle dice que recaudo esta pendiente y por cuanto",
  r14.pendientes.length === 1 && r14.pendientes[0].numeroRecaudo === "REC-1" &&
  r14.pendientes[0].pendiente === 1000000 && r14.pendientes[0].numFactura === "F-1")

ok("no se altera el saldo original de SAP que viaja al cliente",
  r1.documentos[0].saldo === 4000000 && r1.saldoSap === 4000000)

for (const [nombre, bien] of out) process.stdout.write((bien ? "OK    " : "FALLA ") + nombre + "\n")
const todo = out.every(([, bien]) => bien)
process.stdout.write("\n" + (todo ? "CARTERA (UNIDAD) OK\n" : "HAY FALLOS EN CARTERA (UNIDAD)\n"))
process.exit(todo ? 0 : 1)
