#!/bin/bash
# Put this machine on the laser's subnet - the Linux equivalent of IPSet.exe.
#   sudo ./laser-network.sh            -> 10.1.1.100/24
#   sudo ./laser-network.sh 10.1.1.123 -> custom address
#   sudo ./laser-network.sh --revert   -> back to DHCP
CON="${CON:-Wired connection 1}"
ADDR="${1:-10.1.1.100}"

[ "$(id -u)" = 0 ] || { echo "needs sudo"; exit 1; }

if [ "$1" = "--revert" ]; then
  nmcli con mod "$CON" ipv4.method auto ipv4.addresses "" ipv4.never-default no
  nmcli con up "$CON"; echo "reverted to DHCP"; exit 0
fi

# never-default: the laser subnet is isolated and must NEVER become the
# default route, or it takes out your internet. Gateway deliberately unset.
nmcli con mod "$CON" ipv4.method manual ipv4.addresses "$ADDR/24" ipv4.never-default yes
nmcli con up "$CON"
echo "set $CON to $ADDR/24"
echo
for ip in 10.1.1.168 10.1.1.169 10.1.1.170; do
  printf '%-14s ' "$ip"
  ping -c1 -W1 "$ip" >/dev/null 2>&1 && echo "reachable" || echo "no reply"
done
