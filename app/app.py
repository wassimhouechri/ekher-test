from flask import Flask, jsonify, request, abort
from functools import wraps
import time
import os

app = Flask(__name__)

# ─── Security Headers ───
@app.after_request
def set_security_headers(response):
    response.headers["Content-Security-Policy"] = "default-src 'none'; frame-ancestors 'none'"
    response.headers["Strict-Transport-Security"] = "max-age=31536000; includeSubDomains"
    response.headers["X-Content-Type-Options"] = "nosniff"
    response.headers["X-Frame-Options"] = "DENY"
    response.headers["Referrer-Policy"] = "no-referrer"
    response.headers["Permissions-Policy"] = "geolocation=(), microphone=(), camera=()"
    response.headers.pop("Server", None)
    return response


# ─── Rate Limiting (simple in-memory) ───
RATE_LIMIT = int(os.environ.get("RATE_LIMIT", "60"))
RATE_WINDOW = int(os.environ.get("RATE_WINDOW", "60"))

_rate_store: dict = {}

# TODO en production : utiliser Redis ou flask-limiter
# Ce rate limiter ne scale pas avec plusieurs replicas Kubernetes
def rate_limited(f):
    @wraps(f)
    def decorated(*args, **kwargs):
        ip = request.remote_addr or "unknown"
        now = time.time()
        window_start = now - RATE_WINDOW

        if ip in _rate_store:
            _rate_store[ip] = [t for t in _rate_store[ip] if t > window_start]
        else:
            _rate_store[ip] = []

        if len(_rate_store[ip]) >= RATE_LIMIT:
            abort(429)

        _rate_store[ip].append(now)
        return f(*args, **kwargs)
    return decorated


# ─── API Key Auth ───
# Lecture sécurisée depuis un fichier monté par Kubernetes (fix CKV_K8S_35)
# Le secret est monté en lecture seule dans /secrets/api-key

API_KEY_FILE = "/secrets/api-key"
API_KEY = ""

if os.path.exists(API_KEY_FILE):
    try:
        with open(API_KEY_FILE, "r") as f:
            API_KEY = f.read().strip()
    except Exception:
        API_KEY = ""
else:
    # Fallback pour le développement local (quand on lance python app.py)
    API_KEY = os.environ.get("API_KEY", "")


def require_api_key(f):
    @wraps(f)
    def decorated(*args, **kwargs):
        if not API_KEY:
            # Si aucune clé n'est configurée → auth désactivée (mode dev)
            return f(*args, **kwargs)
        key = request.headers.get("X-API-Key", "")
        if key != API_KEY:
            abort(401)
        return f(*args, **kwargs)
    return decorated


# ─── Routes ───
@app.route("/")
@rate_limited
def home():
    return jsonify({"status": "ok", "message": "DevSecOps app running"})


@app.route("/health")
def health():
    return "OK", 200


@app.route("/api/data")
@rate_limited
@require_api_key
def data():
    return jsonify({"data": [1, 2, 3], "count": 3})


# ─── Error handlers ───
@app.errorhandler(401)
def unauthorized(e):
    return jsonify({"error": "Unauthorized"}), 401

@app.errorhandler(429)
def too_many_requests(e):
    return jsonify({"error": "Too Many Requests"}), 429


if __name__ == "__main__":
    app.run()