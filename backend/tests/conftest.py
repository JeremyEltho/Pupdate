import os
import sys
from pathlib import Path

# Tests must never touch the live database or the shared Redis. app/main.py loads walkbuddy/.env, which holds
# the live MONGODB_URI; setting these to empty first wins, because load_dotenv never overrides a variable that is
# already set. (Before this, every test run saved its fake state to the live MongoDB snapshot.)
for _k in ("MONGODB_URI", "KV_REST_API_URL", "KV_REST_API_TOKEN", "UPSTASH_REDIS_REST_URL", "UPSTASH_REDIS_REST_TOKEN"):
    os.environ[_k] = ""
# Same for Gemini: tests use the fallbacks and must not wait on the network.
os.environ["GEMINI_API_KEY"] = ""

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
