# Keycloak SSO Implementation Plan

## Objective

Implement configurable authentication for the NexaCore project with two modes:

- `LOCAL`: current Spring Security username/password login with backend-issued JWT.
- `SSO`: Keycloak-based login, with frontend SSO flow and backend validation/synchronization.

Both frontend applications must support the same authentication mode through shared `frontend-libs/auth`.

## Current State

Backend currently has:

- `/auth/authenticate` for username/password login.
- `AuthServiceImpl` authenticating through `AuthenticationManager`.
- `JwtUtil` generating application access/refresh tokens.
- `JwtAuthenticationFilter` validating backend-issued JWT on API calls.
- Privilege APIs using the authenticated username and local auth-module users/roles/privileges.
- `spring-boot-starter-oauth2-client` already present, but no complete Keycloak SSO flow.

Frontend currently has:

- Shared login implementation in `frontend-libs/auth`.
- Shared API infrastructure in `frontend-libs/api-common`.
- NexaCore frontend applications consume shared auth/layout libraries.

## Key Design Decision

Use a configurable authentication mode:

```properties
app.auth.mode=LOCAL
# or
app.auth.mode=SSO
```

Recommended first implementation: **Keycloak token bridge**.

In `SSO` mode:

1. Frontend redirects user to Keycloak using Authorization Code + PKCE.
2. Frontend receives Keycloak access token.
3. Frontend sends the Keycloak token to backend `/auth/sso/authenticate`.
4. Backend validates the Keycloak token against Keycloak issuer/JWKS.
5. Backend finds or creates/synchronizes a local `User`.
6. Backend issues the existing application JWT and refresh token.
7. Frontend continues calling APIs exactly as today using backend JWT.

Reason: this preserves the existing authorization/privilege system and minimizes changes to all existing APIs.

Later enhancement: switch APIs to validate Keycloak JWT directly with Spring Resource Server if full token delegation is required.

## Keycloak Database Plan

The request says Keycloak should use `kyc_db`.

Recommended safe setup:

- Use the same PostgreSQL server/database name `kyc_db`.
- Put Keycloak tables in a dedicated schema, for example `keycloak`.
- Do not mix Keycloak internal tables with existing KYC/Auth/GIS tables.

Example:

```sql
CREATE SCHEMA IF NOT EXISTS keycloak;
CREATE USER keycloak_user WITH PASSWORD 'change_me';
GRANT USAGE, CREATE ON SCHEMA keycloak TO keycloak_user;
ALTER ROLE keycloak_user SET search_path TO keycloak;
```

Important: Keycloak does not automatically use your existing application `users` table as its user store. If direct reuse of the existing `authmodule.user` table is required, that is a separate Keycloak User Storage SPI implementation and should be a later phase.

## Backend Configuration

Add properties:

```properties
app.auth.mode=${AUTH_MODE:LOCAL}

keycloak.issuer-uri=${KEYCLOAK_ISSUER_URI:http://localhost:9200/realms/kyc}
keycloak.jwk-set-uri=${KEYCLOAK_JWK_SET_URI:http://localhost:9200/realms/kyc/protocol/openid-connect/certs}
keycloak.client-id=${KEYCLOAK_CLIENT_ID:nexacore-client}
keycloak.required-audience=${KEYCLOAK_AUDIENCE:nexacore}
keycloak.sync-user=true
```

Add frontend-facing config endpoint:

```http
POST /auth/config
```

Response:

```json
{
  "authMode": "LOCAL",
  "issuerUri": "http://localhost:9200/realms/kyc",
  "clientId": "nexacore-client",
  "redirectUri": "http://localhost:4200/auth/callback"
}
```

## Backend Implementation Tasks

1. Add auth mode enum:

```java
public enum AuthenticationMode {
    LOCAL,
    SSO
}
```

2. Add `AuthenticationProperties`:

- `app.auth.mode`
- Keycloak issuer/client/audience settings
- Allowed redirect origins if needed

3. Add DTOs:

- `AuthConfigResponse`
- `SsoAuthenticateRequest`
- `SsoUserProfileDto`

4. Add `/auth/config`.

Purpose: frontend decides whether to show local login form or start SSO.

5. Add `/auth/sso/authenticate`.

Request:

```json
{
  "source": "NEXACORE_APP",
  "accessToken": "keycloak_access_token"
}
```

Response: same `AuthResponse` as existing login.

6. Add Keycloak token verifier service:

- Validate JWT signature using issuer JWKS.
- Validate issuer.
- Validate expiry.
- Validate audience/client if configured.
- Extract username, email, first name, last name, subject.

7. Add user synchronization service:

- Find local user by Keycloak subject if stored.
- Else find by email or username.
- Else create a local user if `keycloak.sync-user=true`.
- Assign default role if new SSO user has no role.
- Treat Keycloak as the identity source.
- Keep the local app privilege system as the authorization source.

8. Extend `User` entity if needed:

Suggested fields:

- `externalProvider`
- `externalSubject`
- `emailVerified`
- `lastLoginAt`

9. Keep existing `/auth/authenticate`.

Behavior:

- In `LOCAL` mode: enabled.
- In `SSO` mode: disabled. Return `400` or `403` with message `LOCAL_LOGIN_DISABLED`.

10. Security config:

- Keep current `JwtAuthenticationFilter` for application JWT.
- Whitelist:
  - `/auth/authenticate`
  - `/auth/sso/authenticate`
  - `/auth/config`
  - Swagger paths
- Keep all business APIs protected by backend JWT.

11. Add dependency if using Spring JWT decoder:

```xml
<dependency>
  <groupId>org.springframework.boot</groupId>
  <artifactId>spring-boot-starter-oauth2-resource-server</artifactId>
</dependency>
```

12. Audit logging:

- Log login source: `LOCAL` or `SSO`.
- Log Keycloak subject for SSO.
- Never log raw tokens.

## Frontend Implementation Tasks

Shared library changes should be made in `frontend-libs/auth` and `frontend-libs/api-common`.

1. Add auth mode config model:

```ts
export interface AuthConfig {
  authMode: 'LOCAL' | 'SSO';
  issuerUri?: string;
  clientId?: string;
  redirectUri?: string;
}
```

2. Add `AuthService.loadAuthConfig()`.

Call backend:

```http
POST /auth/config
```

3. Update login screen:

- If `LOCAL`, show username/password form.
- If `SSO`, show `Login with SSO` button.
- Do not show local username/password login when `SSO` mode is active.

4. Add SSO client flow.

Use direct Authorization Code + PKCE in the shared auth library. No additional frontend SSO package is required for the first implementation.

5. Add SSO login flow:

- Load issuer/client/redirect URI from `/auth/config`.
- Generate PKCE verifier/challenge and state.
- Redirect to Keycloak authorization endpoint.
- Use Authorization Code + PKCE.
- On successful Keycloak login, call backend `/auth/sso/authenticate`.
- Store backend-issued access token and refresh token exactly like current login.
- Load `/auth/privilege/context` as currently done.

6. Add SSO callback route:

Examples:

- `/auth/callback`
- `/sso/callback`

7. Update logout:

- In `LOCAL`, clear local storage and route to login.
- In `SSO`, call Keycloak logout then clear local storage.

8. Update both apps:

- NexaCore frontend uses shared SSO login automatically.
- Privilege frontend uses shared SSO login automatically.
- Each app can have different redirect URI and Keycloak client if needed.

Suggested frontend env/config:

```ts
authConfigApi: 'auth/config'
authSsoApi: 'auth/sso/authenticate'
```

## Keycloak Setup Tasks

1. Run Keycloak using Docker.

2. Configure DB:

- DB: PostgreSQL
- DB name: `kyc_db`
- Schema: `keycloak`
- User: `keycloak_user`

3. Create realm:

```text
kyc
```

4. Create clients:

```text
nexacore-client
privilege-frontend
```

5. Configure frontend clients:

- Public client
- Authorization Code flow
- PKCE required
- `nexacore-client` redirect URI: `http://localhost:4200/*`
- `privilege-frontend` redirect URI: `http://localhost:4300/*`
- Valid redirect URIs:
  - `http://localhost:4200/*`
  - `http://localhost:4300/*`
- Web origins:
  - `http://localhost:4200`
  - `http://localhost:4300`

6. Configure API audience if backend validates audience.

7. Create test users in Keycloak.

8. Map Keycloak user to local user:

- Preferred matching: Keycloak subject stored in local user.
- Fallback matching: email or username.
- Keycloak owns identity data; NexaCore owns roles and privileges.

## Docker / Local Dev Tasks

Add Keycloak service to Docker Compose:

- Keycloak container
- Uses existing Postgres service or host Postgres.
- Connects to `kyc_db`.
- Uses schema `keycloak`.

Add environment variables:

```bash
AUTH_MODE=SSO
KEYCLOAK_ISSUER_URI=http://localhost:9200/realms/kyc
KEYCLOAK_CLIENT_ID=nexacore-client
KEYCLOAK_AUDIENCE=nexacore
```

Keep local mode default:

```bash
AUTH_MODE=LOCAL
```

## Rollout Plan

Phase 1: Backend config foundation

- Add auth mode properties.
- Add `/auth/config`.
- Keep existing local auth unchanged.

Phase 2: Keycloak token validation

- Add `/auth/sso/authenticate`.
- Validate Keycloak token.
- Sync local user.
- Issue backend JWT.

Phase 3: Frontend SSO login

- Add Keycloak client in shared auth library.
- Add callback route.
- Add mode-aware login screen.

Phase 4: Docker and Keycloak setup

- Add Keycloak service.
- Add realm/client setup documentation or import file.

Phase 5: Verification

- Test `LOCAL` mode.
- Test `SSO` mode.
- Test both frontends.
- Test privilege context loading.
- Test logout/session expiry.

## Test Scenarios

LOCAL mode:

- Username/password login works.
- Invalid password fails.
- Existing JWT-protected APIs work.
- Privilege context loads after login.
- Auto logout still works.

SSO mode:

- Login redirects to Keycloak.
- Keycloak callback returns to frontend.
- Backend validates Keycloak token.
- Backend creates or maps local user.
- Backend returns access/refresh token.
- Privilege context loads.
- `/auth/authenticate` rejects local username/password login with `LOCAL_LOGIN_DISABLED`.
- Logout clears app token and Keycloak session.

Regression:

- Swagger remains accessible.
- `/auth/authenticate` behavior matches configured mode.
- CORS works for `4200` and `4300`.
- Docker startup works with Keycloak enabled and disabled.

## Risks And Decisions Needed

1. Keycloak database usage:

Using `kyc_db` is fine if Keycloak uses a separate schema. Sharing the same application tables directly is not recommended for the first phase.

2. User source of truth:

Keycloak handles identity. The local NexaCore app stores the mapped user record needed for application access and handles roles/privileges.

3. Role source:

Recommended: keep authorization privileges in local backend because the current privilege system already supports module/menu/feature/action permissions.

4. Token strategy:

Recommended first phase: Keycloak validates login, backend issues current app JWT. This keeps existing APIs stable.

5. Local fallback:

`LOCAL` login is disabled when `SSO` mode is active. Do not add local-login fallback for the first implementation.

## Suggested File Changes

Backend:

- `appconfigmodule/security/SecurityConfig.java`
- `authmodule/controller/AuthController.java`
- `authmodule/service/interfaces/AuthService.java`
- `authmodule/service/implementations/AuthServiceImpl.java`
- New `authmodule/service/implementations/KeycloakSsoService.java`
- New `authmodule/dto/AuthConfigResponse.java`
- New `authmodule/dto/SsoAuthenticateRequest.java`
- New `authmodule/enums/AuthenticationMode.java`
- New config properties class under `appconfigmodule`
- `application.properties`
- `docker-compose.yml`

Frontend libs:

- `frontend-libs/auth/src/lib/auth.service.ts`
- `frontend-libs/auth/src/lib/login/login.component.ts`
- `frontend-libs/auth/src/lib/login/login.component.html`
- `frontend-libs/api-common/src/lib/model/auth-config.ts`
- `frontend-libs/api-common/src/public-api.ts`

Applications:

- `frontend/src/app/app.routes.ts`
- `privilege-frontend/src/app/app.routes.ts`
- app config/environment if separate redirect URIs are required
