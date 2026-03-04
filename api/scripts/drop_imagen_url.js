require('dotenv').config();
const sql = require('mssql');

const config = {
  server: process.env.DB_SERVER || '192.168.2.244',
  database: 'Pedidos',
  user: process.env.DB_USER || 'sa',
  password: process.env.DB_PASSWORD || 'Sky2022*!',
  port: parseInt(process.env.DB_PORT || '1433', 10),
  options: {
    encrypt: false,
    trustServerCertificate: true,
    enableArithAbort: true,
  },
};




