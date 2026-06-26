#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# speedtest.sh — amrita.town webring performance audit
#
# Reads the member websites from src/members.json and runs a multi-target
# performance/HTTP/TLS audit across all of them, then prints a comparison
# summary highlighting the best value per metric.
#
# Usage:
#   ./scripts/speedtest.sh                    # audit every member
#   ./scripts/speedtest.sh --quick           # fast pass (RUNS=2, no hops)
#   ./scripts/speedtest.sh --runs 10         # custom sample count
#   ./scripts/speedtest.sh nithitsuki.com     # audit only the given hosts
#   ./scripts/speedtest.sh --only nikhil     # filter members by name/website
#   ./scripts/speedtest.sh --no-traceroute --no-ping --no-geo
#   ./scripts/speedtest.sh --json out.json   # also write metrics as JSON
#
# Requires: curl, awk, dig, (optional: ping, traceroute, openssl, jq)
# ─────────────────────────────────────────────────────────────────────────────

set -u

RUNS=5
DO_TRACEROUTE=1
DO_PING=1
DO_GEO=1
JSON_OUT=""
ONLY_FILTER=""
MEMBERS_FILE=""

usage() {
	sed -n '3,18p' "$0" | sed 's/^# \{0,1\}//'
	exit "${1:-0}"
}

# ── Flag parsing ──────────────────────────────────────────────────────────────
POSITIONAL=()
while [[ $# -gt 0 ]]; do
	case "$1" in
		-h|--help)    usage 0 ;;
		--runs)       RUNS="$2"; shift 2 ;;
		--quick)      RUNS=2; DO_TRACEROUTE=0; DO_PING=0; shift ;;
		--no-traceroute) DO_TRACEROUTE=0; shift ;;
		--no-ping)    DO_PING=0; shift ;;
		--no-geo)     DO_GEO=0; shift ;;
		--only)       ONLY_FILTER="$2"; shift 2 ;;
		--json)       JSON_OUT="$2"; shift 2 ;;
		--members)    MEMBERS_FILE="$2"; shift 2 ;;
		--)          shift; break ;;
		-*)           echo "Unknown flag: $1" >&2; usage 1 ;;
		*)            POSITIONAL+=("$1"); shift ;;
	esac
done
# reset positional params (avoid the "${arr[@]:-}" trap which yields one
# empty arg under set -u when the array is empty)
if (( ${#POSITIONAL[@]} )); then
	set -- "${POSITIONAL[@]}"
else
	set --
fi

# ── Locate members.json ───────────────────────────────────────────────────────
if [[ -z "$MEMBERS_FILE" ]]; then
	SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
	if [[ -f "$SCRIPT_DIR/../src/members.json" ]]; then
		MEMBERS_FILE="$SCRIPT_DIR/../src/members.json"
	elif [[ -f "src/members.json" ]]; then
		MEMBERS_FILE="src/members.json"
	else
		echo "Could not find src/members.json (pass --members <path>)." >&2
		exit 1
	fi
fi

# ── Colours ──────────────────────────────────────────────────────────────────
BOLD=$'\e[1m'; CYAN=$'\e[36m'; GREEN=$'\e[32m'; YELLOW=$'\e[33m'
RED=$'\e[31m'; MAGENTA=$'\e[35m'; DIM=$'\e[2m'; RESET=$'\e[0m'

sep()  { printf "${DIM}%.0s─${RESET}" $(seq 1 1 76); echo; }
hdr()  { echo; sep; printf "${BOLD}${CYAN}  ▶  %s${RESET}\n" "$1"; sep; }
ok()   { printf "  ${GREEN}✔${RESET}  %-36s %s\n"   "$1" "$2"; }
warn() { printf "  ${YELLOW}⚠${RESET}  %-36s %s\n"  "$1" "$2"; }
fail() { printf "  ${RED}✘${RESET}  %-36s %s\n"     "$1" "$2"; }
info() { printf "  ${DIM}→${RESET}  %-36s %s\n"    "$1" "$2"; }
have() { command -v "$1" &>/dev/null; }

col_ms() {
	local v=$1
	if   (( v <  50 ));  then printf "${GREEN}%4d ms${RESET}"  "$v"
	elif (( v < 150 ));  then printf "${YELLOW}%4d ms${RESET}" "$v"
	else                      printf "${RED}%4d ms${RESET}"    "$v"
	fi
}

# float seconds → integer milliseconds (awk, no bc dep)
to_ms() { awk "BEGIN{printf \"%d\", ($1)*1000}"; }
# delta in ms between two float-second values, floored at 0
delta_ms() { awk "BEGIN{d=($1)-($2); if(d<0)d=0; printf \"%d\", d*1000}"; }
avg() { local s=0 n=0 x; for x in "$@"; do s=$((s+x)); n=$((n+1)); done; ((n)) && echo $((s/n)) || echo 0; }

# strip scheme/path/port/userinfo → bare lowercase hostname
norm_host() {
	local u=$1
	u="${u#https://}"; u="${u#http://}"
	u="${u%%/*}"; u="${u%%:*}"; u="${u%%@*}"
	echo "${u,,}"
}

# ── Target collection ────────────────────────────────────────────────────────
collect_targets() {
	if [[ $# -gt 0 ]]; then
		# ad-hoc hosts supplied on the CLI
		local h
		for h in "$@"; do
			h=$(norm_host "$h")
			[[ -n "$h" ]] && echo "$h"
		done
		return
	fi

	# read websites from members.json (skip the amrita.town entry at index 0)
	if have jq; then
		jq -r '.[1:][] | .website' "$MEMBERS_FILE" 2>/dev/null
	elif have python3; then
		python3 - "$MEMBERS_FILE" <<'PY' 2>/dev/null
import json, sys
with open(sys.argv[1]) as f:
    data = json.load(f)
for m in data[1:]:
    print(m.get("website", ""))
PY
	else
		# last-resort regex scrape
		grep -oE '"website"[[:space:]]*:[[:space:]]*"[^"]+"' "$MEMBERS_FILE" \
			| sed -E 's/.*"website"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/'
	fi
}

# apply --only filter (substring match on host)
filter_targets() {
	local t
	if [[ -z "$ONLY_FILTER" ]]; then
		while read -r t; do [[ -n "$t" ]] && echo "$t"; done
	else
		while read -r t; do
			[[ -n "$t" && "$t" == *"$ONLY_FILTER"* ]] && echo "$t"
		done
	fi
}

# ── Global comparison arrays ─────────────────────────────────────────────────
COMP_TARGETS=()
declare -a COMP_DNS COMP_TCP COMP_TLS COMP_TTFB COMP_TOT
declare -a COMP_SIZE COMP_SPEED_KB COMP_HTTP_VER COMP_HTTP_CODE COMP_REDIRECTS
declare -a COMP_SCRIPTS COMP_BLOCKING COMP_STYLES COMP_IMAGES COMP_PRELOADS COMP_EXT
declare -a COMP_TLS_VER COMP_COMPRESSION COMP_HSTS COMP_CSP
# JSON output registry (per-target dict)
declare -A JSON_ROWS=()

json_escape() { awk 'BEGIN{RS=""} {gsub(/\\/,"\\\\"); gsub(/"/,"\\\""); printf "%s",$0}' <<< "$1"; }

# ─────────────────────────────────────────────────────────────────────────────
#  audit_target
# ─────────────────────────────────────────────────────────────────────────────
audit_target() {
	local TARGET=$1

	local HTTPS_CODE URL SCHEME
	HTTPS_CODE=$(curl -s -o /dev/null --max-time 10 -w "%{http_code}" \
	             "https://${TARGET}" 2>/dev/null)
	if [[ "$HTTPS_CODE" =~ ^[23] ]]; then
		URL="https://${TARGET}"; SCHEME="https"
	else
		URL="http://${TARGET}";  SCHEME="http"
	fi

	echo
	printf "${BOLD}${MAGENTA}╔══════════════════════════════════════════════════╗${RESET}\n"
	printf "${BOLD}${MAGENTA}║     Speed & Performance Audit  ·  %-14s║${RESET}\n" "$TARGET "
	printf "${BOLD}${MAGENTA}╚══════════════════════════════════════════════════╝${RESET}\n"
	printf "  Started   : %s\n" "$(date)"
	if (( DO_GEO )); then
		printf "  Your IP   : %s\n" \
			"$(curl -s --max-time 5 https://ipinfo.io/ip 2>/dev/null || echo 'unknown')"
	fi
	printf "  Target URL: %s\n" "$URL"

	# ── 1. DNS ─────────────────────────────────────────────────────────────
	hdr "1 · DNS RESOLUTION"
	if ! have dig; then
		warn "dig" "not found — install bind-utils/dnsutils"; mkdir -p /dev/null
	fi
	local DIG_OUT QUERY_MS TTL IPS NS_LINE NS_IP NS_PORT
	DIG_OUT=$(dig "$TARGET" +stats 2>&1 || true)
	QUERY_MS=$(echo "$DIG_OUT" | awk '/Query time/{print $4; exit}')
	TTL=$(dig "$TARGET" 2>/dev/null | awk '/[[:space:]]IN[[:space:]]+A[[:space:]]/{print $2; exit}')
	IPS=$(dig +short "$TARGET" 2>/dev/null | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$')
	NS_LINE=$(echo "$DIG_OUT" | grep "^;; SERVER:" || true)
	NS_IP=$(echo "$NS_LINE"   | grep -oP '\d+\.\d+\.\d+\.\d+(?=#)' || true)
	NS_PORT=$(echo "$NS_LINE" | grep -oP '(?<=:)\d+(?=\()' || true)

	[[ -n "$QUERY_MS" ]] && ok "Query time"    "${QUERY_MS} ms" || warn "Query time" "n/a"
	[[ -n "$TTL"      ]] && ok "TTL"           "${TTL}s (cache lifetime)" || info "TTL" "n/a"
	[[ -n "$NS_IP"    ]] && info "Nameserver"  "${NS_IP} port ${NS_PORT}"

	echo
	echo "  Resolved IPs + ASN:"
	if [[ -n "$IPS" ]]; then
		while IFS= read -r ip; do
			printf "    ${YELLOW}%-18s${RESET}" "$ip"
			if (( DO_GEO )); then
				printf " %s\n" "$(curl -s --max-time 3 "https://ipinfo.io/${ip}/org" 2>/dev/null || echo '?')"
			else
				echo
			fi
		done <<< "$IPS"
	else
		info "no IPs" "DNS returned nothing"
	fi

	if (( DO_GEO )); then
		echo
		echo "  DNS lookup time from public resolvers:"
		local entry IP LABEL MS
		for entry in "8.8.8.8|Google" "1.1.1.1|Cloudflare" "9.9.9.9|Quad9"; do
			IP=${entry%%|*}; LABEL=${entry##*|}
			MS=$( { time dig "@${IP}" "$TARGET" +tries=1 +time=3 A &>/dev/null; } 2>&1 \
			      | awk '/real/{gsub(/[ms]/,"",$2); split($2,a,"m"); printf "%d", (a[1]*60+a[2])*1000}')
			printf "    %-12s (%s)   %s ms\n" "$IP" "$LABEL" "${MS:-?}"
		done
	fi

	# ── 2. Server Geolocation ──────────────────────────────────────────────
	if (( DO_GEO )) && [[ -n "$IPS" ]]; then
		hdr "2 · SERVER GEOLOCATION"
		local FIRST_IP GEO
		FIRST_IP=$(echo "$IPS" | head -1)
		GEO=$(curl -s --max-time 5 "https://ipinfo.io/${FIRST_IP}/json" 2>/dev/null || true)
		parse_geo() { echo "$GEO" | grep -o "\"$1\":\"[^\"]*\"" | cut -d'"' -f4; }
		ok "IP (first resolved)"  "$FIRST_IP"
		ok "City"                 "$(parse_geo city)"
		ok "Region"               "$(parse_geo region)"
		ok "Country"              "$(parse_geo country)"
		ok "Organisation"         "$(parse_geo org)"
		ok "Timezone"             "$(parse_geo timezone)"
	fi

	# ── 3. Ping / RTT ──────────────────────────────────────────────────────
	if (( DO_PING )) && have ping; then
		hdr "3 · NETWORK ROUND-TRIP TIME (ICMP ping)"
		local PING_OUT STATS MIN AVG RTT MAX LOSS
		PING_OUT=$(ping -c 10 -W 2 "$TARGET" 2>&1)
		if echo "$PING_OUT" | grep -q "min/avg/max"; then
			STATS=$(echo "$PING_OUT" | grep -oP '[\d.]+/[\d.]+/[\d.]+')
			MIN=$(echo "$STATS" | cut -d/ -f1); AVG=$(echo "$STATS" | cut -d/ -f2)
			MAX=$(echo "$STATS" | cut -d/ -f3)
			LOSS=$(echo "$PING_OUT" | grep -oP '\d+(?=% packet loss)' || echo 0)
			ok "Min RTT"  "${MIN} ms"; ok "Avg RTT"  "${AVG} ms"; ok "Max RTT"  "${MAX} ms"
			[[ "$LOSS" == "0" ]] && ok "Packet loss" "0%" || warn "Packet loss" "${LOSS}%"
			RTT="$AVG"
		else
			warn "ping" "No ICMP response (CDN may filter ICMP)"
		fi
	fi

	# ── 4. Traceroute ─────────────────────────────────────────────────────
	if (( DO_TRACEROUTE )); then
		hdr "4 · TRACEROUTE  (network path, max 20 hops)"
		if have traceroute; then
			traceroute -m 20 -w 2 "$TARGET" 2>/dev/null | while IFS= read -r line; do
				echo "  $line"
			done
		else
			info "traceroute not found" "apt install traceroute / brew install traceroute"
		fi
	fi

	# ── 5. TLS / SSL Certificate ──────────────────────────────────────────
	local TLS_VER_OUT=""
	if [[ "$SCHEME" == "https" ]] && have openssl; then
		hdr "5 · TLS / SSL CERTIFICATE"
		local CERT
		CERT=$(echo | openssl s_client -connect "${TARGET}:443" \
		       -servername "$TARGET" -status 2>/dev/null)

		TLS_VER_OUT=$(echo "$CERT" | awk '/Protocol/{print $NF; exit}')
		ok "TLS Version"  "${TLS_VER_OUT:-unknown}"
		ok "Cipher Suite" "$(echo "$CERT" | awk '/Cipher[[:space:]]*:/{print $NF; exit}')"
		ok "Issuer"       "$(echo "$CERT" | grep 'issuer='  | head -1 | sed 's/.*issuer=//')"
		ok "Subject"      "$(echo "$CERT" | grep 'subject=' | head -1 | sed 's/.*subject=//')"
		ok "Expires"      "$(echo "$CERT" | grep 'NotAfter' | head -1 | sed 's/.*NotAfter: //')"
		local OCSP
		OCSP=$(echo "$CERT" | grep -i "OCSP Response Status")
		[[ -n "$OCSP" ]] && ok "OCSP Stapling" "enabled" || warn "OCSP Stapling" "not detected"

		echo
		echo "  TLS handshake timing (${RUNS} samples — TCP+TLS combined):"
		local TLS_SUM=0 i RAW MS
		for i in $(seq 1 "$RUNS"); do
			RAW=$(curl -s -o /dev/null --max-time 10 \
			      -w "%{time_appconnect}" "https://${TARGET}" 2>/dev/null)
			MS=$(to_ms "${RAW:-0}")
			printf "    Run %-2d : " "$i"; col_ms "$MS"; echo " (TCP+TLS)"
			TLS_SUM=$((TLS_SUM + MS))
		done
		echo
		ok "TLS handshake avg" "$((TLS_SUM / RUNS)) ms"
	else
		info "TLS" "skipped (${SCHEME} target or openssl missing)"
	fi

	# ── 6. HTTP Headers & Protocol ─────────────────────────────────────────
	hdr "6 · HTTP HEADERS & PROTOCOL NEGOTIATION"
	local HDR_DUMP HTTP_VER HTTP_CODE
	HDR_DUMP=$(curl -sL --max-time 10 -D - -o /dev/null "$URL" 2>/dev/null)
	HTTP_VER=$(curl -s  --max-time 10 -o /dev/null -w "%{http_version}" "$URL" 2>/dev/null)
	HTTP_CODE=$(curl -s --max-time 10 -o /dev/null -w "%{http_code}"    "$URL" 2>/dev/null)

	ok "HTTP Version" "${HTTP_VER:-unknown}"
	ok "Status Code"  "${HTTP_CODE:-unknown}"
	echo
	echo "  Selected response headers:"
	echo "$HDR_DUMP" | grep -iE \
	  "^(server|x-served|content-type|cache-control|etag|last-modified|\
x-fastly|x-cache|x-github|age|vary|content-encoding|x-frame|\
strict-transport|access-control|x-content|referrer-policy|x-served-by):" \
	  | while IFS= read -r line; do
	      KEY=$(echo "$line" | cut -d: -f1 | tr '[:upper:]' '[:lower:]')
	      VAL=$(echo "$line" | cut -d: -f2- | sed 's/^ //')
	      printf "  ${DIM}%-32s${RESET}%s\n" "$KEY:" "$VAL"
	    done

	local ENC CC COMP_OUT
	ENC=$(echo "$HDR_DUMP" | grep -i "^content-encoding:" | awk '{print $2}' | tr -d '\r')
	if [[ -n "$ENC" ]]; then
		ok "Compression" "$ENC active"; COMP_OUT="$ENC"
	else
		warn "Compression" "none — enable gzip/br in server config"; COMP_OUT="none"
	fi
	CC=$(echo "$HDR_DUMP" | grep -i "^cache-control:" | cut -d: -f2- | tr -d '\r')
	[[ -n "$CC" ]] && ok "Cache-Control" "$CC" || warn "Cache-Control" "missing — set cache headers for assets"

	# ── 7. Redirect Chain ──────────────────────────────────────────────────
	hdr "7 · REDIRECT CHAIN"
	echo "  Tracing all hops from http://${TARGET}:"
	CHAIN=$(curl -s --max-time 15 -L --max-redirs 10 \
	        -w "\n%{url_effective}" -D - -o /dev/null "http://${TARGET}" 2>/dev/null)
	echo "$CHAIN" | grep -iE "^HTTP/|^Location:" | while IFS= read -r line; do
		if echo "$line" | grep -iq "^HTTP/"; then
			printf "  ${DIM}%s${RESET}\n" "$line" | tr -d '\r'
		else
			printf "    ${YELLOW}→${RESET} %s\n" "$(echo "$line" | cut -d: -f2- | tr -d '\r ')"
		fi
	done
	local RCOUNT
	RCOUNT=$(curl -s -o /dev/null -w "%{num_redirects}" -L --max-redirs 10 "http://${TARGET}" 2>/dev/null)
	RCOUNT=${RCOUNT:-0}
	ok "Total redirects" "$RCOUNT"
	if (( RCOUNT <= 1 )); then
		ok "Redirect depth" "Good (≤1)"
	else
		warn "Redirect depth" "High ($RCOUNT) — each hop adds latency"
	fi

	# ── 8. Curl Timing Breakdown ──────────────────────────────────────────
	hdr "8 · CURL TIMING BREAKDOWN  (${RUNS} runs)"
	echo
	printf "  ${DIM}%-4s  %-10s %-10s %-10s %-12s %-10s${RESET}\n" \
		"Run" "DNS(ms)" "TCP(ms)" "TLS(ms)" "TTFB(ms)" "Total(ms)"
	sep

	local D_ALL=() C_ALL=() S_ALL=() B_ALL=() T_ALL=()
	local i t_dns t_tcp t_tls t_ttfb t_tot ms_dns ms_tcp ms_tls ms_ttfb ms_tot
	for i in $(seq 1 "$RUNS"); do
		read -r t_dns t_tcp t_tls t_ttfb t_tot < <(
			curl -s -o /dev/null --max-time 15 \
			     -w "%{time_namelookup} %{time_connect} %{time_appconnect} %{time_starttransfer} %{time_total}" \
			     "$URL" 2>/dev/null
		)
		t_dns=${t_dns:-0}; t_tcp=${t_tcp:-0}; t_tls=${t_tls:-0}
		t_ttfb=${t_ttfb:-0}; t_tot=${t_tot:-0}

		ms_dns=$(to_ms "$t_dns")
		ms_tcp=$(delta_ms "$t_tcp" "$t_dns")
		ms_tls=$([[ "$SCHEME" == "https" ]] && delta_ms "$t_tls" "$t_tcp" || echo 0)
		ms_ttfb=$(to_ms "$t_ttfb")
		ms_tot=$(to_ms "$t_tot")

		D_ALL+=("$ms_dns"); C_ALL+=("$ms_tcp"); S_ALL+=("$ms_tls")
		B_ALL+=("$ms_ttfb"); T_ALL+=("$ms_tot")

		printf "  %-4d  " "$i"
		col_ms "$ms_dns";  printf "   "
		col_ms "$ms_tcp";  printf "   "
		col_ms "$ms_tls";  printf "   "
		col_ms "$ms_ttfb"; printf "     "
		col_ms "$ms_tot";  echo
	done

	sep
	AVG_DNS=$(avg "${D_ALL[@]:-0}"); AVG_TCP=$(avg "${C_ALL[@]:-0}")
	AVG_TLS=$(avg "${S_ALL[@]:-0}"); AVG_TTFB=$(avg "${B_ALL[@]:-0}")
	AVG_TOT=$(avg "${T_ALL[@]:-0}")
	printf "  ${BOLD}%-4s  %-10s %-10s %-10s %-12s %-10s${RESET}\n" \
		"AVG" "${AVG_DNS}ms" "${AVG_TCP}ms" "${AVG_TLS}ms" "${AVG_TTFB}ms" "${AVG_TOT}ms"
	sep
	echo
	info "DNS"   "Hostname → IP lookup"
	info "TCP"   "Three-way handshake (Δ after DNS)"
	info "TLS"   "TLS negotiation       (Δ after TCP)"
	info "TTFB"  "Time to first byte — server think time + network"
	info "Total" "All bytes received"

	# ── 9. Page Size & Assets ──────────────────────────────────────────────
	hdr "9 · PAGE SIZE & TRANSFER"
	local SIZE_DL SPEED_DL PAGE SPEED_KB TMPF
	TMPF=$(mktemp)
	read -r SIZE_DL SPEED_DL < <(
		curl -s -o "$TMPF" --max-time 15 \
		     -w "%{size_download} %{speed_download}" "$URL" 2>/dev/null
	)
	PAGE=$(<"$TMPF" 2>/dev/null || true)
	rm -f "$TMPF"
	SIZE_DL=${SIZE_DL:-0}
	SPEED_KB=$(awk "BEGIN{printf \"%.1f\", ${SPEED_DL:-0}/1024}")

	local LINKS SCRIPTS_TOTAL SCRIPTS_BLOCKING SCRIPTS_DEFERRED \
	      STYLES IMAGES PRELOADS EXT_LOADED EXT_COUNT EXT_LINKS_ONLY
	# note: grep -c prints "0" AND exits 1 on no-match, so `|| echo 0`
	# would yield "0\n0". Use `|| true` then default the variable instead.
	gcount()   { echo "$PAGE" | grep -ic "$1" || true; }
	gcountcv() { echo "$PAGE" | grep -i "$1" | grep -icv "$2" || true; }
	gcountcc() { echo "$PAGE" | grep -i "$1" | grep -icE "$2" || true; }

	LINKS=$(echo "$PAGE" | grep -oiE 'href="[^"]+"' | wc -l)
	SCRIPTS_TOTAL=$(gcount '<script');              SCRIPTS_TOTAL=${SCRIPTS_TOTAL:-0}
	SCRIPTS_BLOCKING=$(gcountcv '<script' 'defer\|async');  SCRIPTS_BLOCKING=${SCRIPTS_BLOCKING:-0}
	SCRIPTS_DEFERRED=$(gcountcc '<script' 'defer|async');   SCRIPTS_DEFERRED=${SCRIPTS_DEFERRED:-0}
	STYLES=$(gcount '<link[^>]*stylesheet');        STYLES=${STYLES:-0}
	IMAGES=$(gcount '<img');                         IMAGES=${IMAGES:-0}
	PRELOADS=$(gcount '<link[^>]*preload');          PRELOADS=${PRELOADS:-0}

	EXT_LOADED=$(echo "$PAGE" \
	    | grep -oiE '<(script|link|img|iframe|source|video|audio)[^>]+(src|href)="https?://[^"]+"' \
	    | grep -oiE 'https?://[^/"]+' \
	    | grep -iv "$TARGET" \
	    | sort -u)
	EXT_COUNT=$(echo "$EXT_LOADED" | grep -c 'http' || true)
	EXT_COUNT=${EXT_COUNT:-0}
	EXT_LINKS_ONLY=$(echo "$PAGE" \
	    | grep -oiE '<a[^>]+href="https?://[^"]+"' \
	    | grep -oiE 'https?://[^/"]+' \
	    | grep -iv "$TARGET" \
	    | sort -u \
	    | grep -vFf <(printf '%s\n' "$EXT_LOADED") 2>/dev/null || true)

	ok "Bytes downloaded"      "$(printf "%'d" "$SIZE_DL")"
	ok "Download speed"        "${SPEED_KB} KB/s"
	ok "Navigational links"    "$LINKS (no network cost)"
	ok "Script tags (total)"   "$SCRIPTS_TOTAL"
	if [[ "$SCRIPTS_BLOCKING" -eq 0 ]]; then
		ok   "  Render-blocking scripts" "0 ✓"
	else
		warn "  Render-blocking scripts" "$SCRIPTS_BLOCKING (add defer/async)"
	fi
	ok "  Deferred/async"      "$SCRIPTS_DEFERRED"
	ok "Stylesheets"           "$STYLES"
	ok "Images"                "$IMAGES"
	ok "Preload hints"         "$PRELOADS"
	echo
	echo "  External subresources loaded on page load:"
	if [[ "$EXT_COUNT" -eq 0 ]]; then
		ok "  External fetches"  "0 — fully self-contained ✓"
	else
		warn "  External fetches" "$EXT_COUNT domain(s):"
		echo "$EXT_LOADED" | while IFS= read -r d; do
			[[ -n "$d" ]] && printf "    ${YELLOW}→${RESET} %s\n" "$d"
		done
	fi
	if [[ -n "$EXT_LINKS_ONLY" ]]; then
		echo
		info "  Linked-to only (no load cost)" ""
		echo "$EXT_LINKS_ONLY" | while IFS= read -r d; do
			[[ -n "$d" ]] && printf "    ${DIM}→ %s${RESET}\n" "$d"
		done
	fi
	echo
	if (( SIZE_DL > 524288 )); then
		warn "Page weight" "Over 500 KB — consider minification"
	else
		ok   "Page weight" "Under 500 KB ✓"
	fi

	# ── 10. HTTP/2 & Keep-Alive ───────────────────────────────────────────
	hdr "10 · CONNECTION REUSE & KEEP-ALIVE"
	local VERB ALT_SVC
	VERB=$(curl -v --max-time 10 "$URL" 2>&1)
	if echo "$VERB" | grep -qiE "re.using|keep.alive|already connected|existing connection"; then
		ok "Connection reuse" "detected"
	else
		info "Connection reuse" "not seen (may still be active)"
	fi
	if echo "$VERB" | grep -qiE "h2|HTTP/2"; then
		ok "HTTP/2 multiplexing" "confirmed — parallel requests on one TCP"
	else
		warn "HTTP/2" "not detected — check server config"
	fi
	ALT_SVC=$(echo "$VERB" | grep -i "alt-svc" | head -1)
	[[ -n "$ALT_SVC" ]] && ok "Alt-Svc / HTTP/3" "$ALT_SVC" || info "HTTP/3 (QUIC)" "not advertised"

	# ── 11. CDN Cache Status ──────────────────────────────────────────────
	if [[ -n "$IPS" ]]; then
		hdr "11 · CDN CACHE STATUS  (per edge IP)"
		printf "  ${DIM}%-20s %-20s %-8s %s${RESET}\n" "IP" "X-Cache" "Age(s)" "Served-By"
		sep
		local ip HDR XCACHE AGE SRV CACHE_C
		while IFS= read -r ip; do
			HDR=$(curl -s -D - -o /dev/null --max-time 10 \
			      --resolve "${TARGET}:443:${ip}" "https://${TARGET}" 2>/dev/null)
			XCACHE=$(echo "$HDR" | grep -i "^x-cache:"    | head -1 | cut -d: -f2- | tr -d '\r ')
			AGE=$(echo "$HDR"    | grep -i "^age:"         | head -1 | cut -d: -f2- | tr -d '\r ')
			SRV=$(echo "$HDR"    | grep -i "^x-served-by:" | head -1 | cut -d: -f2- | tr -d '\r ')
			[[ -z "$XCACHE" ]] && XCACHE="—"
			[[ -z "$AGE"    ]] && AGE="—"
			[[ -z "$SRV"    ]] && SRV="—"
			if   echo "$XCACHE" | grep -qi "HIT";  then CACHE_C="${GREEN}"
			elif echo "$XCACHE" | grep -qi "MISS"; then CACHE_C="${YELLOW}"
			else CACHE_C="${DIM}"; fi
			printf "  ${YELLOW}%-20s${RESET} ${CACHE_C}%-20s${RESET} %-8s %s\n" \
				"$ip" "$XCACHE" "$AGE" "$SRV"
		done <<< "$IPS"
		echo
		info "HIT"  "served from CDN edge cache (fast)"
		info "MISS" "fetched from origin and cached (first visitor pays)"
		info "Age"  "seconds the object has lived in cache"
	fi

	# ── 12. Security Headers ──────────────────────────────────────────────
	hdr "12 · SECURITY HEADERS"
	local HDR2
	HDR2=$(curl -sL --max-time 10 -D - -o /dev/null "$URL" 2>/dev/null)
	check_hdr() {
		local h=$1 label=$2
		if echo "$HDR2" | grep -qi "^${h}:"; then ok  "$label" "present"
		else warn "$label" "missing"; fi
	}
	check_hdr "strict-transport-security"  "HSTS"
	check_hdr "x-content-type-options"     "X-Content-Type-Options"
	check_hdr "x-frame-options"            "X-Frame-Options"
	check_hdr "referrer-policy"            "Referrer-Policy"
	check_hdr "permissions-policy"         "Permissions-Policy"
	check_hdr "content-security-policy"    "Content-Security-Policy"

	local HSTS_OUT="missing" CSP_OUT="missing"
	echo "$HDR2" | grep -qi "^strict-transport-security:" && HSTS_OUT="present"
	echo "$HDR2" | grep -qi "^content-security-policy:"   && CSP_OUT="present"

	# ── 13. Performance Scorecard ──────────────────────────────────────────
	hdr "13 · PERFORMANCE SCORECARD"
	grade() {
		local v=$1 g=$2 w=$3
		if   (( v <= g )); then printf "${GREEN}  EXCELLENT${RESET}  (target ≤%dms)" "$g"
		elif (( v <= w )); then printf "${YELLOW}  GOOD${RESET}      (target ≤%dms)" "$g"
		else                    printf "${RED}  SLOW${RESET}      (target ≤%dms)" "$g"
		fi
	}
	echo
	printf "  ${BOLD}%-28s  %6s     %s${RESET}\n" "Metric" "Avg" "Rating"
	sep
	printf "  %-28s  %6d ms  %s\n" "DNS resolution"      "$AVG_DNS"  "$(grade "$AVG_DNS"   50  150)"
	printf "  %-28s  %6d ms  %s\n" "TCP connect"         "$AVG_TCP"  "$(grade "$AVG_TCP"   50  150)"
	printf "  %-28s  %6d ms  %s\n" "TLS handshake"       "$AVG_TLS"  "$(grade "$AVG_TLS"  100  300)"
	printf "  %-28s  %6d ms  %s\n" "Time to first byte"  "$AVG_TTFB" "$(grade "$AVG_TTFB" 200  600)"
	printf "  %-28s  %6d ms  %s\n" "Total transfer"      "$AVG_TOT"  "$(grade "$AVG_TOT"  500 1500)"
	sep

	echo
	echo "  ${BOLD}${YELLOW}Quick wins you control:${RESET}"
	echo "    ⚡  Minify HTML/CSS/JS (jekyll-minifier or a build step)"
	echo "    ⚡  Convert images to WebP + add loading=\"lazy\""
	echo "    ⚡  Preload critical fonts:  <link rel=preload as=font>"
	echo "    ⚡  Add dns-prefetch for every external domain you use"
	echo "    ⚡  Inline critical CSS (<style> in <head>) to cut render-blocking"
	echo "    ⚡  Add a _headers file to set long Cache-Control on /assets/*"
	echo "    ⚡  Audit & remove unused JS/CSS (check Coverage tab in DevTools)"
	echo
	echo "  ${BOLD}${CYAN}Dig deeper:${RESET}"
	echo "    🔍  webpagetest.org        — waterfall + filmstrip + Web Vitals"
	echo "    🔍  pagespeed.web.dev      — LCP / CLS / INP scores"
	echo "    🔍  securityheaders.com    — full header audit"
	echo "    🔍  ssllabs.com/ssltest    — TLS grade & cipher detail"
	echo "    🔍  bundlephobia.com       — JS package weight checker"

	# ── record metrics for the comparison summary ────────────────────────
	COMP_TARGETS+=("$TARGET")
	COMP_DNS+=("$AVG_DNS");        COMP_TCP+=("$AVG_TCP")
	COMP_TLS+=("$AVG_TLS");        COMP_TTFB+=("$AVG_TTFB")
	COMP_TOT+=("$AVG_TOT")
	COMP_SIZE+=("$(printf "%'d" "$SIZE_DL")")
	COMP_SPEED_KB+=("$SPEED_KB")
	COMP_HTTP_VER+=("${HTTP_VER:-?}"); COMP_HTTP_CODE+=("${HTTP_CODE:-?}")
	COMP_REDIRECTS+=("$RCOUNT")
	COMP_SCRIPTS+=("${SCRIPTS_TOTAL:-0}"); COMP_BLOCKING+=("${SCRIPTS_BLOCKING:-0}")
	COMP_STYLES+=("${STYLES:-0}"); COMP_IMAGES+=("${IMAGES:-0}")
	COMP_PRELOADS+=("${PRELOADS:-0}"); COMP_EXT+=("$EXT_COUNT")
	COMP_TLS_VER+=("${TLS_VER_OUT:-?}"); COMP_COMPRESSION+=("${COMP_OUT:-?}")
	COMP_HSTS+=("$HSTS_OUT"); COMP_CSP+=("$CSP_OUT")

	# ── JSON row ─────────────────────────────────────────────────────────
	JSON_ROWS["$TARGET"]=$(cat <<JSON
    "$(json_escape "$TARGET")": {
      "dns_ms": $AVG_DNS, "tcp_ms": $AVG_TCP, "tls_ms": $AVG_TLS,
      "ttfb_ms": $AVG_TTFB, "total_ms": $AVG_TOT,
      "page_bytes": $SIZE_DL, "speed_kbps": $SPEED_KB,
      "http_version": "$(json_escape "${HTTP_VER:-?}")",
      "http_code": "$(json_escape "${HTTP_CODE:-?}")",
      "redirects": $RCOUNT,
      "tls_protocol": "$(json_escape "${TLS_VER_OUT:-?}")",
      "compression": "$(json_escape "${COMP_OUT:-?}")",
      "scripts": ${SCRIPTS_TOTAL:-0}, "blocking_scripts": ${SCRIPTS_BLOCKING:-0},
      "stylesheets": ${STYLES:-0}, "images": ${IMAGES:-0},
      "preloads": ${PRELOADS:-0}, "external_fetches": $EXT_COUNT,
      "hsts": "$(json_escape "$HSTS_OUT")", "csp": "$(json_escape "$CSP_OUT")"
    }
JSON
)
}

# ─────────────────────────────────────────────────────────────────────────────
#  Comparison summary
# ─────────────────────────────────────────────────────────────────────────────
print_comparison() {
	local n=${#COMP_TARGETS[@]}
	(( n < 2 )) && return

	clear

	echo
	sep
	printf "${BOLD}${CYAN}  ▶  COMPARISON SUMMARY  (%d targets)${RESET}\n" "$n"
	sep

	local colw=14 wid h
	for h in "${COMP_TARGETS[@]}"; do
		wid=${#h}; (( wid > colw )) && colw=$wid
	done
	(( colw < 14 )) && colw=14
	local labelw=26

	row_metric() {  # lowest numeric wins
		local label=$1; shift
		local i v idx=0 best_idx=-1 best_val=""
		for i in "$@"; do
			v="${i//[^0-9.]/}"
			[[ -z "$v" ]] && { ((idx++)); continue; }
			if [[ -z "$best_val" ]] || awk "BEGIN{exit !($v < $best_val)}"; then
				best_val=$v; best_idx=$idx
			fi
			((idx++))
		done
		printf "  ${BOLD}%-*s${RESET}" "$labelw" "$label"
		idx=0
		for i in "$@"; do
			if [[ $idx -eq $best_idx ]]; then
				printf "  ${GREEN}${BOLD}%-*s${RESET}" "$colw" "$i"
			else
				printf "  ${DIM}%-*s${RESET}" "$colw" "$i"
			fi
			((idx++))
		done
		echo
	}
	row_higher() {  # highest numeric wins
		local label=$1; shift
		local i v idx=0 best_idx=-1 best_val=""
		for i in "$@"; do
			v="${i//[^0-9.]/}"
			[[ -z "$v" ]] && { ((idx++)); continue; }
			if [[ -z "$best_val" ]] || awk "BEGIN{exit !($v > $best_val)}"; then
				best_val=$v; best_idx=$idx
			fi
			((idx++))
		done
		printf "  ${BOLD}%-*s${RESET}" "$labelw" "$label"
		idx=0
		for i in "$@"; do
			if [[ $idx -eq $best_idx ]]; then
				printf "  ${GREEN}${BOLD}%-*s${RESET}" "$colw" "$i"
			else
				printf "  ${DIM}%-*s${RESET}" "$colw" "$i"
			fi
			((idx++))
		done
		echo
	}
	row_simple() {
		local label=$1; shift
		printf "  ${BOLD}%-*s${RESET}" "$labelw" "$label"
		local i
		for i in "$@"; do printf "  ${DIM}%-*s${RESET}" "$colw" "$i"; done
		echo
	}

	printf "\n  ${BOLD}%-*s${RESET}" "$labelw" "METRIC"
	for h in "${COMP_TARGETS[@]}"; do
		printf "  ${BOLD}${CYAN}%-${colw}s${RESET}" "$h"
	done
	echo
	sep
	row_metric "DNS (ms)"      "${COMP_DNS[@]}"
	row_metric "TCP (ms)"      "${COMP_TCP[@]}"
	row_metric "TLS (ms)"      "${COMP_TLS[@]}"
	row_metric "TTFB (ms)"     "${COMP_TTFB[@]}"
	row_metric "Total (ms)"    "${COMP_TOT[@]}"
	sep
	row_metric "Page bytes"    "${COMP_SIZE[@]}"
	row_higher  "Speed KB/s"    "${COMP_SPEED_KB[@]}"
	sep
	row_simple "HTTP version"  "${COMP_HTTP_VER[@]}"
	row_simple "Status code"   "${COMP_HTTP_CODE[@]}"
	row_simple "Redirects"     "${COMP_REDIRECTS[@]}"
	row_simple "TLS protocol"  "${COMP_TLS_VER[@]}"
	row_simple "Compression"   "${COMP_COMPRESSION[@]}"
	sep
	row_metric "Scripts"        "${COMP_SCRIPTS[@]}"
	row_metric "Blocking JS"    "${COMP_BLOCKING[@]}"
	row_metric "Stylesheets"    "${COMP_STYLES[@]}"
	row_metric "Images"         "${COMP_IMAGES[@]}"
	row_metric "Preloads"       "${COMP_PRELOADS[@]}"
	row_metric "Ext. fetches"   "${COMP_EXT[@]}"
	sep
	row_simple "HSTS"           "${COMP_HSTS[@]}"
	row_simple "CSP"            "${COMP_CSP[@]}"
	sep
	echo
	info "Legend" "Lowest numeric value per row is highlighted in bold green"
	info "Re-run" "Add --runs N or pass extra hosts to widen the comparison"
	echo
	sep
	printf "  Finished : %s\n" "$(date)"
	sep
	echo
}

write_json() {
	[[ -z "$JSON_OUT" ]] && return
	{
		echo "{"
		echo "  \"generated\": \"$(date -Iseconds)\","
		echo "  \"runs\": $RUNS,"
		echo "  \"targets\": {"
		local first=1 k
		for k in "${!JSON_ROWS[@]}"; do
			(( first )) || echo ","
			printf '%s' "${JSON_ROWS[$k]}"
			first=0
		done
		echo
		echo "  }"
		echo "}"
	} > "$JSON_OUT"
	echo "📝 JSON metrics written to $JSON_OUT"
}

# ─────────────────────────────────────────────────────────────────────────────
#  Main
# ─────────────────────────────────────────────────────────────────────────────
RAW_TARGETS=()
while read -r host; do
	host=$(norm_host "$host")
	[[ -n "$host" ]] && RAW_TARGETS+=("$host")
done < <(collect_targets "$@" | filter_targets)

# de-dup preserving order
declare -A SEEN=()
TARGETS=()
if (( ${#RAW_TARGETS[@]} )); then
	for t in "${RAW_TARGETS[@]}"; do
		[[ -z "$t" ]] && continue
		if [[ -z "${SEEN[$t]:-}" ]]; then
			SEEN[$t]=1; TARGETS+=("$t")
		fi
	done
fi

if [[ ${#TARGETS[@]} -eq 0 ]]; then
	echo "No valid targets. Check members.json or pass hosts as arguments." >&2
	exit 1
fi

echo
printf "${BOLD}${CYAN}amrita.town multi-target performance audit${RESET}\n"
printf "Targets (%d): %s\n" "${#TARGETS[@]}" "$(IFS=', '; echo "${TARGETS[*]}")"
printf "${DIM}runs=%d  geo=%s ping=%s traceroute=%s${RESET}\n" \
	"$RUNS" "$((DO_GEO?1:0))" "$((DO_PING?1:0))" "$((DO_TRACEROUTE?1:0))"
printf "${DIM}(Best value per metric is highlighted in the final summary)${RESET}\n"

for t in "${TARGETS[@]}"; do
	audit_target "$t"
done

print_comparison
write_json