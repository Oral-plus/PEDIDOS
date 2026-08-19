const sql = require('mssql');

const dbConfig = {
  server: process.env.DB_SERVER,
  database: process.env.DB_DATABASE,
  user: process.env.DB_USER,
  password: process.env.DB_PASSWORD,
  port: parseInt(process.env.DB_PORT, 10) || 1433,
  connectionTimeout: 15000,
  requestTimeout: 15000,
  options: {
    encrypt: process.env.DB_ENCRYPT === 'true',
    trustServerCertificate: process.env.DB_TRUST_CERT === 'true',
  },
  pool: {
    max: 10,
    min: 0,
    idleTimeoutMillis: 30000,
  },
};

const sapConfig = {
  server: process.env.SAP_SERVER,
  database: process.env.SAP_DATABASE,
  user: process.env.SAP_USER,
  password: process.env.SAP_PASSWORD,
  options: {
    encrypt: process.env.SAP_ENCRYPT === 'true',
    trustServerCertificate: process.env.SAP_TRUST_CERT === 'true',
  },
  pool: {
    max: 10,
    min: 0,
    idleTimeoutMillis: 30000,
  },
};

const ordersConfig = {
  server: process.env.ORDERS_SERVER,
  database: process.env.ORDERS_DATABASE,
  user: process.env.ORDERS_USER,
  password: process.env.ORDERS_PASSWORD,
  options: {
    encrypt: process.env.ORDERS_ENCRYPT === 'true',
    trustServerCertificate: process.env.ORDERS_TRUST_CERT === 'true',
  },
  pool: {
    max: 10,
    min: 0,
    idleTimeoutMillis: 30000,
  },
};

let dbPool = null;
let sapPool = null;
let ordersPool = null;

async function getDbPool() {
  if (!dbPool) {
    dbPool = await new sql.ConnectionPool(dbConfig).connect();
    console.log('Conectado a base de datos Ruta');
  }
  return dbPool;
}

async function getSapPool() {
  if (!sapPool) {
    sapPool = await new sql.ConnectionPool(sapConfig).connect();
    console.log('Conectado a base de datos SAP');
  }
  return sapPool;
}

async function getOrdersPool() {
  if (!ordersPool) {
    ordersPool = await new sql.ConnectionPool(ordersConfig).connect();
    console.log('Conectado a base de datos Pedidos');
  }
  return ordersPool;
}

async function closeAll() {
  if (dbPool) {
    await dbPool.close();
    dbPool = null;
  }
  if (sapPool) {
    await sapPool.close();
    sapPool = null;
  }
  if (ordersPool) {
    await ordersPool.close();
    ordersPool = null;
  }
}

module.exports = { sql, getDbPool, getSapPool, getOrdersPool, closeAll };
