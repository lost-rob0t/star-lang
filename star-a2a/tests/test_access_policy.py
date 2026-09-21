from __future__ import annotations

import unittest

from star_a2a.access_policy import (
    AccessPolicyError,
    ProxyRoute,
    choose_proxy_route,
    route_challenge,
)


class AccessPolicyTests(unittest.TestCase):
    def setUp(self) -> None:
        self.routes = {
            "gov-egress": ProxyRoute(
                route_id="gov-egress",
                max_requests_per_minute=60,
                tenant_ids=frozenset({"tenant-a"}),
                source_hosts=frozenset({"data.example.gov"}),
            )
        }

    def test_proxy_route_requires_host_configured_entitlement(self) -> None:
        decision = choose_proxy_route(
            {
                "route_id": "gov-egress",
                "tenant_id": "tenant-a",
                "source_host": "data.example.gov",
            },
            self.routes,
        )
        self.assertTrue(decision.allowed)

        denied = choose_proxy_route(
            {
                "route_id": "gov-egress",
                "tenant_id": "tenant-b",
                "source_host": "data.example.gov",
            },
            self.routes,
        )
        self.assertFalse(denied.allowed)

    def test_tasks_cannot_inject_raw_proxy_endpoint(self) -> None:
        with self.assertRaises(AccessPolicyError):
            choose_proxy_route(
                {
                    "route_id": "gov-egress",
                    "tenant_id": "tenant-a",
                    "source_host": "data.example.gov",
                    "proxy_url": "https://untrusted.invalid",
                },
                self.routes,
            )

    def test_challenge_provider_is_explicitly_authorized(self) -> None:
        result = route_challenge(
            {"challenge_id": "c1", "provider_id": "configured-provider"},
            authorized_provider_ids=frozenset({"configured-provider"}),
        )
        self.assertEqual(result["status"], "authorized-provider")

        review = route_challenge(
            {"challenge_id": "c2", "provider_id": "unknown"},
            authorized_provider_ids=frozenset({"configured-provider"}),
        )
        self.assertEqual(review["status"], "review-required")

    def test_challenge_task_cannot_carry_provider_secrets(self) -> None:
        with self.assertRaises(AccessPolicyError):
            route_challenge(
                {"challenge_id": "c3", "api_key": "secret"},
                authorized_provider_ids=frozenset(),
            )


if __name__ == "__main__":
    unittest.main()
