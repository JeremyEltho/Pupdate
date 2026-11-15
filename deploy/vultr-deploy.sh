#!/bin/bash
# Creates a Vultr server running the Pupdate backend with MongoDB persistence and HTTPS.
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
USER_DATA=$(python3 -c "
import sys,os,base64
s=open(sys.argv[1]).read().replace('__MONGODB_URI__', os.environ['MONGODB_URI'])
print(base64.b64encode(s.encode()).decode())" "$DIR/deploy/cloud-init.sh")
# SSH key so the server can be updated later without rebuilding it
KEY="$HOME/.ssh/walkbuddy_vultr"
[ -f "$KEY" ] || ssh-keygen -t ed25519 -N "" -C walkbuddy-vultr -f "$KEY" >/dev/null
SSHKEY_ID=$(curl -sf "${H[@]}" "$API/ssh-keys" | python3 -c "
import json,sys
k=[x for x in json.load(sys.stdin)['ssh_keys'] if x['name']=='walkbuddy']
print(k[0]['id'] if k else '')")
if [ -z "$SSHKEY_ID" ]; then
  SSHKEY_ID=$(python3 -c "import json,sys;print(json.dumps({'name':'walkbuddy','ssh_key':open(sys.argv[1]).read().strip()}))" "$KEY.pub" \
    | curl -sf "${H[@]}" -X POST "$API/ssh-keys" -d @- | python3 -c "import json,sys;print(json.load(sys.stdin)['ssh_key']['id'])")
fi
BODY=$(python3 -c "
import json,sys
print(json.dumps({'region':'lax','plan':'vc2-1c-1gb','os_id':int(sys.argv[1]),'label':'walkbuddy','hostname':'walkbuddy','user_data':sys.argv[2],'backups':'disabled','sshkey_id':[sys.argv[3]]}))" "$OS_ID" "$USER_DATA" "$SSHKEY_ID")
RESP=$(curl -s "${H[@]}" -X POST "$API/instances" -d "$BODY")
ID=$(echo "$RESP" | python3 -c "import json,sys;d=json.loads(sys.stdin.read() or '{}');print(d.get('instance',{}).get('id',''))")
if [ -z "$ID" ]; then echo "Vultr refused to create the server: $RESP"; exit 1; fi
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
