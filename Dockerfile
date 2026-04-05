# Supasoka Flutter web → static files, served on Railway ($PORT).
# https://docs.railway.app/deploy/dockerfiles

FROM ghcr.io/cirruslabs/flutter:stable AS build

WORKDIR /app

COPY pubspec.yaml pubspec.lock ./
RUN flutter pub get

COPY . .
RUN flutter build web --release

# Tiny static server; respects Railway PORT
FROM node:20-alpine
RUN npm install -g serve@14

WORKDIR /srv
COPY --from=build /app/build/web ./web

ENV NODE_ENV=production
# Railway injects PORT at runtime (e.g. 8080). Fallback 8080 for local runs.
EXPOSE 8080

# -s: SPA fallback; bind all interfaces for Railway
CMD ["sh", "-c", "serve -s web -l tcp://0.0.0.0:${PORT:-8080}"]
