# Authentication and SSO

## Current documentation

- [Auth module business and implementation](../../backend/src/main/java/com/nexacore/authmodule/AUTH_MODULE_BUSINESS_AND_IMPLEMENTATION.md)
- [SSO login process](../../SSO_LOGIN_PROCESS_DOCUMENTATION.md)
- [Keycloak SSO implementation plan](../../KEYCLOAK_SSO_IMPLEMENTATION_PLAN.md)
- [Keycloak integration](../../keycloak2/README.md)
- [User-storage SPI](../../keycloak2/user-storage-spi/README.md)
- [User-storage SPI implementation details](../../keycloak2/user-storage-spi/IMPLEMENTATION_DETAILS.md)
- [Global person and tenant account plan](../../backend/AUTH_GLOBAL_PERSON_TENANT_ACCOUNT_IMPLEMENTATION_PLAN.md)

## Related code

- [`TenantAccountResolver`](../../backend/src/main/java/com/nexacore/authmodule/security/service/TenantAccountResolver.java) validates the active client, resolved tenant context, and active client–tenant assignment.

Authentication establishes identity. Tenant resolution and authorization must
still fail closed when client, tenant, or scope information is missing or invalid.

