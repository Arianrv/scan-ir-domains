#!/usr/bin/env python3
"""
Iranian Domain Accessibility Checker
https://github.com/Arianrv/scan-ir-domains
=====================================
Checks CT-known .ir hostnames from an external VPS/network.

Important scope note:
    This does not enumerate every registered .ir domain. It enumerates .ir hostnames
    visible in public Certificate Transparency data and then checks reachability from
    the machine where the scanner runs.

Usage:
    python3 iran_domain_checker.py [--output results.jsonl] [--workers 50] [--timeout 10]
    python3 iran_domain_checker.py --domains diver.ir,nic.ir,time.ir

Requirements:
    pip install aiohttp aiofiles certifi requests
"""

import asyncio
import aiofiles
import aiohttp
import json
import logging
import socket
import sys
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Dict, List, Optional, Sequence, Set

DEFAULT_CT_PREFIXES = "0123456789abcdefghijklmnopqrstuvwxyz"

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    handlers=[
        logging.FileHandler("iran_domain_checker.log"),
        logging.StreamHandler(),
    ],
)
logger = logging.getLogger(__name__)


class CtResponseTooLarge(RuntimeError):
    """Raised when a CT query response exceeds the configured memory budget."""


class DomainChecker:
    """
    Checks CT-known .ir hostname accessibility from the current VPS/network.
    CT discovery is sharded by hostname prefix so crt.sh is not asked for the
    whole .ir namespace in one fragile query.
    """

    def __init__(
        self,
        output_file: str = "iran_domains_accessible.jsonl",
        workers: int = 50,
        timeout: int = 10,
        batch_size: int = 10,
        ct_timeout: int = 60,
        ct_retries: int = 2,
        ct_prefixes: str = DEFAULT_CT_PREFIXES,
        ct_max_depth: int = 2,
        ct_query_delay: float = 1.0,
        ct_max_response_mb: int = 50,
    ):
        self.output_file = output_file
        self.workers = workers
        self.timeout = timeout
        self.batch_size = batch_size
        self.ct_timeout = ct_timeout
        self.ct_retries = ct_retries
        self.ct_prefixes = self._normalize_prefixes(ct_prefixes)
        self.ct_shard_chars = self._normalize_prefixes(DEFAULT_CT_PREFIXES)
        self.ct_max_depth = max(1, ct_max_depth)
        self.ct_query_delay = max(0.0, ct_query_delay)
        self.ct_max_response_bytes = max(1, ct_max_response_mb) * 1024 * 1024
        self.checked_domains: Set[str] = set()
        self.results_buffer: List[Dict] = []
        self.write_lock = asyncio.Lock()
        self.session: Optional[aiohttp.ClientSession] = None
        self.queue: asyncio.Queue = asyncio.Queue()

    @staticmethod
    def _normalize_prefixes(raw_prefixes: str) -> List[str]:
        if "," in raw_prefixes:
            candidates = [item.strip().lower() for item in raw_prefixes.split(",")]
        else:
            candidates = [char.lower() for char in raw_prefixes if not char.isspace()]

        prefixes: List[str] = []
        seen: Set[str] = set()
        for prefix in candidates:
            if not prefix or prefix in seen:
                continue
            if not all(char.isalnum() or char == "-" for char in prefix):
                raise ValueError(f"Invalid CT prefix: {prefix!r}")
            seen.add(prefix)
            prefixes.append(prefix)

        if not prefixes:
            raise ValueError("At least one CT prefix is required")
        return prefixes

    async def __aenter__(self):
        connector = aiohttp.TCPConnector(
            limit=self.workers,
            limit_per_host=5,
            ttl_dns_cache=300,
        )
        self.session = aiohttp.ClientSession(
            connector=connector,
            timeout=aiohttp.ClientTimeout(total=self.timeout),
            headers={
                "User-Agent": "scan-ir-domains/1.0 (+https://github.com/Arianrv/scan-ir-domains)"
            },
        )
        return self

    async def __aexit__(self, exc_type, exc_val, exc_tb):
        if self.session:
            await self.session.close()

    def _require_session(self) -> aiohttp.ClientSession:
        if self.session is None or self.session.closed:
            raise RuntimeError("HTTP session is not active")
        return self.session

    async def resolve_dns(self, domain: str) -> Optional[str]:
        try:
            loop = asyncio.get_event_loop()
            infos = await asyncio.wait_for(
                loop.getaddrinfo(
                    domain,
                    443,
                    family=socket.AF_UNSPEC,
                    type=socket.SOCK_STREAM,
                ),
                timeout=self.timeout,
            )
            for info in infos:
                address = info[4][0]
                if address:
                    return address
            return None
        except (socket.gaierror, asyncio.TimeoutError, OSError):
            return None

    @staticmethod
    def _url_host(ip_or_host: str) -> str:
        if ":" in ip_or_host and not ip_or_host.startswith("["):
            return f"[{ip_or_host}]"
        return ip_or_host

    async def check_http_status(self, domain: str, ip: Optional[str] = None) -> Optional[int]:
        session = self._require_session()
        urls = [f"https://{domain}/", f"http://{domain}/"]

        if ip:
            urls.append(f"https://{self._url_host(ip)}/")

        for url in urls:
            try:
                async with session.get(url, ssl=False, allow_redirects=True) as resp:
                    return resp.status
            except Exception:
                continue

        return None

    async def check_tls_certificate(self, domain: str) -> bool:
        try:
            import ssl

            async def _get_cert():
                context = ssl.create_default_context()
                reader, writer = await asyncio.open_connection(
                    domain,
                    443,
                    ssl=context,
                    server_hostname=domain,
                )
                cert = writer.get_extra_info("peercert")
                writer.close()
                await writer.wait_closed()
                return cert is not None

            return await asyncio.wait_for(_get_cert(), timeout=self.timeout)
        except Exception:
            return False

    async def check_domain(self, domain: str) -> Optional[Dict]:
        if domain in self.checked_domains:
            return None

        self.checked_domains.add(domain)

        result = {
            "domain": domain,
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "accessible": False,
            "dns_resolves": False,
            "http_status": None,
            "tls_valid": False,
            "ip": None,
            "checked_from": "external_vps",
        }

        try:
            ip = await self.resolve_dns(domain)
            result["dns_resolves"] = ip is not None
            result["ip"] = ip

            if not ip:
                logger.debug(f"DNS resolution failed: {domain}")
                return result

            http_status = await self.check_http_status(domain, ip)
            result["http_status"] = http_status

            tls_valid = await self.check_tls_certificate(domain)
            result["tls_valid"] = tls_valid

            result["accessible"] = (
                result["dns_resolves"]
                and ((http_status and 200 <= http_status < 400) or tls_valid)
            )

            logger.info(f"✓ {domain} | IP: {ip} | Accessible: {result['accessible']}")

        except Exception as exc:
            logger.error(f"Error checking {domain}: {exc}")

        return result

    async def _write_results(self, batch: Sequence[Dict]) -> None:
        if not batch:
            return
        try:
            output_path = Path(self.output_file)
            output_path.parent.mkdir(parents=True, exist_ok=True)
            async with aiofiles.open(output_path, "a") as f:
                for result in batch:
                    await f.write(json.dumps(result) + "\n")
            logger.info(f"💾 Saved {len(batch)} results to {self.output_file}")
        except Exception as exc:
            logger.error(f"Failed to save batch: {exc}")

    async def buffer_result(self, result: Dict) -> None:
        batch_to_write: List[Dict] = []
        async with self.write_lock:
            self.results_buffer.append(result)
            if len(self.results_buffer) >= self.batch_size:
                batch_to_write = self.results_buffer
                self.results_buffer = []

        if batch_to_write:
            await self._write_results(batch_to_write)

    async def flush_results(self) -> None:
        batch_to_write: List[Dict] = []
        async with self.write_lock:
            if self.results_buffer:
                batch_to_write = self.results_buffer
                self.results_buffer = []

        if batch_to_write:
            await self._write_results(batch_to_write)

    async def worker(self, worker_id: int):
        while True:
            try:
                domain = await asyncio.wait_for(self.queue.get(), timeout=1.0)
            except asyncio.TimeoutError:
                break

            try:
                result = await self.check_domain(domain)
                if result:
                    await self.buffer_result(result)
                self.queue.task_done()
            except Exception as exc:
                logger.error(f"Worker {worker_id} error: {exc}")
                self.queue.task_done()

    async def _download_ct_json(self, query: str) -> Optional[List[Dict]]:
        session = self._require_session()
        url = "https://crt.sh/"
        params = {"q": query, "output": "json"}
        data = bytearray()

        async with session.get(
            url,
            params=params,
            timeout=aiohttp.ClientTimeout(total=self.ct_timeout),
        ) as resp:
            if resp.status != 200:
                logger.warning(f"CT log query returned HTTP {resp.status} for {query}")
                return None

            content_length = resp.headers.get("Content-Length")
            if content_length and int(content_length) > self.ct_max_response_bytes:
                raise CtResponseTooLarge(
                    f"CT response for {query} exceeds {self.ct_max_response_bytes} bytes"
                )

            async for chunk in resp.content.iter_chunked(1024 * 512):
                data.extend(chunk)
                if len(data) > self.ct_max_response_bytes:
                    raise CtResponseTooLarge(
                        f"CT response for {query} exceeds {self.ct_max_response_bytes} bytes"
                    )

        try:
            parsed = json.loads(data.decode("utf-8", errors="replace"))
        except json.JSONDecodeError:
            logger.warning(f"Failed to parse JSON from CT logs for {query}")
            return None

        if not isinstance(parsed, list):
            logger.warning(f"Unexpected CT log response format for {query}")
            return None
        return parsed

    @staticmethod
    def _extract_ir_domains(cert_rows: Sequence[Dict]) -> Set[str]:
        domains: Set[str] = set()
        for cert in cert_rows:
            raw_names = str(cert.get("name_value", ""))
            for domain in raw_names.split("\n"):
                domain = domain.strip().lower().rstrip(".")
                if domain.startswith("*."):
                    domain = domain[2:]
                if domain.endswith(".ir") and len(domain) > 3:
                    domains.add(domain)
        return domains

    async def _query_ct_shard(self, prefix: str) -> Optional[Set[str]]:
        query = f"{prefix}%.ir"
        for attempt in range(1, self.ct_retries + 1):
            logger.info(
                f"Querying CT logs for: {query} "
                f"(attempt {attempt}/{self.ct_retries}, timeout {self.ct_timeout}s)"
            )
            try:
                rows = await self._download_ct_json(query)
                if rows is None:
                    domains: Set[str] = set()
                else:
                    domains = self._extract_ir_domains(rows)
                logger.info(f"CT shard {query} returned {len(domains)} unique .ir hostnames")
                return domains
            except CtResponseTooLarge as exc:
                logger.warning(str(exc))
                raise
            except asyncio.TimeoutError:
                logger.warning(f"CT log query timeout for {query}")
            except Exception as exc:
                logger.error(f"CT log query error for {query}: {exc}")

            if attempt < self.ct_retries:
                delay = min(10 * attempt, 30)
                logger.info(f"Retrying CT shard {query} in {delay}s")
                await asyncio.sleep(delay)

        return None

    async def process_ct_logs(self) -> Set[str]:
        """
        Fetch CT-known .ir hostnames from crt.sh using sharded prefix queries.
        Test-domain fallback is intentionally not allowed for production scans.
        """
        ct_domains: Set[str] = set()
        pending: List[str] = list(self.ct_prefixes)
        processed: Set[str] = set()

        while pending:
            prefix = pending.pop(0)
            if prefix in processed:
                continue
            processed.add(prefix)

            try:
                shard_domains = await self._query_ct_shard(prefix)
            except CtResponseTooLarge:
                if len(prefix) < self.ct_max_depth:
                    logger.info(f"Splitting oversized CT shard {prefix!r} into deeper shards")
                    pending.extend(f"{prefix}{char}" for char in self.ct_shard_chars)
                else:
                    logger.warning(
                        f"Skipping oversized CT shard {prefix!r}; increase --ct-max-depth "
                        "or --ct-max-response-mb for broader coverage"
                    )
                shard_domains = None

            if shard_domains:
                before = len(ct_domains)
                ct_domains.update(shard_domains)
                logger.info(
                    f"CT discovery total: {len(ct_domains)} unique .ir hostnames "
                    f"(+{len(ct_domains) - before})"
                )

            if self.ct_query_delay:
                await asyncio.sleep(self.ct_query_delay)

        logger.info(f"Found {len(ct_domains)} unique CT-known .ir hostnames")
        return ct_domains

    async def run(self, domains: Optional[List[str]] = None):
        logger.info("=== Iranian Domain Checker Starting ===")
        logger.info(f"Output file: {self.output_file}")
        logger.info(f"Workers: {self.workers}, Timeout: {self.timeout}s, Batch: {self.batch_size}")

        start_time = time.time()

        if not domains:
            domains = list(await self.process_ct_logs())
            if not domains:
                raise RuntimeError(
                    "CT discovery returned zero .ir hostnames after all shards. "
                    "No fallback test scan was run. Try again later or check crt.sh/network availability."
                )

        logger.info(f"Starting checks on {len(domains)} domains...")

        for domain in domains:
            await self.queue.put(domain)

        workers = [asyncio.create_task(self.worker(i)) for i in range(self.workers)]

        await self.queue.join()

        for worker in workers:
            worker.cancel()
        await asyncio.gather(*workers, return_exceptions=True)

        await self.flush_results()

        elapsed = time.time() - start_time
        logger.info(f"=== Completed in {elapsed:.1f}s ===")
        logger.info(f"Checked domains: {len(self.checked_domains)}")
        logger.info(f"Results saved to: {self.output_file}")

        self._print_summary()

    def _print_summary(self):
        try:
            accessible_count = 0
            total_count = 0

            with open(self.output_file, "r") as f:
                for line in f:
                    try:
                        result = json.loads(line)
                        total_count += 1
                        if result.get("accessible"):
                            accessible_count += 1
                    except json.JSONDecodeError:
                        continue

            logger.info("\n📊 Summary:")
            logger.info(f"  Total checked: {total_count}")
            logger.info(f"  Accessible: {accessible_count}")
            logger.info(f"  Blocked: {total_count - accessible_count}")
            if total_count > 0:
                logger.info(f"  Accessibility rate: {100 * accessible_count / total_count:.1f}%")
        except FileNotFoundError:
            pass


async def main():
    import argparse

    parser = argparse.ArgumentParser(
        description="Check CT-known .ir hostname accessibility from this VPS/network"
    )
    parser.add_argument(
        "--output",
        "-o",
        default="iran_domains_accessible.jsonl",
        help="Output JSONL file (default: iran_domains_accessible.jsonl)",
    )
    parser.add_argument(
        "--workers",
        "-w",
        type=int,
        default=50,
        help="Number of concurrent workers (default: 50)",
    )
    parser.add_argument(
        "--timeout",
        "-t",
        type=int,
        default=10,
        help="Timeout per domain check in seconds (default: 10)",
    )
    parser.add_argument(
        "--batch",
        "-b",
        type=int,
        default=10,
        help="Save results every N domains (default: 10)",
    )
    parser.add_argument(
        "--ct-timeout",
        type=int,
        default=60,
        help="Per-shard Certificate Transparency query timeout in seconds (default: 60)",
    )
    parser.add_argument(
        "--ct-retries",
        type=int,
        default=2,
        help="Per-shard Certificate Transparency query retry count (default: 2)",
    )
    parser.add_argument(
        "--ct-prefixes",
        default=DEFAULT_CT_PREFIXES,
        help="Initial CT shard prefixes. Use a string like abc or comma-separated prefixes like a,b,1 (default: 0-9a-z)",
    )
    parser.add_argument(
        "--ct-max-depth",
        type=int,
        default=2,
        help="Maximum prefix depth for splitting oversized CT shards (default: 2)",
    )
    parser.add_argument(
        "--ct-query-delay",
        type=float,
        default=1.0,
        help="Delay between CT shard queries in seconds (default: 1.0)",
    )
    parser.add_argument(
        "--ct-max-response-mb",
        type=int,
        default=50,
        help="Maximum CT response size per shard in MiB before deeper sharding/skipping (default: 50)",
    )
    parser.add_argument(
        "--domains",
        help="Comma-separated list of domains to check instead of CT discovery. Use this only for manual tests.",
    )

    args = parser.parse_args()

    custom_domains = None
    if args.domains:
        custom_domains = [d.strip().lower() for d in args.domains.split(",") if d.strip()]

    async with DomainChecker(
        output_file=args.output,
        workers=args.workers,
        timeout=args.timeout,
        batch_size=args.batch,
        ct_timeout=args.ct_timeout,
        ct_retries=args.ct_retries,
        ct_prefixes=args.ct_prefixes,
        ct_max_depth=args.ct_max_depth,
        ct_query_delay=args.ct_query_delay,
        ct_max_response_mb=args.ct_max_response_mb,
    ) as checker:
        await checker.run(domains=custom_domains)


if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        logger.info("Interrupted by user")
        sys.exit(0)
    except Exception as exc:
        logger.error(str(exc))
        sys.exit(1)
