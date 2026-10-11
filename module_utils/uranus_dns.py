"""Validate A and AAAA independently without conflating address families."""
import ipaddress
import socket


def verify_dns(domain, ipv4, ipv6, resolver=socket.getaddrinfo, assigned_ipv6=None):
    expected4 = {str(ipaddress.IPv4Address(ipv4))}
    expected6 = {str(ipaddress.IPv6Address(address)) for address in ipv6}
    if any(not ipaddress.ip_address(address).is_global for address in expected4 | expected6):
        raise ValueError('Public ingress addresses must be globally routable')
    if assigned_ipv6 is not None and not expected6.issubset({str(ipaddress.IPv6Address(a)) for a in assigned_ipv6}):
        raise ValueError('Every advertised AAAA address must be assigned to this ingress host')
    result = {}
    for family, name, expected in ((socket.AF_INET, 'A', expected4), (socket.AF_INET6, 'AAAA', expected6)):
        try:
            records = resolver(domain, 443, family=family, type=socket.SOCK_STREAM, flags=0)
            actual = {str(ipaddress.ip_address(record[4][0])) for record in records}
        except socket.gaierror as exc:
            if exc.errno not in (socket.EAI_NONAME, getattr(socket, 'EAI_NODATA', socket.EAI_NONAME)):
                raise ValueError(f'{name} resolution failed for {domain}: {exc}') from exc
            actual = set()
        if actual != expected:
            raise ValueError(f'{domain}: {name} records {sorted(actual)} differ from expected {sorted(expected)}')
        result[name] = sorted(actual)
    return result
