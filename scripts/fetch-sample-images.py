#!/usr/bin/env python3
import json
import pathlib
import sys
import urllib.parse
import urllib.request

QUERY = "person desk posture side view"
OUT = pathlib.Path("Samples")


def main() -> int:
    OUT.mkdir(exist_ok=True)
    url = "https://api.openverse.org/v1/images/?" + urllib.parse.urlencode(
        {"q": QUERY, "license_type": "commercial,modification", "page_size": 10}
    )
    with urllib.request.urlopen(url, timeout=20) as response:
        payload = json.load(response)

    saved = 0
    for item in payload.get("results", []):
        image_url = item.get("url")
        if not image_url:
            continue
        parsed = urllib.parse.urlparse(image_url)
        if parsed.scheme not in {"http", "https"}:
            print(f"skip {image_url}: unsupported URL scheme", file=sys.stderr)
            continue
        suffix = pathlib.Path(parsed.path).suffix.lower()
        if suffix not in {".jpg", ".jpeg", ".png"}:
            suffix = ".jpg"
        target = OUT / f"sample-{saved + 1:02d}{suffix}"
        try:
            with urllib.request.urlopen(image_url, timeout=20) as image_response:
                target.write_bytes(image_response.read())
            saved += 1
        except Exception as exc:
            print(f"skip {image_url}: {exc}", file=sys.stderr)

    print(f"saved {saved} images to {OUT}")
    return 0 if saved else 1


if __name__ == "__main__":
    raise SystemExit(main())
