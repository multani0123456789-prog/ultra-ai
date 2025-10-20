#!/usr/bin/env bash
set -e
export DEBIAN_FRONTEND=noninteractive

echo "🚀 Installing CavrixCore Ultra AI (Pro + Voice + Jarvis)..."

# Update + essentials
apt update -y && apt upgrade -y
apt install -y curl git ufw fail2ban nginx build-essential ca-certificates python3 python3-pip ffmpeg

# Node.js + PM2
curl -fsSL https://deb.nodesource.com/setup_22.x | bash -
apt install -y nodejs
npm install -g pm2

# Ollama + models
curl -fsSL https://ollama.com/install.sh | bash
systemctl enable --now ollama
ollama pull llama3.2:1b
ollama pull llama3.2:3b

# Whisper.cpp
git clone https://github.com/ggerganov/whisper.cpp /opt/whisper.cpp
cd /opt/whisper.cpp && make -j$(nproc)

# Coqui TTS
pip install --upgrade pip
pip install TTS==0.13.1
python3 -m TTS --list_models | head -n 5

# Backend
mkdir -p /opt/cavrixcore-ai && cd /opt/cavrixcore-ai
npm init -y
npm install express cors axios better-sqlite3

cat <<'JS' > server.js
import express from "express";
import cors from "cors";
import { spawn } from "child_process";
import Database from "better-sqlite3";

const db = new Database("./memory.db");
db.prepare("CREATE TABLE IF NOT EXISTS mem (k TEXT PRIMARY KEY, v TEXT)").run();

const app = express();
app.use(cors());
app.use(express.json());

function remember(k,v){ db.prepare("INSERT OR REPLACE INTO mem (k,v) VALUES (?,?)").run(k,v); }
function recall(k){ const r=db.prepare("SELECT v FROM mem WHERE k=?").get(k); return r?r.v:null; }

async function ask(prompt){
  return new Promise(r=>{
    const p=spawn("ollama",["run","llama3.2:1b"]);
    let o=""; p.stdin.write(prompt+"\\n"); p.stdin.end();
    p.stdout.on("data",d=>o+=d.toString()); p.on("close",()=>r(o.trim()));
  });
}

app.post("/chat",async(req,res)=>{
  try{ const msg=req.body.message;
    const ctx=recall("ctx")||""; const ans=await ask(ctx+"\\nUser:"+msg);
    remember("ctx",msg+"=>"+ans);
    res.json({reply:ans});
  }catch(e){ res.status(500).json({error:e.message}); }
});

app.listen(5000,()=>console.log("✅ CavrixCore Ultra AI running on port 5000"));
JS

pm2 start server.js --name cavrixcore
pm2 save
pm2 startup -u root --hp /root

# Security
ufw allow 22/tcp
ufw allow 80/tcp
ufw allow 5000/tcp
ufw --force enable
systemctl enable --now fail2ban

echo "🎯 CavrixCore Ultra AI installed successfully!"
echo "Open in browser: http://$(curl -s ifconfig.me)"
