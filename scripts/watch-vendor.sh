#!/bin/bash
# Focused logger: ONLY traffic to the laser vendor's monitoring server.
# Default target is the Alibaba Cloud IP from ipAdd.ini. Add more with WATCH=...
#
#   sudo ~/netlog/watch-vendor.sh start
#   ~/netlog/watch-vendor.sh report
#   sudo ~/netlog/watch-vendor.sh stop

BASE=/home/karstein/netlog
PCAP="$BASE/vendor"
LOG="$BASE/vendor.log"
PIDFILE="$BASE/.vendor-pids"
WATCH="${WATCH:-47.104.17.21}"

build_filter() {
  local f="" ip
  for ip in $WATCH; do [ -n "$f" ] && f="$f or "; f="${f}host $ip"; done
  echo "$f"
}

start() {
  [ "$(id -u)" = 0 ] || { echo "needs sudo"; exit 1; }
  mkdir -p "$PCAP"
  local FILTER; FILTER=$(build_filter)
  echo "watching: $WATCH"

  tcpdump -i any -n -s 0 -U -Z karstein -W 24 -G 3600 \
          -w "$PCAP/vendor-%Y%m%d-%H%M%S.pcap" "$FILTER" >/dev/null 2>&1 &
  echo $! > "$PIDFILE"

  # attribution, watched IPs only
  (
    declare -A seen
    while :; do
      while read -r proto local remote proc; do
        for ip in $WATCH; do
          case "$remote" in
            "$ip":*)
              key="$remote|$proc"
              [ -z "${seen[$key]}" ] && {
                seen[$key]=1
                printf '%s  %-22s %s\n' "$(date '+%F %T')" "$remote" "$proc" >> "$LOG"
              } ;;
          esac
        done
      done < <(ss -tunpH state established 2>/dev/null \
                | awk '{proc=($6==""?"-":$6); print $1, $4, $5, proc}' \
                | sed -E 's/users:\(\("?//; s/"?,fd=[0-9]+\)\)$//; s/"//g')
      sleep 2
    done
  ) >/dev/null 2>&1 &
  echo $! >> "$PIDFILE"
  chown karstein "$LOG" 2>/dev/null
  echo "started. pcap -> $PCAP/   log -> $LOG"
}

stop() {
  [ -f "$PIDFILE" ] || { echo "not running"; exit 0; }
  while read -r p; do kill "$p" 2>/dev/null; done < "$PIDFILE"
  rm -f "$PIDFILE"; echo "stopped"
}

report() {
  echo "=== connections to vendor server ==="
  [ -s "$LOG" ] && cat "$LOG" || echo "(none seen yet)"
  echo
  echo "=== traffic volume ==="
  local files; files=$(ls -1 "$PCAP"/*.pcap 2>/dev/null)
  [ -z "$files" ] && { echo "(no captures)"; return; }
  for f in $files; do
    n=$(tcpdump -nr "$f" 2>/dev/null | wc -l)
    printf '%-45s %s packets\n' "$(basename "$f")" "$n"
  done
  echo
  echo "=== encrypted or plaintext? ==="
  # TLS records start 0x16 0x03; anything else with readable ASCII is cleartext
  for f in $files; do
    tcpdump -nr "$f" -x -c 40 2>/dev/null | grep -qE '0x0000:.*1603' \
      && { echo "$(basename "$f"): TLS handshake seen -> ENCRYPTED"; continue; }
    tcpdump -nr "$f" -A -c 40 2>/dev/null | grep -qE '[[:print:]]{12,}' \
      && echo "$(basename "$f"): printable payload -> likely PLAINTEXT" \
      || echo "$(basename "$f"): no verdict yet (too few packets)"
  done
}

case "$1" in
  start) start ;; stop) stop ;; report) report ;;
  *) echo "usage: $0 {start|stop|report}   (WATCH='ip1 ip2' to add targets)"; exit 1 ;;
esac
