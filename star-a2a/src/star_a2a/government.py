from __future__ import annotations

from dataclasses import dataclass
from typing import Any
from urllib.parse import urljoin, urlparse


class GovernmentAdapterError(ValueError):
    pass


@dataclass(frozen=True, slots=True)
class PageRequest:
    method: str
    url: str
    params: dict[str, str | int]
    provider: str
    cursor: str | int | None = None


@dataclass(frozen=True, slots=True)
class PageResult:
    records: list[dict[str, Any]]
    next_cursor: str | int | None
    source_url: str


def _https_base(url: str) -> str:
    parsed = urlparse(url)
    if parsed.scheme != "https" or not parsed.hostname:
        raise GovernmentAdapterError("government source URL must use HTTPS")
    if parsed.username or parsed.password:
        raise GovernmentAdapterError("government source URL must not contain credentials")
    return url.rstrip("/")


def _bounded_page_size(value: Any, *, default: int = 500, maximum: int = 1000) -> int:
    if value is None:
        return default
    if isinstance(value, bool) or not isinstance(value, int):
        raise GovernmentAdapterError("page_size must be an integer")
    if value < 1 or value > maximum:
        raise GovernmentAdapterError(f"page_size must be between 1 and {maximum}")
    return value


def socrata_catalog_request(task: dict[str, Any]) -> PageRequest:
    domain = str(task.get("domain", "")).strip().lower()
    if not domain or "/" in domain or ":" in domain:
        raise GovernmentAdapterError("Socrata domain must be a bare host name")
    limit = _bounded_page_size(task.get("page_size"), default=100, maximum=1000)
    offset = task.get("offset", 0)
    if isinstance(offset, bool) or not isinstance(offset, int) or offset < 0:
        raise GovernmentAdapterError("Socrata offset must be a non-negative integer")
    params: dict[str, str | int] = {
        "search_context": domain,
        "limit": limit,
        "offset": offset,
    }
    query = task.get("query")
    if query:
        params["q"] = str(query)
    return PageRequest(
        method="GET",
        url="https://api.us.socrata.com/api/catalog/v1",
        params=params,
        provider="socrata-catalog",
        cursor=offset,
    )


def parse_socrata_catalog(payload: dict[str, Any], request: PageRequest) -> PageResult:
    results = payload.get("results", [])
    if not isinstance(results, list):
        raise GovernmentAdapterError("Socrata catalog results must be a list")
    records = [item for item in results if isinstance(item, dict)]
    limit = int(request.params["limit"])
    offset = int(request.params["offset"])
    next_cursor = offset + len(records) if len(records) == limit else None
    return PageResult(records=records, next_cursor=next_cursor, source_url=request.url)


def socrata_dataset_request(task: dict[str, Any]) -> PageRequest:
    domain = str(task.get("domain", "")).strip().lower()
    dataset_id = str(task.get("dataset_id", "")).strip()
    if not domain or "/" in domain or ":" in domain:
        raise GovernmentAdapterError("Socrata domain must be a bare host name")
    if not dataset_id or any(ch not in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_" for ch in dataset_id):
        raise GovernmentAdapterError("invalid Socrata dataset id")
    limit = _bounded_page_size(task.get("page_size"))
    offset = task.get("offset", 0)
    if isinstance(offset, bool) or not isinstance(offset, int) or offset < 0:
        raise GovernmentAdapterError("Socrata offset must be a non-negative integer")
    return PageRequest(
        method="GET",
        url=f"https://{domain}/resource/{dataset_id}.json",
        params={"$limit": limit, "$offset": offset},
        provider="socrata",
        cursor=offset,
    )


def parse_socrata_dataset(payload: Any, request: PageRequest) -> PageResult:
    if not isinstance(payload, list):
        raise GovernmentAdapterError("Socrata dataset page must be a JSON list")
    records = [item for item in payload if isinstance(item, dict)]
    limit = int(request.params["$limit"])
    offset = int(request.params["$offset"])
    next_cursor = offset + len(records) if len(records) == limit else None
    return PageResult(records=records, next_cursor=next_cursor, source_url=request.url)


def ckan_catalog_request(task: dict[str, Any]) -> PageRequest:
    base = _https_base(str(task.get("base_url", "")))
    rows = _bounded_page_size(task.get("page_size"), default=100, maximum=1000)
    start = task.get("offset", 0)
    if isinstance(start, bool) or not isinstance(start, int) or start < 0:
        raise GovernmentAdapterError("CKAN offset must be a non-negative integer")
    params: dict[str, str | int] = {"rows": rows, "start": start}
    if task.get("query"):
        params["q"] = str(task["query"])
    return PageRequest(
        method="GET",
        url=urljoin(base + "/", "api/3/action/package_search"),
        params=params,
        provider="ckan",
        cursor=start,
    )


def parse_ckan_catalog(payload: dict[str, Any], request: PageRequest) -> PageResult:
    if payload.get("success") is not True:
        raise GovernmentAdapterError("CKAN action did not report success")
    result = payload.get("result")
    if not isinstance(result, dict) or not isinstance(result.get("results"), list):
        raise GovernmentAdapterError("invalid CKAN package_search result")
    records = [item for item in result["results"] if isinstance(item, dict)]
    rows = int(request.params["rows"])
    start = int(request.params["start"])
    count = result.get("count")
    next_cursor = start + len(records)
    if len(records) < rows or (isinstance(count, int) and next_cursor >= count):
        next_cursor = None
    return PageResult(records=records, next_cursor=next_cursor, source_url=request.url)


def arcgis_catalog_request(task: dict[str, Any]) -> PageRequest:
    base = _https_base(str(task.get("base_url", "")))
    count = _bounded_page_size(task.get("page_size"), default=100, maximum=100)
    start = task.get("start", 1)
    if isinstance(start, bool) or not isinstance(start, int) or start < 1:
        raise GovernmentAdapterError("ArcGIS start must be a positive integer")
    params: dict[str, str | int] = {
        "f": "json",
        "num": count,
        "start": start,
        "q": str(task.get("query") or "type:Feature Service"),
    }
    return PageRequest(
        method="GET",
        url=urljoin(base + "/", "sharing/rest/search"),
        params=params,
        provider="arcgis-catalog",
        cursor=start,
    )


def parse_arcgis_catalog(payload: dict[str, Any], request: PageRequest) -> PageResult:
    if "error" in payload:
        raise GovernmentAdapterError("ArcGIS catalog returned an error")
    results = payload.get("results")
    if not isinstance(results, list):
        raise GovernmentAdapterError("invalid ArcGIS catalog response")
    records = [item for item in results if isinstance(item, dict)]
    next_start = payload.get("nextStart", -1)
    next_cursor = next_start if isinstance(next_start, int) and next_start > 0 else None
    return PageResult(records=records, next_cursor=next_cursor, source_url=request.url)


def arcgis_feature_request(task: dict[str, Any]) -> PageRequest:
    service = _https_base(str(task.get("service_url", "")))
    size = _bounded_page_size(task.get("page_size"), default=500, maximum=2000)
    offset = task.get("offset", 0)
    if isinstance(offset, bool) or not isinstance(offset, int) or offset < 0:
        raise GovernmentAdapterError("ArcGIS offset must be a non-negative integer")
    return PageRequest(
        method="GET",
        url=service + "/query",
        params={
            "f": "json",
            "where": str(task.get("where") or "1=1"),
            "outFields": str(task.get("out_fields") or "*"),
            "returnGeometry": "true" if task.get("return_geometry", True) else "false",
            "resultOffset": offset,
            "resultRecordCount": size,
        },
        provider="arcgis-feature",
        cursor=offset,
    )


def parse_arcgis_feature(payload: dict[str, Any], request: PageRequest) -> PageResult:
    if "error" in payload:
        raise GovernmentAdapterError("ArcGIS feature query returned an error")
    features = payload.get("features")
    if not isinstance(features, list):
        raise GovernmentAdapterError("invalid ArcGIS feature response")
    records = [item for item in features if isinstance(item, dict)]
    offset = int(request.params["resultOffset"])
    size = int(request.params["resultRecordCount"])
    exceeded = payload.get("exceededTransferLimit") is True
    next_cursor = offset + len(records) if exceeded or len(records) == size else None
    return PageResult(records=records, next_cursor=next_cursor, source_url=request.url)
