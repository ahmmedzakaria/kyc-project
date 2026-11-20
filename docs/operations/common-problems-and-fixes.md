# Common Problems and Fixes

This guide records recurring runtime and configuration problems in the NexaCore
stack. Add new entries with the observed symptom, root cause, diagnosis, durable
fix, and verification steps.

## Problem index

| # | Area | Problem | Typical cause | Guide |
|---:|---|---|---|---|
| 1 | Navigation | Menu click redirects to the dashboard | The backend menu URL does not match an Angular route, so the wildcard route handles it | [Open guide](#menu-click-redirects-to-the-dashboard) |
| 2 | Navigation | Menu destination is not implemented | The backend exposes a menu before its frontend page is available | [Open guide](#menu-destination-is-not-implemented) |

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

The system frontend also retains this compatibility redirect so navigation data
cached before the migration remains usable:

```typescript
{
    path: 'client-feature-permission',
    redirectTo: 'access-control/client-applications',
    pathMatch: 'full',
}
```

The same issue affected `Client API Permission`. Migration
[V77__fix_client_api_permission_navigation_route.sql](../../backend/src/main/resources/db/migration/system/V77__fix_client_api_permission_navigation_route.sql)
changes the feature linked to privilege `11020100381` from
`/access-control/client-api-permission` to the client-application page. Cached
navigation is supported by this compatibility redirect:

```typescript
{
    path: 'access-control/client-api-permission',
    redirectTo: 'access-control/client-applications',
    pathMatch: 'full',
}
```

Do not edit an already deployed Flyway migration or correct only the current
database row manually. Add a new migration so every environment receives the
same route correction.

### Verification

1. Start the backend and confirm Flyway applies migrations `76` and `77`
   successfully.
2. Refresh the application context or sign in again to reload navigation data.
3. Confirm the menu API returns:

   ```text
   /access-control/client-applications
   ```

4. Select `Client Feature Permission` and verify that the client-application list
   opens.
5. Open an application and verify that feature permissions load and save for the
   resolved tenant.
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
