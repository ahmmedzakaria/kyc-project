# Frontend Tenant, Privilege, and API Access-Control Architecture Plan

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

## 2. Current-state matrix

| Concern | `frontend-libs-21` | `system-frontend-21` | `kyc-frontend-21` |
|---|---|---|---|
| Authentication | Shared implementation exists | Uses shared auth | Uses shared auth |
| Client identity | Shared `ApiService` sends client code | `SYSTEM_ADMIN_WEB` | `WEB` |
| Route policy | Shared guard exists | Bypassed on admin routes | Enabled on person routes |
| UI policy | Shared directive exists | Inconsistent use | Used for major person actions |
| Effective tenant/scopes | Not modeled | Manually decodes JWT tenant | Not consumed |
| Revocation refresh | Login/logout oriented | Stale UI possible | Stale UI possible |
| Denial handling | Generic 401/403 behavior | No recovery policy | No recovery policy |
| Safe replacement | No shared abstraction | Client grants are unsafe | Not currently used |
| Hierarchical scope UI | Missing | Required for clients/users | Presentation only |
| Direct-ID loading | Generic API support | Client list-and-filter | Person pages require router state |
| Domain coverage | Infrastructure only | Broad admin UI, incomplete parity | Person CRUD; documents missing |
| App tests | Shared primitives have some tests | Essentially absent | One endpoint test |

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

## 5. `frontend-libs-21` gap list

| ID | Gap | Required outcome |
|---|---|---|
| FL-1 | Authorization state split between signals and local storage | One live reactive authority |
| FL-2 | Effective tenant/scopes absent | Typed server-validated context |
| FL-3 | No revocation refresh protocol | Single-flight refresh/version or TTL |
| FL-4 | Generic interceptor lacks stable-code behavior | Typed denial coordinator |
| FL-5 | Policy checks split across services/directives/roles | One programmatic policy service |
| FL-6 | No safe full-replacement abstraction | Load-before-save invariant |
| FL-7 | No hierarchical scope control | Normalized tuple selector |
| FL-8 | Hard-coded development ports | Environment-driven origin selection |
| FL-9 | `ApiService.post()` mutates JSON bodies | Immutable enrichment |
| FL-10 | Missing multi-user/multi-app lifecycle tests | Context isolation coverage |

## 6. `system-frontend-21` gap list

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

## 8. Required backend additions

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

- Disable unresolved system client replacement editors.
- Production-disable the KYC component demo.
- Hide local-only workflow decisions.
- Confirm both Angular clients are registered as public browser clients with no bundled secret.

Gate: the current UI cannot silently erase grants or present nonfunctional security operations.

### Phase 1 — Shared authorization core

- Implement effective tenant/scope models and reactive context in `platform`.
- Consolidate privilege/policy evaluation.
- Add refresh/clear lifecycle and typed denial coordination.
- Correct backend-origin selection and immutable request enrichment.

Gate: both apps consume one live, fail-closed authorization source.

### Phase 2 — Shared safety UI

- Implement replacement state/checklist and confirmation summary in `shared`.
- Implement hierarchical scope selector.
- Implement reusable denial/configuration/retry presentation.

Gate: shared components remain domain-neutral and dependency direction is preserved.

### Phase 3 — Backend contract completion

- Extend application context.
- Add client detail and current assignments.
- Normalize client scope writes.
- Add user scope administration.
- Add KYC profile detail.
- Seed both clients' route/UI policies.

Gate: every editable or directly addressable state has an authoritative protected read.

### Phase 4 — Align `system-frontend-21`

- Adopt shared context, replacement, and scope primitives.
- Remove JWT decoding and route bypasses.
- Gate every specialized action.
- Add user scope administration and context refresh after mutations.

Gate: VIEW-only, specialized-action, and full-admin accounts see and perform exactly their allowed operations.

### Phase 5 — Align `kyc-frontend-21`

- Add direct profile loading and typed services.
- Implement document flows.
- Add multipart field allowlists.
- Improve photo loading and error classification.
- Show effective scope and verify policies.

Gate: direct URLs work through scoped backend reads and profile/global IDs cannot be confused.

### Phase 6 — Revocation and multi-tenant validation

- Verify privilege removal during active sessions.
- Verify sequential users in one browser do not share context.
- Test hostname/token/client/scope mismatches.
- Test tenant, business, branch, and sibling-branch decisions.

Gate: the next request and UI refresh reflect revocation without logout.

### Phase 7 — Automated enforcement gate

- Run shared unit tests, app HTTP/component tests, Playwright matrices, backend filter-chain tests, API metadata coverage, and object-authorization tests.

Gate: enforcement mode is enabled and the complete frontend/backend authorization suite passes.

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

## 12. Definition of done

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

