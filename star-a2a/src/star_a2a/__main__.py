from __future__ import annotations

import os
from pathlib import Path

import uvicorn

from .host import build_app, load_beast_catalog


def main() -> None:
    catalog_path = Path(
        os.environ.get(
            "STAR_A2A_CATALOG",
            "catalog/starintel/beast-workers.json",
        )
    )
    host = os.environ.get("STAR_A2A_BIND_HOST", "127.0.0.1")
    port = int(os.environ.get("STAR_A2A_PORT", "9797"))
    public_url = os.environ.get("STAR_A2A_PUBLIC_URL", f"http://127.0.0.1:{port}")
    catalog = load_beast_catalog(catalog_path)
    app, _ = build_app(catalog, public_url=public_url)
    uvicorn.run(app, host=host, port=port)


if __name__ == "__main__":
    main()
