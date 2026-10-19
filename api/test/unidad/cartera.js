const path = require("path")
const { netear, revisarCruce } = require(path.join(process.cwd(), "modules", "cartera"))

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

// --- La factura sigue cobrable hasta que lo recaudado la cubra -------------
// Lo recaudado sale de dbo.recaudos, sin ventana de tiempo.

const n1 = netear([doc(1, 500000)], [abono(1, 200000, 500000, { dias: 90 })])
ok("un recaudo de hace 3 meses sigue contando: la factura no se vuelve a ofrecer entera",
  n1.documentos[0].totalRecaudado === 200000 && n1.documentos[0].saldoNeto === 300000,
  `recaudado ${n1.documentos[0].totalRecaudado} neto ${n1.documentos[0].saldoNeto}`)

const n2 = netear([doc(1, 500000)], [abono(1, 200000, 500000), abono(1, 150000, 500000)])
ok("dos abonos parciales se suman y queda cobrable lo que falta",
  n2.documentos[0].totalRecaudado === 350000 && n2.documentos[0].porCobrar === 150000 &&
  n2.documentos[0].saldoNeto === 150000,
  `recaudado ${n2.documentos[0].totalRecaudado} falta ${n2.documentos[0].porCobrar}`)

const n3 = netear([doc(1, 500000)], [abono(1, 300000, 500000), abono(1, 200000, 500000)])
ok("solo cuando lo recaudado iguala la factura deja de estar cobrable",
  n3.documentos[0].totalRecaudado === 500000 && n3.documentos[0].porCobrar === 0 &&
  n3.documentos[0].saldoNeto === 0)

const n4 = netear([doc(1, 300000, { total: 1000000 })], [abono(1, 300000, 300000)])
ok("si SAP ya traia parte pagada, basta recaudar lo que debia, no el total de la factura",
  n4.documentos[0].porCobrar === 0 && n4.documentos[0].saldoNeto === 0,
  `falta ${n4.documentos[0].porCobrar}`)

const n5 = netear([doc(1, 450000)], [])
ok("sin recaudos, no hay nada recaudado y se debe toda la factura",
  n5.documentos[0].totalRecaudado === 0 && n5.documentos[0].porCobrar === 450000)

const n6 = netear([doc(1, 100000)], [abono(1, 200000, 500000)])
ok("si el cliente pago aparte, no reaparece como cobrable la plata ya recaudada",
  n6.documentos[0].saldoNeto === 100000 && n6.documentos[0].totalRecaudado === 200000,
  `neto ${n6.documentos[0].saldoNeto}`)

// --- No se puede aplicar mas plata de la que el cliente entrego ------------
// Todos los casos salen de recaudos reales que si se guardaron asi.

const c1 = revisarCruce({ totalRecaudo: 200000, totalAplicado: 498828, documentos: [{ docEntry: 1, abono: 498828 }] })
ok("el caso real: recibe 200.000 y cruza la factura completa de 498.828",
  c1.ok === false && c1.exceso === 298828, `exceso ${c1.exceso}`)

const c2 = revisarCruce({ totalRecaudo: 200000, totalAplicado: 200000, documentos: [{ docEntry: 1, abono: 200000 }] })
ok("un abono parcial bien hecho si pasa: aplica solo lo que recibio",
  c2.ok === true && c2.exceso === 0)

const c3 = revisarCruce({ totalRecaudo: 498828, totalAplicado: 498828, documentos: [{ docEntry: 1, abono: 498828 }] })
ok("pagar la factura completa sigue siendo valido", c3.ok === true)

const c4 = revisarCruce({ totalRecaudo: 200000, totalAplicado: 200000, documentos: [{ docEntry: 1, abono: 498828 }] })
ok("si la cabecera cuadra pero el detalle se pasa, manda el detalle",
  c4.ok === false && c4.aplicado === 498828, `aplicado ${c4.aplicado}`)

const c5 = revisarCruce({ totalRecaudo: 200000, totalAplicado: 498828, documentos: [{ docEntry: 1, abono: 200000 }] })
ok("si el detalle cuadra pero la cabecera se pasa, tampoco entra",
  c5.ok === false && c5.aplicado === 498828)

const c6 = revisarCruce({ totalRecaudo: 383008, totalAplicado: 383008.4, documentos: [{ docEntry: 1, abono: 383008.4 }] })
ok("una diferencia de centavos es redondeo, no se bloquea", c6.ok === true)

const c7 = revisarCruce({
  totalRecaudo: 1581420,
  totalAplicado: 1987774,
  documentos: [{ docEntry: 1, abono: 987774 }, { docEntry: 2, abono: 1000000 }],
})
ok("varias facturas que entre todas se pasan de lo recibido",
  c7.ok === false && c7.exceso === 406354, `exceso ${c7.exceso}`)

const c8 = revisarCruce({ totalRecaudo: 0, totalAplicado: 0, documentos: [{ docEntry: 1, abono: 500000 }] })
ok("sin declarar cuanto recibio no se puede aplicar nada", c8.ok === false)

const c9 = revisarCruce({ totalRecaudo: "200000", totalAplicado: "498828", documentos: [{ docEntry: 1, abono: "498828" }] })
ok("los importes en texto se leen igual (la app los manda asi)",
  c9.ok === false && c9.exceso === 298828)

const c10 = revisarCruce({ totalRecaudo: 200000, totalAplicado: 150000, documentos: [{ docEntry: 1, abono: 150000 }] })
ok("sobra plata del recaudo: eso es legitimo, queda de saldo", c10.ok === true)

const c11 = revisarCruce({})
ok("un cuerpo vacio no revienta", c11.ok === true && c11.aplicado === 0)

const c12 = revisarCruce({ totalRecaudo: 200000, totalAplicado: 498828, documentos: "no es una lista" })
ok("documentos mal formados no abren la puerta", c12.ok === false)

for (const [nombre, bien] of out) process.stdout.write((bien ? "OK    " : "FALLA ") + nombre + "\n")
const todo = out.every(([, bien]) => bien)
process.stdout.write("\n" + (todo ? "CARTERA (UNIDAD) OK\n" : "HAY FALLOS EN CARTERA (UNIDAD)\n"))
process.exit(todo ? 0 : 1)
