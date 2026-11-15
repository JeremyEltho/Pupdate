#!/bin/bash
# Creates a Vultr server running the WalkBuddy backend with MongoDB persistence and HTTPS.
# Needs VULTR_API_KEY and MONGODB_URI in walkbuddy/.env (git-ignored).
set -euo pipefail
DIR="$(cd "$(dirname "$0")/.." && pwd)"
set -a; source "$DIR/.env"; set +a
: "${VULTR_API_KEY:?add VULTR_API_KEY to walkbuddy/.env}"
: "${MONGODB_URI:?add MONGODB_URI to walkbuddy/.env}"
API=https://api.vultr.com/v2
H=(-H "Authorization: Bearer $VULTR_API_KEY" -H "Content-Type: application/json")

OS_ID=$(curl -sf "${H[@]}" "$API/os?per_page=500" | python3 -c "
import json,sys
oses=json.load(sys.stdin)['os']
ub=[o for o in oses if o['family']=='ubuntu' and '24.04' in o['name'] and 'x64' in o['name']]
print(ub[0]['id'])")
USER_DATA=$(sed "s|__MONGODB_URI__|$MONGODB_URI|" "$DIR/deploy/cloud-init.sh" | base64 | tr -d '\n')
BODY=$(python3 -c "
import json,sys
print(json.dumps({'region':'lax','plan':'vc2-1c-1gb','os_id':int(sys.argv[1]),'label':'walkbuddy','hostname':'walkbuddy','user_data':sys.argv[2],'backups':'disabled'}))" "$OS_ID" "$USER_DATA")
ID=$(curl -sf "${H[@]}" -X POST "$API/instances" -d "$BODY" | python3 -c "import json,sys;print(json.load(sys.stdin)['instance']['id'])")
echo "created instance $ID, waiting for an IP..."
for i in $(seq 1 60); do
  IP=$(curl -sf "${H[@]}" "$API/instances/$ID" | python3 -c "import json,sys;i=json.load(sys.stdin)['instance'];print(i['main_ip'] if i['main_ip']!='0.0.0.0' else '')")
  [ -n "$IP" ] && break; sleep 5
done
URL="https://$(echo "$IP" | tr . -).sslip.io"
echo "$ID" > "$DIR/deploy/.instance"; echo "$URL" > "$DIR/deploy/.url"
echo "server IP $IP; waiting for $URL/health (first boot takes 3-5 minutes)..."
for i in $(seq 1 90); do
  if curl -sf -m 5 "$URL/health" >/dev/null; then echo "LIVE: $URL"; exit 0; fi
  sleep 10
done
echo "not healthy yet; check later: curl $URL/health"; exit 1
