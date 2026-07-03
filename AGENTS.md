# Repository Agent Guide

## Project Overview

This repository contains the NexaCore KYC stack:

- `backend/`: Spring Boot 3.5 Java 21 API, Maven project, PostgreSQL-backed multi-datasource application.
- `frontend/`: Angular 19 KYC user interface.
- `privilege-frontend/`: Angular 19 privilege-management user interface.
- `frontend-libs/`: shared Angular libraries used by the frontends.
- `keycloak2/`: Keycloak 26 local integration and custom user-storage SPI for federating NexaCore users.
- `v3/`: versioned project snapshot. Do not change this unless the task explicitly targets `v3`.
- `uploads/`, `node_modules/`, Angular `dist/` and `.angular/` folders are generated/runtime artifacts.

The active application is wired by the root `docker-compose.yml`.

## Source Control Notes

- The root `.gitignore` intentionally ignores large application folders and generated artifacts. Check `git status --short` before and after edits.
- `keycloak2/` is currently untracked in this working tree. Treat existing contents as user work and do not remove or overwrite them casually.
- `frontend-libs/` contains its own `.git` directory. Avoid modifying nested repository metadata.
- Do not commit local secrets. Existing local values in `.env`, `application.properties`, and Compose files may be development defaults, but new sensitive values should be environment-driven.

## Backend

- Main build file: `backend/pom.xml`
- Java version: 21
- Framework: Spring Boot 3.5
- Main concerns: auth, KYC, GIS, log datasources; OAuth2 resource server; Keycloak SSO mode; MinIO/file storage; Redis cache.

Useful commands:

```bash
cd backend
mvn test
mvn spring-boot:run
```

When changing backend code:

- Keep package and module boundaries under `com.nexacore`.
- Prefer Spring configuration properties and environment variables over hard-coded deployment values.
- Validate auth changes against both local JWT behavior and SSO/Keycloak configuration where relevant.
- Do not broaden CORS, token, or datasource behavior without an explicit reason.

Database table naming convention:

- Use explicit `@Table(name = "...")` mappings for persistent entities.
- Prefix tables with the owning module code: `auth_`, `kyc_`, `gis_`, `log_`.
- Prefix join tables too, for example `auth_user_roles` and `auth_role_privileges`.
- Do not prefix column names solely for module ownership; keep relationship columns readable, such as `user_id`, `role_id`, and `person_id`.
- Every persistent table in every module, submodule, service, and feature must include `created_by` and `updated_by` columns in addition to timestamp audit fields such as `created_at` and `updated_at`.
- `created_by` and `updated_by` should store the authenticated user or system actor responsible for the change. Use a clear system actor value for seed data, scheduled jobs, migrations, and automated integrations.
- When renaming existing tables, add or document a migration path. `spring.jpa.hibernate.ddl-auto=update` can create new prefixed tables but does not move old data.
- Keep external SQL clients, Keycloak SPI queries, reports, and documentation aligned with entity table names.

## Frontends

Both Angular apps use Angular 19, Angular Material, Bootstrap, RxJS, and TypeScript 5.7.

Useful commands:

```bash
cd frontend
npm run build
npm test

cd ../privilege-frontend
npm run build
npm test
```

When changing frontend code:

- Keep shared behavior in `frontend-libs/` when it is used by both frontends.
- Prefer existing Angular services in `src/app/core` for API/auth behavior.
- Avoid committing generated Angular output such as `dist/` and `.angular/`.
- Keep UI changes consistent between `frontend/` and `privilege-frontend/` when they share auth or layout behavior.

## Keycloak

SSO documentation lives in:

- `KEYCLOAK_SSO_IMPLEMENTATION_PLAN.md`
- `SSO_LOGIN_PROCESS_DOCUMENTATION.md`
- `keycloak2/README.md`
- `keycloak2/user-storage-spi/README.md`

The Keycloak user-storage SPI lives in `keycloak2/user-storage-spi/`.

Useful commands:

```bash
cd keycloak2/user-storage-spi
./build-provider.sh

cd ..
./run-keycloak-in-docker.sh
```

Provider id:

```text
nexacore-authmodule-user-storage
```

When changing Keycloak integration:

- Keep the provider compatible with Keycloak 26 and Java 21.
- The SPI reads `auth_users`, `auth_roles`, and `auth_user_roles` from `auth_db`.
- Preserve BCrypt password validation behavior unless explicitly replacing local password auth.
- Verify frontend client IDs and backend accepted audiences together.

## Docker And Local Services

Root Compose exposes:

- Backend: `localhost:9100`
- Main frontend: `localhost:4200`
- Privilege frontend: `localhost:4300`
- Keycloak: `localhost:9200`

Compose expects local PostgreSQL on port `5433`, MinIO on `9000`, and Redis according to backend configuration.

Useful command:

```bash
docker compose up --build
```

## Verification Expectations

Run the narrowest meaningful checks for the files touched:

- Backend Java changes: `cd backend && mvn test`
- Main frontend changes: `cd frontend && npm run build`
- Privilege frontend changes: `cd privilege-frontend && npm run build`
- Keycloak SPI changes: `cd keycloak2/user-storage-spi && mvn package`
- Compose/config changes: inspect rendered configuration and, when practical, run `docker compose config`

If a command cannot be run because required local services or dependencies are unavailable, note that clearly in the final response.
