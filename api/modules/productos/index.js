// Módulo de catálogo de productos (SAP + configuración + imágenes en BD).
// server.js lo inicia con las dependencias que ya tiene (sql, pools, auth).

const { AlmacenImagenes } = require("./imagenes")
const { RepositorioProductos } = require("./repositorio")
const { registrarRutas } = require("./rutas")

function crear({ sql, getSapPool, getPedidosPool, env, log }) {
  const imagenes = new AlmacenImagenes({ sql, getPool: getPedidosPool })
  const repositorio = new RepositorioProductos({ sql, getSapPool, getPedidosPool, imagenes, env, log })
  return {
    imagenes,
    repositorio,
    registrarRutas: (app, auth) => registrarRutas(app, { repositorio, imagenes, ...auth }),
    // Crea las tablas, carga las versiones de las imágenes y deja el primer
    // catálogo cargando en segundo plano
    async iniciar() {
      await repositorio.ensureTabla()
      await imagenes.ensureTabla()
      await imagenes.cargarVersiones()
      repositorio.refrescar().catch(() => {})
    },
  }
}

module.exports = { crear }
