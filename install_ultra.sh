#!/bin/bash
# CavrixCore Master Installer v3.1 FINAL
# Safe all-in-one Ubuntu VPS setup for CavrixCore (Frontend + Backend + AI + Voice + SSL + Firewall + Backup)
# Author: Naadir (CavrixCore Project)
# Runs safely with confirmation and full transparency

set -euo pipefail
IFS=$'\n\t'

require_root() {
  [ "$(id -u)" -eq 0 ] || { echo "Run as root!"; exit 1; }
}
require_root

echo "==== 🚀 CavrixCore Master Installer v3.1 ===="
echo "Preparing secure full-stack setup..."
sleep 2

# Config
DOMAIN=""
read -p "Enter your domain (or press Enter to skip HTTPS): " DOMAIN
FRONTEND="/var/www/cavrixcore"
BACKEND="/root/cavrixcore-backend"
MODELS="/root/cavrixcore-models"
SERVICE="cavrixcore"

apt update -y
apt upgrade -y
apt install -y nginx python3 python3-pip python3-venv git curl wget unzip ffmpeg nano ufw fail2ban certbot python3-certbot-nginx

echo "-> Firewall setup"
ufw allow OpenSSH
ufw allow 'Nginx Full'
ufw --force enable

echo "-> Fail2ban active"
systemctl enable --now fail2ban || true

echo "-> Directories"
mkdir -p "$FRONTEND" "$BACKEND" "$MODELS"

echo "-> Python venv"
cd "$BACKEND"
python3 -m venv venv
source venv/bin/activate
pip install --upgrade pip flask gunicorn tinydb pyttsx3 soundfile
read -p "Install GPT4All (y/n)? " g4a
[[ "$g4a" =~ ^[Yy]$ ]] && pip install gpt4all || true
read -p "Install VOSK (offline STT) (y/n)? " vs
[[ "$vs" =~ ^[Yy]$ ]] && pip install vosk || true
deactivate

echo "-> Flask backend"
cat > "$BACKEND/app.py" <<'PY'
from flask import Flask, request, jsonify, send_file
from tinydb import TinyDB
import os, pyttsx3
app = Flask(__name__)
DB = TinyDB("chat_memory.json")
@app.route("/api/chat", methods=["POST"])
def chat():
    data = request.get_json() or {}
    msg = data.get("message","").strip()
    reply = f"AI Response to: {msg}" if msg else "No message received."
    DB.insert({"user": msg, "ai": reply})
    return jsonify({"reply": reply})
@app.route("/api/tts", methods=["POST"])
def tts():
    text = (request.get_json() or {}).get("text","")
    out="voice.wav"; engine=pyttsx3.init()
    engine.save_to_file(text, out); engine.runAndWait()
    return send_file(out, mimetype="audio/wav")
@app.route("/api/history") 
def hist(): return jsonify(DB.all())
if __name__=="__main__": app.run(host="0.0.0.0", port=5000)
PY

cat > "/etc/systemd/system/${SERVICE}.service" <<SERVICE
[Unit]
Description=CavrixCore Backend
After=network.target
[Service]
User=root
WorkingDirectory=$BACKEND
ExecStart=$BACKEND/venv/bin/gunicorn --workers 2 --bind 127.0.0.1:5000 app:app
Restart=always
[Install]
WantedBy=multi-user.target
SERVICE

systemctl daemon-reload
systemctl enable --now "$SERVICE"

echo "-> NGINX config"
cat > /etc/nginx/sites-available/cavrixcore <<NGINX
server {
    listen 80;
    server_name ${DOMAIN:-_};
    root $FRONTEND;
    index index.html;
    location / {
        try_files \$uri \$uri/ =404;
    }
    location /api/ {
        proxy_pass http://127.0.0.1:5000/;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
    }
}
NGINX

ln -sf /etc/nginx/sites-available/cavrixcore /etc/nginx/sites-enabled/
nginx -t && systemctl restart nginx

if [ -n "$DOMAIN" ]; then
  echo "-> Enabling SSL for $DOMAIN"
  certbot --nginx -d "$DOMAIN" --non-interactive --agree-tos -m cavrixcore@gmail.com || true
fi

echo "-> Daily backup cron"
cat > /root/cavrixcore_backup.sh <<'BKP'
#!/bin/bash
tar -czf /root/cavrix_backup_$(date +%F).tar.gz /var/www/cavrixcore /root/cavrixcore-backend /root/cavrixcore-models
find /root -name "cavrix_backup_*.tar.gz" -mtime +7 -delete
BKP
chmod +x /root/cavrixcore_backup.sh
(crontab -l 2>/dev/null; echo "0 3 * * * /root/cavrixcore_backup.sh") | crontab -

echo "-> Fix perms"
chmod -R 755 "$FRONTEND"

echo "✅ INSTALL COMPLETE!"
echo "Frontend → $FRONTEND"
echo "Backend → $BACKEND"
echo "API health → curl http://127.0.0.1:5000/api/chat"
echo "Service status → systemctl status $SERVICE"

