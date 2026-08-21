# Observability

## Current documentation

- [Backend observability guide](../../backend/OBSERVABILITY.md)
- [Backend access-control analysis](../../backend/src/main/java/com/nexacore/systemmodule/accesscontrol/BACKEND_API_ACCESS_CONTROL_ANALYSIS.md)

## Authorization events

[`AuthorizationEventEmitter`](../../backend/src/main/java/com/nexacore/systemmodule/accesscontrol/security/AuthorizationEventEmitter.java)
publishes an `AuthorizationDecisionEvent` and emits the same decision as
structured JSON under the `authorization_event` log field. The access-control
index identifies the filters and metrics listener that participate in this flow.

