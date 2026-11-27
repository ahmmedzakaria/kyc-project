# System General Public Navigation Implementation Plan

## Document control

- Status: proposed; migration approval pending
- Created: 2026-11-27
- Scope: `backend`, `system_db`, `system-frontend-21`, shared frontend contracts,
  `catalog-frontend-21`, and the Catalog compatibility cutover
- Related plan: `CATALOG_BACKEND_CONTROLLED_LAYOUT_INTEGRATION_PLAN.md`
- Decision: public navigation and its translations will be owned by
  `system_db` as a reusable tenant/client service for every application type
- Migration rule: no database migration is implemented by this plan. The
  proposed migration and cross-database cutover require explicit approval.

## 1. Objective

Create a general System-owned public navigation service that can supply
localized, published navigation to Catalog, corporate sites, portals, login
pages, and future public applications without reusing authenticated privilege
navigation or duplicating navigation schemas in each application database.

The service must support:

- tenant and client ownership;
- multiple named navigation sets and rendering surfaces;
- draft editing and atomic publication;
- localized labels and accessibility text;
- internal routes, external links, groups, and disabled placeholders;
- deterministic hierarchy and ordering;
- tenant-scoped administration privileges;
- anonymous read access through a narrow gateway;
- version-aware caching and invalidation;
- numeric actor IDs for all audit and publication fields;
- fail-closed resolution for missing, inactive, unknown, or ambiguous context.

## 2. Ownership boundaries

| Concern | Authority |
| --- | --- |
| Tenant, verified hostname, client, and tenant/client mapping | `system_db` |
| Public layout profile, theme, sizes, fonts, and region switches | `system_db` |
| Public navigation sets, versions, items, translations, and publication pointer | `system_db` |
| Authenticated application navigation and privilege filtering | Existing System privilege/layout tables |
| Authentication, users, roles, and actor identity | `auth_db` |
| Catalog products, categories, pages, media, contact data, and SEO | `catalog_db` |

Public navigation must not use or extend `sys_priv_modules`,
`sys_layout_navigation_categories`, `sys_layout_feature_groups`, or
`sys_layout_features`. Those tables describe authenticated application
features and privilege-filtered navigation.

## 3. Core model

### 3.1 `sys_public_navigation_sets`

One logical navigation definition for a tenant/client and public rendering
surface.

Proposed columns:

| Column | Type | Rules |
| --- | --- | --- |
| `id` | `bigserial` | Primary key |
| `tenant_id` | `bigint` | Required FK to `sys_tenants` |
| `client_application_id` | `bigint` | Required FK to `sys_acc_client_applications` |
| `navigation_code` | `varchar(80)` | Stable uppercase business key |
| `navigation_name` | `varchar(150)` | Administrator-facing name |
| `surface` | `varchar(30)` | `PRIMARY`, `UTILITY`, `FOOTER`, `MOBILE`, or `LOGIN` |
| `default_locale` | `varchar(20)` | Required locale fallback |
| `default_for_surface` | `boolean` | Explicit default for this tenant/client/surface |
| `active` | `boolean` | Inactive sets cannot resolve publicly |
| `created_by`, `updated_by` | `bigint` | Numeric actor IDs |
| `created_at`, `updated_at` | `timestamp` | Required audit timestamps |

Unique key:

```text
tenant_id + client_application_id + navigation_code
```

Only one active default set per tenant/client/surface is allowed. The default
selection should be represented explicitly rather than inferred from creation
order.

### 3.2 `sys_public_navigation_versions`

A version is an immutable publication candidate. Editors modify a draft
version; anonymous readers resolve only the version selected by the publication
record.

Proposed columns:

```text
id
navigation_set_id
version_number
state                 -- DRAFT, PUBLISHED, RETIRED
change_summary
created_by
updated_by
published_by
created_at
updated_at
published_at
```

Constraints:

- unique `(navigation_set_id, version_number)`;
- at most one mutable draft per set;
- published versions are immutable;
- `published_by` and `published_at` are both populated only for published
  versions;
- all actor fields use numeric IDs, with system actor `0` for migrations and
  automation.

### 3.3 `sys_public_navigation_items`

Items belong to one version, allowing publication to switch the complete tree
atomically.

Proposed columns:

```text
id
navigation_version_id
item_key
parent_id
item_type             -- GROUP, INTERNAL_ROUTE, EXTERNAL_URL
route_path
external_url
target                 -- SELF, BLANK
icon
display_order
active
created_by
updated_by
created_at
updated_at
```

Rules:

- `item_key` is unique within a version and remains stable when cloning a new
  draft;
- `parent_id` must reference an item from the same version;
- a root item has `parent_id = NULL`;
- `INTERNAL_ROUTE` requires a normalized application-relative `route_path`;
- `EXTERNAL_URL` requires an approved `https` URL;
- `GROUP` has no destination;
- cycles, excessive depth, duplicate sibling order, malformed destinations,
  and cross-version parents block publication;
- direct-ID reads and mutations include the navigation set's authorized
  tenant in their repository predicate.

Enforce the same-version parent rule with a unique key on
`(id, navigation_version_id)` and a composite self-reference from
`(parent_id, navigation_version_id)`. Service validation remains necessary for
cycles and maximum depth.

### 3.4 `sys_public_navigation_item_translations`

Proposed columns:

```text
id
navigation_item_id
locale
label
description
aria_label
created_by
updated_by
created_at
updated_at
```

Unique key:

```text
navigation_item_id + locale
```

Publication requires a nonblank label in the set's default locale for every
active item. Requested locale resolution follows:

1. exact normalized requested locale;
2. language-only locale when configured, for example `bn-BD` to `bn`;
3. navigation set default locale;
4. fail publication or omit the invalid item according to validation policy;
   never return a label from another tenant or client.

### 3.5 `sys_public_navigation_publications`

This table is the atomic pointer used by public readers.

Proposed columns:

```text
id
navigation_set_id
published_version_id
publication_number
published_by
published_at
created_by
updated_by
created_at
updated_at
```

There is exactly one current publication row per navigation set. Publishing
validates the complete draft and changes this pointer in one
`systemTransactionManager` transaction. Previous published versions remain
available for audit and rollback.

## 4. Resolution contract

The first release is tenant/client scoped. Business- or branch-specific public
navigation requires a later trusted business/branch resolver and must not be
added by accepting caller-controlled scope IDs. The schema review must reserve
a compatible extension path if that requirement is expected.

Add a presentation-neutral gateway under `gatewaymodule.navigation`:

```java
public interface PublicNavigationModuleGateway extends ModuleGateway {
    PublicNavigationContextDto getPublishedNavigation(
            String clientCode,
            String locale,
            Set<PublicNavigationSurface> surfaces);
}
```

The gateway DTO contains only public fields:

```text
clientCode
locale
publicationVersion
regions[]
  surface
  navigationCode
  items[]
    key
    label
    description
    ariaLabel
    type
    path or externalUrl
    target
    icon
    children[]
```

It must not expose numeric database IDs, tenant IDs, actor IDs, drafts,
privileges, roles, users, client secrets, or authenticated navigation metadata.

Tenant identity comes exclusively from `ResolvedTenantContextHolder`. The
gateway accepts no tenant ID, hostname override, or caller-selected scope. It
must verify an active tenant/client mapping before resolving a set.

## 5. Resolution and failure behavior

Resolution is deterministic:

1. require the trusted resolved tenant;
2. resolve exactly one active client by normalized `clientCode`;
3. verify the active tenant/client mapping;
4. resolve one active default navigation set for every requested surface;
5. resolve its current published version;
6. load all active items and translations with tenant/client ownership in the
   query path;
7. validate hierarchy integrity and build the ordered tree;
8. apply locale fallback and return the reduced public DTO.

Fail closed when tenant or client resolution is unknown, inactive, or
ambiguous. A surface with no published set returns an empty region and an
operational diagnostic; it must not fall back to another tenant, client, or an
authenticated navigation tree. A `system_db` failure propagates as service
unavailability and affects readiness.

## 6. Administration access control

Add a System-owned `Public Navigation` administration feature with separate
privileges:

```text
VIEW
SEARCH
CREATE
UPDATE
PUBLISH
ROLLBACK
DELETE
```

The feature is registered in the privilege catalog and granted explicitly to
administration clients. Missing grants deny access.

All administration APIs require authenticated tenant scope:

```text
GET    /api/v1/system/public-navigation/sets
POST   /api/v1/system/public-navigation/sets
GET    /api/v1/system/public-navigation/sets/{id}
POST   /api/v1/system/public-navigation/sets/{id}/draft
PUT    /api/v1/system/public-navigation/drafts/{versionId}
POST   /api/v1/system/public-navigation/drafts/{versionId}/validate
POST   /api/v1/system/public-navigation/drafts/{versionId}/publish
POST   /api/v1/system/public-navigation/sets/{id}/rollback/{versionId}
DELETE /api/v1/system/public-navigation/sets/{id}
```

Controllers use action-specific `@PrivilegeApi`/authorization checks with
`ApiDataScope.TENANT`. Service and repository methods independently enforce
the authorized tenant. Client, business, branch, tenant, actor, and publication
fields are never trusted from writable request fields.

## 7. System administration UI

Add `Public Navigation Administration` under System Setup. The UI includes:

- authorized tenant selector;
- client application selector filtered by the selected tenant;
- navigation set and surface selector;
- locale management;
- hierarchical item editor with explicit ordering;
- internal/external destination validation;
- draft validation results;
- published versus draft comparison;
- publish and rollback actions protected by their specific privileges;
- active/inactive and publication status indicators;
- read-only publication history with numeric actors resolved to display data
  through the Auth-owned boundary.

Changing tenant or client must reload all dependent data. The UI must never
retain or submit a set from a previously selected scope.

## 8. Catalog integration

`CatalogContextService` remains the response composer. It will call:

```text
LayoutModuleGateway.getPublicLayout("CATALOG", origin)
PublicNavigationModuleGateway.getPublishedNavigation(
    "CATALOG", locale, {PRIMARY, UTILITY, FOOTER})
```

The Catalog repository will continue reading site identity, SEO, contact,
products, categories, pages, and media from `catalog_db`. It will stop being
the authoritative reader for public navigation after cutover.

For response compatibility, the first rollout maps the System `PRIMARY` region
to the existing `PublicSiteResponse.navigation` field. Add an explicit
`navigationRegions` field when the Catalog shell begins consuming utility and
footer regions. The frontend renders these public regions and never consumes
the authenticated System `navTree`.

## 9. Catalog data migration and cutover

Because PostgreSQL cannot create foreign keys or a single Flyway transaction
across `catalog_db` and `system_db`, use an audited export/import/reconciliation
procedure rather than a cross-database migration.

### Phase A: inventory

1. Inventory every tenant/site with `catalog_navigation_items` and
   `catalog_navigation_item_translations`.
2. Reject orphaned parents, cycles, unresolved tenants, duplicate locale rows,
   missing default-locale labels, unsupported URL schemes, and nonnumeric
   actors.
3. Produce a review report before writing System data.

### Phase B: System schema and service

1. Add the five `sys_public_navigation_*` tables through the next approved
   additive System Flyway migration.
2. Add constraints, indexes, repositories, services, gateway, admin APIs,
   privileges, health checks, and backup coverage.
3. Validate empty and upgraded database migration paths.

### Phase C: deterministic import

1. Resolve tenant and client by trusted stable keys.
2. Create a `CATALOG_PRIMARY` set for each Catalog tenant/client.
3. Copy the complete hierarchy into version 1 using stable item keys derived
   from the source identity.
4. Copy translations and numeric audit actors.
5. Validate counts, hierarchy hashes, paths, locales, and ordered tree output.
6. Publish version 1 with system actor `0` only when all validation passes.

The importer is rerunnable and records source database, source table, source
identity, target set, target version, execution ID, and result. Ambiguous or
invalid rows remain unpublished for explicit repair.

### Phase D: comparison and cutover

1. Add shadow reads that compare Catalog and System navigation without changing
   the response.
2. Require matching normalized trees for supported locales.
3. Switch `CatalogContextService` to System navigation through a configuration
   flag.
4. Observe errors, empty-set diagnostics, cache behavior, and SSR output.
5. Make System authoritative after acceptance.

Do not dual-write indefinitely. During the short transition, either freeze
Catalog navigation edits or route all edits through one orchestration service
with explicit failure reporting.

### Phase E: retirement

Keep Catalog navigation tables read-only for one release and retain them for
rollback evidence. Drop or archive them only through a separately approved
Catalog migration after the rollback window closes.

## 10. Cache and publication semantics

Cache public trees using at least:

```text
tenantId + clientApplicationId + navigationSetId
+ publishedVersionId + locale + surface
```

Draft edits do not invalidate public caches. Publishing or rollback changes the
publication pointer and evicts only the affected tenant/client/set entries.
Do not cache solely by hostname, client code, locale, or navigation code.

## 11. Backup and recovery

System backup and restore verification must include all
`sys_public_navigation_*` tables and prove:

- current publication pointers reference valid versions;
- each item parent belongs to the same version;
- default-locale translations are complete;
- a known tenant/client/locale resolves the expected tree;
- no draft becomes public after restore;
- Catalog and System recovery points are recorded independently.

Catalog content recovery still requires `catalog_db`; public navigation and
layout recovery require `system_db`. Recovery documentation must state this
split explicitly.

## 12. Testing strategy

### Database

- clean and upgraded Flyway migration tests;
- unique tenant/client/code and default-surface constraints;
- same-version parent constraint and orphan detection;
- immutable published-version behavior;
- numeric audit and publication actor enforcement;
- deterministic import and rerun tests.

### Backend

- tenant isolation for list, detail, update, publish, rollback, and delete;
- wrong client and inactive mapping rejection;
- unknown, inactive, and ambiguous context failure;
- locale fallback ordering;
- cycle, depth, destination, and missing-label publication rejection;
- atomic publication pointer change;
- public DTO serialization excludes internal IDs and authorization data;
- `CatalogContextService` uses System navigation and keeps Catalog content
  reads in `catalog_db`.

### Frontend

- tenant/client changes reload sets and clear stale selection;
- locale editor completeness;
- hierarchy editing and ordering;
- privilege-specific action visibility;
- SSR and hydration produce identical published navigation;
- PRIMARY, UTILITY, FOOTER, and MOBILE regions render independently;
- empty published regions do not reveal authenticated application navigation.

## 13. Delivery phases

### Phase 1: contract and schema review — Pending

- approve ownership model, surfaces, DTOs, constraints, and publication rules;
- approve the System migration before creating it;
- approve the Catalog import/cutover procedure.

### Phase 2: System backend — Pending

- implement migration, entities, repositories, services, validation,
  publication, gateway, privileges, health, and tests.

### Phase 3: administration UI — Pending

- implement tenant/client scoped navigation editing, translation, validation,
  publication, history, and rollback.

### Phase 4: Catalog import and shadow comparison — Pending

- inventory and repair source data;
- import Catalog navigation into System;
- compare normalized output for every supported locale.

### Phase 5: application cutover — Pending

- compose System public navigation in `CatalogContextService`;
- update the Catalog shell to render navigation regions;
- verify SSR, tenant isolation, cache invalidation, and failure behavior.

### Phase 6: source retirement — Pending

- complete rollback window;
- separately approve archival or removal of Catalog navigation tables;
- update backup, recovery, operational, and ownership documentation.

## 14. Acceptance criteria

- One reusable System service resolves public navigation for any active
  tenant/client application.
- Anonymous responses contain only a published, localized public tree.
- Drafts and authenticated privilege navigation never appear publicly.
- Tenant and client scope cannot be selected or widened by request input.
- Administration actions require explicit tenant-scoped privileges.
- Publication and rollback switch a complete version atomically.
- Catalog returns System-owned public navigation while continuing to read its
  business content from `catalog_db`.
- Invalid, missing, inactive, unknown, or ambiguous configuration fails closed
  without falling back across tenant or client boundaries.
- Migration, import, comparison, backup, restore, and rollback procedures are
  reproducible and auditable.
