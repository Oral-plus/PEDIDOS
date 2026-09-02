const { spawnSync } = require("child_process")
const path = require("path")

const PRUEBAS = ["seguridad.js", "sesion.js", "catalogo.js", "pagos.js", "insercion_completa.js", "atomicidad.js"]
const raizApi = path.join(__dirname, "..", "..")
let fallos = 0

for (const p of PRUEBAS) {
  process.stdout.write(`\n===== ${p}\n`)
  const r = spawnSync(process.execPath, [path.join(__dirname, p)], {
    cwd: raizApi,
    stdio: "inherit",
    env: { ...process.env, NODE_OPTIONS: "--no-deprecation" },
  })
  if (r.status !== 0) fallos++
}

process.stdout.write(`\n${fallos === 0 ? "TODAS LAS SUITES OK" : `${fallos} suite(s) con fallos`}\n`)
process.exit(fallos === 0 ? 0 : 1)
