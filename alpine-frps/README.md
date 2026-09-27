# alpine-frps

The public entry point: a VPS at Linode/Akamai (`vmbr1.ingress.ragib.dev`,
`172.237.74.181` / `2600:3c15::2000:b5ff:fea4:8fb8`, hostname
`vmbr0-alpine-frps-vmbr1`). frpc in the vmbr1-k3s cluster (flux-deploy,
`infrastructure/frp/`) dials in on port 7000 and frps publishes its proxies
here.

- **80/443**: haproxy (TCP mode) forwards to frps on `127.0.0.1:8080` and
  `:8443` with the PROXY protocol, which ingress-nginx expects.
- **53/udp, 53/tcp**: frps serves these itself (haproxy doesn't do UDP),
  forwarding to acme-dns in the cluster. acme-dns is authoritative for
  `acme.ragib.dev` (delegated in ClouDNS to `vmbr1.ingress.ragib.dev`) and
  answers the DNS-01 challenges for wildcard certs.

frps listens on both IPv4 and IPv6 by default (`:::53`, `:::8080`, ...).

## Firewall

The VPS runs no host firewall (iptables `INPUT` policy `ACCEPT`). Filtering is
done by the cloud firewall in front of it, configured in the Linode/Akamai
console and not in this repo. It must allow inbound:

| Port | Proto | For |
|------|-------|-----|
| 22 | tcp | SSH |
| 80 | tcp | haproxy → ingress-nginx (HTTP, HTTP-01 challenges) |
| 443 | tcp | haproxy → ingress-nginx (HTTPS) |
| 7000 | tcp | frpc → frps control connection |
| 53 | udp | acme-dns (DNS-01 challenges) |
| 53 | tcp | acme-dns (DNS-01 challenges, truncated responses) |

8080 and 8443 must stay closed: they are frps's side of the haproxy hop.

If 53 is closed, wildcard cert issuance and renewals (DNS-01) fail. To check
from outside the VPS:

```shell
dig +short @172.237.74.181 acme.ragib.dev NS         # udp
dig +short +tcp @172.237.74.181 acme.ragib.dev NS    # tcp
# expect: vmbr1.ingress.ragib.dev.
```

## Setup

```shell
cp example.env .env   # AUTH_TOKEN from ./gen-token.sh, same as frpc's
docker compose up -d
```
