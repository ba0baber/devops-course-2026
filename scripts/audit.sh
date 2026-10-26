#!/usr/bin/env bash
set -uo pipefail
export LC_ALL=C
PASS=0; FAIL=0
check() {
  local desc="$1" expected="$2" actual="$3"
  if [[ "$actual" == "$expected" ]]; then
    printf ' [OK] %s\n' "$desc"; ((PASS+=1))
  else
    printf " [FAIL] %s (expected: '%s', actual: '%s')\n" "$desc" "$expected" "$actual"; ((FAIL+=1))
  fi
}
printf 'Configuration audit: %s, %s\n' "$(hostname -f)" "$(date '+%Y-%m-%d %H:%M')"
sudo -v || exit 1
sshd_config=$(sudo /usr/sbin/sshd -T) || exit 1
value() { awk -v key="$1" '$1==key {print $2}' <<< "$sshd_config"; }
echo '[1] SSH service'
check 'Root login disabled' 'no' "$(value permitrootlogin)"
check 'Password authentication disabled' 'no' "$(value passwordauthentication)"
ports=$(value port)
port_check=no
if [[ -n "$ports" ]] && ! grep -qx 22 <<< "$ports"; then port_check=yes; fi
check 'SSH uses a non-default port' 'yes' "$port_check"
check 'Maximum authentication attempts' '3' "$(value maxauthtries)"
echo '[2] Firewall'
ufw_status=$(sudo ufw status verbose) || exit 1
check 'Firewall active' 'active' "$(awk '/^Status:/{print $2}' <<< "$ufw_status")"
check 'Default incoming policy' 'deny' "$(sed -n 's/^Default: \([^ ]*\) (incoming).*/\1/p' <<< "$ufw_status")"
echo '[3] User accounts'
awk -F: '$3>=1000 && $3<65534 {printf " %s (uid=%s)\n",$1,$3}' /etc/passwd
printf 'Passed: %s, failed: %s\n' "$PASS" "$FAIL"
[[ $FAIL -eq 0 ]]
