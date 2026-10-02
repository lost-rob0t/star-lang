from __future__ import annotations

from dataclasses import dataclass
from typing import Any


class AccessPolicyError(ValueError):
    pass


@dataclass(frozen=True, slots=True)
class ProxyRoute:
    route_id: str
    max_requests_per_minute: int
    tenant_ids: frozenset[str]
    source_hosts: frozenset[str]


@dataclass(frozen=True, slots=True)
class ProxyDecision:
    route_id: str
    allowed: bool
    reason: str


def choose_proxy_route(
    task: dict[str, Any],
    routes: dict[str, ProxyRoute],
) -> ProxyDecision:
    """Select a host-configured route by opaque id; never accept raw proxy URLs.

    This policy layer is for routing/isolation/accounting. It intentionally has no
    notion of rotating around source blocks or rate limits.
    """

    route_id = str(task.get("route_id", "")).strip()
    tenant_id = str(task.get("tenant_id", "")).strip()
    source_host = str(task.get("source_host", "")).strip().lower()
    if not route_id or not tenant_id or not source_host:
        raise AccessPolicyError("route_id, tenant_id, and source_host are required")
    if "proxy_url" in task or "proxy" in task:
        raise AccessPolicyError("tasks cannot supply raw proxy endpoints")
    route = routes.get(route_id)
    if route is None:
        return ProxyDecision(route_id, False, "unknown route")
    if tenant_id not in route.tenant_ids:
        return ProxyDecision(route_id, False, "tenant is not entitled to route")
    if source_host not in route.source_hosts:
        return ProxyDecision(route_id, False, "source host is not allowed on route")
    if route.max_requests_per_minute < 1:
        return ProxyDecision(route_id, False, "route is disabled")
    return ProxyDecision(route_id, True, "allowed by configured route policy")


def route_challenge(
    task: dict[str, Any], *, authorized_provider_ids: frozenset[str]
) -> dict[str, Any]:
    """Route an access challenge without implementing protection bypass.

    A provider is usable only when the host already configured its opaque id and
    the task explicitly requests that authorized provider. Otherwise the outcome
    is human review. Credentials/site keys/tokens are never accepted here.
    """

    if any(key in task for key in ("provider_key", "api_key", "site_key", "token")):
        raise AccessPolicyError("challenge task must not carry provider credentials or tokens")
    challenge_id = str(task.get("challenge_id", "")).strip()
    if not challenge_id:
        raise AccessPolicyError("challenge_id is required")
    provider_id = str(task.get("provider_id", "")).strip()
    if provider_id and provider_id in authorized_provider_ids:
        return {
            "challenge_id": challenge_id,
            "status": "authorized-provider",
            "provider_id": provider_id,
        }
    return {
        "challenge_id": challenge_id,
        "status": "review-required",
        "provider_id": None,
    }
