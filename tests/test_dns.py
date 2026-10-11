import socket

import pytest
from uranus_dns import verify_dns

V4, V6 = '94.130.236.38', '2a01:4f8:13b:34c7::2'


def resolver(a, aaaa):
    def resolve(domain, port, *, family, type, flags):
        assert flags == 0 and type == socket.SOCK_STREAM
        addresses = a if family == socket.AF_INET else aaaa
        if not addresses:
            raise socket.gaierror(socket.EAI_NONAME, 'No records for this family')
        return [(family, type, 6, '', (address, port)) for address in addresses]
    return resolve


def test_ipv4_only_dns_accepts_absent_aaaa():
    assert verify_dns('app.example.com', V4, [], resolver([V4], [])) == {'A': [V4], 'AAAA': []}


def test_dual_stack_records_are_verified_separately_and_normalized():
    assert verify_dns('app.example.com', V4, [V6], resolver([V4, V4], ['2a01:04f8:013b:34c7:0:0:0:2'])) == {'A': [V4], 'AAAA': [V6]}


@pytest.mark.parametrize('a,aaaa,expected6', [([], [V6], [V6]), ([V4, '1.1.1.1'], [], []),
    ([V4], ['2606:4700:4700::1111'], [V6]), ([V4], [V6], []), ([V4], [], [V6])])
def test_missing_or_foreign_addresses_fail_closed(a, aaaa, expected6):
    with pytest.raises(ValueError, match='differ from expected'):
        verify_dns('app.example.com', V4, expected6, resolver(a, aaaa))


def test_temporary_resolver_error_is_not_treated_as_no_aaaa():
    def resolve(*args, **kwargs):
        if kwargs['family'] == socket.AF_INET6:
            raise socket.gaierror(socket.EAI_AGAIN, 'Temporary failure')
        return resolver([V4], [])(*args, **kwargs)
    with pytest.raises(ValueError, match='resolution failed'):
        verify_dns('app.example.com', V4, [], resolve)


def test_advertised_ipv6_must_be_assigned_and_uses_normalized_comparison():
    with pytest.raises(ValueError, match='assigned'):
        verify_dns('app.example.com', V4, [V6], resolver([V4], [V6]), assigned_ipv6=[])
    assert verify_dns('app.example.com', V4, [V6], resolver([V4], [V6]),
                      assigned_ipv6=['2a01:04f8:013b:34c7:0:0:0:2'])['AAAA'] == [V6]
