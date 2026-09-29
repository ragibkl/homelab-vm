#!/bin/bash
# Rebuild one DigitalOcean Bancuh DNS node onto the base image and set it up,
# keeping its IPv4 (including the reserved IP) and IPv6 addresses.
# Run from a machine with doctl (authenticated), python3 and SSH access.
#
#   SSH_KEY=~/.ssh/id_ed25519 ./rebuild-node.sh <node> <droplet-id> <base-snapshot-id> <partner>
#   ./rebuild-node.sh sg-dns1 71746677 247551413 sg-dns2
#
# Steps, stopping at the first problem:
#   1. check the partner node answers DNS (it carries the region meanwhile)
#   2. back up the node's .env and letsencrypt volume, and check them
#   3. start probing <node>:53 from here, once a second
#   4. rebuild the droplet from the base snapshot
#   5. copy the backup and setup-node.sh over, run it
#   6. wait for filtered answers from outside, print the timeline
set -u
N=$1; ID=$2; IMG=$3; PARTNER=$4
H=$N.bancuh.com
HERE=$(cd "$(dirname "$0")" && pwd)
KEY=${SSH_KEY:-$HOME/.ssh/id_ed25519}
O="-o BatchMode=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new -i $KEY -o IdentitiesOnly=yes"
B=$(mktemp -d); LOG=$B/probe.log
trap 'rm -rf "$B"' EXIT # the backup holds the certificate's private key
die() { echo "!! $*"; [ -n "${PROBE:-}" ] && kill $PROBE 2>/dev/null; exit 1; }

# query <host> <name>: prints "blocked", "answer" or "down" (UDP 53).
query() {
  python3 - "$1" "$2" <<'PY'
import random, socket, struct, sys
host, name = sys.argv[1], sys.argv[2]
i = random.randint(0, 0xFFFF)
q = struct.pack(">HHHHHH", i, 0x0100, 1, 0, 0, 0) + b"".join(bytes([len(p)]) + p.encode() for p in name.split(".")) + b"\0" + struct.pack(">HH", 1, 1)
try:
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as s:
        s.settimeout(2); s.sendto(q, (socket.gethostbyname(host), 53)); r = s.recv(512)
    print("blocked" if r[-4:] == b"\0\0\0\0" else "answer")
except OSError:
    print("down")
PY
}

echo "== 1. partner"
[ "$(query $PARTNER.bancuh.com example.com)" = answer ] || die "$PARTNER is not answering; not touching $N"
echo "$PARTNER answers"

echo "== 2. backup"
ssh $O root@$H 'cat /root/adblock-dns-server/EXAMPLES/default/.env' > $B/env || die "no .env"
ssh $O root@$H 'docker run --rm -v default_letsencrypt:/d:ro busybox tar c -C /d .' | gzip > $B/letsencrypt.tgz
chmod 600 $B/env $B/letsencrypt.tgz
grep -q "^TLS_DOMAIN=$H$" $B/env || die ".env backup has no TLS_DOMAIN=$H"
[ "$(tar tzf $B/letsencrypt.tgz | wc -l)" -gt 3 ] || die "letsencrypt backup looks empty"
echo "ok: .env and $(tar tzf $B/letsencrypt.tgz | wc -l) volume entries"

echo "== 3. probe $H:53 from here"
( while :; do echo "$(date +%s) $(query $H zedo.com)"; sleep 1; done ) > $LOG 2>/dev/null &
PROBE=$!

T0=$(date +%s)
echo "== 4. rebuild $N ($ID) from snapshot $IMG at $(date -u +%T) UTC"
doctl compute droplet-action rebuild $ID --image $IMG --wait --format Status --no-header || die "rebuild failed"
echo "rebuilt +$(( $(date +%s)-T0 ))s"
ssh-keygen -R $H >/dev/null 2>&1
for i in $(seq 1 60); do ssh $O root@$H true 2>/dev/null && break; sleep 3; done
ssh $O root@$H true 2>/dev/null || die "no SSH after rebuild; use the DigitalOcean web console"
echo "ssh up +$(( $(date +%s)-T0 ))s"

echo "== 5. setup"
ssh $O root@$H 'install -d -m 700 /root/restore'
scp -q $O $B/env $B/letsencrypt.tgz "$HERE/setup-node.sh" root@$H:/root/restore/
ssh $O root@$H "sh /root/restore/setup-node.sh $N /root/restore && rm -rf /root/restore" || die "setup failed; fix and re-run setup-node.sh on the node"
echo "setup done +$(( $(date +%s)-T0 ))s"

echo "== 6. wait for filtered DNS from outside"
for i in $(seq 1 120); do tail -1 $LOG | grep -q ' blocked$' && break; sleep 3; done
kill $PROBE 2>/dev/null
echo "filtered +$(( $(date +%s)-T0 ))s. Timeline of $H:53 seen from here:"
awk '{ if ($2 != s) { if (s) printf "  %-8s %4ds\n", s, $1 - t; s = $2; t = $1 } } END { printf "  %-8s (now)\n", s }' $LOG
echo "Next: check DoT/DoH and IPv6 from outside, and Gatus."
