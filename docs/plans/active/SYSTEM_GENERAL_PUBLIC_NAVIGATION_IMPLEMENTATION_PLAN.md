# System General Public Navigation Implementation Plan

## Document control

- Status: in progress; foundation implemented, backend and application cutover pending
- Created: 2026-11-27
- Last updated: 2026-11-27
- Scope: `backend`, `system_db`, `system-frontend-21`, shared frontend
  contracts, `catalog-frontend-21`, and the Catalog cutover
- Related plan: `CATALOG_BACKEND_CONTROLLED_LAYOUT_INTEGRATION_PLAN.md`
- Future upgrade:
  `CENTRAL_NAVIGATION_VERSIONING_PUBLICATION_LOCALIZATION_UPGRADE_PLAN.md`
- Decision: implement public navigation using the same direct hierarchy,
  active-state, client-assignment, and runtime-filtering pattern used by the
  existing privilege-controlled navigation
- Deferred: navigation versions, drafts, publication pointers, rollback,
  translations, and public/private audience conversion are excluded from this
  phase and moved to the future central upgrade plan
- Migration status: System migration
  `V84__add_public_navigation_registry.sql` now exists in the current codebase.
  Any further migration or change to the deployed schema still requires
  explicit approval.

## Current implementation status

Reviewed against the codebase on 2026-11-27.

### Done

- Added System migration `V84__add_public_navigation_registry.sql` with the
  three planned tables, hierarchy and tenant ownership constraints,
  destination checks, audit columns, optimistic-lock columns, and resolution
  indexes.
- Added JPA entities for public navigation groups, items, and client item
  assignments with explicit System table mappings and audit fields.
- Added the presentation-neutral `PublicNavigationModuleGateway` boundary.
- Added `PublicNavigationContextDto` with regions, groups, recursive items,
  destinations, targets, icons, and presentation labels.

### Partially done

- The backend data model and external gateway contract exist, but there is no
  repository, service implementation, validation layer, or gateway adapter.
- The gateway currently accepts `Set<String>` surfaces; the planned
  `PublicNavigationSurface` enum and typed contract are not yet implemented.
- Optimistic-lock fields exist on groups and items, but stale-write behavior
  is not implemented or tested through administration services.
- The Catalog frontend has an existing public navigation shell and an end-to-
  end navigation test, but it still renders navigation supplied by the
  Catalog-owned response rather than System public navigation regions.

### Pending

- Implement tenant-qualified repositories, tree resolution, assignment
  replacement, validation, integrity checks, preview, and mutation services.
- Implement administration controllers, action-specific privileges, API
  registration, cache eviction, health evidence, and targeted backend tests.
- Implement the System administration UI and its tenant/client scope reset,
  hierarchy editing, assignment, preview, integrity, and conflict workflows.
- Inventory and reconcile existing Catalog navigation and translations, then
  perform the deterministic import and shadow comparison.
- Compose System navigation in `CatalogContextService`, add navigation regions
  to the public response, and switch the Catalog shell to those regions.
- Verify clean and upgraded migration paths, tenant isolation, failure and
  empty-state behavior, cache eviction, SSR, backup, and restore.

## 1. Objective

Create a reusable System-owned public navigation registry for Catalog,
corporate sites, login pages, portals, and future public clients.

The first implementation deliberately follows the existing authenticated
navigation model:

```text
Active public navigation hierarchy
        +
Active tenant/client item assignments
        +
Trusted resolved tenant and client
        ↓
Effective public navigation tree
```

The first implementation supports:

- tenant-owned public navigation definitions;
- client-specific item assignment;
- PRIMARY, UTILITY, FOOTER, MOBILE, and LOGIN surfaces;
- hierarchical groups and items;
- internal routes, external links, and non-clickable groups;
- active/inactive state and deterministic ordering;
- numeric audit actor IDs;
- tenant-scoped administration privileges;
- a narrow anonymous gateway;
- fail-closed tenant/client resolution;
- direct changes becoming effective immediately after a successful write.

The first implementation does not support:

- draft navigation trees;
- immutable navigation versions;
- publication or rollback;
- translation tables or locale fallback;
- public/private/restricted audience transitions;
- reuse of authenticated privilege-navigation tables.

## 2. Relationship to existing privilege-controlled navigation

Existing authenticated navigation is a shared hierarchy filtered at runtime:

```text
sys_layout_module_groups
  → sys_priv_modules
    → sys_layout_navigation_categories
      → sys_layout_feature_groups
        → sys_layout_features
          → sys_layout_feature_privileges

sys_acc_client_feature_permissions
  → limits features for the resolved tenant/client

authenticated user privileges
  → limit features for the current user
```

The new public model uses the same architectural style without privileges:

```text
sys_public_navigation_groups
  → sys_public_navigation_items

sys_acc_client_public_navigation_items
  → limits items for the resolved tenant/client
```

Public navigation remains separate from the authenticated hierarchy. Public
links are not authenticated application features and must not enter the
privilege tree.

## 3. Ownership boundaries

| Concern | Authority |
| --- | --- |
| Tenant, verified hostname, client, and tenant/client mapping | `system_db` |
| Public layout profile, theme, fonts, sizes, and region switches | `system_db` |
| Public navigation groups, items, and client assignments | `system_db` |
| Authenticated feature navigation and privilege filtering | Existing System layout/privilege tables |
| Authentication, users, roles, and audit actor identity | `auth_db` |
| Catalog products, categories, pages, media, contact data, and SEO | `catalog_db` |

## 4. Initial database model

### 4.1 `sys_public_navigation_groups`

A group is the tenant-owned root for one public rendering surface.

| Column | Type | Rules |
| --- | --- | --- |
| `id` | `bigserial` | Primary key |
| `tenant_id` | `bigint` | Required FK to `sys_tenants` |
| `group_code` | `varchar(80)` | Stable uppercase business key |
| `group_name` | `varchar(150)` | Administration label |
| `surface` | `varchar(30)` | `PRIMARY`, `UTILITY`, `FOOTER`, `MOBILE`, or `LOGIN` |
| `display_order` | `integer` | Required deterministic order |
| `active` | `boolean` | Inactive groups are not resolved |
| `version` | `bigint` | Optimistic-lock counter only |
| `created_by`, `updated_by` | `bigint` | Required numeric actor IDs |
| `created_at`, `updated_at` | `timestamp` | Required audit timestamps |

Constraints:

```text
unique (tenant_id, group_code)
check surface in (PRIMARY, UTILITY, FOOTER, MOBILE, LOGIN)
```

A tenant may have multiple groups for a surface. `display_order` determines
their order; resolution never infers order from primary keys.

### 4.2 `sys_public_navigation_items`

Items form a recursive hierarchy within a group.

```text
id
tenant_id
navigation_group_id
parent_id
item_code
item_type             -- GROUP, INTERNAL_ROUTE, EXTERNAL_URL
label
description
aria_label
route_path
external_url
target                -- SELF, BLANK
icon
display_order
active
version               -- optimistic-lock counter only
created_by
updated_by
created_at
updated_at
```

Constraints and rules:

- unique `(navigation_group_id, item_code)`;
- `parent_id` is optional for a root item;
- parent and child must belong to the same tenant and group;
- use a composite self-reference so a cross-group parent cannot be stored;
- `INTERNAL_ROUTE` requires a normalized application-relative path;
- `EXTERNAL_URL` requires an allowed `https` destination;
- `GROUP` has no destination;
- active children cannot have an inactive parent;
- service validation rejects cycles and excessive depth;
- sibling order is deterministic by `display_order`, then `id`;
- all direct-ID reads and writes include authorized `tenant_id` in the
  repository predicate.

`label`, `description`, and `aria_label` contain the single configured language
for this phase. Do not create translation columns or locale-specific duplicate
items. Central translations are deferred to the future upgrade plan.

### 4.3 `sys_acc_client_public_navigation_items`

This assignment table is analogous to
`sys_acc_client_feature_permissions`. It determines which tenant-owned public
items a client may expose.

```text
id
tenant_id
client_application_id
public_navigation_item_id
active
created_by
updated_by
created_at
updated_at
```

Constraints:

```text
unique (tenant_id, client_application_id, public_navigation_item_id)
foreign key tenant_id → sys_tenants.id
foreign key client_application_id → sys_acc_client_applications.id
foreign key public_navigation_item_id → sys_public_navigation_items.id
```

The service must additionally prove that the item belongs to the same tenant
and that an active `sys_acc_client_application_tenants` mapping exists. It must
not trust a tenant or client relationship supplied only by the request.

Assign leaf links explicitly. Ancestor `GROUP` items are included only when
they contain at least one assigned, active descendant. This mirrors the
authenticated navigation service pruning empty branches.

## 5. Effective tree resolution

Add a presentation-neutral boundary under `gatewaymodule.navigation`:

```java
public interface PublicNavigationModuleGateway extends ModuleGateway {
    PublicNavigationContextDto getPublicNavigation(
            String clientCode,
            Set<PublicNavigationSurface> surfaces);
}
```

The public DTO contains only presentation fields:

```text
clientCode
regions[]
  surface
  groups[]
    code
    label
    items[]
      code
      label
      description
      ariaLabel
      type
      path or externalUrl
      target
      icon
      children[]
```

It must not expose tenant IDs, client database IDs, item database IDs, actor
IDs, privilege codes, users, roles, assignments, secrets, or inactive rows.

Resolution is deterministic:

1. require `ResolvedTenantContextHolder`;
2. resolve exactly one active client by normalized `clientCode`;
3. require an active tenant/client mapping;
4. query active groups for the resolved tenant and requested surfaces;
5. query active items and active tenant/client item assignments using
   tenant-qualified repository predicates;
6. reject inconsistent parent relationships rather than repairing them in
   memory;
7. build the tree in deterministic order;
8. remove groups and branches with no assigned link descendants;
9. return the reduced public DTO.

Missing, inactive, unknown, or ambiguous tenant/client context fails closed.
Missing assignments return empty regions with an operational diagnostic; they
never fall back to another tenant, another client, or authenticated navigation.
A `system_db` failure propagates and affects readiness.

## 6. Write and visibility behavior

This phase intentionally uses direct writes, matching existing authenticated
navigation administration:

```text
Administrator saves an item or assignment
        ↓
Existing audited row changes in one System transaction
        ↓
Relevant cache entries are evicted
        ↓
Subsequent public requests see the new effective tree
```

Use optimistic locking on mutable public navigation rows to prevent stale
administrator updates. This technical `version` counter is not a navigation
snapshot and must not be described as publication versioning.

Deactivation is the safe removal operation. Deactivating a group, item, or
assignment removes it from subsequent public resolution. Physical deletion is
allowed only when dependency checks succeed and a separate DELETE privilege is
authorized.

## 7. Administration access control

Register a System-owned `Public Navigation` feature with:

```text
VIEW
SEARCH
CREATE
UPDATE
DELETE
ASSIGN
```

No `PUBLISH`, `PUBLISH_PUBLIC`, or `ROLLBACK` action is part of this phase.

Proposed administration APIs:

```text
POST /api/v1/system/public-navigation/groups/list
POST /api/v1/system/public-navigation/groups/save
POST /api/v1/system/public-navigation/items/list
POST /api/v1/system/public-navigation/items/save
POST /api/v1/system/public-navigation/items/deactivate
POST /api/v1/system/public-navigation/items/delete
POST /api/v1/system/public-navigation/assignments/list
POST /api/v1/system/public-navigation/assignments/replace
POST /api/v1/system/public-navigation/integrity
POST /api/v1/system/public-navigation/preview
```

Controllers use action-specific authorization with `ApiDataScope.TENANT`.
Services and repositories independently enforce tenant scope. Writable DTOs do
not accept audit actors, timestamps, or resolved ownership. They include only
the expected optimistic-lock counter for stale-write protection.

## 8. System frontend changes

Add `Public Navigation Administration` under System Setup with:

- authorized tenant selector;
- client selector filtered by active tenant/client assignments;
- surface selector;
- group and recursive item editor;
- item type and destination validation;
- active/inactive indicators;
- deterministic sibling ordering;
- client item assignment checklist;
- full replacement summary before assignment save;
- effective-tree preview for the selected tenant/client/surface;
- integrity report for cycles, orphaned parents, inactive-parent violations,
  invalid destinations, and invalid assignments;
- optimistic-lock conflict handling;
- action visibility controlled by VIEW, CREATE, UPDATE, DELETE, and ASSIGN.

Changing tenant clears the selected client, group, item, assignment state, and
preview. Changing client clears assignment and preview state and reloads the
effective tree. The UI must never retain IDs from a previous scope.

The existing authenticated `NavigationTreeComponent` remains unchanged. Shared
editor primitives may be reused, but public navigation uses its own models,
service, routes, and authorization contract.

## 9. Catalog integration

`CatalogContextService` remains the response composer:

```text
LayoutModuleGateway.getPublicLayout("CATALOG", origin)
PublicNavigationModuleGateway.getPublicNavigation(
    "CATALOG", {PRIMARY, UTILITY, FOOTER})
```

The Catalog repository continues to read site identity, SEO, contact,
products, categories, pages, and media from `catalog_db`. After cutover it no
longer owns public navigation.

For compatibility, map the PRIMARY region to the existing
`PublicSiteResponse.navigation` field. Add `navigationRegions` when the Catalog
shell consumes UTILITY and FOOTER independently. The frontend never consumes
the authenticated System `navTree` as public navigation.

Because translations are deferred, this phase returns the configured label
regardless of the Catalog `lang` request. The UI and API must state this
limitation explicitly until the central localization upgrade is implemented.

## 10. Catalog data cutover

PostgreSQL cannot perform one Flyway transaction across `catalog_db` and
`system_db`. Use an audited, rerunnable import and reconciliation procedure.

### Phase A: inventory

1. Inventory existing Catalog navigation and translation rows.
2. Select and document the one source locale imported into the initial System
   label fields.
3. Reject orphaned parents, cycles, unsupported URLs, unresolved tenants,
   invalid actors, and duplicate business keys.
4. Produce a review report before writing System data.

### Phase B: schema and service

1. Add the three approved System tables.
2. Add constraints, entities, repositories, services, gateway, administration
   APIs, privileges, health evidence, and tests.
3. Validate clean and upgraded System migration paths.

### Phase C: deterministic import

1. Resolve tenant and CATALOG client by trusted stable keys.
2. Import groups and hierarchical items with system actor `0` only for
   migration-created rows.
3. Create tenant/client item assignments.
4. Compare item counts, business keys, hierarchy, routes, order, and state.
5. Keep invalid or ambiguous source rows inaccessible for explicit repair.

### Phase D: shadow comparison and cutover

1. Compare normalized Catalog and System trees without changing the response.
2. Switch `CatalogContextService` to the System gateway through a configuration
   flag.
3. Verify empty-state behavior, cache eviction, tenant isolation, and SSR.
4. Make System authoritative after acceptance.

### Phase E: retirement

Keep Catalog navigation tables read-only for one release. Archive or remove
them only through a separately approved Catalog migration after the rollback
window.

## 11. Cache behavior

Cache effective public trees using at least:

```text
tenantId + clientApplicationId + surface + navigationChangeToken
```

Every group, item, or assignment mutation evicts the affected tenant/client
entries. Do not cache by hostname, client code, or surface alone. The future
central versioning plan may replace `navigationChangeToken` with an immutable
published version identifier.

## 12. Backup and recovery

System backup and restore verification includes the three public navigation
tables and proves parent ownership, assignment ownership, active client mapping,
deterministic tree resolution, and exclusion of inactive or unassigned items.

Catalog business-content recovery still requires `catalog_db`; public
navigation and layout recovery require `system_db`.

## 13. Testing strategy

### Database

- clean and upgraded migration paths;
- tenant/group business-key uniqueness;
- same-tenant and same-group parent constraints;
- item type and destination checks;
- assignment uniqueness and referential integrity;
- numeric actor and timestamp requirements;
- optimistic-lock column defaults.

### Backend

- unknown, inactive, and ambiguous tenant/client failure;
- inactive tenant/client mapping rejection;
- tenant isolation for every direct-ID operation;
- active group, item, and assignment filtering in repository predicates;
- cycle, depth, parent, and destination validation;
- deterministic order and empty-ancestor pruning;
- client assignment replacement authorization;
- stale update rejection and cache eviction;
- public DTO serialization excludes internal and authorization metadata;
- Catalog composition uses System navigation while Catalog business content
  remains in `catalog_db`.

### Frontend

- tenant changes clear client and all dependent state;
- client changes reload assignments and preview;
- unauthorized actions are hidden or disabled;
- active/inactive status remains visible;
- hierarchy editing prevents invalid parents and excessive depth;
- item type changes clear incompatible destination fields;
- assignment replacement summary matches submitted changes;
- stale update conflicts reload current data without changing scope;
- preview contains only assigned active links and necessary ancestors.

## 14. Delivery phases

### Phase 1: model and migration — Partially done

- **Done:** created the three-table direct hierarchy and assignment migration.
- **Done:** added same-tenant group/item and same-group parent constraints,
  destination checks, audit columns, optimistic-lock columns, and resolution
  indexes.
- **Pending:** verify the migration on both clean and upgraded System databases.
- **Pending:** record acceptance of the single-language limitation and approve
  the Catalog import and cutover procedure before that data work begins.

### Phase 2: System backend — Partially done

- **Done:** added group, item, and client-assignment entities.
- **Done:** added the public gateway interface and presentation DTO.
- **Pending:** implement repositories, validation, effective-tree resolution,
  gateway implementation, administration APIs, privileges, caching, health
  evidence, and tests.

### Phase 3: System administration UI — Pending

- implement tenant/client scoped hierarchy, assignment, integrity, and preview
  workflows.

### Phase 4: Catalog import and comparison — Pending

- inventory source navigation and translations;
- import the selected source locale;
- compare effective trees and repair invalid data.

### Phase 5: application cutover — Pending

- compose System navigation in `CatalogContextService`;
- render System regions in the Catalog shell;
- verify SSR, tenant isolation, cache eviction, and failure behavior.
- remove the Catalog-owned navigation read only after shadow comparison and
  cutover acceptance; it is still the active source today.

### Phase 6: future central upgrade — Deferred

- follow
  `CENTRAL_NAVIGATION_VERSIONING_PUBLICATION_LOCALIZATION_UPGRADE_PLAN.md`;
- introduce versions, drafts, publications, rollback, translations, and
  controlled audience transitions for both public and authenticated
  navigation through a separately approved change.

## 15. Acceptance criteria

- System resolves an effective public tree for an active tenant/client using
  direct hierarchy and assignment records.
- Public navigation follows the existing authenticated-navigation pattern
  without reusing privilege-navigation tables.
- Only active, assigned links and their necessary active ancestors are
  returned.
- Changes become effective immediately after successful audited writes and
  cache eviction.
- Tenant/client ownership cannot be selected or widened by caller input.
- Administration actions require explicit tenant-scoped privileges.
- Catalog consumes System navigation while retaining its business content in
  `catalog_db`.
- No draft, publication, rollback, audience-transition, or translation claim
  is made by this phase.
- Migration, import, backup, restore, and cutover procedures are reproducible
  and auditable.
