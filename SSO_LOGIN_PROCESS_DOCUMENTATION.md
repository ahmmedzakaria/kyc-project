# NexaCore SSO Login Process Documentation

## Purpose

This document describes the current SSO implementation across the NexaCore backend, KYC frontend, privilege frontend, and shared frontend libraries.

The implementation uses Keycloak for identity and NexaCore for application authorization. Keycloak authenticates the user and issues a Keycloak access token. The NexaCore backend validates that token, maps or creates a local application user, and then issues the existing NexaCore JWT used by APIs and privilege checks.

## Applications And Ports

| Application | URL | Keycloak Client | Responsibility |
| --- | --- | --- | --- |
| KYC frontend | `http://localhost:4200` | `nexacore-client` | KYC application UI |
| Privilege frontend | `http://localhost:4300` | `privilege-frontend` | Privilege management UI |
| NexaCore backend | `http://localhost:9100` | Backend validates both clients | API, token bridge, local privileges |
| Keycloak | `http://localhost:9200` | Realm `kyc` | Identity provider |

## Core Design

The SSO implementation follows a token bridge design:

1. The frontend redirects the browser to Keycloak using Authorization Code + PKCE.
2. Keycloak authenticates the user.
3. Keycloak redirects back to the frontend callback route.
4. The frontend exchanges the authorization code with Keycloak for a Keycloak access token.
5. The frontend sends the Keycloak access token to the backend.
6. The backend validates the Keycloak token.
7. The backend maps or syncs a local NexaCore user.
8. The backend issues a NexaCore access token and refresh token.
9. The frontend uses the NexaCore JWT for all protected API calls.

Keycloak owns identity. NexaCore owns local roles, privileges, menus, and business authorization.

## Important Routes

### Frontend Routes

Common frontend auth routes are centralized in:

```text
frontend-libs/auth/src/lib/auth.routes.ts
```

The shared routes are:

```text
/login
/sso/callback
```

Both frontend applications import these routes:

```ts
import { AUTH_ROUTES, authGuard } from '@nexacore/auth';

export const routes: Routes = [
  ...AUTH_ROUTES,
  {
    path: '',
    loadComponent: () => import('@nexacore/layout').then(m => m.LayoutComponent),
    canActivate: [authGuard],
    children: [
      // app-specific protected routes
    ],
  },
];
```

The callback route is a frontend route, not a backend endpoint:

```text
http://localhost:4200/sso/callback
http://localhost:4300/sso/callback
```

### Backend Auth APIs

General backend auth APIs are defined in:

```text
backend/src/main/java/com/nexacore/authmodule/controller/AuthController.java
```

SSO APIs are defined separately in:

```text
backend/src/main/java/com/nexacore/authmodule/sso/controller/SsoController.java
```

| Method | Endpoint | Public | Purpose |
| --- | --- | --- | --- |
| `POST` | `/auth/config` | Yes | Returns auth mode and Keycloak config |
| `POST` | `/auth/sso/authenticate` | Yes | Receives Keycloak token and returns NexaCore JWT |
| `POST` | `/auth/authenticate` | Yes | Local username/password login, disabled in SSO mode |
| `POST` | `/auth/logout` | No | Marks current NexaCore JWT user as logged out |
| `POST` | `/auth/login-status` | Yes | Checks whether a username is tracked as actively logged in |
| `POST` | `/auth/session-status` | No | Session poll endpoint used by frontend |
| `POST` | `/auth/refresh-token` | No | Existing refresh-token flow |

### Local Frontend API Routing

The shared API service is defined in:

```text
frontend-libs/api-common/src/lib/api.service.ts
```

For local development, when the browser is running from either frontend origin:

```text
http://localhost:4200
http://localhost:4300
```

the shared API service sends backend calls directly to:

```text
http://localhost:9100
```

Therefore logout is called as:

```text
POST http://localhost:9100/auth/logout
```

not:

```text
POST http://localhost:4300/auth/logout
```

The relative `/auth` and `/api` defaults remain available for non-local/proxied deployments.

## Configuration

Backend configuration is in:

```text
backend/src/main/resources/application.properties
```

Current SSO-related settings:

```properties
app.auth.mode=${AUTH_MODE:SSO}
keycloak.issuer-uri=${KEYCLOAK_ISSUER_URI:http://localhost:9200/realms/kyc}
keycloak.jwk-set-uri=${KEYCLOAK_JWK_SET_URI:http://localhost:9200/realms/kyc/protocol/openid-connect/certs}
keycloak.client-id=${KEYCLOAK_CLIENT_ID:nexacore-client}
keycloak.allowed-client-ids=${KEYCLOAK_ALLOWED_CLIENT_IDS:nexacore-client,privilege-frontend}
keycloak.required-audience=${KEYCLOAK_AUDIENCE:nexacore}
keycloak.sync-user=${KEYCLOAK_SYNC_USER:true}
keycloak.default-role=${KEYCLOAK_DEFAULT_ROLE:ROLE_KYC_OPERATOR}
```

Key points:

- `AUTH_MODE=SSO` makes SSO the default.
- Local login is rejected in SSO mode.
- Backend accepts tokens from both frontend clients:
  - `nexacore-client`
  - `privilege-frontend`
- Backend also accepts `aud` or `azp` matching `nexacore`, depending on how Keycloak token mappers are configured.

## Frontend SSO Flow

The main frontend SSO implementation is in:

```text
frontend-libs/auth/src/lib/auth.service.ts
```

### 1. Protected Route Guard

The protected route guard is:

```text
frontend-libs/auth/src/lib/auth.guard.ts
```

When a protected route is opened:

1. `authGuard` checks `authService.isAuthenticated()`.
2. `isAuthenticated()` checks the local NexaCore JWT in `localStorage.token`.
3. If the token exists and is not expired, access is allowed.
4. If no token exists:
   - The guard calls `/auth/config`.
   - If mode is `SSO`, it starts `loginWithSso(state.url)`.
   - If mode is `LOCAL`, it redirects to `/login`.

This is what enables cross-application SSO:

1. User logs in to KYC frontend at `4200`.
2. User opens privilege frontend at `4300/privileges`.
3. Privilege frontend has no local NexaCore JWT because `4200` and `4300` have separate localStorage.
4. Guard starts Keycloak SSO automatically.
5. Keycloak reuses the existing Keycloak browser session.
6. Privilege frontend receives its own NexaCore JWT and opens `/privileges`.

### 2. Load Auth Config

Frontend calls:

```http
POST /auth/config
```

Backend returns:

```json
{
  "authMode": "SSO",
  "issuerUri": "http://localhost:9200/realms/kyc",
  "clientId": "nexacore-client",
  "redirectUri": "http://localhost:4200/sso/callback"
}
```

The frontend normalizes this response in `normalizeAuthConfig()`:

```ts
private normalizeAuthConfig(config: AuthConfig): AuthConfig {
  return {
    ...config,
    clientId: this.resolveFrontendClientId(config),
    redirectUri: `${window.location.origin}/sso/callback`
  };
}
```

This is important because the frontend knows its true browser origin. It avoids backend origin inference problems caused by Angular dev proxying.

Client selection:

```ts
private resolveFrontendClientId(config: AuthConfig): string | undefined {
  if (window.location.port === '4300') {
    return 'privilege-frontend';
  }

  return config.clientId;
}
```

So:

- `localhost:4200` uses `nexacore-client`.
- `localhost:4300` uses `privilege-frontend`.

The normalized auth config is saved in:

```text
localStorage.authConfig
localStorage.authMode
```

### 3. Start SSO Login

`loginWithSso(returnUrl)` does the following:

1. Clears old local NexaCore token state.
2. Clears `keycloakIdToken`.
3. Clears short-lived auto-SSO suppression.
4. Stores requested route in:

```text
sessionStorage.post_login_url
```

5. Loads auth config.
6. Redirects to Keycloak.

### 4. PKCE And Keycloak Redirect

`redirectToKeycloak(config)` generates:

- `code_verifier`
- `code_challenge`
- `state`

It stores:

```text
sessionStorage.kc_code_verifier
sessionStorage.kc_state
```

Then it redirects the browser to:

```text
{issuerUri}/protocol/openid-connect/auth
```

With query parameters:

```text
client_id
redirect_uri
response_type=code
scope=openid profile email
state
code_challenge
code_challenge_method=S256
```

Example for KYC frontend:

```text
http://localhost:9200/realms/kyc/protocol/openid-connect/auth
  ?client_id=nexacore-client
  &redirect_uri=http://localhost:4200/sso/callback
  &response_type=code
  &scope=openid profile email
  &state=...
  &code_challenge=...
  &code_challenge_method=S256
```

Example for privilege frontend:

```text
http://localhost:9200/realms/kyc/protocol/openid-connect/auth
  ?client_id=privilege-frontend
  &redirect_uri=http://localhost:4300/sso/callback
  &response_type=code
  &scope=openid profile email
  &state=...
  &code_challenge=...
  &code_challenge_method=S256
```

When SSO starts automatically from a protected-route guard, the authorization URL does not include `prompt=login`. This keeps cross-app SSO silent, so a user logged into KYC can open the privilege frontend without manually logging in again.

When SSO starts from the visible `Login with SSO` button on `/login`, the frontend checks the last logged-out user against:

```text
POST /auth/login-status
```

If that username is not present in the backend active-login map, the frontend adds:

```text
prompt=login
```

This forces Keycloak to show the login/account screen. It is needed after logout so the user can sign in again as a different Keycloak user instead of silently reusing any remaining Keycloak browser session.

### 5. Keycloak Callback

After successful Keycloak login, Keycloak redirects to:

```text
http://localhost:4200/sso/callback?code=...&state=...
```

or:

```text
http://localhost:4300/sso/callback?code=...&state=...
```

The callback component is:

```text
frontend-libs/auth/src/lib/sso-callback/sso-callback.component.ts
```

It calls:

```ts
authService.handleSsoCallback()
```

The callback handler validates:

- `code` exists.
- `state` exists.
- `state` matches `sessionStorage.kc_state`.
- `sessionStorage.kc_code_verifier` exists.

If callback params are missing, the current component restarts SSO.

### 6. Exchange Code For Keycloak Token

The frontend exchanges the authorization code directly with Keycloak:

```http
POST {issuerUri}/protocol/openid-connect/token
Content-Type: application/x-www-form-urlencoded
```

Body:

```text
grant_type=authorization_code
client_id={clientId}
redirect_uri={redirectUri}
code={code}
code_verifier={verifier}
```

Keycloak returns:

```json
{
  "access_token": "...",
  "refresh_token": "...",
  "id_token": "..."
}
```

Only the Keycloak access token is sent to the backend bridge endpoint.

### 7. Send Keycloak Token To Backend

Frontend calls:

```http
POST /auth/sso/authenticate
Content-Type: application/json
```

Payload:

```json
{
  "source": "NEXACORE_APP",
  "accessToken": "keycloak_access_token"
}
```

`source` is added automatically by `ApiService.post()`.

### 8. Store NexaCore Tokens

Backend returns:

```json
{
  "accessToken": "nexacore_jwt",
  "refreshToken": "nexacore_refresh_jwt"
}
```

Frontend stores:

```text
localStorage.token
localStorage.refreshToken
localStorage.keycloakIdToken
```

Then it:

1. Decodes the NexaCore JWT.
2. Stores decoded user in `currentUserSubject`.
3. Schedules auto logout based on JWT expiry.
4. Starts session monitoring.
5. Loads application context and privilege menus.

Application context data is stored in:

```text
localStorage.privilegeCodes
localStorage.sidebarMenus
```

Finally it redirects to:

```text
sessionStorage.post_login_url
```

## Backend SSO Flow

### 1. `/auth/config`

The backend method is:

```java
AuthServiceImpl.getAuthConfig(String origin)
```

It returns:

- auth mode
- issuer URI
- client ID
- redirect URI

Current backend also contains origin-based client selection:

```java
private String resolveClientId(String origin) {
  if (StringUtils.hasText(origin) && origin.contains(":4300")) {
    return "privilege-frontend";
  }
  return keycloakProperties.getClientId();
}
```

However, the frontend normalizes client ID and redirect URI based on `window.location`, so frontend origin is the final source of truth for browser redirect configuration.

### 2. `/auth/sso/authenticate`

The backend SSO controller delegates to:

```java
SsoAuthService.authenticate(SsoAuthenticateRequest request)
```

Behavior:

1. If `AUTH_MODE` is not `SSO`, return:

```text
SSO_LOGIN_DISABLED
```

2. Validate the Keycloak access token.
3. Sync local user.
4. Load local user details.
5. Issue NexaCore JWT and refresh JWT.

### 3. Keycloak Token Validation

Validation is implemented in:

```text
backend/src/main/java/com/nexacore/authmodule/sso/service/KeycloakSsoService.java
```

The backend uses:

```java
NimbusJwtDecoder.withJwkSetUri(keycloakProperties.getJwkSetUri()).build()
```

This validates the JWT signature using the Keycloak JWKS endpoint.

Additional checks:

- issuer equals configured `keycloak.issuer-uri`
- audience or authorized party is valid

Audience/client validation accepts any of:

- `aud` contains `keycloak.required-audience`, currently `nexacore`
- `azp` equals `nexacore`
- `azp` equals configured `keycloak.client-id`
- `azp` is in `keycloak.allowed-client-ids`

Allowed client IDs:

```text
nexacore-client
privilege-frontend
```

Common failure:

```text
Invalid Keycloak token audience
```

This happens when Keycloak issues a token whose `aud` and `azp` do not match backend configuration.

### 4. Local User Sync

After token validation, the backend extracts:

- `sub`
- `preferred_username`
- `email`
- `given_name`
- `family_name`
- `email_verified`

It builds:

```java
SsoUserProfileDto
```

Then `syncUser()` finds or creates a local `User`:

1. Find by `externalProvider=KEYCLOAK` and `externalSubject=sub`.
2. Else find by email.
3. Else find by username.
4. Else create a user if `keycloak.sync-user=true`.

Synced user fields:

- `username`
- `email`
- `emailVerified`
- `externalProvider`
- `externalSubject`
- `enabled=true`
- `lastLoginAt`

If the user has no roles, the backend assigns:

```text
ROLE_KYC_OPERATOR
```

This role is controlled by:

```properties
keycloak.default-role=${KEYCLOAK_DEFAULT_ROLE:ROLE_KYC_OPERATOR}
```

### 5. NexaCore JWT Generation

The backend loads local user details and roles using:

```text
MyUserDetailsService
```

Then it issues:

```java
jwtUtil.generateToken(userDetails)
jwtUtil.generateRefreshToken(userDetails)
```

The NexaCore JWT contains:

- subject: local username
- roles: local authorities
- issued at
- expiration

The frontend uses this NexaCore JWT for all later API calls.

## Local Login Behavior

Local login endpoint:

```http
POST /auth/authenticate
```

In `SSO` mode, local login is disabled:

```java
if (authenticationProperties.isSsoMode()) {
  return FORBIDDEN LOCAL_LOGIN_DISABLED;
}
```

Frontend also hides the username/password form in SSO mode and shows only the SSO login button.

## Authorization And Privileges

Keycloak only authenticates identity.

Authorization remains inside NexaCore:

- local `User`
- local `Role`
- local `Privilege`
- dynamic menu/context APIs

After login, frontend loads application context through the shared layout/sidebar services. The resulting privilege codes and menus are stored in localStorage.

This is why a Keycloak user still needs a mapped or synced local NexaCore user with local roles and privileges.

## Cross-App SSO Behavior

### Expected Login Behavior

If the user logs into KYC frontend:

```text
http://localhost:4200/dashboard
```

Then opens privilege frontend:

```text
http://localhost:4300/privileges
```

The privilege frontend does not have the KYC app's localStorage token because browser storage is origin-specific.

Therefore:

1. Privilege frontend guard sees no NexaCore JWT.
2. It starts SSO.
3. Keycloak sees the existing Keycloak browser session.
4. Keycloak redirects back without asking for credentials.
5. Privilege frontend exchanges the code and gets its own NexaCore JWT.

This is correct SSO behavior.

### Why Each App Needs Its Own NexaCore JWT

`localhost:4200` and `localhost:4300` are different origins. They do not share localStorage.

Therefore:

- KYC frontend stores a token under `localhost:4200`.
- Privilege frontend stores a token under `localhost:4300`.

SSO removes repeated manual login but does not share frontend localStorage.

## Logout Behavior

Logout is implemented in the shared frontend auth service.

### Frontend Logout Steps

When `logout()` is called:

1. Read current auth config and Keycloak ID token.
2. Call backend:

```http
POST /auth/logout
Authorization: Bearer nexacore_jwt
```

3. Clear localStorage values:

```text
token
refreshToken
privilegeCodes
sidebarMenus
keycloakIdToken
```

4. Clear timers and session monitor.
5. Set layout to public.
6. In SSO mode, redirect browser to Keycloak logout:

```text
{issuerUri}/protocol/openid-connect/logout
  ?post_logout_redirect_uri={origin}/login
  &client_id={clientId}
  &id_token_hint={idToken}
```

### Backend Login State

Backend login state is implemented with:

```text
LogoutSessionService
```

It uses a single source of truth for login and logout:

```text
username -> loginAfter timestamp
```

On successful local or SSO login, the username is added to `loginAfterByUsername` only if it is not already present. This allows the same user to be logged in to both frontend apps at the same time without the later login invalidating the earlier app's JWT.

On logout, the username is removed from `loginAfterByUsername`.

The JWT filter checks every incoming NexaCore JWT:

1. Extract username.
2. Extract token issued-at time.
3. Check that `loginAfterByUsername` contains the username.
4. Check that the JWT `iat` is not before the stored `loginAfter` timestamp.
5. If either check fails, reject the token.

Rejected message:

```text
User session is not active
```

### Other App Logout Detection

Each authenticated frontend starts a session monitor:

```text
POST /auth/session-status
```

Interval:

```text
15 seconds
```

The request uses header:

```text
X-Silent: true
```

So the interceptor does not show snackbars every 15 seconds.

If one app logs out, the backend removes the username from `loginAfterByUsername`. The other app's session monitor gets a 401 and logs itself out.

## Auto-SSO Suppression After Logout

There is a short-lived session-only suppression:

```text
sessionStorage.auto_sso_suppress_until
```

Duration:

```text
120 seconds
```

Purpose:

- After explicit logout, if the user immediately hits app root `/`, the app should not silently auto-login again.
- Instead it redirects to `/login`.

Current guard condition:

```ts
if (config.authMode === 'SSO' && authService.isAutoSsoSuppressed()) {
  return of(router.createUrlTree(['/login']));
}
```

Important operational note:

This suppression can conflict with cross-app auto-login if it exists in the target app's `sessionStorage`. Because sessionStorage is per-origin and per-tab, a stale suppression flag on `localhost:4300` can cause `http://localhost:4300/privileges` to show login instead of silently starting SSO.

If cross-app auto-login must always win for feature URLs, narrow this condition to root-only:

```ts
if (config.authMode === 'SSO' && authService.isAutoSsoSuppressed() && state.url === '/') {
  return of(router.createUrlTree(['/login']));
}
```

## Storage Keys

### localStorage

| Key | Purpose |
| --- | --- |
| `token` | NexaCore access JWT |
| `refreshToken` | NexaCore refresh JWT |
| `authMode` | `LOCAL` or `SSO` |
| `authConfig` | Normalized auth config |
| `keycloakIdToken` | Keycloak ID token for logout hint |
| `privilegeCodes` | Local privilege codes for UI authorization |
| `sidebarMenus` | Backend-provided menu context |

### sessionStorage

| Key | Purpose |
| --- | --- |
| `kc_code_verifier` | PKCE verifier |
| `kc_state` | CSRF/state validation value |
| `post_login_url` | Route to return to after SSO callback |
| `auto_sso_suppress_until` | Temporary post-logout auto-SSO suppression |

## Keycloak Client Settings

### `nexacore-client`

Recommended settings:

```text
Client type: Public
Standard flow: Enabled
PKCE: Required
Valid redirect URIs:
  http://localhost:4200/*
Valid post logout redirect URIs:
  http://localhost:4200/*
Web origins:
  http://localhost:4200
Home URL:
  http://localhost:4200
Admin URL:
  http://localhost:4200
```

### `privilege-frontend`

Recommended settings:

```text
Client type: Public
Standard flow: Enabled
PKCE: Required
Valid redirect URIs:
  http://localhost:4300/*
Valid post logout redirect URIs:
  http://localhost:4300/*
Web origins:
  http://localhost:4300
Home URL:
  http://localhost:4300
Admin URL:
  http://localhost:4300
```

### Audience Mapper

If backend requires `aud=nexacore`, configure an audience mapper in Keycloak so tokens include:

```json
"aud": ["nexacore"]
```

The current backend also accepts `azp` values from:

```text
nexacore-client
privilege-frontend
```

## Common Failure Cases

### `Invalid SSO callback`

Usually means:

- `/sso/callback` was opened manually.
- Callback URL has no `code` or `state`.
- Browser lost `sessionStorage.kc_code_verifier`.
- Keycloak returned to a different origin than the one that started SSO.
- Multiple tabs started SSO and overwrote sessionStorage state.

Current callback component attempts to recover by restarting SSO.

### Backend Logs `Securing GET /auth/callback`

This means `/auth/callback` was being sent to backend, usually because Angular dev proxy forwards `/auth/**` to backend.

The implementation now uses:

```text
/sso/callback
```

This avoids conflict with `/auth/**` backend APIs.

### `Invalid Keycloak token audience`

The backend rejected the Keycloak token because neither `aud` nor `azp` matched configuration.

Check:

```properties
keycloak.allowed-client-ids=nexacore-client,privilege-frontend
keycloak.required-audience=nexacore
```

Also inspect the token claims:

```json
{
  "aud": "...",
  "azp": "..."
}
```

### `LOCAL_LOGIN_DISABLED`

This is expected when:

```properties
app.auth.mode=SSO
```

The backend intentionally blocks local username/password login in SSO mode.

### Other App Does Not Logout Immediately

The other app detects logout through `/auth/session-status` polling every 15 seconds. It may remain visible until:

- the next poll happens, or
- it makes another protected backend API call.

## Current Implementation Caveats

1. `LogoutSessionService` is in-memory.

If the backend restarts, logout invalidation markers are lost. For production, store logout/session invalidation in a database or distributed cache.

2. Auto-SSO suppression can conflict with cross-app SSO.

If the suppression guard is broad, `4300/privileges` may redirect to `/login` instead of auto-starting SSO. Prefer root-only suppression if this problem appears.

3. Frontend token storage is origin-specific.

Each app must complete the bridge flow and get its own NexaCore JWT.

4. Backend cannot reliably infer frontend origin behind proxies.

The frontend currently normalizes `clientId` and `redirectUri` using `window.location`, which is the safer source of truth for browser redirects.

5. Backend compile should be verified locally.

This environment does not have `mvn`, so backend compilation must be checked on a machine with Maven or a Maven wrapper.

## Recommended Manual Test Checklist

### KYC Login

1. Open `http://localhost:4200/`.
2. App should start SSO or show login page with SSO button depending on route and suppression state.
3. Login through Keycloak.
4. App should land on `/dashboard`.
5. `localStorage.token` should exist under `localhost:4200`.

### Privilege Auto-Login After KYC Login

1. Stay logged in to KYC.
2. Open `http://localhost:4300/privileges`.
3. App should redirect through Keycloak.
4. Keycloak should not ask for credentials if browser session is active.
5. App should return to `/privileges`.
6. `localStorage.token` should exist under `localhost:4300`.

### Logout Propagation

1. Login to both apps.
2. Logout from KYC.
3. KYC should redirect through Keycloak logout to `/login`.
4. Privilege frontend should logout within about 15 seconds or on its next backend API call.

### Post-Logout Root Access

1. Logout from KYC.
2. Immediately open `http://localhost:4200/`.
3. App should not silently auto-login if auto-SSO suppression is active.
4. It should route to `/login`.

### Login Again After Logout

1. Click `Login with SSO`.
2. App should clear suppression and start SSO.
3. If Keycloak session was correctly ended, Keycloak should ask for credentials.
4. If Keycloak session still exists, review Keycloak logout settings and `id_token_hint`.
