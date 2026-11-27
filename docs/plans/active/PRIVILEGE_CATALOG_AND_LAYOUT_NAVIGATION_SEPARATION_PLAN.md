# Privilege Catalog and Layout Navigation Separation Plan

## Document control

- Status: proposed
- Created: 2026-11-28
- Scope: `system_db`, System privilege catalog, authenticated layout navigation,
  license entitlements, client feature permissions, backend services, and
  `system-frontend-21`
- Primary implementation area:
  `backend/src/main/java/com/nexacore/systemmodule/layout/service/implementations/LayoutNavigationServiceImpl.java`
- Migration rule: this plan does not authorize a database migration. Any new
  or changed Flyway migration requires separate review and explicit approval
  before it is written.
- Historical rule: do not edit deployed migrations V68, V69, V73, or any
  other deployed migration. Implement the separation through new versioned
  migrations.

## 1. Objective

Separate the authorization catalog from layout navigation so that each domain
has its own hierarchy and lifecycle.

The authorization catalog must define stable capabilities and privilege codes
without depending on UI navigation records. The layout domain must define
groups, modules, categories, feature groups, routes, and presentation without
owning authorization semantics. The existing
`sys_layout_feature_privileges` table remains the explicit integration point.

The target model is:

```text
Authorization catalog
sys_priv_modules
    └── sys_priv_submodules
            └── sys_priv_feature_types
                    └── sys_priv_features
                            └── sys_priv_privileges

Navigation layout
sys_layout_module_groups
    └── sys_layout_navigation_modules
            └── sys_layout_navigation_categories
                    └── sys_layout_feature_groups
                            └── sys_layout_features

Integration
sys_layout_feature_privileges
    ├── layout_feature_id → sys_layout_features.id
    └── privilege_id → sys_priv_privileges.id
```

Existing 11-digit privilege codes remain stable:

```text
module(2) + submodule(2) + feature type(2) + feature(3) + action(2)
```

For example, `11020100101` continues to mean System / Access Control /
Setup / Client Application / View.

## 2. Current-state problem

The current schema contains two intended hierarchies but merges core records
between them:

1. `sys_priv_modules` is both a privilege module and a navigation module.
2. `sys_layout_navigation_categories` is both a layout category and the
   privilege feature-type source.
3. `sys_priv_features` references both a privilege submodule and a layout
   navigation category.
4. The database does not guarantee that those two parents belong to the same
   logical module.
5. Privilege registration fails unless a suitable layout category already
   exists.
6. Layout administration can affect records used by authorization and
   licensing.
7. Catalog-only or API-only capabilities require artificial layout records.

The current effective graph is:

```text
sys_layout_module_groups
    └── sys_priv_modules
            ├── sys_priv_submodules
            │       └── sys_priv_features
            └── sys_layout_navigation_categories
                    ├── sys_priv_features
                    └── sys_layout_feature_groups
                            └── sys_layout_features
```

This coupling was introduced deliberately by earlier consolidation work,
especially V68 and V73. The separation must therefore preserve data created
before and after those migrations.

## 3. Architecture decisions

### 3.1 Authorization owns privilege composition

Only privilege-owned tables may supply the five code segments used to compose
a privilege code. Layout names, identifiers, status, or hierarchy must not
change a privilege code.

### 3.2 Layout owns presentation and routes

Layout tables own navigation grouping, labels, icons, ordering, routes,
T-codes, and active presentation state. Deactivating a layout node must not
deactivate its privilege catalog record.

### 3.3 Feature types are a reusable privilege catalog

Restore `sys_priv_feature_types` as a reusable authorization lookup, with
stable two-digit codes such as Setup, Operation, and Report. Privilege
features reference both a submodule and a feature type. The database unique
key expresses their logical position:

```text
UNIQUE (submodule_id, feature_type_id, feature_code)
```

This avoids duplicating identical feature-type rows for every submodule while
preserving the logical module → submodule → feature type → feature hierarchy.

### 3.4 Privilege links are the authorization integration

`sys_layout_feature_privileges` remains the authoritative relationship
between a menu/route and the privileges required to see it. It continues to
support multiple privileges per layout feature, reuse of a privilege across
multiple features, and ANY/ALL matching.

### 3.5 Preserve authorization identities

Do not change IDs of existing privilege modules, submodules, features,
actions, or privileges. These IDs are referenced by assignments, client
permissions, license entitlements, route/UI policies, and other access-control
data. New IDs are introduced only for restored layout navigation modules and
new privilege feature-type records.

## 4. Target database model

### 4.1 `sys_priv_modules`

Retain authorization-owned fields:

```text
id
module_priv_code
name
active
created_by
updated_by
created_at
updated_at
```

Move navigation-owned fields out of this table:

```text
module_group_id
navigation_module_code
navigation_module_name
icon
description
display_order
navigation_enabled
```

Keep current columns during the compatibility phase and remove them only in a
later contract migration.

### 4.2 `sys_layout_navigation_modules`

Restore a dedicated layout module table with:

```text
id
module_group_id
navigation_module_code
navigation_module_name
icon
description
display_order
navigation_enabled
active
created_by
updated_by
created_at
updated_at
```

Required constraints include:

```text
FOREIGN KEY (module_group_id) REFERENCES sys_layout_module_groups(id)
UNIQUE (navigation_module_code)
```

The table must not require a privilege module. A navigation-only module is
valid, and a privilege-only module is valid.

### 4.3 `sys_priv_feature_types`

Restore a privilege-owned table with:

```text
id
feature_type_code varchar(2)
feature_type_name
icon
display_order
active
created_by
updated_by
created_at
updated_at
```

Required constraints include:

```text
UNIQUE (feature_type_code)
CHECK (feature_type_code ~ '^[0-9]{2}$')
```

### 4.4 `sys_priv_features`

Replace `navigation_category_id` with `feature_type_id`:

```text
submodule_id       → sys_priv_submodules.id
feature_type_id    → sys_priv_feature_types.id
feature_code
feature_name
active
audit fields
```

Required constraints include:

```text
FOREIGN KEY (submodule_id) REFERENCES sys_priv_submodules(id)
FOREIGN KEY (feature_type_id) REFERENCES sys_priv_feature_types(id)
UNIQUE (submodule_id, feature_type_id, feature_code)
CHECK (feature_code ~ '^[0-9]{3}$')
```

### 4.5 `sys_layout_navigation_categories`

Change `navigation_module_id` to reference
`sys_layout_navigation_modules.id`. Retain layout-owned fields:

```text
category_code
category_name
category_kind
icon
display_order
active
audit fields
```

Remove `feature_type_code` only after privilege services have stopped reading
it. Layout categories such as Setup or Report may resemble privilege feature
types, but they no longer share identity.

### 4.6 `sys_layout_features`

Continue to own route-bearing navigation features. The current physical code
columns require a separate compatibility decision:

```text
physical_module_code
physical_submodule_code
physical_feature_type_code
physical_feature_code
```

They must no longer control authorization. During transition they may remain
as descriptive compatibility metadata. After all consumers are inventoried,
either remove them or replace them with a normalized optional reference. The
privilege links remain the source of truth for visibility.

## 5. Data migration plan

Use an expand–migrate–contract rollout. Do not perform the separation as a
single destructive deployment unless an explicit downtime deployment is
approved.

### Phase 1: inventory and preflight

Produce read-only reports for:

1. Every privilege module and its current navigation fields.
2. Every navigation category and its current module.
3. Every privilege feature, submodule, category, feature-type code, action,
   and stored privilege code.
4. Null or invalid feature-type codes.
5. Duplicate `(submodule, feature type, feature code)` combinations.
6. Privilege features whose submodule module and category module disagree.
7. Duplicate logical navigation module codes.
8. Archived or fallback `PRIV_*` navigation modules.
9. Layout features with physical codes that disagree with their linked
   privileges.
10. Orphaned or inactive privilege and layout links.

The migration must fail closed when a required privilege feature cannot be
mapped unambiguously. It must not infer ownership from unrelated names or
caller-controlled values.

### Phase 2: expand schema

Create `sys_layout_navigation_modules` and `sys_priv_feature_types`. Add a
nullable `feature_type_id` to `sys_priv_features`. Keep the existing
`navigation_category_id` and current module columns temporarily.

### Phase 3: backfill layout modules

For each current logical module that has valid navigation configuration:

1. Insert one layout navigation module.
2. Copy group, code, name, icon, description, order, navigation-enabled, active,
   and audit data.
3. Record an explicit old-module-ID to new-layout-module-ID mapping during the
   migration.
4. Update each layout category to the new layout module ID.

Privilege-only modules must not receive artificial layout records. Archived
fallback records need deterministic reconciliation based on the V68/V73
history and current active logical module, not merely on matching names.

### Phase 4: backfill privilege feature types

Create feature-type records from trusted existing category feature-type codes.
Populate `sys_priv_features.feature_type_id` through the existing
`navigation_category_id` relationship.

Before accepting the backfill, reconstruct every stored privilege code using:

```text
module_priv_code
+ submodule_priv_code
+ feature_type_code
+ feature_code
+ action_code
```

The reconstructed value must exactly equal
`sys_priv_privileges.privilege_code`. Any mismatch blocks the migration.

### Phase 5: application cutover

Deploy code that reads and writes the new layout module and privilege
feature-type relationships. Keep old compatibility columns populated only if
rollback support requires it. Do not allow two independent writers to diverge.

### Phase 6: contract schema

After production verification:

1. Make `sys_priv_features.feature_type_id` non-null.
2. Add final foreign keys and uniqueness constraints.
3. Remove `sys_priv_features.navigation_category_id`.
4. Remove `sys_layout_navigation_categories.feature_type_code`.
5. Remove navigation-owned columns from `sys_priv_modules`.
6. Resolve or remove deprecated physical code columns separately.
7. Remove compatibility triggers or views after the rollback window.

## 6. Backend implementation impact

### 6.1 New entities and repositories

Add:

- `SysLayoutNavigationModule`
- `SysPrivFeatureType`
- a layout navigation module repository targeting
  `SysLayoutNavigationModule`
- a privilege feature-type repository targeting `SysPrivFeatureType`

### 6.2 `SysPrivModule`

Remove layout ownership from `SysPrivModule` after the transition. License
entitlements and privilege submodules continue to reference it because they
describe authorization capabilities.

### 6.3 `SysLayoutNavigationCategory`

Change its parent type from `SysPrivModule` to
`SysLayoutNavigationModule`. Remove feature-type behavior after privilege
services have migrated.

### 6.4 `SysPrivFeature`

Replace the `SysLayoutNavigationCategory` association with
`SysPrivFeatureType`. `getFeatureTypeCode()` and `getFeatureTypeName()` resolve
through the privilege feature type.

### 6.5 `LayoutNavigationServiceImpl`

Refactor the navigation service so all module tree operations use
`SysLayoutNavigationModule`:

- `getNavigationTree`
- `getFullNavigationTree`
- `buildModuleGroupNode`
- `buildModuleNode`
- `saveModule`
- `saveCategory`
- category reorder
- integrity validation
- duplicate-code validation

The service must stop writing privilege module codes and must not require a
feature-type code when creating a layout category. Feature-group creation
must resolve its parent through an explicit navigation category ID.

Navigation visibility remains based on active
`sys_layout_feature_privileges` links and effective user/client privilege
codes.

### 6.6 `PrivilegeServiceImpl`

Replace layout category resolution with privilege feature-type resolution.
Privilege creation must work even when no layout category or layout feature
exists.

Preserve the `/api/v1/system/privilege/definitions` response shape so the
Privilege Catalog frontend continues to receive module, submodule, feature
type, feature, and action definitions.

### 6.7 `SystemPrivilegeRegistryServiceImpl`

Remove its dependency on `LayoutNavigationCategoryRepository`. Provider-based
privilege synchronization must create or resolve only privilege-owned module,
submodule, feature-type, feature, action, and privilege records.

Navigation creation and privilege registration become separate operations.
Seed/reconciliation code that needs both must call the two domain services
explicitly and then create the privilege link.

### 6.8 License services

License plan entitlements and subscription overrides retain their current
references to privilege modules, submodules, features, and privileges. Update
feature-type access and queries, then regression-test:

- `LicenseDecisionServiceImpl`
- `LicensePlanServiceImpl`
- `LicenseSubscriptionServiceImpl`

### 6.9 Access-control and client permissions

Client feature permissions already resolve to privilege codes. Preserve that
contract. Navigation continues to intersect client-allowed privilege codes
with user privilege codes and layout feature privilege requirements.

## 7. API and DTO impact

Keep these endpoint contracts stable where practical:

```text
POST /api/v1/system/privilege/definitions
POST /api/v1/system/privilege/save
POST /api/v1/system/layout/navigation/tree
POST /api/v1/system/layout/navigation/tree/admin
```

Review and deprecate layout DTO fields that expose privilege or physical
catalog internals:

```text
modulePrivCode
physicalModuleCode
featureTypeCode
physicalSubmoduleCode
physicalFeatureTypeCode
physicalFeatureCode
```

During the compatibility release, responses may retain deprecated fields so
older frontend builds remain readable. New layout writes must use layout IDs
and explicit `privilegeCodes` assignments.

## 8. Frontend impact

### 8.1 Privilege Catalog

Retain the authorization selection hierarchy:

```text
Module → Submodule → Feature Type → Feature → Action
```

The dropdown source becomes purely privilege-owned. For client application
authorization, the expected selection remains:

```text
System → Access Control → Setup → Client Application → View/Manage
```

`Client Application Setup` is a layout feature-group label and must not appear
as a privilege submodule.

If the privilege definitions DTO remains stable, changes to
`privileges-list.component.ts` and `privileges.model.ts` should be minimal.

### 8.2 Navigation Tree administration

Update the editor to manage only:

```text
Module group
Navigation module
Navigation category
Feature group
Layout feature
Required privileges and ANY/ALL match mode
```

Remove privilege module code and privilege feature-type code from ordinary
layout module/category editing. Remove physical hierarchy fields after their
compatibility period. The privilege selector on a layout feature is the
explicit authorization integration.

Likely affected frontend files include:

- `src/app/pages/layout/layout.model.ts`
- `src/app/pages/layout/navigation-tree/navigation-tree.component.ts`
- `src/app/pages/access-control/privileges/privileges.model.ts`
- `src/app/pages/access-control/privileges/privileges-list.component.ts`

## 9. Integrity rules

The separated model must enforce:

1. Privilege modules do not require layout modules.
2. Layout modules do not require privilege modules.
3. A privilege feature belongs to exactly one privilege submodule and one
   privilege feature type.
4. A layout category belongs to exactly one layout navigation module.
5. A layout feature belongs to exactly one layout feature group.
6. A visible restricted layout feature has at least one active privilege link.
7. Every active privilege link references an active privilege unless an
   explicit administrative repair state is supported.
8. Privilege codes reconstruct exactly from normalized authorization parents.
9. Layout mutations never rewrite privilege codes.
10. Privilege catalog mutations never create layout presentation implicitly.

## 10. Testing and verification

### 10.1 Migration verification

Validate before and after counts for:

- privilege modules, submodules, feature types, features, actions, privileges;
- role and user privilege assignments;
- client feature permissions;
- license entitlement references;
- layout module groups, navigation modules, categories, groups, and features;
- layout feature privilege links;
- route and UI policy privilege links.

Verify that no existing privilege code changes and no assignment or
entitlement becomes orphaned.

### 10.2 Backend tests

Update existing tests for:

- `LayoutNavigationServiceImpl`
- `PrivilegeServiceImpl`
- `SystemPrivilegeRegistryServiceImpl`
- `LicenseDecisionServiceImpl`

Add focused coverage for:

1. Registering an API-only privilege without layout data.
2. Creating a navigation-only module without privilege data.
3. Linking one layout feature to multiple privileges.
4. Linking one privilege to multiple layout features.
5. ANY and ALL navigation visibility.
6. Client permission and user privilege intersection.
7. Preserving all existing 11-digit privilege codes.
8. Navigation deactivation without privilege deactivation.
9. Privilege deactivation impact reporting for linked layout features.
10. License decisions after feature-type separation.
11. Rejection of ambiguous or invalid legacy mappings.

Run the backend suite with:

```bash
cd backend
mvn test
```

### 10.3 Frontend verification

Verify:

- Privilege Catalog dropdown dependency order and labels.
- Creation and editing of privilege records.
- Navigation tree CRUD and reorder behavior.
- Privilege assignment on layout features.
- Navigation preview for users and clients with different privileges.
- No regression in Client Applications, API Registry, licensing, or dashboard
  navigation.

Run:

```bash
cd frontendApplications/system-frontend-21
npm run build
npm test
```

## 11. Deployment and rollback

### Deployment sequence

1. Approve the proposed expand migration.
2. Run preflight reports against a production-like copy.
3. Apply additive schema and backfill changes.
4. Validate privilege reconstruction and relationship counts.
5. Deploy dual-compatible backend code.
6. Deploy the updated System frontend.
7. Monitor navigation output, privilege definitions, authorization decisions,
   license decisions, and reconciliation logs.
8. Complete the rollback observation window.
9. Approve and apply the contract migration separately.

### Rollback requirements

The expand release must retain old columns and relationships long enough to
run the previous application version. Backfills must be deterministic and
repeatable. Do not drop old foreign keys or columns until the new code has
passed production verification.

If shadow comparisons find mismatches, stop before the contract phase, restore
the previous application version, and retain the additive tables for
diagnosis. Rollback must not renumber or recreate privilege IDs.

## 12. Implementation work packages

### WP-1: inventory and migration proposal

- Produce schema/data diagnostics.
- Define exact new DDL and backfill SQL.
- Document ambiguous records and repair decisions.
- Present the migration for explicit approval before writing it.

### WP-2: additive domain model

- Add layout navigation module and privilege feature-type entities.
- Add repositories and mapping tests.
- Keep compatibility mappings intact.

### WP-3: privilege catalog cutover

- Refactor privilege feature resolution and provider synchronization.
- Preserve API contracts and code composition.
- Verify assignments, caching, policies, and licensing.

### WP-4: layout navigation cutover

- Refactor `LayoutNavigationServiceImpl` and layout repositories.
- Update navigation integrity checks and CRUD behavior.
- Preserve privilege-based visibility.

### WP-5: administration frontend

- Separate layout editing fields from privilege catalog fields.
- Keep explicit privilege assignment on layout features.
- Validate create, edit, reorder, preview, and error handling.

### WP-6: contract cleanup

- Remove obsolete cross-domain columns and foreign keys.
- Resolve physical code compatibility fields.
- Update architecture documentation and operational queries.

## 13. Acceptance criteria

The separation is complete when:

1. Privileges can be registered without any layout records.
2. Navigation modules and categories can be created without privilege modules
   or feature types.
3. `sys_priv_features` no longer references layout tables.
4. `sys_layout_navigation_categories` no longer references privilege tables.
5. `sys_priv_modules` contains no layout parent or presentation ownership.
6. `sys_layout_navigation_modules` is the sole parent of navigation
   categories.
7. `sys_layout_feature_privileges` is the explicit authorization integration.
8. All existing privilege codes and privilege record IDs are preserved.
9. Role, user, client, policy, and license references remain intact.
10. Navigation output remains correct for representative users, tenants, and
    clients.
11. Backend tests and the System frontend build/tests pass.
12. Migration reconciliation reports contain no unresolved records.

## 14. Out of scope

- Changing the 11-digit privilege-code format.
- Replacing role or user privilege assignments.
- Redesigning client application authorization.
- Replacing route or UI policy enforcement.
- Editing historical Flyway migrations.
- Merging public navigation with authenticated privilege-controlled
  navigation.
