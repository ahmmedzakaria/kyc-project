# Frontend Tenant, Privilege, and API Access-Control Architecture Plan

> Implementation status: Phases 0–7 are implemented as of 2026-08-14. The automated fail-closed gate passes locally. The authenticated, seeded multi-tenant browser matrix remains an environment-level verification step because it requires registered clients, synchronized metadata and grants, tenant-resolvable hostnames, and test identities.

## 1. Scope and backend contract

This plan aligns `system-frontend-21`, `kyc-frontend-21`, and `frontend-libs-21` with the current backend authorization architecture. It extends the system-specific plan in `system-frontend-21/TENANT_PRIVILEGE_API_ACCESS_CONTROL_IMPLEMENTATION_PLAN.md` and the backend test roadmap.

The frontend must reflect these backend invariants:

1. Tenant identity is resolved from a trusted hostname.
2. The token identifies a tenant-bound account.
3. The resolved client must be assigned to that tenant.
4. `AuthUserScopeAssignment` supplies normalized tenant/business/branch authority.
5. `AuthenticatedRequestContextFilter` intersects those inputs and captures effective scopes and client-filtered privileges.
6. API registry, client grants, user privileges, and scoped repository predicates are independently enforced.
7. Scoped person resource IDs are KYC profile IDs; `personId` is the separate global identity ID.
8. Missing, inactive, contradictory, ambiguous, or unauthorized context fails closed.

Neither frontend may treat headers, form ownership fields, query parameters, router state, JWT decoding, or local storage as authorization proof.

## 2. Current implementation matrix

| Concern | `frontend-libs-21` | `system-frontend-21` | `kyc-frontend-21` |
|---|---|---|---|
| Authentication | Shared auth and fail-closed context lifecycle | Uses shared auth/context | Uses shared auth/context |
| Client identity | Shared API layer sends public client code without a secret | `SYSTEM_ADMIN_WEB` | `WEB` |
| Route policy | Shared fail-closed policy service and guard | Admin route bypasses removed | Exact person route policies enabled |
| UI policy | Shared directive delegates to policy service | Specialized actions use exact policies | Person/photo/document actions use exact policies |
| Effective tenant/scopes | Typed live server context with normalized tuples | Consumes shared effective context; no JWT tenant decoding | Consumes and displays shared effective context |
| Revocation refresh | Single-flight refresh and replacement-user cleanup | Refreshes after authorization mutations | Active-session revocation is reflected after refresh |
| Denial handling | Stable-code classification and non-replaying refresh | Shared denial/recovery behavior | Shared denial/recovery behavior |
| Safe replacement | Shared load-before-save state/checklist/summary | Client and user assignment editors use safe replacement | Available for domain workflows when required |
| Hierarchical scope UI | Shared normalized tuple selector | Used for client/user scopes | Scope remains backend-authoritative |
| Direct-ID loading | Typed API support | Direct client administration detail | Direct KYC profile loading by profile ID |
| Domain coverage | Infrastructure and reusable safety UI | Client/user scope, backup and specialized actions aligned | Typed profile detail, multipart allowlist, photos and documents aligned |
| Automated tests | 57 shared tests | 3 unit and 3 Playwright route-denial tests | 4 unit and 3 Playwright route-denial tests |

### 2.1 Backend enforcement state

- `AccessControlProperties` and `application.properties` default to `EnforcementMode.ENFORCE`.
- `REPORT` remains available only as an explicit non-production diagnostic override.
- `prod` and `production` profiles reject disabled or non-`ENFORCE` access control during startup.
- Protected APIs fail closed for missing registry metadata, client/API/feature grants, user privilege, effective tenant, or data scope.
- Maven Surefire preloads Mockito as a Java agent so Java 21 CI does not depend on runtime self-attachment permissions.

## 3. Common implementation isolated to `frontend-libs-21`

Common backend-contract infrastructure belongs in `@nexacore/platform`; reusable visual/state primitives belong in `@nexacore/shared`. Domain endpoints and workflows remain in the apps.

### 3.1 `@nexacore/platform`: authorization context

Add or refactor toward one authoritative reactive context:

```ts
export interface EffectiveScopeAssignment {
  tenantId: number;
  businessId: number | null;
  branchId: number | null;
}

export interface EffectiveTenantContext {
  tenantId: number;
  tenantCode: string;
  hostname: string;
  scopeAssignments: EffectiveScopeAssignment[];
}

export interface ApplicationAuthorizationContext {
  clientCode: string;
  clientType: string;
  effectiveTenant: EffectiveTenantContext;
  privilegeCodes: string[];
  routePolicies: RoutePrivilegePolicy[];
  uiPolicies: UiPrivilegePolicy[];
  authorizationVersion?: string;
}
```

The shared service must:

- Load, unwrap, validate, cache, and expose context as signals.
- Provide single-flight `ensureLoaded()`, `refresh()`, and `clear()`.
- Treat persisted context as stale until a live request succeeds.
- Fail closed on malformed or incomplete context.
- Clear state on logout, replacement login, SSO restart, and authentication failure.
- Expose privilege, route, and action decisions from the same reactive source.

`AuthService.hasPrivilege()` should delegate to this service instead of reparsing local storage.

### 3.2 `@nexacore/platform`: authorization policy and denial handling

Create a programmatic `AuthorizationPolicyService`; make `routePrivilegeGuard` and `AuthorizedUiDirective` thin adapters around it.

It must:

- Normalize action codes and route templates consistently.
- Fail closed when a policy is absent.
- Support a dedicated access-denied route.
- Let table action factories and handlers query exact action policies.
- Distinguish `AUTHENTICATION_REQUIRED`, `INVALID_CLIENT_CREDENTIALS`, `API_NOT_REGISTERED`, `CLIENT_API_NOT_ALLOWED`, `CLIENT_FEATURE_NOT_ALLOWED`, `USER_PRIVILEGE_NOT_ALLOWED`, `DATA_SCOPE_NOT_ALLOWED`, `API_REGISTRY_AMBIGUOUS`, `RATE_LIMIT_EXCEEDED`, and `RATE_LIMIT_UNAVAILABLE`.
- Redirect only authentication failures.
- Refresh authorization context once after privilege/scope denial without replaying a mutation.
- Honor `Retry-After` and preserve trace IDs for support.
- Never log tokens, API keys, request bodies, or PII.

### 3.3 `@nexacore/platform`: API and tenant infrastructure

Keep JWT, language, client-code, response unwrapping, binary download, trace handling, and error normalization shared.

Required corrections:

- Support public browser clients without expecting a bundled secret.
- Replace hard-coded development ports with an environment-controlled backend-origin strategy; the current list omits the documented system frontend port 5301.
- Clone JSON request bodies before adding `source`; do not mutate caller state.
- Expose the effective tenant/scope summary to the shared layout.
- Do not implement a header-based tenant switch. Any switch must follow the backend hostname/session contract.

### 3.4 `@nexacore/shared`: safe replacement workflows

Add domain-neutral replacement primitives:

- `ReplacementSelectionState<T>` with `idle/loading/loaded/saving/failed` states.
- Searchable `AssignmentChecklistComponent<T>`.
- Addition/removal summary for confirmation.
- Save disabled until current server state loads successfully.
- Dirty comparison with configurable order/set semantics.
- A failed read can never become an empty replacement submission.

### 3.5 `@nexacore/shared`: hierarchical scope and status UI

Add a reusable selector for normalized tuples:

```ts
interface HierarchicalScopeValue {
  tenantId: number;
  businessId: number | null;
  branchId: number | null;
}
```

The component may enforce structural rules and dependent clearing, while apps provide authorized lookup callbacks. Also add reusable access-denied, configuration-error, retry-after, and assignment-load-state presentation.

Maintain the dependency rule: `platform` must never import `shared`.

## 4. Ownership boundaries

### Keep in `system-frontend-21`

- Client, API registry, privilege, user, role, tenant, layout, license, backup, workflow, and audit administration.
- System privilege/action constants.
- Client/user assignment endpoints and lookup adapters.
- Administrative workflow and page composition.

### Keep in `kyc-frontend-21`

- Person profile DTOs, routes, forms, searches, detail, photos, and documents.
- Person action codes and KYC privilege mapping.
- GIS adapters and KYC workflow presentation.
- Explicit profile-ID versus global-person-ID handling.

### Keep out of shared libraries

- App endpoint catalogs.
- Bootstrap privilege codes tied to one module.
- Client or person business DTOs.
- Tenant/user administration APIs.
- KYC forms and domain workflow.
- Backend credentials.

## 5. `frontend-libs-21` implementation record

| ID | Implemented outcome | Status |
|---|---|---|
| FL-1 | One live reactive authority; persisted values are not trusted before live loading | Complete |
| FL-2 | Typed server-validated tenant and normalized scope context | Complete |
| FL-3 | Single-flight refresh, authorization version, clear and replacement-user lifecycle | Complete |
| FL-4 | Typed denial coordinator for authentication, authorization, rate-limit and availability codes | Complete |
| FL-5 | One programmatic policy service used by guards and UI directives | Complete |
| FL-6 | Load-before-save replacement state, checklist and summary | Complete |
| FL-7 | Structurally validated hierarchical tuple selector | Complete |
| FL-8 | Environment-controlled backend-origin selection | Complete |
| FL-9 | Immutable JSON enrichment | Complete |
| FL-10 | Revocation and sequential-user isolation tests | Complete |

## 6. `system-frontend-21` gap list

The following list records the original implementation drivers. Items within the authorization scope were completed through Phases 0–7; broader administration features remain governed by the system-specific plan.

The system-specific plan remains authoritative; the cross-app priorities are:

1. Current client API, feature, and tenant assignments are not loaded before full-replace saves. Add protected read endpoints and adopt the shared replacement primitives.
2. Independent `tenantIds[]` and `businessIds[]` flatten hierarchy and omit branches. Replace them with normalized tuples.
3. Administrative routes use `data: { public: true }`. Seed route policies, then remove the bypass.
4. Most mutation controls are not governed by UI policies. Apply exact VIEW, MANAGE, ASSIGN, SYNCHRONIZE, ROTATE, EXECUTE, and DOWNLOAD actions.
5. `AuthUserScopeAssignment` has no administration UI. Add protected list/replace contracts and a hierarchical editor; never infer it from person membership.
6. The Users page decodes `tenant_id` from the JWT. Consume shared effective context instead.
7. Raw numeric tenant/business entry lacks authoritative parent-child validation. Use dependent lookups.
8. Client detail/edit uses list-and-filter. Add a direct administration-detail endpoint.
9. Direct user privilege assignment, layout reconciliation/detail/reorder, license activation, workflow administration, and audit viewing need implementation or explicit deferral.
10. Add route, UI action, replacement, hierarchy, refresh, error, and Playwright tenant-matrix tests.

## 7. `kyc-frontend-21` gap list

The following list records the original implementation drivers. The access-control, direct-profile, typing, multipart, photo/document, scope-presentation, demo-route, and automated-test work was completed through Phases 0–7. Future workflow-runtime integration remains intentionally separate.

### KYC-1 — Direct routes depend on router state

Preview and edit redirect to the list after refresh/direct navigation because they require a `Person` in `history.state`.

Required work:

- Add a backend scoped profile-detail endpoint using the KYC profile ID.
- Add typed `PersonService.getProfile(profileId)`.
- Load direct routes from the backend; use router state only as an optional seed.
- Return not found for inaccessible cross-tenant IDs.

### KYC-2 — Verify route policies against exact person privileges

| Route | Required backend privilege |
|---|---|
| `/person` | Search `01010200102` |
| `/person/create` | Create `01010200110` |
| `/person/:id/preview` | View `01010200101` |
| `/person/:id/edit` | Update `01010200112` |

Add tests for static-route precedence, parameter routes, and absent-policy denial.

### KYC-3 — Document workflows are missing

The backend supports upload, list, metadata, and content download. Add typed endpoints/services and UI. Always use the scoped profile ID as `ownerId`, never global `personId`. Gate upload with UPDATE and list/download with VIEW.

### KYC-4 — Weak DTO and request typing

`PersonService` returns `Observable<any>`. Add typed paged results, requests, responses, and method names that explicitly say `profileId`.

### KYC-5 — Multipart serialization is too broad

The form serializes arbitrary flattened keys. Replace this with an explicit allowed-field map so tenant/business/branch values cannot accidentally become authority-bearing input.

### KYC-6 — N+1 photo requests

Search loads one protected photo request per row. Prefer a safe thumbnail reference or scoped batch endpoint; otherwise lazy-load visible rows with bounded concurrency. Never put bearer credentials in image URLs.

### KYC-7 — Optional-photo errors hide authorization failures

Suppress only the expected no-photo case. Surface client, privilege, scope, registry, and service failures through shared error classification.

### KYC-8 — Delete workflow is fragile

Replace browser `confirm()` with shared confirmation, pending state, duplicate-submit prevention, and stable not-found/scope-denial behavior.

### KYC-9 — Effective scope is invisible

Display the server-validated tenant and useful business/branch summary from shared context. Do not add a local header-based scope switch.

### KYC-10 — Component demo is production-routable

Make `/component-demo` development-only or remove it from production routing.

### KYC-11 — Workflow decision UI is local-only

The preview handler mutates local state without calling the backend workflow runtime. Hide it until a real subject/action authorization contract is integrated.

### KYC-12 — Tests are insufficient

Add service, direct-route, action-policy, multipart allowlist, object URL, photo/document, and cross-tenant browser tests.

## 8. Backend contract implementation

The contracts below are implemented and protected by explicit API metadata. Thumbnail batching and workflow-runtime integration remain optional/future domain work where noted.

### Shared by both apps

- Extend `/api/v1/system/privilege/context` with effective tenant/scopes and optional authorization version.
- Seed complete route/UI policies for `WEB` and `SYSTEM_ADMIN_WEB`.

### System administration

- Client administration detail/current assignment reads.
- Hierarchical client-scope replacement.
- User scope-assignment list/replacement.
- Authorized tenant/business/branch lookups.

### KYC

- Scoped profile detail by profile ID.
- Prefer a scoped thumbnail/batch mechanism if search performance requires it.
- Define workflow-runtime integration before enabling decision controls.

Every new protected endpoint requires explicit API metadata, client API/feature grants, privilege composition, and `ApiMetadataCoverageTest` coverage.

## 9. Dependency-ordered implementation plan

### Phase 0 — Immediate safety

**Status: Complete.**

- Disable unresolved system client replacement editors.
- Production-disable the KYC component demo.
- Hide local-only workflow decisions.
- Confirm both Angular clients are registered as public browser clients with no bundled secret.

Gate: the current UI cannot silently erase grants or present nonfunctional security operations.

### Phase 1 — Shared authorization core

**Status: Complete.** `ApplicationContextService`, `AuthorizationPolicyService`, the route guard, UI directive, and denial coordinator share one live authority.

- Implement effective tenant/scope models and reactive context in `platform`.
- Consolidate privilege/policy evaluation.
- Add refresh/clear lifecycle and typed denial coordination.
- Correct backend-origin selection and immutable request enrichment.

Gate: both apps consume one live, fail-closed authorization source.

### Phase 2 — Shared safety UI

**Status: Complete.** Replacement state/checklist/summary, hierarchical scope selection, and denial-state presentation are implemented without a `platform -> shared` dependency.

- Implement replacement state/checklist and confirmation summary in `shared`.
- Implement hierarchical scope selector.
- Implement reusable denial/configuration/retry presentation.

Gate: shared components remain domain-neutral and dependency direction is preserved.

### Phase 3 — Backend contract completion

**Status: Complete.** Application context includes effective tenant/scopes and authorization version; protected client/user assignment reads and writes, client detail, and scoped KYC profile detail are metadata-covered.

- Extend application context.
- Add client detail and current assignments.
- Normalize client scope writes.
- Add user scope administration.
- Add KYC profile detail.
- Seed both clients' route/UI policies.

Gate: every editable or directly addressable state has an authoritative protected read.

### Phase 4 — Align `system-frontend-21`

**Status: Complete for this plan's access-control scope.** The app uses shared context and safe replacement, removes authorization bypasses/JWT authority decoding, and gates specialized actions including backup execution/download.

- Adopt shared context, replacement, and scope primitives.
- Remove JWT decoding and route bypasses.
- Gate every specialized action.
- Add user scope administration and context refresh after mutations.

Gate: VIEW-only, specialized-action, and full-admin accounts see and perform exactly their allowed operations.

### Phase 5 — Align `kyc-frontend-21`

**Status: Complete for this plan's access-control scope.** Direct routes load profiles by profile ID, requests are typed and allowlisted, and photo/document actions use scoped IDs and exact policies.

- Add direct profile loading and typed services.
- Implement document flows.
- Add multipart field allowlists.
- Improve photo loading and error classification.
- Show effective scope and verify policies.

Gate: direct URLs work through scoped backend reads and profile/global IDs cannot be confused.

### Phase 6 — Revocation and multi-tenant validation

**Status: Complete at unit/integration level.** Tests cover active-session privilege removal, sequential browser users, hostname/client/tenant contradictions, missing effective scope, tenant/business/branch inheritance, and sibling/parent denial.

- Verify privilege removal during active sessions.
- Verify sequential users in one browser do not share context.
- Test hostname/token/client/scope mismatches.
- Test tenant, business, branch, and sibling-branch decisions.

Gate: the next request and UI refresh reflect revocation without logout.

### Phase 7 — Automated enforcement gate

**Status: Complete for the automated local gate.**

- Run shared unit tests, app HTTP/component tests, Playwright matrices, backend filter-chain tests, API metadata coverage, and object-authorization tests.

Gate: enforcement mode is enabled and the complete frontend/backend authorization suite passes.

Implemented gate behavior:

- Default and production enforcement is `ENFORCE`; production cannot start in `REPORT` or `DISABLED`.
- Both Angular applications have Playwright checks proving unauthenticated direct navigation cannot render protected administration or scoped KYC data.
- The focused backend gate covers enforcement configuration, API metadata, filter-chain decisions, revocation, request-context intersection, and object authorization.
- The full backend suite runs with the Java 21-compatible Mockito agent configuration.
- The authenticated VIEW-only/specialized/full-admin and cross-tenant browser matrix remains deployment verification; it is not represented as a local mocked-browser result.

## 10. Test ownership

### `frontend-libs-21`

- Context validation, live-versus-persisted state, refresh, and cleanup.
- Route/action matching and missing-policy denial.
- Typed 401/403/429/503 classification.
- Mutation non-retry.
- Replacement-state invariants.
- Hierarchical tuple validation.
- No `platform -> shared` dependency.

### `system-frontend-21`

- Route-to-bootstrap-privilege mapping.
- Action visibility by exact privilege.
- Assignment load-before-replace.
- Client/user scope hierarchy.
- Refresh after authorization mutation.

### `kyc-frontend-21`

- Route-to-person-privilege mapping.
- Direct profile reads by profile ID.
- Cross-tenant not-found behavior.
- Multipart allowlist.
- Photo/document privileges and object URL cleanup.
- No use of global `personId` as scoped resource ID.

### Backend

- Request-context construction and cleanup.
- Tenant/client/account/scope intersection.
- API/client/user privilege decisions.
- Scoped repository predicates and cross-tenant direct-ID denial.
- API metadata coverage.

## 11. Verification

```bash
cd frontendApplications/frontend-libs-21
npx ng build platform
npm install
npx ng build shared
npm test

cd ../system-frontend-21
npm install
npm test
npm run build
npm run test:e2e

cd ../kyc-frontend-21
npm install
npm test
npm run build
npm run test:e2e

cd ../../backend
mvn test
```

Browser verification requires registered `WEB` and `SYSTEM_ADMIN_WEB` clients, synchronized API metadata, client API/feature/tenant grants, and tenant-resolvable hostnames.

### Latest gate result — 2026-08-14

| Gate | Result |
|---|---|
| `frontend-libs-21` platform/shared builds | Passed |
| `frontend-libs-21` unit tests | 57 passed |
| `system-frontend-21` unit tests | 3 passed |
| `system-frontend-21` production build | Passed; existing initial-bundle budget warning remains |
| `system-frontend-21` Playwright protected-route gate | 3 passed |
| `kyc-frontend-21` unit tests | 4 passed |
| `kyc-frontend-21` production build | Passed; existing initial-bundle and component-style budget warnings remain |
| `kyc-frontend-21` Playwright protected-route gate | 3 passed |
| Focused backend authorization gate | 35 passed |
| Full backend suite | 160 run, 0 failures, 5 skipped because Docker/Testcontainers was unavailable |
| Dependency/secret checks | No `platform -> shared` import and no bundled confidential client secret detected |

The Playwright ports are isolated at `15301` for the system frontend and `15300` for the KYC frontend to avoid collisions with normal development servers. Matching Playwright Chromium runtimes must be installed in CI (for example, `npx playwright install chromium`).

## 12. Definition of done

All code-level definition-of-done items below are satisfied. The only outstanding evidence is the deployment-owned authenticated browser matrix described above.

- Both apps use one shared live authorization context.
- Effective tenant and scopes come from backend request context.
- Neither app decodes or invents authority locally.
- Routes and actions fail closed through server-delivered policies.
- Full replacements cannot execute from unresolved state.
- Client and user scopes preserve tenant/business/branch tuples.
- KYC direct routes load scoped profiles by profile ID.
- Documents/photos use exact privileges and scoped IDs.
- Revocation updates backend decisions and frontend presentation without logout.
- Browser bundles contain no confidential client secret.
- Shared infrastructure is isolated in `frontend-libs-21`; domain work remains app-owned.
- Shared, app, Playwright, metadata, filter-chain, and object-authorization tests pass.
