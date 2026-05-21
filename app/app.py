import os
import secrets
import requests
from flask import Flask, redirect, request, session, url_for, render_template

app = Flask(__name__)
app.secret_key = os.getenv("SECRET_KEY", "dev-secret-key-change-in-prod")

# URL acessível pelo browser (via port-forward)
CASDOOR_EXTERNAL_URL = os.getenv("CASDOOR_EXTERNAL_URL", "http://localhost:8000")
# URL interna ao cluster (server-to-server)
CASDOOR_INTERNAL_URL = os.getenv("CASDOOR_INTERNAL_URL", "http://casdoor-svc:8000")

CLIENT_ID     = os.getenv("CLIENT_ID", "flask-demo")
CLIENT_SECRET = os.getenv("CLIENT_SECRET", "flask-demo-secret")
REDIRECT_URI  = os.getenv("REDIRECT_URI", "http://localhost:5000/callback")


@app.route("/")
def index():
    return render_template("index.html", user=session.get("user"))


@app.route("/login")
def login():
    state = secrets.token_urlsafe(16)
    session["oauth_state"] = state
    auth_url = (
        f"{CASDOOR_EXTERNAL_URL}/login/oauth/authorize"
        f"?client_id={CLIENT_ID}"
        f"&response_type=code"
        f"&redirect_uri={REDIRECT_URI}"
        f"&scope=openid profile email"
        f"&state={state}"
    )
    return redirect(auth_url)


@app.route("/callback")
def callback():
    code  = request.args.get("code")
    state = request.args.get("state")

    if state != session.pop("oauth_state", None):
        return "State inválido", 400

    token_resp = requests.post(
        f"{CASDOOR_INTERNAL_URL}/api/login/oauth/access_token",
        data={
            "grant_type":    "authorization_code",
            "client_id":     CLIENT_ID,
            "client_secret": CLIENT_SECRET,
            "code":          code,
            "redirect_uri":  REDIRECT_URI,
        },
        timeout=10,
    )
    token_resp.raise_for_status()
    access_token = token_resp.json().get("access_token")

    userinfo_resp = requests.get(
        f"{CASDOOR_INTERNAL_URL}/api/userinfo",
        headers={"Authorization": f"Bearer {access_token}"},
        timeout=10,
    )
    userinfo_resp.raise_for_status()

    session["user"] = userinfo_resp.json()
    return redirect(url_for("index"))


@app.route("/logout")
def logout():
    session.clear()
    return redirect(url_for("index"))


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000, debug=True)
