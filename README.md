# Aegis – Distributed Server Monitor

**Aegis** ist ein verteiltes Server-Monitoring-System mit E2E-verschlüsselter Kommunikation, Self-Healing und Push-Benachrichtigungen.  
Steuere und überwache deine Server-Prozesse und Docker-Container von unterwegs.

> ⚡ Flutter App (Android) + Web-Dashboard + Python Backend

---

## 🚀 Features

| Feature | Beschreibung |
|---|---|
| **🔐 E2E Encryption** | AES-256-GCM, alle API-Daten verschlüsselt |
| **📱 Mobile App** | Flutter (Android) mit Dark Mode |
| **🌐 Web-Dashboard** | Direkt im Backend integriert (SPA) |
| **🛡️ Self-Healing** | Automatischer Restart bei Crash |
| **📊 System-Statistiken** | CPU, RAM, Disk, Network, Uptime |
| **🐳 Docker Support** | Container starten/stoppen/loggen |
| **🔔 Push-Benachrichtigungen** | Via Firebase Cloud Messaging |
| **⚡ Key-Caching** | PBKDF2 einmal ableiten, dann AES in <1ms |

---

## 📦 Schnellstart

### Backend (Server)

```bash
cd backend/
pip install -r requirements.txt
# .env anlegen (siehe .env.example)
python3 -m uvicorn main:app --host 0.0.0.0 --port 8000
```

Beim ersten Start wird ein API-Key generiert und in den Logs ausgegeben:

```
Generated API key: e6534265c7ffed20d8b6c0eb0b8aa8cf972c2274a6ec14c960e28aeda92a8746
```

**Diesen Key kopieren** – er wird für die App und das Web-Dashboard benötigt.

### Docker

```bash
cd backend/
docker compose up -d
docker compose logs -f  # Hier den API-Key ablesen
```

### Systemd (Production)

```bash
sudo cp -r backend/ /opt/aegis/
sudo cp deploy/server-monitor@.service /etc/systemd/system/aegis@8000.service
sudo systemctl enable --now aegis@8000
journalctl -u aegis@8000  # API-Key ablesen
```

### Mobile App (Android)

1. [Release-APK herunterladen](https://github.com/LuisDev99/aegis/releases/latest) oder selbst bauen:

```bash
cd flutter_app/
flutter pub get
flutter build apk --release
flutter install
```

2. In der App Server-Adresse + API-Key eintragen
3. Fertig! ✅

---

## 📱 Web-Dashboard

Das Backend liefert ein vollständiges SPA-Dashboard — kein Extra-Server nötig.

```
http://<server>:8000/          # Dashboard öffnen
http://<server>:8000/dashboard
```

**Funktionen:**
- 🔒 Login mit API-Key (im Browser gespeichert)
- 📊 System-Stats: CPU, RAM, Disk, Load, Network
- 🚀 Projekt-Management: Start / Stop / Restart / Logs
- 🔄 Auto-Refresh alle 10s
- 🌙 Dark Theme, responsive

---

## 🏗️ Architektur

```
┌─────────────────────────────────────────────────┐
│              Aegis Mobile App (Flutter)          │
│  ┌───────────────────────────────────────────┐   │
│  │  CryptoService (AES-256-GCM)              │   │
│  │  ├── Key-Cache (PBKDF2 once)              │   │
│  │  ├── Inline für <2KB Payloads             │   │
│  │  └── Isolate für große Payloads           │   │
│  └───────────────────────────────────────────┘   │
│  ApiService ── HTTPS ── X-API-Key + E2E Body     │
└──────────────────────┬──────────────────────────┘
                       │
┌──────────────────────▼──────────────────────────┐
│            Aegis Backend (Python/FastAPI)        │
│  ┌───────────────────────────────────────────┐   │
│  │  Middleware Stack:                         │   │
│  │  ├── AuthMiddleware (API-Key Prüfung)      │   │
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
│  ├── push_tokens (FCM-Geräte)                    │
│  └── settings (API-Key, etc.)                    │
└──────────────────────────────────────────────────┘
```

---

## 🔐 E2E-Verschlüsselung

- **Algorithmus:** AES-256-GCM + PBKDF2-HMAC-SHA256
- **Schlüsselableitung:** 100.000 Iterationen PBKDF2
- **Nonce:** 12 Bytes random, als Associated Data gebunden
- **MAC Size:** 128 Bit
- **Transport:** `{"nonce": "<base64>", "ciphertext": "<base64>"}`

### Performance (Mobile)

| Operation | Vor Optimierung | Nach Optimierung |
|---|---|---|
| PBKDF2 (erster Call) | 100–200ms | 100–200ms (einmalig) |
| AES-GCM (Folge-Calls) | 100–200ms | **< 1ms** (Key gecached) |
| 5 API-Calls | ~1s Crypto | **~100ms** |

---

## 🛠️ Entwicklung

### Backend lokal

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
flutter test             # Tests (auch Crypto-Roundtrip)
flutter build apk --release
```

### Crypto-Tests

```bash
flutter test test/crypto_test.dart
# → AES-256-GCM Roundtrip, Key-Caching, Wrong-Key-Handling
```

---

## 📁 Projektstruktur

```
aegis/
├── backend/                      # Python FastAPI Backend
│   ├── main.py                   # FastAPI App + Endpunkte
│   ├── crypto.py                 # AES-256-GCM (Serverseite)
│   ├── e2e_middleware.py         # E2E Encryption Middleware
│   ├── auth.py                   # API-Key Authentifizierung
│   ├── database.py               # SQLite Schema + Verbindung
│   ├── monitor.py                # Background Self-Healing
│   ├── process_manager.py        # Shell/Docker Steuerung
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
│       │   ├── crypto.dart       # Key-Cache + Hybrid Inline/Isolate
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

## 🔧 API Endpunkte

| Methode | Pfad | Beschreibung |
|---|---|---|
| `GET` | `/health` | Healthcheck (keine Auth) |
| `GET` | `/system/stats` | CPU, RAM, Disk, Network |
| `GET` | `/projects` | Alle Projekte |
| `POST` | `/projects` | Projekt anlegen |
| `GET` | `/projects/{id}` | Projektdetails |
| `PUT` | `/projects/{id}` | Projekt bearbeiten |
| `DELETE` | `/projects/{id}` | Projekt löschen |
| `POST` | `/projects/{id}/start` | Starten |
| `POST` | `/projects/{id}/stop` | Stoppen |
| `POST` | `/projects/{id}/restart` | Neustarten |
| `GET` | `/projects/{id}/logs` | Logs abrufen |
| `GET` | `/projects/{id}/events` | Event-Historie |
| `GET` | `/projects/{id}/stats` | Statistiken |
| `POST` | `/devices/register` | FCM-Token registrieren |
| `POST` | `/devices/unregister` | FCM-Token entfernen |

---

## 📄 Lizenz

MIT © [LuisDev99](https://github.com/LuisDev99)
