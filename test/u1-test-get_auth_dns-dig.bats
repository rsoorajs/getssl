#! /usr/bin/env bats

load '/bats-support/load.bash'
load '/bats-assert/load.bash'
load '/getssl/test/test_helper.bash'


# This is run for every test
setup() {
    [ ! -f $BATS_RUN_TMPDIR/failed.skip ] || skip "skipping tests after first failure"
    for app in drill host nslookup
    do
        if [ -f /usr/bin/${app} ]; then
            mv /usr/bin/${app} /usr/bin/${app}.getssl.bak
        fi
    done

    . /getssl/getssl --source
    find_dns_utils
    _USE_DEBUG=1
}


teardown() {
    [ -n "$BATS_TEST_COMPLETED" ] || touch $BATS_RUN_TMPDIR/failed.skip
    for app in drill host nslookup
    do
        if [ -f /usr/bin/${app}.getssl.bak ]; then
            mv /usr/bin/${app}.getssl.bak /usr/bin/${app}
        fi
    done
}


@test "Check get_auth_dns using dig NS" {
    # Test that get_auth_dns() handles scenario where NS query returns Authority section
    #
    # ************** EXAMPLE DIG OUTPUT **************
    #
    # ;; ANSWER SECTION:
    # ubuntu-getssl.duckdns.org. 60   IN      A       54.89.252.137
    #
    # ;; AUTHORITY SECTION:
    # duckdns.org.            600     IN      NS      ns2.duckdns.org.
    # duckdns.org.            600     IN      NS      ns3.duckdns.org.
    # duckdns.org.            600     IN      NS      ns1.duckdns.org.
    #
    # ;; ADDITIONAL SECTION:
    # ns2.duckdns.org.        600     IN      A       54.191.117.119
    # ns3.duckdns.org.        600     IN      A       52.26.169.94
    # ns1.duckdns.org.        600     IN      A       54.187.92.222

    # Disable CNAME check
    _TEST_SKIP_CNAME_CALL=1

    PUBLIC_DNS_SERVER=ns1.afraid.org
    CHECK_PUBLIC_DNS_SERVER=false
    CHECK_ALL_AUTH_DNS=false

    run get_auth_dns ubuntu-getssl.ignorelist.com

    # Assert that we've found the primary_ns server
    assert_output --regexp 'set primary_ns = ns[1-3]+\.afraid\.org'
    # Assert that we had to use dig NS
    assert_line --regexp 'Using dig.* NS'

    # Check all Authoritative DNS servers are returned if requested
    CHECK_ALL_AUTH_DNS=true
    run get_auth_dns ubuntu-getssl.ignorelist.com
    assert_output --regexp 'set primary_ns = (ns[1-3]+\.afraid\.org ?)+'
}


@test "Check get_auth_dns using dig SOA" {
    # Test that get_auth_dns() handles scenario where SOA query returns Authority section
    #
    # ************** EXAMPLE DIG OUTPUT **************
    #
    # ;; AUTHORITY SECTION:
    # duckdns.org.            600     IN      SOA     ns3.duckdns.org. hostmaster.duckdns.org. 2019170803 6000 120 2419200 600

    # DuckDNS server returns nothing for SOA, so use public dns instead
    PUBLIC_DNS_SERVER=1.0.0.1
    CHECK_PUBLIC_DNS_SERVER=false
    CHECK_ALL_AUTH_DNS=false

    run get_auth_dns ubuntu-getssl.duckdns.org

    # Assert that we've found the primary_ns server
    assert_output --regexp 'set primary_ns = ns[1-9]+\.duckdns\.org'

    # Assert that we had to use dig NS
    assert_line --regexp 'Using dig.* SOA'
    refute_line --regexp 'Using dig.* NS'

    # Check all Authoritative DNS servers are returned if requested
    CHECK_ALL_AUTH_DNS=true
    run get_auth_dns ubuntu-getssl.duckdns.org
    assert_output --regexp 'set primary_ns = (ns[1-9]+\.duckdns\.org )+'

    # Check that we also check the public DNS server if requested
    CHECK_PUBLIC_DNS_SERVER=true
    run get_auth_dns ubuntu-getssl.duckdns.org
    assert_output --regexp 'set primary_ns = (ns[1-9]+\.duckdns\.org )+1\.0\.0\.1'
}


@test "Check get_auth_dns using dig CNAME (public dns)" {
    # Test that get_auth_dns() handles scenario where CNAME query returns just a CNAME record
    #
    # ************** EXAMPLE DIG OUTPUT **************
    #
    # ;; ANSWER SECTION:
    # www.duckdns.org.        600     IN      CNAME   DuckDNSAppELB-570522007.us-west-2.elb.amazonaws.com.

    # Disable SOA check
    _TEST_SKIP_SOA_CALL=1

    PUBLIC_DNS_SERVER=1.0.0.1
    CHECK_PUBLIC_DNS_SERVER=false
    CHECK_ALL_AUTH_DNS=false

    run get_auth_dns www.duckdns.org

    # Assert that we've found the primary_ns server
    assert_output --regexp 'set primary_ns = ns.*\.awsdns.*\.net'

    # Assert that we found a CNAME and use dig NS
    assert_line --regexp 'Using dig.* CNAME'
    assert_line --regexp 'Using dig.* NS'

    # Check all Authoritative DNS servers are returned if requested
    CHECK_ALL_AUTH_DNS=true
    run get_auth_dns www.duckdns.org
    assert_output --regexp 'set primary_ns = ns.*\.awsdns.*\.net'

    # Check that we also check the public DNS server if requested
    CHECK_PUBLIC_DNS_SERVER=true
    run get_auth_dns www.duckdns.org
    assert_output --regexp 'set primary_ns = ns.*\.awsdns.*\.net 1\.0\.0\.1'
}
