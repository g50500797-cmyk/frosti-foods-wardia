# Wardia Deployment

## Local fallback

When `DATABASE_URL` is not set, the API uses `backend/data/wardia.json` so the current local demo keeps working.

## PostgreSQL and stable server

1. Install Docker Desktop on the server.
2. Change the passwords in `docker-compose.yml` before deployment.
3. Build the current web release with `flutter build web --release`.
4. Start the stack from the project root:

```powershell
docker compose up -d --build
```

The API is exposed on port `5521` and the web server on port `8080`.

## HTTPS

Put a domain and TLS certificate in front of port `8080` using a managed reverse proxy or Nginx/Certbot. The Flutter client automatically uses the same HTTPS origin for `/api` when served on standard HTTPS ports.

Do not expose PostgreSQL directly to the internet. Keep it on the internal Docker network and rotate `JWT_SECRET`, database passwords, and the seeded admin password before production use.

## Accounts

- System Admin: `admin@wardia.app` / `Admin@123456`
- Shift Manager: `manager@wardia.app` / `123456`

Change both passwords before real factory use.
