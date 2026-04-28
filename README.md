# Aegis – Distributed Server Monitor

**Aegis** is a distributed server monitoring system with E2E-encrypted communication, self-healing, and push notifications.  
Control and monitor your server processes and Docker containers on the go.

> ⚡ Flutter App (Android) + Web-Dashboard + Python Backend

---

## 🚀 Features

| Feature | Description |
|---|---|
| **🔐 E2E Encryption** | AES-256-GCM, all API data encrypted |
| **📱 Mobile App** | Flutter (Android) with Dark Mode |
| **🌐 Web-Dashboard** | Integrated directly in the backend (SPA) |
| **🛡️ Self-Healing** | Automatic restart on crash |
| **📊 System Stats** | CPU, RAM, Disk, Network, Uptime |
| **🐳 Docker Support** | Start/stop/log containers |
| **🔔 Push Notifications** | Via Firebase Cloud Messaging |
| **⚡ Key Caching** | Derive PBKDF2 once, then AES in <1ms |

---

## 📦 Quick Start

### Backend (Server)

```bash
cd backend/
pip install -r requirements.txt
# Create .env file (see .env.example)
python3 -m uvicorn main:app --host 0.0.0.0 --port 8000
```

On first start, an API key is generated and printed in the logs:

```
Generated API key: e6534265c7ffed20d8b6c0eb0b8aa8cf972c2274a6ec14c960e28aeda92a8746
```

**Copy this key** — it is needed for the app and the web dashboard.

### Docker

```bash
cd backend/
docker compose up -d
docker compose logs -f  # Read the API key here
```

### Systemd (Production)

```bash
sudo cp -r backend/ /opt/aegis/
sudo cp deploy/server-monitor@.service /etc/systemd/system/aegis@8000.service
sudo systemctl enable --now aegis@8000
journalctl -u aegis@8000  # Read the API key
```

### Mobile App (Android)

1. [Download the release APK](https://github.com/DerTraurigeHund/aegis/releases/latest) or build it yourself:

```bash
cd flutter_app/
flutter pub get
flutter build apk --release
flutter install
```

2. Enter the server address and API key in the app
3. Done! ✅

---

## 📱 Web-Dashboard

The backend serves a full SPA dashboard — no extra server needed.

```
http://<server>:8000/          # Open dashboard
http://<server>:8000/dashboard
```

**Features:**
- 🔒 Login with API key (saved in browser)
- 📊 System stats: CPU, RAM, Disk, Load, Network
- 🚀 Project management: Start / Stop / Restart / Logs
- 🔄 Auto-refresh every 10s
- 🌙 Dark theme, responsive

---

## 🏗️ Architektur

```
┌─────────────────────────────────────────────────┐
│              Aegis Mobile App (Flutter)          │
│  ┌───────────────────────────────────────────┐   │
│  │  CryptoService (AES-256-GCM)              │   │
│  │  ├── Key-Cache (PBKDF2 once)              │   │
│  │  ├── Inline for <2KB payloads            │   │
│  │  └── Isolate for large payloads          │   │
│  └───────────────────────────────────────────┘   │
│  ApiService ── HTTPS ── X-API-Key + E2E Body     │
└──────────────────────┬──────────────────────────┘
                       │
┌──────────────────────▼──────────────────────────┐
│            Aegis Backend (Python/FastAPI)        │
│  ┌───────────────────────────────────────────┐   │
│  │  Middleware Stack:                         │   │
│  │  ├── AuthMiddleware (API Key Check)      │   │
│  │  ├── CORS                                 │   │
│  │  └── E2EEncryptionMiddleware              │   │
│  ├── Process Manager (Shell/Docker)           │   │
│  ├── Background Monitor (Self-Healing)        │   │
│  ├── System Stats Collector                   │   │
│  ├── Push Notifications (FCM)                 │   │
│  └── Web-Dashboard (SPA)                      │   │
└──────────────────────┬──────────────────────────┘
                       │
┌──────────────────────▼──────────────────────────┐
│              SQLite Database                     │
│  ├── projects (Konfiguration + Status)           │
│  ├── events (Crash/Recovery/Start/Stop)          │
│  ├── push_tokens (FCM Devices)                   │
│  └── settings (API-Key, etc.)                    │
└──────────────────────────────────────────────────┘
```

---

## 🔐 E2E Encryption

- **Algorithm:** AES-256-GCM + PBKDF2-HMAC-SHA256
- **Key derivation:** 100,000 iterations PBKDF2
- **Nonce:** 12 bytes random, bound as associated data
- **MAC Size:** 128 bits
- **Transport:** `{"nonce": "<base64>", "ciphertext": "<base64>"}`

### Performance (Mobile)

| Operation | Before Optimization | After Optimization |
|---|---|---|
| PBKDF2 (first call) | 100–200ms | 100–200ms (one-time) |
| AES-GCM (subsequent calls) | 100–200ms | **< 1ms** (key cached) |
| 5 API calls | ~1s crypto | **~100ms** |

---

## 🛠️ Development

### Backend (local)

```bash
cd backend/
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
uvicorn main:app --reload --host 0.0.0.0 --port 8000
```

### Flutter App

```bash
cd flutter_app/
flutter pub get
flutter run              # Debug
flutter test             # Tests (including crypto roundtrip)
flutter build apk --release
```

### Crypto Tests

```bash
flutter test test/crypto_test.dart
# → AES-256-GCM roundtrip, key caching, wrong-key handling
```

---

## 📁 Project Structure

```
aegis/
├── backend/                      # Python FastAPI Backend
│   ├── main.py                   # FastAPI App + Endpoints
│   ├── crypto.py                 # AES-256-GCM (server-side)
│   ├── e2e_middleware.py         # E2E Encryption Middleware
│   ├── auth.py                   # API Key Authentication
│   ├── database.py               # SQLite Schema + Connection
│   ├── monitor.py                # Background Self-Healing
│   ├── process_manager.py        # Shell/Docker Management
│   ├── system_stats.py           # CPU/RAM/Disk/Network
│   ├── requirements.txt
│   ├── Dockerfile / docker-compose.yml
│   └── web/                      # Web-Dashboard (SPA)
│       ├── index.html
│       ├── app.js
│       └── style.css
│
├── flutter_app/                  # Flutter Mobile App
│   └── lib/
│       ├── main.dart
│       ├── models/
│       ├── services/
│       │   ├── crypto.dart       # Key Cache + Hybrid Inline/Isolate
│       │   ├── api_service.dart
│       │   └── database_service.dart
│       ├── screens/
│       └── theme/
│
├── .github/workflows/            # CI/CD
│   └── release.yml
└── README.md
```

---

## 🔧 API Endpoints

| Method | Path | Description |
|---|---|---|
| `GET` | `/health` | Health check (no auth) |
| `GET` | `/system/stats` | CPU, RAM, Disk, Network |
| `GET` | `/projects` | All projects |
| `POST` | `/projects` | Create project |
| `GET` | `/projects/{id}` | Project details |
| `PUT` | `/projects/{id}` | Edit project |
| `DELETE` | `/projects/{id}` | Delete project |
| `POST` | `/projects/{id}/start` | Start |
| `POST` | `/projects/{id}/stop` | Stop |
| `POST` | `/projects/{id}/restart` | Restart |
| `GET` | `/projects/{id}/logs` | Get logs |
| `GET` | `/projects/{id}/events` | Event history |
| `GET` | `/projects/{id}/stats` | Statistics |
| `POST` | `/devices/register` | Register FCM token |
| `POST` | `/devices/unregister` | Remove FCM token |

---

## 📄 License

MIT © [DerTraurigeHund](https://github.com/DerTraurigeHund)
