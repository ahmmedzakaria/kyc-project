# Common Problems and Fixes

This guide records recurring runtime and configuration problems in the NexaCore
stack. Add new entries with the observed symptom, root cause, diagnosis, durable
fix, and verification steps.

## Problem index

| # | Area | Problem | Typical cause | Guide |
|---:|---|---|---|---|
| 1 | Navigation | Menu click redirects to the dashboard | The backend menu URL does not match an Angular route, so the wildcard route handles it | [Open guide](#menu-click-redirects-to-the-dashboard) |
| 2 | Navigation | Menu destination is not implemented | The backend exposes a menu before its frontend page is available | [Open guide](#menu-destination-is-not-implemented) |
| 3 | Authorization | Visible menu opens Access denied | The menu privilege exists, but the application route policy is missing | [Open guide](#visible-menu-opens-access-denied) |
| 4 | Startup / Privileges | Active logical privilege module is not configured: 12 (Catalog) | The Catalog privilege provider starts before its trusted module hierarchy exists in `system_db` | [Open guide](#catalog-privilege-module-is-not-configured) |

## Catalog privilege module is not configured

### Symptom

Backend startup fails while synchronizing module privileges:

```text
java.lang.IllegalStateException: Active logical privilege module is not configured: 12 (Catalog)
    at com.nexacore.systemmodule.privilege.catalog.service.implementations.SystemPrivilegeRegistryServiceImpl.resolveModule(...)
```

The failure can appear after adding `CatalogPrivilegeProvider`, even though the
provider and `ModuleRepository` compile successfully.

### Root cause

`ApplicationModule.CATALOG` declares logical privilege module code `12`.
`SystemPrivilegeRegistryServiceImpl` intentionally treats the database catalog
as trusted configuration: it will synchronize features and actions only when an
active logical module and submodule already exist. It does not create module
ownership or navigation structure from application code.

The affected `system_db` has no complete Catalog hierarchy in:

- `sys_layout_module_groups`
- `sys_physical_modules` and `sys_physical_submodules`
- `sys_priv_modules` and `sys_priv_submodules`
- `sys_layout_navigation_categories`

Adding a repository fallback or automatically creating rows in
`SystemPrivilegeRegistryServiceImpl` would weaken this fail-closed boundary and
is not the correct fix.

### Diagnosis

Check for the logical module and submodule:

```sql
SELECT id, navigation_module_code, module_priv_code, active
FROM sys_priv_modules
WHERE module_priv_code = '12';

SELECT submodule.submodule_priv_code,
       submodule.submodule_code,
       submodule.active
FROM sys_priv_submodules submodule
JOIN sys_priv_modules module ON module.id = submodule.module_id
WHERE module.module_priv_code = '12';
```

The required result is one active `CATALOG` module with code `12` and one active
`CONTENT` submodule with code `01`. The module also needs active navigation
categories mapping `SETUP`, `OPERATION`, and `REPORT` to feature-type codes
`01`, `02`, and `03` respectively.

### Fix

Apply
[V82__register_catalog_privilege_module.sql](../../backend/src/main/resources/db/migration/system/V82__register_catalog_privilege_module.sql).
It idempotently registers the physical and logical Catalog hierarchy, navigation
categories, audit values, and the links required by privilege synchronization.

Do not manually insert only `sys_priv_modules`, bypass the active check in
`ModuleRepository`, or edit an already deployed migration. A partial seed merely
moves the startup failure to submodule or navigation-category resolution.

### Verification

1. Restart the backend and confirm Flyway records system migration `82` as
   successful.
2. Confirm startup no longer reports module `12` as missing.
3. Verify the registered hierarchy:

   ```sql
   SELECT module.module_priv_code,
          module.navigation_module_code,
          submodule.submodule_priv_code,
          submodule.submodule_code
   FROM sys_priv_modules module
   JOIN sys_priv_submodules submodule ON submodule.module_id = module.id
   WHERE module.module_priv_code = '12';
   ```

4. Confirm catalog privileges such as view `12010100101` and publish
   `12010100123` are synchronized.
5. Run the focused checks:

   ```bash
   cd backend
   mvn -Dtest=SystemDatabaseMigrationTest,SystemPrivilegeRegistryServiceImplTest,CatalogPrivilegeProviderTest test
   ```

### Prevention

- Add the physical/logical module seed migration before enabling a new
  `ModulePrivilegeProvider` in an environment.
- Keep `ApplicationModule`, `ApplicationSubmodule`, system catalog migrations,
  and navigation categories aligned.
- Preserve fail-closed module resolution; trusted ownership structure belongs
  in versioned `system_db` migrations.

## Menu click redirects to the dashboard

### Symptom

A menu is present in the navigation tree, but selecting it opens the dashboard.
For example, the `Client Feature Permission` menu returned this route:

```text
/client-feature-permission
```

Selecting it opened `/dashboard` instead of feature-permission administration.

### Root cause

The backend navigation route did not match any Angular route in the system
frontend. The frontend wildcard route redirects unknown paths to the dashboard:

```typescript
{ path: '**', redirectTo: 'dashboard' }
```

Feature-permission administration is part of the client-application pages. Its
canonical route is:

```text
/access-control/client-applications
```

This problem is unrelated to privilege visibility. A user can have the correct
role, application grant, tenant grant, and menu privilege while the browser still
falls through to the dashboard because the route itself is invalid.

### Diagnosis

1. Inspect the route returned by the effective navigation API or
   `backend/db_script/query_system_db.sql`.
2. Search the target frontend's `app.routes.ts` for the exact path without the
   leading slash.
3. If the path is absent, check the wildcard route. A dashboard redirect usually
   means Angular treated the menu route as unknown.
4. Confirm the intended page's canonical route in the frontend authorization
   contract as well as the Angular route configuration.

Useful searches:

```bash
rg -n "client-feature-permission|access-control/client-applications" \
  backend frontendApplications/system-frontend-21

rg -n "path: '\*\*'|redirectTo: 'dashboard'" \
  frontendApplications/system-frontend-21/src/app
```

### Fix

The durable database correction is migration
[V76__fix_client_feature_permission_navigation_route.sql](../../backend/src/main/resources/db/migration/system/V76__fix_client_feature_permission_navigation_route.sql).
It changes the layout feature linked to privilege `11020100481` to:

```text
/access-control/client-applications
```

That redirect was temporary. After the tenant-scoped feature-permission page
was implemented,
[V79__restore_client_feature_permission_navigation_route.sql](../../backend/src/main/resources/db/migration/system/V79__restore_client_feature_permission_navigation_route.sql)
restored the menu route to `/client-feature-permission`.

The system frontend now loads the dedicated tenant-scoped feature-permission
page for this route.

`Client API Permission` was temporarily redirected to the client-application
page by
[V77__fix_client_api_permission_navigation_route.sql](../../backend/src/main/resources/db/migration/system/V77__fix_client_api_permission_navigation_route.sql).
After the focused API-permission UI was added,
[V78__restore_client_api_permission_navigation_route.sql](../../backend/src/main/resources/db/migration/system/V78__restore_client_api_permission_navigation_route.sql)
restored privilege `11020100381` to `/access-control/client-api-permission`.
That route now loads the application selector and API-assignment workflow
directly; it is no longer a compatibility redirect.

Do not edit an already deployed Flyway migration or correct only the current
database row manually. Add a new migration so every environment receives the
same route correction.

### Verification

1. Start the backend and confirm Flyway applies migrations `76` through `80`
   successfully.
2. Refresh the application context or sign in again to reload navigation data.
3. Confirm the menu API returns:

   ```text
   /client-feature-permission
   ```

4. Select `Client Feature Permission` and verify that its dedicated page opens.
5. Select an application and verify that feature permissions load and save for
   the resolved tenant.
6. Build the frontend:

   ```bash
   cd frontendApplications/system-frontend-21
   npm run build
   ```

### Prevention

- Use route values declared by the target frontend rather than inventing a
  separate menu URL for an action implemented within an existing page.
- Keep layout navigation routes, Angular routes, and the frontend route-policy
  contract aligned.
- Before adding or changing a menu route, verify that the exact path exists in
  the intended client application.
- Treat a wildcard redirect as a fallback, not evidence that navigation
  succeeded.

## Visible menu opens Access denied

### Symptom

`Client Feature Permission` is visible in the navigation menu, but selecting it
opens the access-denied page with this message:

```text
Your current application privileges do not allow this page.
```

### Root cause

Menu visibility and route authorization use separate configuration:

- `sys_layout_feature_privileges` determines whether the menu is visible.
- `sys_layout_route_policies` and
  `sys_layout_route_policy_privileges` determine whether Angular's
  `routePrivilegeGuard` allows the destination.

The user can therefore have privilege `11020100481` and see the menu while the
route still fails closed when `/client-feature-permission` has no effective
route policy for `SYSTEM_ADMIN_WEB`.

### Diagnosis

Run [query_system_db.sql](../../backend/db_script/query_system_db.sql) for the
affected user, tenant, roles, and client. Check these columns on the Client
Feature Permission row:

- `route_policy_id`
- `route_policy_scope`
- `route_policy_match_mode`
- `route_policy_privilege_codes`

`route_policy_scope = MISSING` confirms that navigation visibility exists but
route authorization is not configured.

### Fix

Migration
[V80__authorize_client_feature_permission_route.sql](../../backend/src/main/resources/db/migration/system/V80__authorize_client_feature_permission_route.sql)
creates or reactivates the application-specific route policy for
`SYSTEM_ADMIN_WEB` and `/client-feature-permission`, then links it to Client
Feature Permission Assign privilege `11020100481` with `ANY` matching.

The equivalent correction for Client API Permission is
[V81__authorize_client_api_permission_route.sql](../../backend/src/main/resources/db/migration/system/V81__authorize_client_api_permission_route.sql).
It authorizes `/access-control/client-api-permission` for `SYSTEM_ADMIN_WEB`
and links the route policy to Client API Permission Assign privilege
`11020100381`.

### Verification

1. Confirm Flyway applies migration `80` successfully.
2. Refresh the application context or sign out and sign in again.
3. Run `query_system_db.sql` and confirm the route-policy scope is
   `APPLICATION` and its privilege codes include `11020100481`.
4. Select the menu and confirm the dedicated Client Feature Permissions page
   opens instead of `/access-denied`.
5. Repeat the query and menu check for Client API Permission. Confirm its route
   policy includes `11020100381` and its dedicated page opens.

## Menu destination is not implemented

### Symptom

A backend navigation feature is active and visible to the user, but the target
frontend has no matching Angular page yet.

### Expected behavior

The system frontend displays the `Development in progress` page inside the
authenticated application layout. The page includes an SVG development
illustration, explains that the destination is still being built, shows the
requested path, and provides a link to the dashboard.

The fallback route is the final child of the authenticated layout route:

```typescript
{
    path: '**',
    loadComponent: () =>
        import('@nexacore/shared')
            .then(m => m.DevelopmentInProgressComponent),
    data: { public: true },
}
```

`data.public` bypasses route-policy lookup because an unavailable route cannot
have a matching route policy. Authentication is still required by the parent
layout route.

`DevelopmentInProgressComponent` is exported by `@nexacore/shared`. Applications
should reuse that component for their final authenticated child route instead of
creating an app-specific fallback page.

### Verification

1. Sign in to the system frontend.
2. Open an unimplemented path, such as `/future-administration-page`.
3. Confirm the authenticated shell remains visible.
4. Confirm the development page displays the requested path.
5. Confirm `Go to dashboard` opens `/dashboard`.
6. Confirm existing valid routes continue to load their normal pages.

### Adding the real page later

1. Add the concrete Angular route before the `**` fallback route.
2. Add its route-policy mapping and backend navigation route.
3. Verify the user's application and role privileges expose the menu.
4. Remove any temporary compatibility redirect for that path when cached legacy
   navigation is no longer supported.
