# Authorization and Access Control

The canonical navigation page for the implementation is the
[access-control module index](../../backend/src/main/java/com/nexacore/systemmodule/accesscontrol/README.md).

## Cross-layer documentation

- [Backend access-control analysis](../../backend/src/main/java/com/nexacore/systemmodule/accesscontrol/BACKEND_API_ACCESS_CONTROL_ANALYSIS.md)
- [Frontend access-control architecture](../../frontendApplications/FRONTEND_TENANT_PRIVILEGE_API_ACCESS_CONTROL_ARCHITECTURE_PLAN.md)
- [System frontend implementation plan](../../frontendApplications/system-frontend-21/TENANT_PRIVILEGE_API_ACCESS_CONTROL_IMPLEMENTATION_PLAN.md)
- [Privilege service](../../backend/src/main/java/com/nexacore/systemmodule/privilege/AUTH_PRIVILEGE_SERVICE.md)
- [Tenant ownership and threat model](../../backend/TENANT_OWNERSHIP_AND_THREAT_MODEL.md)

## Runtime boundary

[`TenantAccountResolver`](../../backend/src/main/java/com/nexacore/authmodule/security/service/TenantAccountResolver.java)
validates that the authenticated client may operate in the already resolved
tenant. [`AuthorizationEventEmitter`](../../backend/src/main/java/com/nexacore/systemmodule/accesscontrol/security/AuthorizationEventEmitter.java)
publishes and logs the resulting authorization decision for downstream metrics,
audit, and observability consumers.

