#!/usr/bin/env python3
"""
Common Crawl .ir domain collector for scan-ir-domains.

This script updates a local domain source file before scans. It uses Common
Crawl's CDX index API, extracts .ir hostnames from URLs, normalizes and
deduplicates them, then merges them into data/domains.txt.

It has no third-party dependencies.
"""

import argparse
import json
import re
import sys
import time
import urllib.parse
import urllib.request
from pathlib import Path
from typing import Iterable, Set
from urllib.parse import urlparse

DOMAIN_RE = re.compile(
    r"^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?(?:\.[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?)*\.ir$",
    re.IGNORECASE,
)
DEFAULT_SEEDS = ("diver.ir", "nic.ir", "time.ir")


def normalize_host(raw: str) -> str | None:
    value = (raw or "").strip().lower().rstrip(".")
    if not value:
        return None
    if value.startswith("http://") or value.startswith("https://"):
        value = urlparse(value).hostname or ""
    if value.startswith("*."):
        value = value[2:]
    value = value.split(":", 1)[0]
    if not value.endswith(".ir"):
        return None
    if not DOMAIN_RE.fullmatch(value):
        return None
    return value


def extract_host_from_url(raw_url: str) -> str | None:
    try:
        return normalize_host(urlparse(raw_url).hostname or "")
    except Exception:
        return None


def load_existing(path: Path) -> Set[str]:
    domains: Set[str] = set()
    if not path.exists():
        return domains
    for raw_line in path.read_text(encoding="utf-8", errors="replace").splitlines():
        line = raw_line.split("#", 1)[0].strip()
        if not line:
            continue
        for token in re.split(r"[\s,;]+", line):
            domain = normalize_host(token)
            if domain:
                domains.add(domain)
    return domains


def save_domains(path: Path, domains: Iterable[str]) -> None:
    cleaned = sorted({domain for domain in domains if normalize_host(domain)})
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("\n".join(cleaned) + "\n", encoding="utf-8")


def fetch_json(url: str, timeout: int):
    request = urllib.request.Request(url, headers={"User-Agent": "scan-ir-domains/1.0"})
    with urllib.request.urlopen(request, timeout=timeout) as response:
        return json.loads(response.read().decode("utf-8", errors="replace"))


def query_commoncrawl_index(api_url: str, limit: int, timeout: int) -> Set[str]:
    params = {
        "url": "*.ir/*",
        "output": "json",
        "fl": "url",
        "filter": "status:200",
        "limit": str(limit),
    }
    url = api_url + "?" + urllib.parse.urlencode(params)
    found: Set[str] = set()
    request = urllib.request.Request(url, headers={"User-Agent": "scan-ir-domains/1.0"})

    with urllib.request.urlopen(request, timeout=timeout) as response:
        for raw_line in response:
            line = raw_line.decode("utf-8", errors="replace").strip()
            if not line:
                continue
            try:
                record = json.loads(line)
            except json.JSONDecodeError:
                continue
            host = extract_host_from_url(record.get("url", ""))
            if host:
                found.add(host)
    return found


def main() -> int:
    parser = argparse.ArgumentParser(description="Fetch .ir domains from Common Crawl into domains.txt")
    parser.add_argument("--output", default="data/domains.txt", help="Domain list output path")
    parser.add_argument("--indexes", type=int, default=3, help="Number of recent Common Crawl indexes to query")
    parser.add_argument("--limit-per-index", type=int, default=200000, help="Maximum CDX rows per index")
    parser.add_argument("--timeout", type=int, default=180, help="HTTP timeout in seconds")
    parser.add_argument("--sleep", type=float, default=1.0, help="Delay between index queries")
    parser.add_argument("--no-seeds", action="store_true", help="Do not add the built-in starter domains")
    args = parser.parse_args()

    output = Path(args.output)
    existing = load_existing(output)
    discovered: Set[str] = set()
    seeds = set() if args.no_seeds else {domain for domain in DEFAULT_SEEDS if normalize_host(domain)}

    print("Fetching Common Crawl index list...")
    try:
        collections = fetch_json("https://index.commoncrawl.org/collinfo.json", timeout=args.timeout)
    except Exception as exc:
        merged = existing | seeds
        if merged:
            save_domains(output, merged)
        print(f"WARNING: failed to fetch Common Crawl index list: {exc}", file=sys.stderr)
        print(f"Kept existing domains: {len(existing)}")
        print(f"Total saved: {len(merged)}")
        return 0 if merged else 1

    selected = collections[: max(1, args.indexes)]
    print(f"Existing domains: {len(existing)}")
    print(f"Querying latest {len(selected)} Common Crawl index(es)...")

    for index in selected:
        index_id = index.get("id", "unknown")
        api_url = index.get("cdx-api") or f"https://index.commoncrawl.org/{index_id}-index"
        print(f"\n== {index_id} ==")
        try:
            domains = query_commoncrawl_index(api_url, args.limit_per_index, args.timeout)
            discovered.update(domains)
            print(f"Found {len(domains)} .ir domains in {index_id}")
        except Exception as exc:
            print(f"WARNING: failed {index_id}: {exc}", file=sys.stderr)
        time.sleep(max(0.0, args.sleep))

    merged = existing | discovered | seeds
    save_domains(output, merged)

    print("\nDone.")
    print(f"Newly discovered: {len(discovered - existing)}")
    print(f"Total saved: {len(merged)}")
    print(f"Output: {output}")
    return 0 if merged else 1


if __name__ == "__main__":
    raise SystemExit(main())
