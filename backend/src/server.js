require('dotenv').config({ path: require('node:path').resolve(__dirname, '..', '.env') });

const isProduction = process.env.NODE_ENV === 'production';
const missingProductionConfig = ['DATABASE_URL', 'JWT_SECRET'].filter((key) => !String(process.env[key] || '').trim());

if (isProduction && missingProductionConfig.length) {
  console.error(`Production configuration is incomplete: missing ${missingProductionConfig.join(', ')}`);
  process.exit(1);
}

if (process.env.DATABASE_URL) {
  require('./server-postgres');
} else {
  require('./server-json');
}
