#!/usr/bin/env bash
# Whack-a-Port: kill whatever is listening on a TCP port.
# Usage: ./whack.sh [port]   (prompts for the port if omitted)

set -u

GRACE_SECONDS=3

alive() { ps -p "$1" >/dev/null 2>&1; }

describe() { ps -p "$1" -o pid=,user=,command= 2>/dev/null; }

port="${1:-}"
if [ -z "$port" ]; then
  read -r -p "Port to whack: " port
fi

case "$port" in
  ''|*[!0-9]*) echo "Not a valid port: '$port'" >&2; exit 2 ;;
esac
if [ "$port" -lt 1 ] || [ "$port" -gt 65535 ]; then
  echo "Port out of range (1-65535): $port" >&2
  exit 2
fi

pids=$(lsof -nP -iTCP:"$port" -sTCP:LISTEN -t 2>/dev/null | sort -u)
if [ -z "$pids" ]; then
  echo "Nothing is listening on port $port."
  echo "(If you expected something, it may belong to another user — try: sudo $0 $port)"
  exit 0
fi

echo "Listening on port $port:"
for pid in $pids; do
  echo "  $(describe "$pid")"
done

echo "Sending SIGTERM..."
for pid in $pids; do
  err=$(kill -TERM "$pid" 2>&1) || echo "  kill $pid failed: $err" >&2
done

# Give the processes a moment to exit on their own.
ticks=$((GRACE_SECONDS * 10))
while [ "$ticks" -gt 0 ]; do
  remaining=""
  for pid in $pids; do
    alive "$pid" && remaining="$remaining $pid"
  done
  [ -z "$remaining" ] && break
  sleep 0.1
  ticks=$((ticks - 1))
done

if [ -z "$remaining" ]; then
  echo "Whacked. Port $port is free."
  exit 0
fi

printf '\a'
echo
echo "!! TERMINATION FAILED — still running after ${GRACE_SECONDS}s:"
for pid in $remaining; do
  echo "  $(describe "$pid")"
done

read -r -p "Force kill with SIGKILL (kill -9)? [y/N] " answer
case "$answer" in
  y|Y|yes|YES) ;;
  *) echo "Left running. Port $port is still in use."; exit 1 ;;
esac

for pid in $remaining; do
  err=$(kill -9 "$pid" 2>&1) || echo "  kill -9 $pid failed: $err" >&2
done
sleep 0.3

survivors=""
for pid in $remaining; do
  alive "$pid" && survivors="$survivors $pid"
done

if [ -n "$survivors" ]; then
  printf '\a'
  echo "!! kill -9 failed for:$survivors"
  echo "   Probably owned by another user — try: sudo $0 $port"
  exit 1
fi

echo "Whacked (forcefully). Port $port is free."
