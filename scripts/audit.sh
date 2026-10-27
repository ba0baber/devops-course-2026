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
echo '[4] Web server'
check 'Nginx service active' 'active' "$(systemctl is-active nginx 2>/dev/null || true)"
nginx_ok=no
if sudo nginx -t; then nginx_ok=yes; fi
check 'Nginx configuration valid' 'yes' "$nginx_ok"
cert_days=${AUDIT_CERT_MIN_DAYS:-30}
[[ "$cert_days" =~ ^[0-9]+$ ]] || { echo 'Invalid AUDIT_CERT_MIN_DAYS' >&2; exit 1; }
cert_ok=no
if openssl x509 -in /etc/ssl/certs/devops.crt -noout -checkend "$((cert_days * 86400))"; then cert_ok=yes; fi
check "Certificate valid for at least $cert_days days" 'yes' "$cert_ok"
permissions_ok=no
if writable=$(find /var/www/devops-site -perm -o+w -print) &&
   key_mode=$(sudo stat -c '%a:%U' /etc/ssl/private/devops.key) &&
   [[ -z "$writable" && "$key_mode" == '600:root' ]]; then
    permissions_ok=yes
fi
check 'No world-writable site paths; TLS key root:600' 'yes' "$permissions_ok"
echo '[5] Containerization'
check 'Docker service active' 'active' "$(systemctl is-active docker 2>/dev/null || true)"
check 'PostgreSQL container healthy' 'healthy' "$(sudo docker inspect -f '{{.State.Health.Status}}' app-db-1 2>/dev/null || true)"
listeners=$(ss -H -tln)
bad_ports=$(awk '$4 ~ /:(5000|5432)$/ && $4 !~ /^127\.0\.0\.1:(5000|5432)$/ {print $4}' <<< "$listeners")
ports_safe=no
if [[ -z "$bad_ports" ]] && awk '$4=="127.0.0.1:5000" {found=1} END {exit !found}' <<< "$listeners"; then ports_safe=yes; fi
check 'Application loopback only; no public database port' 'yes' "$ports_safe"
check 'Server .env permissions' '600' "$(stat -c '%a' /home/devops/app/.env 2>/dev/null || true)"
printf 'Passed: %s, failed: %s\n' "$PASS" "$FAIL"
[[ $FAIL -eq 0 ]]
