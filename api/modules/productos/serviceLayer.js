// Cliente del Service Layer de SAP Business One (OData sobre HTTPS).
// Mantiene una sesión (cookie B1SESSION) compartida entre peticiones, vuelve a
// iniciar sesión cuando vence y recorre las páginas de una consulta.

const https = require("https")
const { URL } = require("url")

class ServiceLayer {
  constructor({ url, companyDb, user, password, tlsInsecure = false, timeoutMs = 30000, pageSize = 200 }) {
    this.base = (url || "").replace(/\/+$/, "")
    this.companyDb = companyDb
    this.user = user
    this.password = password
    this.timeoutMs = timeoutMs
    this.pageSize = pageSize
    this.cookies = null
    this.sesionDesde = 0
    this.iniciando = null
    this.agent = new https.Agent({ keepAlive: true, maxSockets: 4, rejectUnauthorized: !tlsInsecure })
  }

  get configurado() {
    return Boolean(this.base && this.companyDb && this.user && this.password)
  }

  // Inicia sesión una sola vez aunque lleguen varias peticiones a la vez
  login() {
    if (this.iniciando) return this.iniciando
    this.iniciando = this._peticion("POST", "/Login", {
      CompanyDB: this.companyDb,
      UserName: this.user,
      Password: this.password,
    }, false)
      .then((r) => {
        if (r.status !== 200) {
          throw new Error(`Login Service Layer: HTTP ${r.status} ${extraerMensaje(r.body)}`)
        }
        this.cookies = r.cookies
        this.sesionDesde = Date.now()
        return r.body
      })
      .finally(() => {
        this.iniciando = null
      })
    return this.iniciando
  }

  async get(path) {
    if (!this.cookies) await this.login()
    let r = await this._peticion("GET", path, null, true)
    if (r.status === 401) {
      // Sesión vencida: se renueva y se reintenta una vez
      this.cookies = null
      await this.login()
      r = await this._peticion("GET", path, null, true)
    }
    if (r.status !== 200) {
      throw new Error(`Service Layer GET ${path.split("?")[0]}: HTTP ${r.status} ${extraerMensaje(r.body)}`)
    }
    return r.body
  }

  // Devuelve todos los registros de una consulta siguiendo odata.nextLink
  async getAll(path) {
    const registros = []
    let siguiente = path
    while (siguiente) {
      const cuerpo = await this.get(siguiente)
      registros.push(...(cuerpo.value || []))
      const enlace = cuerpo["odata.nextLink"] || cuerpo["@odata.nextLink"]
      siguiente = enlace ? enlace.replace(/^.*\/b1s\/v\d+\//, "/") : null
    }
    return registros
  }

  _peticion(metodo, path, cuerpo, conSesion) {
    return new Promise((resolve, reject) => {
      const destino = new URL(this.base + (path.startsWith("/") ? path : `/${path}`))
      const datos = cuerpo ? JSON.stringify(cuerpo) : null
      const headers = {
        Accept: "application/json",
        Prefer: `odata.maxpagesize=${this.pageSize}`,
      }
      if (datos) {
        headers["Content-Type"] = "application/json"
        headers["Content-Length"] = Buffer.byteLength(datos)
      }
      if (conSesion && this.cookies) headers.Cookie = this.cookies
      const req = https.request(
        {
          host: destino.hostname,
          port: destino.port || 443,
          path: destino.pathname + destino.search,
          method: metodo,
          headers,
          agent: this.agent,
          timeout: this.timeoutMs,
        },
        (res) => {
          let b = ""
          res.setEncoding("utf8")
          res.on("data", (c) => (b += c))
          res.on("end", () => {
            let body = null
            try {
              body = b ? JSON.parse(b) : null
            } catch (_) {
              body = { raw: b.slice(0, 200) }
            }
            const setCookie = res.headers["set-cookie"] || []
            const cookies = setCookie.map((c) => c.split(";")[0]).join("; ")
            resolve({ status: res.statusCode, body, cookies: cookies || null })
          })
        },
      )
      req.on("timeout", () => req.destroy(new Error("timeout")))
      req.on("error", reject)
      if (datos) req.write(datos)
      req.end()
    })
  }
}

function extraerMensaje(body) {
  const m = body && body.error && body.error.message
  return m ? (m.value || JSON.stringify(m)) : ""
}

module.exports = { ServiceLayer }
