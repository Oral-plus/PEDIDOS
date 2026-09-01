
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
    async iniciar() {
      await repositorio.ensureTabla()
      await imagenes.ensureTabla()
      await imagenes.cargarVersiones()
      repositorio.refrescar().catch(() => {})
    },
  }
}

module.exports = { crear }
