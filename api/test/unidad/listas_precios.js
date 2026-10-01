const path = require("path")
const { armar, preciosEn } = require(path.join(process.cwd(), "modules", "productos", "listas"))

const out = []
const ok = (nombre, condicion, extra) => out.push([nombre + (extra ? `  [${extra}]` : ""), !!condicion])

const item = (codigo, nombre, precios, extra = {}) => ({
  codigo,
  nombre,
  grupoNombre: "PT-CEPILLOS NACIONAL",
  precios,
  ...extra,
})
const proyectar = (i) => ({ codigo: i.codigo, nombre: i.nombre, categoria: "Cepillos" })

const LISTAS = [
  { id: 1, nombre: "General", clientes: 30 },
  { id: 2, nombre: "Mayorista", clientes: 12 },
]

const catalogo = [
  item("B", "Cepillo B", { 1: 5000, 2: 4200 }),
  item("A", "Cepillo A", { 1: 3000, 2: 2500, 9: 1000 }),
  item("C", "Solo mayorista", { 2: 7000 }),
  item("D", "Sin precio en mis listas", { 9: 900 }),
  item("E", "Oculto", { 1: 1000 }, { oculto: true }),
  item("F", "Precio en cero", { 1: 0, 2: 0 }),
]

const r = armar({ items: catalogo, listas: LISTAS, proyectar, ocultar: (i) => i.oculto === true })

ok("cada producto trae su precio en cada lista del gestor",
  r.productos.find((p) => p.codigo === "A").precios[1] === 3000 &&
    r.productos.find((p) => p.codigo === "A").precios[2] === 2500,
  JSON.stringify(r.productos.find((p) => p.codigo === "A").precios))

ok("los precios de listas que no son del gestor no viajan",
  r.productos.find((p) => p.codigo === "A").precios[9] === undefined)

ok("un producto sin precio en ninguna de mis listas no aparece",
  !r.productos.some((p) => p.codigo === "D"))

ok("un precio en cero no cuenta como precio",
  !r.productos.some((p) => p.codigo === "F"))

ok("lo que Soporte oculta no se muestra", !r.productos.some((p) => p.codigo === "E"))

ok("un producto que solo esta en una lista si aparece, con esa sola",
  r.productos.find((p) => p.codigo === "C") &&
    Object.keys(r.productos.find((p) => p.codigo === "C").precios).join() === "2")

ok("los productos salen ordenados por categoria y nombre",
  r.productos.map((p) => p.codigo).join() === "A,B,C",
  r.productos.map((p) => p.codigo).join())

ok("cada lista dice cuantos productos tiene",
  r.listas[0].productos === 2 && r.listas[1].productos === 3,
  r.listas.map((l) => `${l.nombre}:${l.productos}`).join(" · "))

ok("la lista conserva el nombre y cuantos clientes la usan",
  r.listas[0].nombre === "General" && r.listas[0].clientes === 30)

ok("el total es la cantidad de productos, no de precios", r.total === 3, `${r.total}`)

const sinPrecios = armar({
  items: [item("X", "X", { 7: 100 })],
  listas: LISTAS,
  proyectar,
})
ok("una lista sin un solo precio no se muestra",
  sinPrecios.listas.length === 0 && sinPrecios.productos.length === 0)

const vacio = armar({ items: [], listas: [], proyectar })
ok("un gestor sin clientes no rompe la pantalla",
  vacio.listas.length === 0 && vacio.productos.length === 0 && vacio.total === 0)

ok("preciosEn ignora nulos, textos y negativos",
  JSON.stringify(preciosEn({ precios: { 1: null, 2: "x", 3: -5, 4: 100 } }, [1, 2, 3, 4])) === '{"4":100}')

ok("un articulo sin precios no revienta", JSON.stringify(preciosEn({}, [1])) === "{}")

for (const [nombre, bien] of out) process.stdout.write((bien ? "OK    " : "FALLA ") + nombre + "\n")
const todo = out.every(([, bien]) => bien)
process.stdout.write("\n" + (todo ? "LISTAS DE PRECIOS (UNIDAD) OK\n" : "HAY FALLOS EN LISTAS DE PRECIOS\n"))
process.exit(todo ? 0 : 1)
