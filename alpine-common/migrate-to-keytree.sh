#!/bin/sh
# Move a running VM from github-keys.sh (AuthorizedKeysCommand) to keytree,
# without risking a lockout. Run it from a machine that can already SSH in as
# root, not on the VM itself.
#
#   ./migrate-to-keytree.sh 10.15.1.21
#   ./migrate-to-keytree.sh 10.15.2.11 -J 10.15.1.1,10.15.0.196
#   ./migrate-to-keytree.sh root@vmbr1.ingress.ragib.dev -i ~/.ssh/id_ed25519
#
# Steps, stopping at the first problem:
#   1. install keytree (the old command stays active, so access can't shrink)
#   2. check keytree's block in root's authorized_keys is not empty
#   3. open a spare SSH connection, kept open in the background
#   4. remove the AuthorizedKeysCommand lines (sshd_config and 00_common.conf),
#      keeping backups, check with sshd -t, reload sshd
#   5. log in again without the spare connection; this can only work through
#      the file keytree wrote. If it fails, put the old config back over the
#      spare connection and reload.
#   6. delete github-keys.sh, its cache and the backups
set -u
[ $# -ge 1 ] || { sed -n '2,8p' "$0"; exit 2; }
H=$1; shift
O="-o BatchMode=yes -o ConnectTimeout=10 $*"
S=/tmp/ktm-$$ # control socket; keep the path short
URL=https://raw.githubusercontent.com/ragibkl/server-keys/main/keytree.yaml
FILES="/etc/ssh/sshd_config /etc/ssh/sshd_config.d/00_common.conf"

fail() { echo "!! $*"; ssh -o ControlPath=$S -O exit $H 2>/dev/null; exit 1; }
reload='if command -v rc-service >/dev/null; then rc-service sshd reload; else systemctl reload ssh; fi'

echo "== $H: install keytree"
ssh $O $H "command -v keytree >/dev/null && echo 'already installed' ||
  wget -qO- https://ragibkl.github.io/keytree/install | sh -s $URL" || fail "install failed"

n=$(ssh $O $H "sed -n '/^# BEGIN keytree/,/^# END keytree/p' /root/.ssh/authorized_keys 2>/dev/null | grep -c keytree:")
[ "${n:-0}" -gt 0 ] || fail "keytree's block is empty; not touching sshd (does the hostname match server-keys?)"
echo "== keytree wrote $n keys for root"

ssh $O -o ControlMaster=yes -o ControlPath=$S -o ControlPersist=10m -fN $H &&
  ssh -o ControlPath=$S -O check $H 2>/dev/null || fail "spare connection did not open"

echo "== remove AuthorizedKeysCommand, check, reload"
ssh -o ControlPath=$S $H "
set -e
for f in $FILES; do
  [ -f \$f ] && grep -q '^AuthorizedKeysCommand ' \$f || continue
  cp \$f /root/\$(basename \$f).keytree-bak
  sed -i '/^# Fetch keys from GitHub\$/d; /^AuthorizedKeysCommand /d; /^AuthorizedKeysCommandUser /d' \$f
  echo \"edited \$f\"
done
if ! sshd -t; then
  for f in $FILES; do b=/root/\$(basename \$f).keytree-bak; [ -f \$b ] && cp \$b \$f; done
  echo 'sshd -t failed; restored'; exit 1
fi
$reload" || fail "sshd change failed"

echo "== fresh login"
if ssh $O -o ControlMaster=no -o ControlPath=none $H 'sshd -T 2>/dev/null | grep -i "^authorizedkeyscommand "' | grep -q none; then
  echo "fresh login ok; sshd uses no key command"
else
  echo "!! fresh login failed: restoring the old sshd config over the spare connection"
  ssh -o ControlPath=$S $H "for f in $FILES; do b=/root/\$(basename \$f).keytree-bak; [ -f \$b ] && cp \$b \$f; done; $reload"
  fail "restored; investigate before retrying"
fi

echo "== clean up"
ssh -o ControlPath=$S $H 'rm -fv /usr/local/bin/github-keys.sh /tmp/github-keys-*.txt /root/*.keytree-bak; keytree sync && echo "sync ok"'
ssh -o ControlPath=$S -O exit $H 2>/dev/null
echo "== $H done"
