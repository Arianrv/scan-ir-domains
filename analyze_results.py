#!/usr/bin/env python3
"""
Iranian Domain Checker - Results Analyzer
==========================================
Analyze, filter, and export results from iran_domain_checker.py

Usage:
    python3 analyze_results.py [input.jsonl] [--format csv|json|summary]
    
Examples:
    python3 analyze_results.py iran_domains_accessible.jsonl --format summary
    python3 analyze_results.py iran_domains_accessible.jsonl --accessible-only
    python3 analyze_results.py iran_domains_accessible.jsonl --format csv > results.csv
"""

import json
import argparse
import sys
from pathlib import Path
from typing import Dict, List, Optional
from collections import defaultdict
from datetime import datetime


class ResultsAnalyzer:
    """Analyze domain checker results."""
    
    def __init__(self, input_file: str):
        self.input_file = input_file
        self.results: List[Dict] = []
        self.load_results()
    
    def load_results(self):
        """Load all results from JSONL file."""
        if not Path(self.input_file).exists():
            print(f"Error: {self.input_file} not found", file=sys.stderr)
            sys.exit(1)
        
        with open(self.input_file, 'r') as f:
            for line_num, line in enumerate(f, 1):
                try:
                    result = json.loads(line.strip())
                    if result:  # Skip empty lines
                        self.results.append(result)
                except json.JSONDecodeError as e:
                    print(f"Warning: Line {line_num} is invalid JSON: {e}", file=sys.stderr)
        
        print(f"Loaded {len(self.results)} results from {self.input_file}", file=sys.stderr)
    
    def filter_accessible(self, only_accessible: bool = True) -> List[Dict]:
        """Filter for accessible (or blocked) domains."""
        return [r for r in self.results if r.get('accessible') == only_accessible]
    
    def filter_dns_blocked(self) -> List[Dict]:
        """Filter for DNS-blocked domains (DNS fails but would resolve)."""
        return [r for r in self.results if not r.get('dns_resolves')]
    
    def filter_censored(self) -> List[Dict]:
        """Filter for censorship-intercepted domains (DNS works, but blocked)."""
        return [r for r in self.results if r.get('dns_resolves') and not r.get('accessible')]
    
    def print_summary(self):
        """Print summary statistics."""
        accessible = self.filter_accessible(only_accessible=True)
        dns_blocked = self.filter_dns_blocked()
        censored = self.filter_censored()
        
        print("\n" + "="*60)
        print("DOMAIN ACCESSIBILITY SUMMARY")
        print("="*60)
        print(f"Total domains checked:     {len(self.results)}")
        print(f"Accessible:                {len(accessible)} ({100*len(accessible)/len(self.results):.1f}%)")
        print(f"DNS-blocked:               {len(dns_blocked)} ({100*len(dns_blocked)/len(self.results):.1f}%)")
        print(f"Censorship-intercepted:    {len(censored)} ({100*len(censored)/len(self.results):.1f}%)")
        print("="*60)
        
        # HTTP status distribution
        print("\nHTTP Status Distribution:")
        status_counts = defaultdict(int)
        for result in self.results:
            status = result.get('http_status')
            if status:
                status_counts[status] += 1
            else:
                status_counts['(timeout/no-response)'] += 1
        
        for status in sorted([s for s in status_counts.keys() if isinstance(s, int)]):
            print(f"  {status}: {status_counts[status]}")
        print(f"  {status_counts.get('(timeout/no-response)', 0)} timed out / no response")
        
        # TLS validity
        print("\nTLS Certificate Status:")
        tls_valid = len([r for r in self.results if r.get('tls_valid')])
        print(f"  Valid TLS certificates:    {tls_valid} ({100*tls_valid/len(self.results):.1f}%)")
        print(f"  Invalid/Intercepted:       {len(self.results) - tls_valid} ({100*(len(self.results)-tls_valid)/len(self.results):.1f}%)")
    
    def print_accessible_domains(self):
        """Print list of accessible domains."""
        accessible = self.filter_accessible(only_accessible=True)
        print("\nAccessible Domains:")
        print("-" * 60)
        for result in accessible:
            ip = result.get('ip', 'N/A')
            status = result.get('http_status', 'N/A')
            print(f"  {result['domain']:40} | IP: {ip:15} | HTTP: {status}")
    
    def print_blocked_domains(self):
        """Print list of blocked domains."""
        blocked = self.filter_accessible(only_accessible=False)
        print("\nBlocked Domains:")
        print("-" * 60)
        
        dns_blocked = self.filter_dns_blocked()
        censored = self.filter_censored()
        
        print(f"\nDNS-Blocked ({len(dns_blocked)}):")
        for result in dns_blocked[:20]:  # First 20
            print(f"  {result['domain']}")
        if len(dns_blocked) > 20:
            print(f"  ... and {len(dns_blocked) - 20} more")
        
        print(f"\nCensorship-Intercepted ({len(censored)}):")
        for result in censored[:20]:  # First 20
            ip = result.get('ip', 'N/A')
            status = result.get('http_status', 'N/A')
            print(f"  {result['domain']:40} | IP: {ip:15} | HTTP: {status}")
        if len(censored) > 20:
            print(f"  ... and {len(censored) - 20} more")
    
    def export_csv(self, output_file: Optional[str] = None):
        """Export results as CSV."""
        import csv
        
        csv_file = output_file or 'results.csv'
        with open(csv_file, 'w', newline='') as f:
            writer = csv.DictWriter(
                f,
                fieldnames=['domain', 'accessible', 'dns_resolves', 'http_status', 'tls_valid', 'ip', 'timestamp']
            )
            writer.writeheader()
            for result in self.results:
                writer.writerow(result)
        
        print(f"Exported {len(self.results)} results to {csv_file}")
    
    def export_json(self, output_file: Optional[str] = None):
        """Export results as JSON."""
        json_file = output_file or 'results.json'
        with open(json_file, 'w') as f:
            json.dump(self.results, f, indent=2)
        print(f"Exported {len(self.results)} results to {json_file}")
    
    def export_domains_only(self, accessible_only: bool = False, output_file: Optional[str] = None):
        """Export just domain names, one per line."""
        domains = self.filter_accessible(only_accessible=accessible_only)
        domain_names = [r['domain'] for r in domains]
        
        output = output_file or ('accessible_domains.txt' if accessible_only else 'blocked_domains.txt')
        with open(output, 'w') as f:
            f.write('\n'.join(domain_names))
        
        status = "accessible" if accessible_only else "blocked"
        print(f"Exported {len(domain_names)} {status} domains to {output}")
    
    def find_domain(self, domain: str):
        """Find and print details for a specific domain."""
        for result in self.results:
            if result['domain'].lower() == domain.lower():
                print(f"\nResult for {domain}:")
                print("-" * 60)
                for key, value in result.items():
                    print(f"  {key:20}: {value}")
                return
        
        print(f"Domain {domain} not found in results")
    
    def compare_with_previous(self, other_file: str):
        """Compare results with previous scan."""
        other = ResultsAnalyzer(other_file)
        
        self_domains = {r['domain']: r for r in self.results}
        other_domains = {r['domain']: r for r in other.results}
        
        newly_blocked = []
        newly_accessible = []
        
        for domain, result in self_domains.items():
            if domain not in other_domains:
                continue
            
            was_accessible = other_domains[domain].get('accessible')
            is_accessible = result.get('accessible')
            
            if was_accessible and not is_accessible:
                newly_blocked.append(domain)
            elif not was_accessible and is_accessible:
                newly_accessible.append(domain)
        
        print("\n" + "="*60)
        print("COMPARISON WITH PREVIOUS SCAN")
        print("="*60)
        print(f"Previously scanned:    {len(other_domains)} domains")
        print(f"Currently scanned:     {len(self_domains)} domains")
        print(f"Newly blocked:         {len(newly_blocked)}")
        print(f"Newly accessible:      {len(newly_accessible)}")
        print("="*60)
        
        if newly_blocked:
            print(f"\nNewly Blocked Domains ({len(newly_blocked)}):")
            for domain in newly_blocked[:20]:
                print(f"  {domain}")
            if len(newly_blocked) > 20:
                print(f"  ... and {len(newly_blocked) - 20} more")
        
        if newly_accessible:
            print(f"\nNewly Accessible Domains ({len(newly_accessible)}):")
            for domain in newly_accessible[:20]:
                print(f"  {domain}")
            if len(newly_accessible) > 20:
                print(f"  ... and {len(newly_accessible) - 20} more")


def main():
    parser = argparse.ArgumentParser(
        description="Analyze Iranian domain checker results"
    )
    parser.add_argument(
        'input_file',
        default='iran_domains_accessible.jsonl',
        nargs='?',
        help='Input JSONL file (default: iran_domains_accessible.jsonl)'
    )
    parser.add_argument(
        '--format', '-f',
        choices=['summary', 'csv', 'json', 'accessible', 'blocked', 'domains'],
        default='summary',
        help='Output format'
    )
    parser.add_argument(
        '--output', '-o',
        help='Output file (for csv/json formats)'
    )
    parser.add_argument(
        '--accessible-only',
        action='store_true',
        help='Show only accessible domains'
    )
    parser.add_argument(
        '--blocked-only',
        action='store_true',
        help='Show only blocked domains'
    )
    parser.add_argument(
        '--find',
        help='Find details for a specific domain'
    )
    parser.add_argument(
        '--compare',
        help='Compare with previous results file'
    )
    
    args = parser.parse_args()
    
    analyzer = ResultsAnalyzer(args.input_file)
    
    # Handle comparisons
    if args.compare:
        analyzer.compare_with_previous(args.compare)
        return
    
    # Handle domain search
    if args.find:
        analyzer.find_domain(args.find)
        return
    
    # Handle exports
    if args.format == 'summary':
        analyzer.print_summary()
        if not args.blocked_only:
            analyzer.print_accessible_domains()
        if not args.accessible_only:
            analyzer.print_blocked_domains()
    
    elif args.format == 'csv':
        analyzer.export_csv(args.output)
    
    elif args.format == 'json':
        analyzer.export_json(args.output)
    
    elif args.format == 'accessible':
        analyzer.export_domains_only(accessible_only=True, output_file=args.output)
    
    elif args.format == 'blocked':
        analyzer.export_domains_only(accessible_only=False, output_file=args.output)
    
    elif args.format == 'domains':
        analyzer.export_domains_only(accessible_only=not args.blocked_only, output_file=args.output)


if __name__ == '__main__':
    try:
        main()
    except KeyboardInterrupt:
        print("\nInterrupted by user")
        sys.exit(0)
