# Catalog Backend-Controlled Layout Integration Plan

## Document control

- Status: in progress
- Created: 2026-11-25
- Last updated: 2026-11-27
- Scope: `backend`, `catalog_db`, `system_db`, `catalog-frontend-21`, `frontend-libs-21`, and `system-frontend-21`
- Parent plan: `PUBLIC_CATALOG_AND_CORPORATE_WEBSITE_IMPLEMENTATION_PLAN.md`
- Related backend design: `systemmodule/layout/LAYOUT_SUBMODULE_BUSINESS_AND_IMPLEMENTATION_PLAN.md`
- Public navigation plan: `SYSTEM_GENERAL_PUBLIC_NAVIGATION_IMPLEMENTATION_PLAN.md`
- Migration status: Catalog V3 and System V83 are implemented. System V83 was
  validated against the upgraded local database in a rollback transaction.

### Implementation status

| Area | Status | Evidence / remaining work |
| --- | --- | --- |
| Trusted hostname, CATALOG client, and Origin validation | **Done** | Public Catalog requests resolve tenant and validate the exact client/origin contract. |
| Catalog datasource, schema, Flyway, health, and Compose wiring | **Done** | `catalog_db` is configured; Catalog V1-V3 are applied. |
| System layout profile | **Done** | `WEB_CATALOG_LAYOUT` is public-safe and System V83 reproducibly bootstraps its profile, theme, sizes, fonts, mapping, and assignment. |
| Tenant/client layout assignment | **Done** | Assignment ID `11` is active and default for tenant `7`, client `CATALOG` (ID `11`). |
| CATALOG tenant mapping | **Done** | Active `sys_acc_client_application_tenants` mapping exists for tenant `7`. |
| Layout administration UI | **Done** | Authorized tenant selector, client-specific reload, inactive records, and profile/assignment statuses are implemented. |
| Public layout DTO and Catalog gateway | **Done** | A reduced gateway contract is mapped by System and composed into `PublicSiteResponse`; missing or unsafe assignments use an explicit public-safe fallback. |
| General public navigation | **Planned** | Public navigation ownership moves to reusable `system_db` tables and a public navigation gateway; see `SYSTEM_GENERAL_PUBLIC_NAVIGATION_IMPLEMENTATION_PLAN.md`. |
| Catalog shell, theme tokens, and region switches | **Pending** | The Catalog root still uses compiled shell markup and fixed CSS tokens. |
| API-driven header/footer navigation | **Pending** | Header and footer links remain hard-coded. |
| Centralized breadcrumbs | **Pending** | Breadcrumb markup remains page-owned. |
| SSR/hydration verification for layout | **Pending** | Cannot be completed before backend composition and shell integration. |
| Cache invalidation for public layout | **Pending** | No combined Catalog/layout cache contract is implemented. |
| Backup and restore inclusion | **Pending** | `backup-all-databases.sh` does not yet include `catalog_db` by default. |

Database status can be rechecked with
`backend/db_script/query_system_db_layout_details.sql` using tenant `7` and
client code `CATALOG`.

> **Architecture update (2026-11-27):**
> `SYSTEM_GENERAL_PUBLIC_NAVIGATION_IMPLEMENTATION_PLAN.md` supersedes this
> document wherever it assigns public header/footer navigation and translations
> to `catalog_db`. Catalog business content remains in `catalog_db`; reusable
> public navigation will be owned and published by `system_db`.

## 1. Objective

Connect the public Catalog website to NexaCore's existing backend-controlled
layout configuration without mounting the authenticated KYC application shell
or weakening tenant, client, publication, privilege, or SSR boundaries.

The integration will let an administrator control Catalog presentation through
the existing System layout model:

- active public layout profile;
- theme colors;
- fonts and dimensions;
- header, footer, and breadcrumb visibility;
- tenant-specific branding overrides;
- density and RTL capability.

Public website navigation remains Catalog content in `catalog_db`. KYC
navigation remains a privilege-filtered application tree in `system_db`.

## 2. Current state

### 2.1 Catalog frontend

`catalog-frontend-21` currently owns a fixed public shell containing a utility
bar, header, hard-coded primary links, router outlet, and footer. It loads site
identity and contact data from:

```text
GET /api/v1/public/site?lang=<locale>
```

The response already includes `navigation`, but the header does not render it.
Breadcrumb HTML is duplicated in individual product, service, and article
components. Theme and shell visibility are compiled into the frontend.

### 2.2 Existing layout backend

`LayoutContextService#getPublicLayout(clientCode, origin)` already resolves a
tenant-owned default client layout assignment and returns:

- `activeProfileCode`;
- `availableProfiles`;
- themes and primary colors;
- sizes;
- fonts;
- branding within the active profile.

The public method intentionally returns an empty `navTree`. The authenticated
method builds a privilege-filtered `navTree` for KYC/System/Log application
navigation.

### 2.3 Catalog authorization

The public Catalog endpoint requires:

```http
X-Client-Code: CATALOG
```

The verified request hostname resolves the tenant. The `CATALOG` client is
validated independently, including exact Origin validation when an Origin is
present.

Administrative catalog actions are registered by
`CatalogPrivilegeProvider`. Its `Catalog Content` feature currently provides:

- VIEW;
- SEARCH;
- CREATE;
- UPDATE;
- PUBLISH;
- DELETE.

Those privileges govern authenticated content administration. They do not
govern anonymous rendering of an already-published site.

## 3. Architecture decisions

### ADR-CATALOG-LAYOUT-001: reuse configuration, not the KYC shell

The Catalog will consume the existing backend layout contract but will render a
Catalog-specific public shell. It will not use the shared authenticated
`LayoutComponent`, `RailNavComponent`, authenticated header, logout controls,
status bar, or mega-panel navigation.

Reason: those components assume a logged-in user, application privileges, rail
navigation, and client feature authorization. Catalog is an anonymous,
SEO-sensitive, SSR-rendered website.

### ADR-CATALOG-LAYOUT-002: split presentation from public content

Ownership is:

| Concern | Authority |
| --- | --- |
| Layout profile and region switches | `system_db` layout tables |
| Theme, fonts, sizes, density, RTL | `system_db` layout tables |
| Tenant presentation overrides | `sys_client_layout_profiles` |
| Site name, contact, locales, SEO | `catalog_db` |
| Public header/footer navigation and translations | General public navigation tables in `system_db` |
| Product-category navigation | `catalog_db` category tables |
| KYC operational navigation | privilege/layout tables in `system_db` |

### ADR-CATALOG-LAYOUT-003: extend the existing public site response

`GET /api/v1/public/site` will include a reduced public layout block. The
Catalog will not call `/api/v1/auth/application-context/public`.

Reason: the auth application-context flow also resolves login policy, OAuth
client configuration, redirect URIs, and registration settings. Those are not
requirements for an anonymous public Catalog.

### ADR-CATALOG-LAYOUT-004: no privilege navigation in the public response

The public Catalog layout response must not include authenticated application
features, privilege codes, route policies, UI policies, users, roles, or scope
assignments. `layout.navTree` remains empty or is omitted. Public navigation is
resolved through the separate System public-navigation gateway and initially
mapped to the existing Catalog `navigation` field for response compatibility.

### ADR-CATALOG-LAYOUT-005: site identity wins over generic branding

Precedence is:

1. `catalog_db` owns the public site name, contact details, SEO, and published
   logo.
2. The layout profile owns presentation tokens and region visibility.
3. Tenant/client assignment branding may supply favicon, support URL, or
   presentation fallback assets when the Catalog site has no published value.

The API assembler must apply this precedence once. The frontend must not make
independent conflicting choices between two logo or display-name values.

### ADR-CATALOG-LAYOUT-006: action performers are numeric actor references

Every action-performer field written by this integration, including
`created_by`, `updated_by`, `published_by`, and equivalent lifecycle fields,
must contain the actor's numeric ID. Do not store a username, display name,
email address, migration label, or other descriptive string. User actions use
the authenticated user ID; migrations, seeders, jobs, and integrations use the
reserved numeric system actor ID. Resolve display information from the
Auth-owned source when reading it.

This is an application-level reference across databases. Do not introduce a
cross-database foreign key, and do not guess an ID from an unresolved string.
Catalog migration V3 converts every existing `created_by`, `updated_by`, and
`published_by` column from `VARCHAR(255)` to `BIGINT`, maps the trusted V2
marker to system actor ID `0`, and rejects any unresolved descriptive value.
V1 and V2 remain unchanged to preserve their deployed Flyway checksums.

## 4. Target request and response flow

```text
Browser / SSR request
  -> trusted Host resolves active tenant
  -> CATALOG client is validated
  -> catalog_db returns the published site and Catalog business content
  -> system_db returns the tenant/client public layout and published navigation
  -> backend assembles one public presentation DTO
  -> Catalog SSR shell renders configuration and content
```

Target response shape:

```json
{
  "siteKey": "arsv-public-site",
  "hostname": "abd.localhost",
  "name": "Rohman & Shuvo",
  "navigation": [],
  "categoryNavigation": [],
  "contact": {},
  "socialLinks": [],
  "defaultSeo": {},
  "layout": {
    "activeProfileCode": "WEB_CATALOG_LAYOUT",
    "availableProfiles": [
      {
        "code": "WEB_CATALOG_LAYOUT",
        "layoutType": "PUBLIC",
        "topbarEnabled": true,
        "sidebarEnabled": false,
        "footerEnabled": true,
        "breadcrumbEnabled": true,
        "commandBarEnabled": false,
        "rtlEnabled": false,
        "brand": {}
      }
    ],
    "themes": [],
    "sizes": {},
    "fonts": {}
  }
}
```

## 5. Backend changes

### 5.1 Add a presentation-neutral public layout contract

Do not expose JPA entities. Either reuse `LayoutContextDto` after verifying
that every field is safe for anonymous use, or introduce a narrower contract:

```text
PublicLayoutContextDto
PublicLayoutProfileDto
PublicThemeDto
PublicSizeConfigDto
PublicFontConfigDto
PublicBrandDto
```

The preferred implementation is a narrow public DTO so future authenticated
layout fields cannot accidentally become public through serialization.

**Implemented:** public DTOs live under `gatewaymodule.layout.dto`; they omit
tenant IDs, assignment IDs, privilege navigation, policies, roles, and users.

### 5.2 Add a Catalog-facing layout gateway

`catalogmodule` must not access System layout repositories. Add or extend a
stable gateway contract under `gatewaymodule.layout`:

```java
PublicLayoutContextDto getPublicLayout(String clientCode, String origin);
```

Tenant identity must come from `ResolvedTenantContextHolder`. Do not accept a
tenant ID from a request header, parameter, or Catalog DTO. Origin validation
remains the responsibility of client authentication and must not select the
tenant.

**Implemented:** `SystemLayoutModuleGateway` maps the internal System layout
DTO to the reduced contract. Catalog passes the request Origin while tenant
selection continues to use `ResolvedTenantContextHolder`.

### 5.3 Assemble layout into `PublicSiteResponse`

Update `PublicSiteResponse` and `CatalogContextService` to include the public
layout resolved for constant client code `CATALOG`.

The repository remains responsible only for `catalog_db` reads. Layout lookup
and response composition belong in the service layer so the Catalog repository
does not cross datasource boundaries.

**Implemented:** `PublicCatalogSiteRepository` remains Catalog-only;
`CatalogContextService` performs composition for constant client code
`CATALOG`.

### 5.4 Failure behavior

The endpoint must preserve current fail-closed behavior:

- unknown, inactive, unverified, or ambiguous hostname: reject before the
  controller;
- missing/inactive/wrong client: reject;
- no published Catalog site: `404`;
- assigned layout profile missing or inactive: apply the documented public
  fallback profile and emit an operational warning;
- system layout database unavailable: readiness must fail; the public endpoint
  must not silently return an unrelated tenant's layout;
- catalog database unavailable: readiness and the public request fail.

The fallback profile must be public-safe: no sidebar, no command bar, no
authenticated navigation, and no authenticated user controls.

### 5.5 Cache boundaries

If public-site caching is added, cache keys must contain at least:

```text
tenantId + hostname + locale + catalog publication version + layout assignment/profile version
```

Catalog publication and layout assignment/profile mutations must invalidate
the appropriate tenant/client entries. Do not cache by hostname alone without
tenant resolution.

## 6. System database work

The live configuration was created through System administration and captured
by additive migration `V83__bootstrap_catalog_public_layout.sql` for repeatable
environments.

### 6.1 Create the public Catalog profile — **Done**

Create an active profile with the intended defaults:

| Field | Value |
| --- | --- |
| `profile_code` | `WEB_CATALOG_LAYOUT` |
| `layout_type` | `PUBLIC` |
| `navigation_mode` | `MODULE_LIST` |
| `theme_mode` | `LIGHT` initially |
| `density` | `COMFORTABLE` |
| `topbar_enabled` | `true` |
| `sidebar_enabled` | `false` |
| `sidebar_collapsed` | `false` |
| `footer_enabled` | `true` |
| `breadcrumb_enabled` | `false` currently; change to `true` before breadcrumb integration |
| `command_bar_enabled` | `true` currently; change to `false` for the public-safe contract |
| `rtl_enabled` | `false` initially |
| `active` | `true` |

The active profile, theme, primary colors, sizes, and fonts exist in
`system_db`. Optional profile branding is absent and is not required while the
published Catalog site owns identity. A reviewed additive bootstrap migration
is still pending so clean environments can reproduce the configuration. Every
future inserted row must populate `created_by`, `updated_by`, `created_at`, and
`updated_at`.

### 6.2 Assign the profile to tenant and client — **Done**

Create an active default `sys_client_layout_profiles` assignment for:

```text
tenant_id = 7
client_code = CATALOG
profile_code = WEB_CATALOG_LAYOUT
assignment_scope = CLIENT
device_target = ANY
default_profile = true
selectable = true
active = true
```

The deployed assignment is ID `11`, active, default, and selectable. Whether a
public Catalog should expose profile selection remains pending; the recommended
production value is `selectable = false`. Reproducible migrations or bootstrap
code must use joins to resolve IDs and must not hardcode client or profile
primary keys.

### 6.3 Add the CATALOG tenant assignment — **Done**

Ensure `CATALOG` has an active tenant assignment in
`sys_acc_client_application_tenants` for tenant 7. This keeps layout assignment
integrity checks and client ownership aligned.

Long term, Catalog client creation and tenant/profile assignment should use a
dedicated idempotent bootstrap service or reviewed migrations rather than
remaining coupled to the general authentication `DataSeeder`.

## 7. Catalog database work — **Pending**

The current published site migration creates the site and English site
translation but no navigation rows. A separate additive `catalog_db` migration
is required and must be explicitly approved before implementation.

Seed tenant-owned, published navigation and English translations for:

| Label | Path | Order |
| --- | --- | ---: |
| Home | `/` | 10 |
| Products | `/products` | 20 |
| Services | `/services` | 30 |
| About | `/about` | 40 |
| News | `/news` | 50 |
| Gallery | `/gallery` | 60 |
| Contact | `/contact` | 70 |

All relationships must use the tenant-qualified site key/ID. Populate
publication metadata and every audit column. Use conflict-safe inserts without
overwriting administrator-managed content.

Future Catalog administration must edit these records through tenant-scoped
services, not through direct System layout navigation tables.

## 8. Privilege and administration changes

### 8.1 Existing privileges

`CatalogPrivilegeProvider` already registers one `Catalog Content` feature with
VIEW, SEARCH, CREATE, UPDATE, PUBLISH, and DELETE actions. These actions are
appropriate for site, navigation, page, product, and media administration when
controller and service predicates remain tenant-scoped.

### 8.2 Layout administration

Layout profile and client-layout assignment operations continue to use the
existing System layout/client administration privileges. Catalog content
privileges must not grant permission to edit global layout profiles or another
tenant's client assignment.

### 8.3 Optional privilege split

If navigation and theme administration need different operator roles, extend
`CatalogPrivilegeProvider` with separately approved feature codes rather than
checking ad hoc role names. Candidate features are:

- Catalog Site Configuration;
- Catalog Navigation;
- Catalog Content;
- Catalog Publication;
- Catalog Media.

Do not change feature codes already deployed. Add new stable codes and update
backend `@PrivilegeApi`, `@PreAuthorize`, route policies, UI policies, and menu
linkage together.

## 9. Frontend library changes — **Pending**

### 9.1 Extend Catalog contracts

Add public layout interfaces to `@nexacore/catalog`, or move neutral layout
interfaces into a small shared contract library. Do not add a dependency from
the public Catalog app to the entire authenticated platform package merely to
reuse TypeScript types.

Extend `CatalogSiteView` with:

```ts
readonly layout: CatalogPublicLayoutView;
```

Keep the TypeScript contract aligned with the backend public DTO.

### 9.2 Add an SSR-safe layout service

Create `CatalogLayoutService` that exposes computed state for:

- active profile;
- topbar/header visibility;
- footer visibility;
- breadcrumb visibility;
- theme;
- fonts;
- sizes/density;
- RTL;
- resolved favicon/branding.

Browser DOM work must use Angular `DOCUMENT` and `isPlatformBrowser`. Prefer
server-renderable classes and CSS variables. Do not reference `window` or
`document` unguarded during SSR/prerender.

### 9.3 Map shared tokens to Catalog tokens

Create an explicit mapping instead of assuming KYC CSS variable names:

| Backend value | Catalog token |
| --- | --- |
| theme text | `--catalog-color-text` |
| theme paper | `--catalog-color-background` |
| theme card | `--catalog-color-surface` |
| theme accent | `--catalog-color-primary` |
| body font | `--catalog-font-body` |
| heading font | `--catalog-font-heading` |
| base radius | `--catalog-radius-base` |
| space unit | `--catalog-space-unit` |

Validate and constrain remote font URLs before injecting a stylesheet link.

## 10. Catalog application changes — **Pending**

### 10.1 Split the public shell

Refactor the current root template into focused components:

```text
CatalogShellComponent
CatalogUtilityBarComponent
CatalogHeaderComponent
CatalogPrimaryNavigationComponent
CatalogBreadcrumbComponent
CatalogFooterComponent
```

The shell uses layout signals to render configured regions. It does not render
an authenticated rail or status bar.

### 10.2 Render System-owned public navigation

Replace hard-coded header and footer links with the published navigation
regions resolved by the System public-navigation gateway. During compatibility
rollout, the PRIMARY region is mapped to `site.navigation`. Support published
child items as accessible dropdowns. Route links must pass through the existing
locale-aware path helper.

Define empty-navigation behavior explicitly. Recommended behavior is a visible
brand/home link and no fabricated content links, with an operational warning in
development.

### 10.3 Centralize breadcrumbs

Create a `CatalogBreadcrumbService` and render one shared breadcrumb component.
Static routes provide route metadata; dynamic product, service, and article
pages add the content title after loading.

Breadcrumb requirements:

- linked Home and ancestor segments;
- localized paths and labels;
- current item rendered as text;
- valid server-rendered markup;
- reset on navigation and not retain stale dynamic segments;
- hidden when the active profile disables breadcrumbs.

### 10.4 Preserve SSR and SEO

Layout and navigation must be available during SSR. Avoid a browser-only shell
that changes structure after hydration. Verify canonical URL, language, title,
structured data, header navigation, and breadcrumbs in generated HTML.

## 11. System frontend changes — **Partially done**

Use existing layout/profile and client assignment administration where
possible. Ensure administrators can find and inspect:

```text
client: CATALOG
tenant: 7
profile: WEB_CATALOG_LAYOUT
layout type: PUBLIC
```

The layout assignment administration portion is done. It now supports an
explicit authorized tenant selector, client-change reload, active/inactive
assignment visibility, and separate profile and assignment status indicators.
General public-navigation administration remains pending.

Add the general `Public Navigation Administration` feature described in
`SYSTEM_GENERAL_PUBLIC_NAVIGATION_IMPLEMENTATION_PLAN.md`. Do not edit public
navigation using the authenticated application navigation-tree editor because
the two trees have different ownership and authorization semantics.

## 12. Backup and recovery changes — **Pending**

`DATABASE_BACKUP_AND_RECOVERY_IMPLEMENTATION_PLAN.md` currently lists Auth,
System, KYC, GIS, and Log in its initial scope. Add:

| Logical module | Database |
| --- | --- |
| Catalog content and public site configuration | `catalog_db` |
| General public navigation and translations | `system_db` |

A usable Catalog recovery requires both:

- `system_db` for tenants, verified domains, the CATALOG client, origins,
  layout assignments/profiles, and published public navigation;
- `catalog_db` for the published site, site translations, products, categories,
  pages, media, and other Catalog content.

The backup manifest and restore verification must check both databases and
record their independent snapshot timestamps. Restore verification must prove
that a known verified hostname can resolve a published Catalog site and its
assigned public layout without exposing secrets.

## 13. Implementation phases

### Phase 1: contracts and backend composition — **Done**

1. Define reduced public layout DTOs and gateway.
2. Extend `PublicSiteResponse`.
3. Compose published Catalog data with the public layout.
4. Add fail-closed and fallback tests.

Exit criteria: the public site endpoint returns a tenant-specific, anonymous-
safe layout block with no privilege navigation.

### Phase 2: System configuration — **Done**

1. Create `WEB_CATALOG_LAYOUT` and its audited supporting configuration.
   **Done:** records exist with public-safe flags and V83 provides the
   reproducible bootstrap.
2. Assign `WEB_CATALOG_LAYOUT` to tenant 7 and CATALOG. **Done**
3. Add/verify the active CATALOG tenant assignment.
   **Done**
4. Validate a reproducible migration on clean and upgraded databases.
   **Done for the upgraded database path:** V83 executed successfully in a
   rollback transaction. The clean Testcontainers path remains environment-
   dependent when Docker is unavailable.

Exit criteria: tenant 7 resolves `WEB_CATALOG_LAYOUT`; another tenant cannot use
tenant 7's assignment.

### Phase 3: general System public navigation — **Pending**

1. Implement the approved System public-navigation schema and gateway.
2. Import and publish tenant 7 Catalog navigation and translations.
3. Verify tenant-qualified relationships, versions, audit actors, and locale
   fallback.
4. Confirm the public endpoint returns the System-owned hierarchy.

Exit criteria: navigation is data-backed and contains no frontend-only link.

### Phase 4: frontend shell integration — **Pending**

1. Add Catalog public layout models and service. **Models done; token
   application service pending.**
2. Map theme/font/size values to Catalog tokens.
3. Split the shell and apply region switches.
4. Render API-provided navigation.
5. Centralize breadcrumbs.

Exit criteria: changing the assigned layout/theme/navigation changes the
server-rendered tenant site without rebuilding the frontend.

### Phase 5: administration and operations — **Partially done**

1. Confirm layout assignment management for CATALOG. **Done**
2. Implement privilege-controlled general public-navigation administration.
   **Pending**
3. Add cache invalidation and authorization audit evidence. **Pending**
4. Add `catalog_db` to backup documentation, scripts, and restore verification.
   **Pending**

## 14. Verification plan

### Backend

- `CATALOG` and tenant 7 resolve `WEB_CATALOG_LAYOUT`.
- Public response contains only anonymous-safe layout fields.
- Unknown, inactive, ambiguous, or unverified hosts fail closed.
- Missing, wrong, or inactive CATALOG client fails closed.
- Origin mismatch is rejected when Origin is present.
- Tenant 8 cannot read tenant 7's site, navigation, branding, or assignment.
- Missing published site returns `404`.
- Missing layout assignment uses only the documented public-safe fallback.
- Layout database failure never falls back to another tenant.
- Migration tests pass on a clean schema and from the prior Flyway version.

### Frontend

- SSR and production builds pass.
- Header/footer/breadcrumb switches are honored.
- Theme, fonts, size, favicon, and RTL values are applied safely.
- Published nested navigation renders with keyboard-accessible behavior.
- English and Bengali paths remain correct.
- Dynamic breadcrumbs use loaded content titles.
- Direct URL load and hydration produce the same shell and breadcrumb.
- Empty and malformed optional layout fields use deterministic safe defaults.

### Operations

- Compose configuration renders successfully.
- Backend and Catalog readiness checks include required databases/services.
- Backup target inventory includes `catalog_db`.
- Restore verification proves the system/catalog cross-database references.

## 15. Acceptance criteria

The integration is complete when:

1. A verified tenant hostname returns its published Catalog site and assigned
   public layout through one endpoint.
2. Catalog appearance and region visibility can change through backend layout
   administration without a frontend rebuild.
3. Header/footer navigation is sourced from published tenant/client-owned
   System public-navigation records rather than hard-coded links.
4. Breadcrumbs are centralized, localized, linked, SSR-rendered, and driven by
   route/content context.
5. No authenticated KYC navigation, privilege metadata, user state, or tenant
   header is exposed to the public site.
6. Catalog content privileges protect every administrative operation, while
   layout administration retains its existing System privilege boundary.
7. Tenant isolation, audit fields, migration validation, frontend builds,
   backend tests, Compose validation, and backup/restore evidence pass.

## 16. Material risks

- Reusing the authenticated shell would expose unsuitable UX and increase the
  risk of leaking authenticated metadata.
- Treating `layout.navTree` and Catalog navigation as one model would mix
  privilege navigation with published content.
- Duplicate site/layout branding without defined precedence would produce
  inconsistent tenant identity.
- Browser-only DOM mutation would break SSR or cause hydration differences.
- Hard-coded tenant/client/profile primary keys would make migrations unsafe.
- Restoring only `system_db` or only `catalog_db` would leave the public site
  incomplete.
