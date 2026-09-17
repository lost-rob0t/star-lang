from __future__ import annotations

import unittest

from star_a2a.government import (
    GovernmentAdapterError,
    arcgis_catalog_request,
    arcgis_feature_request,
    ckan_catalog_request,
    parse_arcgis_catalog,
    parse_arcgis_feature,
    parse_ckan_catalog,
    parse_socrata_catalog,
    parse_socrata_dataset,
    socrata_catalog_request,
    socrata_dataset_request,
)


class GovernmentAdapterTests(unittest.TestCase):
    def test_socrata_catalog_is_bounded_and_checkpointed(self) -> None:
        request = socrata_catalog_request(
            {"domain": "data.example.gov", "page_size": 2, "offset": 4, "query": "permits"}
        )
        self.assertEqual(request.url, "https://api.us.socrata.com/api/catalog/v1")
        self.assertEqual(request.params["search_context"], "data.example.gov")
        result = parse_socrata_catalog(
            {"results": [{"resource": {"id": "a"}}, {"resource": {"id": "b"}}]},
            request,
        )
        self.assertEqual(result.next_cursor, 6)

    def test_socrata_dataset_uses_resource_api(self) -> None:
        request = socrata_dataset_request(
            {"domain": "data.example.gov", "dataset_id": "abcd-1234", "page_size": 2}
        )
        self.assertEqual(request.url, "https://data.example.gov/resource/abcd-1234.json")
        result = parse_socrata_dataset([{"id": 1}, {"id": 2}], request)
        self.assertEqual(result.next_cursor, 2)
        self.assertEqual(len(result.records), 2)

    def test_ckan_catalog_uses_action_api(self) -> None:
        request = ckan_catalog_request(
            {"base_url": "https://catalog.example.gov", "page_size": 2, "offset": 2}
        )
        self.assertEqual(request.url, "https://catalog.example.gov/api/3/action/package_search")
        result = parse_ckan_catalog(
            {"success": True, "result": {"count": 5, "results": [{"id": "a"}, {"id": "b"}]}},
            request,
        )
        self.assertEqual(result.next_cursor, 4)

    def test_arcgis_catalog_and_feature_queries_are_bounded(self) -> None:
        catalog_request = arcgis_catalog_request(
            {"base_url": "https://gis.example.gov", "page_size": 10, "start": 1}
        )
        self.assertEqual(catalog_request.url, "https://gis.example.gov/sharing/rest/search")
        catalog_result = parse_arcgis_catalog(
            {"results": [{"id": "svc"}], "nextStart": 11}, catalog_request
        )
        self.assertEqual(catalog_result.next_cursor, 11)

        feature_request = arcgis_feature_request(
            {"service_url": "https://gis.example.gov/FeatureServer/0", "page_size": 2}
        )
        self.assertTrue(feature_request.url.endswith("/FeatureServer/0/query"))
        feature_result = parse_arcgis_feature(
            {"features": [{"attributes": {"id": 1}}, {"attributes": {"id": 2}}],
             "exceededTransferLimit": True},
            feature_request,
        )
        self.assertEqual(feature_result.next_cursor, 2)

    def test_invalid_or_unbounded_inputs_fail_closed(self) -> None:
        with self.assertRaises(GovernmentAdapterError):
            ckan_catalog_request({"base_url": "http://catalog.example.gov"})
        with self.assertRaises(GovernmentAdapterError):
            arcgis_feature_request(
                {"service_url": "https://gis.example.gov/FeatureServer/0", "page_size": 5000}
            )
        with self.assertRaises(GovernmentAdapterError):
            socrata_dataset_request(
                {"domain": "data.example.gov/path", "dataset_id": "abcd-1234"}
            )


if __name__ == "__main__":
    unittest.main()
