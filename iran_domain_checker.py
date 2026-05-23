#!/usr/bin/env python3
"""
Iranian Domain Accessibility Checker
https://github.com/Arianrv/scan-ir-domains
=====================================
Checks which Iranian domains (.ir) are accessible from outside Iran.
Streams domains from Certificate Transparency logs, performs async checks, and saves JSONL results.

Usage:
    python3 iran_domain_checker.py [--output results.jsonl] [--workers 50] [--timeout 10]

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
from typing import Dict, List, Optional, Set

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    handlers=[
        logging.FileHandler("iran_domain_checker.log"),
        logging.StreamHandler(),
    ],
)
logger = logging.getLogger(__name__)


class DomainChecker:
    """
    Checks Iranian domain accessibility from outside Iran.
    Streams from CT logs, deduplicates, runs async checks, saves batches.
    """

    def __init__(
        self,
        output_file: str = "iran_domains_accessible.jsonl",
        workers: int = 50,
        timeout: int = 10,
        batch_size: int = 10,
        ct_timeout: int = 180,
        ct_retries: int = 3,
    ):
        self.output_file = output_file
        self.workers = workers
        self.timeout = timeout
        self.batch_size = batch_size
        self.ct_timeout = ct_timeout
        self.ct_retries = ct_retries
        self.checked_domains: Set[str] = set()
        self.results_buffer: List[Dict] = []
        self.session: Optional[aiohttp.ClientSession] = None
        self.queue: asyncio.Queue = asyncio.Queue()

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
            ip = await asyncio.wait_for(
                loop.getaddrinfo(domain, 443, family=socket.AF_INET),
                timeout=self.timeout,
            )
            return ip[0][4][0] if ip else None
        except (socket.gaierror, asyncio.TimeoutError, OSError):
            return None

    async def check_http_status(self, domain: str, ip: Optional[str] = None) -> Optional[int]:
        session = self._require_session()
        urls = [f"https://{domain}/", f"http://{domain}/"]

        if ip:
            urls.append(f"https://{ip}/")

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
            "checked_from": "external",
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

    async def save_batch(self, force: bool = False):
        if len(self.results_buffer) >= self.batch_size or (force and self.results_buffer):
            try:
                output_path = Path(self.output_file)
                output_path.parent.mkdir(parents=True, exist_ok=True)
                async with aiofiles.open(output_path, "a") as f:
                    for result in self.results_buffer:
                        await f.write(json.dumps(result) + "\n")

                count = len(self.results_buffer)
                logger.info(f"💾 Saved {count} results to {self.output_file}")
                self.results_buffer = []
            except Exception as exc:
                logger.error(f"Failed to save batch: {exc}")

    async def worker(self, worker_id: int):
        while True:
            try:
                domain = await asyncio.wait_for(self.queue.get(), timeout=1.0)
            except asyncio.TimeoutError:
                break

            try:
                result = await self.check_domain(domain)
                if result:
                    self.results_buffer.append(result)

                    if len(self.results_buffer) >= self.batch_size:
                        await self.save_batch()

                self.queue.task_done()
            except Exception as exc:
                logger.error(f"Worker {worker_id} error: {exc}")
                self.queue.task_done()

    async def process_ct_logs(self) -> Set[str]:
        """
        Fetch .ir domains from crt.sh. This must return real CT-derived domains.
        Test-domain fallback is intentionally not allowed for production scans.
        """
        session = self._require_session()
        ct_domains: Set[str] = set()
        query = "%.ir"
        url = f"https://crt.sh/?q={query}&output=json"

        for attempt in range(1, self.ct_retries + 1):
            logger.info(
                f"Querying CT logs for: {query} "
                f"(attempt {attempt}/{self.ct_retries}, timeout {self.ct_timeout}s)"
            )
            try:
                async with session.get(
                    url,
                    timeout=aiohttp.ClientTimeout(total=self.ct_timeout),
                ) as resp:
                    if resp.status != 200:
                        logger.warning(f"CT log query returned HTTP {resp.status} for {query}")
                    else:
                        text = await resp.text()
                        try:
                            data = json.loads(text)
                        except json.JSONDecodeError:
                            logger.warning("Failed to parse JSON from CT logs")
                            data = []

                        if isinstance(data, list):
                            for cert in data:
                                for domain in cert.get("name_value", "").split("\n"):
                                    domain = domain.strip().lower().rstrip(".")
                                    if domain.startswith("*."):
                                        domain = domain[2:]
                                    if domain.endswith(".ir") and len(domain) > 3:
                                        ct_domains.add(domain)
                        else:
                            logger.warning("Unexpected CT log response format")
            except asyncio.TimeoutError:
                logger.warning(f"CT log query timeout for {query}")
            except Exception as exc:
                logger.error(f"CT log query error: {exc}")

            if ct_domains:
                logger.info(f"Found {len(ct_domains)} unique .ir domains from CT logs")
                return ct_domains

            if attempt < self.ct_retries:
                delay = min(10 * attempt, 30)
                logger.info(f"No CT domains found yet; retrying in {delay}s")
                await asyncio.sleep(delay)

        logger.error("Found 0 unique .ir domains from CT logs")
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
                    "CT log discovery returned zero .ir domains after retries. "
                    "No fallback test scan was run. Try again later or check crt.sh/network availability."
                )

        logger.info(f"Starting checks on {len(domains)} domains...")

        for domain in domains:
            await self.queue.put(domain)

        workers = [asyncio.create_task(self.worker(i)) for i in range(self.workers)]

        await self.queue.join()

        for worker in workers:
            worker.cancel()

        await self.save_batch(force=True)

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
        description="Check Iranian domain accessibility from outside Iran"
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
        default=180,
        help="Certificate Transparency query timeout in seconds (default: 180)",
    )
    parser.add_argument(
        "--ct-retries",
        type=int,
        default=3,
        help="Certificate Transparency query retry count (default: 3)",
    )
    parser.add_argument(
        "--domains",
        help="Comma-separated list of domains to check instead of CT logs. Use this only for manual tests.",
    )

    args = parser.parse_args()

    custom_domains = None
    if args.domains:
        custom_domains = [d.strip() for d in args.domains.split(",") if d.strip()]

    async with DomainChecker(
        output_file=args.output,
        workers=args.workers,
        timeout=args.timeout,
        batch_size=args.batch,
        ct_timeout=args.ct_timeout,
        ct_retries=args.ct_retries,
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
