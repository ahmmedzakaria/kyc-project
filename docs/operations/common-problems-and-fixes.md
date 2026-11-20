# Common Problems and Fixes

This guide records recurring runtime and configuration problems in the NexaCore
stack. Add new entries with the observed symptom, root cause, diagnosis, durable
fix, and verification steps.

## Problem index

| # | Area | Problem | Typical cause | Guide |
|---:|---|---|---|---|
| 1 | Navigation | Menu click redirects to the dashboard | The backend menu URL does not match an Angular route, so the wildcard route handles it | [Open guide](#menu-click-redirects-to-the-dashboard) |

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
`V76__fix_client_feature_permission_navigation_route.sql`. It changes the layout
feature linked to privilege `11020100481` to:

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

Do not edit an already deployed Flyway migration or correct only the current
database row manually. Add a new migration so every environment receives the
same route correction.

### Verification

1. Start the backend and confirm Flyway applies migration `76` successfully.
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
