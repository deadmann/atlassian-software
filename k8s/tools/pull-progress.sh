#!/usr/bin/env bash
# pull-progress.sh - show image layer downloads in progress on this Kubernetes node (containerd)
#
# Usage (on the node):
#   sudo bash pull-progress.sh            # one snapshot, measures speed over 3s
#   sudo bash pull-progress.sh -w 10      # refresh every 10s until Ctrl+C
#   sudo bash pull-progress.sh -s 5       # measure speed over 5s instead of 3s

INGEST="${INGEST:-/var/lib/containerd/io.containerd.content.v1.content/ingest}"
NAMESPACE="${NAMESPACE:-k8s.io}"
SAMPLE=3
WATCH=0
STALL_AFTER=60   # seconds without new data before a download is flagged as stalled

while getopts "w:s:h" opt; do
  case $opt in
    w) WATCH=$OPTARG ;;
    s) SAMPLE=$OPTARG ;;
    *) sed -n '2,8p' "$0"; exit 0 ;;
  esac
done

if [ ! -r "$INGEST" ]; then
  echo "Cannot read $INGEST - run with sudo on a containerd node." >&2
  exit 1
fi

human() { # bytes -> MiB/GiB
  awk -v b="$1" 'BEGIN { if (b >= 1073741824) printf "%.2f GiB", b/1073741824; else printf "%.1f MiB", b/1048576 }'
}

duration() { # seconds -> 1h02m / 4m05s / 12s
  local s=$1
  if   [ "$s" -ge 3600 ]; then printf "%dh%02dm" $((s/3600)) $((s%3600/60))
  elif [ "$s" -ge 60 ];   then printf "%dm%02ds" $((s/60)) $((s%60))
  else printf "%ds" "$s"; fi
}

bar() { # percent -> [#########-----------]
  local filled=$(( $1 / 5 ))
  printf "[%s%s]" "$(printf '%*s' "$filled" '' | tr ' ' '#')" "$(printf '%*s' $((20 - filled)) '' | tr ' ' '-')"
}

snapshot() {
  # Map layer digest -> image name using the labels containerd puts on already-fetched manifests
  local content
  content=$(ctr -n "$NAMESPACE" content ls 2>/dev/null)

  declare -A before
  local d
  for d in "$INGEST"/*/; do
    [ -f "$d/total" ] && before[$d]=$(stat -c %s "$d/data" 2>/dev/null || echo 0)
  done

  if [ ${#before[@]} -eq 0 ]; then
    echo "$(date '+%F %T')  Nothing is downloading on this node right now."
    echo
    echo "  This means one of:"
    echo "    - all pulls FINISHED      -> pod shows Running / ContainerCreating briefly"
    echo "    - a pull FAILED, retrying -> pod shows ErrImagePull / ImagePullBackOff (retries within 5 min)"
    echo "    - no pull was started     -> image already on the node, or pod scheduled elsewhere"
    echo
    echo "  Check the pods (from Windows):  kubectl get pods -A | Select-String \"ContainerCreating|ImagePull|ErrImage\""
    return
  fi

  sleep "$SAMPLE"

  local now total_done=0 total_size=0
  now=$(date +%s)
  echo "$(date '+%F %T')  ${#before[@]} layer(s) downloading"
  echo
  printf "%-28s %-14s %-22s %-22s %6s %10s %8s  %s\n" "IMAGE" "LAYER" "PROGRESS" "" "%" "SPEED" "ETA" "STATUS"

  for d in "${!before[@]}"; do
    [ -f "$d/total" ] || continue   # finished during the sample
    local ref digest size total image pct speed eta idle status
    ref=$(cat "$d/ref")
    digest=${ref#*-}                 # k8s.io/1/layer-sha256:abc... -> sha256:abc...
    size=$(stat -c %s "$d/data")
    total=$(cat "$d/total")
    idle=$(( now - $(stat -c %Y "$d/data") ))

    image=$(grep -F "$digest" <<<"$content" | grep -o 'distribution\.source\.[^=]*=[^,[:space:]]*' | head -1 | cut -d= -f2)
    image=${image:-unknown}

    pct=$(( total > 0 ? size * 100 / total : 0 ))
    speed=$(( (size - before[$d]) / SAMPLE ))
    if [ "$speed" -gt 0 ]; then eta=$(duration $(( (total - size) / speed ))); else eta="-"; fi

    if   [ "$idle" -ge "$STALL_AFTER" ]; then status="STALLED $(duration "$idle")"
    elif [ "$speed" -gt 0 ];             then status="downloading"
    else status="waiting"; fi

    printf "%-28s %-14s %-22s %-22s %5d%% %8s/s %8s  %s\n" \
      "${image:0:28}" "${digest:7:12}" "$(human "$size") / $(human "$total")" "$(bar "$pct")" \
      "$pct" "$(human "$speed" | sed 's/ //')" "$eta" "$status"

    total_done=$(( total_done + size ))
    total_size=$(( total_size + total ))
  done

  echo
  echo "In-flight total: $(human $total_done) / $(human $total_size)"
}

if [ "$WATCH" -gt 0 ]; then
  while true; do
    clear
    snapshot
    echo
    echo "Refreshing every ${WATCH}s - Ctrl+C to stop"
    sleep "$WATCH"
  done
else
  snapshot
fi
