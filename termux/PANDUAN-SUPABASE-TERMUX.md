# Panduan Lengkap: Supabase di Android (Termux)

## Apa itu Supabase?
Supabase adalah alternatif open-source Firebase yang menyediakan:
- Database PostgreSQL
- Authentication (login/register)
- REST API otomatis
- Realtime subscriptions
- File Storage
- Dashboard Studio

---

## Prasyarat

**Di HP Android:**
- Android 7.0+ (minimal)
- RAM 2GB+ (rekomendasi 4GB+)
- Storage 3-8GB kosong
- Koneksi internet (untuk download)

**Install Termux:**
1. Download dari **F-Droid** (bukan Play Store): https://f-droid.org/packages/com.termux/
2. Install Termux:API (opsional untuk notifikasi)

---

## CARA INSTALL

### Langkah 1: Setup Termux

Buka Termux, jalankan:

```bash
# Update package
pkg update && pkg upgrade -y

# Install git
pkg install -y git

# Izinkan akses storage (ketuk Allow jika muncul popup)
termux-setup-storage
```

### Langkah 2: Download Skrip Installer

```bash
# Clone repositori ini
git clone https://github.com/lydia2802/Pegasus-Lacak-Nomor.git
cd Pegasus-Lacak-Nomor/termux

# Berikan izin eksekusi
chmod +x install-supabase-termux.sh
chmod +x supabase-termux-manager.sh

# Jalankan installer
bash install-supabase-termux.sh
```

---

## DUA METODE INSTALASI

### Metode A: Native Termux (Direkomendasikan untuk pemula)

**Cocok untuk:** HP dengan RAM 2-3GB, tidak butuh Docker

**Yang diinstall:**
- PostgreSQL (database)
- PostgREST (API otomatis)
- Supabase CLI

```bash
# Pilih opsi [2] saat installer berjalan
bash install-supabase-termux.sh
# → Pilih: 2 (Native Termux)
```

**Setelah install, start dengan:**
```bash
bash ~/supabase-start.sh
```

**Akses:**
- Database: `postgresql://localhost:5432/supabase`
- REST API: `http://localhost:3001`

---

### Metode B: proot-distro + Docker (Fitur Lengkap)

**Cocok untuk:** HP dengan RAM 4GB+, butuh Studio dashboard

**Yang diinstall:**
- proot-distro (emulasi Linux)
- Ubuntu di dalam Termux
- Docker + Docker Compose
- Supabase lengkap (semua services)

```bash
# Pilih opsi [1] saat installer berjalan
bash install-supabase-termux.sh
# → Pilih: 1 (proot-distro + Docker)
```

**Setelah install:**
```bash
bash ~/supabase-start.sh
```

**Akses:**
- Supabase Studio: `http://localhost:3000`
- REST API: `http://localhost:8000`
- Database: `postgresql://localhost:5432/postgres`

---

## MENGGUNAKAN MANAGER

```bash
# Buka menu manager interaktif
bash supabase-termux-manager.sh
```

Menu yang tersedia:
```
[1] Start Supabase (Native)
[2] Stop Supabase (Native)
[3] Start Supabase (Docker)
[4] Stop Supabase (Docker)
[5] Buka PostgreSQL console
[6] Buat tabel test
[7] Tampilkan credentials
[8] Test koneksi API
[9] Tampilkan logs
```

---

## MENGGUNAKAN DATABASE

### Via psql (command line)

```bash
# Buka konsol database
psql -d supabase

# Contoh perintah:
CREATE TABLE todos (
    id SERIAL PRIMARY KEY,
    task TEXT,
    done BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

INSERT INTO todos (task) VALUES ('Belajar Supabase'), ('Deploy app');
SELECT * FROM todos;
\q
```

### Via REST API (PostgREST)

```bash
# Ambil semua data
curl http://localhost:3001/todos

# Filter data
curl "http://localhost:3001/todos?done=eq.false"

# Insert data
curl -X POST http://localhost:3001/todos \
  -H "Content-Type: application/json" \
  -d '{"task": "Task baru", "done": false}'

# Update data
curl -X PATCH "http://localhost:3001/todos?id=eq.1" \
  -H "Content-Type: application/json" \
  -d '{"done": true}'

# Delete data
curl -X DELETE "http://localhost:3001/todos?id=eq.1"
```

### Via Python (pakai client bawaan)

```python
from supabase_client_android import SupabaseTermux

# Koneksi
sb = SupabaseTermux(url="http://localhost:3001")

# Query
todos = sb.from_table("todos").select("*").eq("done", False).execute()
print(todos)

# Insert
sb.from_table("todos").insert({"task": "Task baru"}).execute()

# Update
sb.from_table("todos").eq("id", 1).update({"done": True}).execute()
```

---

## KONEKSI DARI APLIKASI ANDROID

Jika menggunakan Supabase di Termux sebagai backend untuk app Android:

### Flutter / Dart

```dart
import 'package:supabase_flutter/supabase_flutter.dart';

await Supabase.initialize(
  url: 'http://10.0.2.2:8000',  // emulator
  // atau: 'http://192.168.x.x:8000'  // IP HP di WiFi lokal
  anonKey: 'your-anon-key',
);
```

### JavaScript / React Native

```javascript
import { createClient } from '@supabase/supabase-js'

const supabase = createClient(
  'http://192.168.x.x:8000',  // IP HP di WiFi
  'your-anon-key'
)
```

### Cara cari IP HP:
```bash
# Di Termux
ifconfig | grep 'inet ' | grep -v '127.0.0'
# atau
ip addr show wlan0 | grep inet
```

---

## TIPS & TROUBLESHOOTING

### PostgreSQL tidak mau start

```bash
# Hapus lock file lama
rm -f $PREFIX/var/lib/postgresql/postmaster.pid

# Cek log error
cat $PREFIX/var/log/postgresql.log

# Init ulang (HATI-HATI: menghapus semua data!)
rm -rf $PREFIX/var/lib/postgresql
initdb $PREFIX/var/lib/postgresql
```

### Port sudah dipakai

```bash
# Cek proses yang pakai port 5432
lsof -i :5432
# atau
netstat -tlnp | grep 5432

# Kill proses
kill -9 <PID>
```

### proot-distro error

```bash
# Reset Ubuntu
proot-distro reset ubuntu

# Install ulang
proot-distro remove ubuntu
proot-distro install ubuntu
```

### Docker tidak bisa start di proot

Beberapa HP Android tidak mendukung Docker di proot karena kernel tidak memiliki cgroups v2. Gunakan Metode Native (PostgreSQL langsung) sebagai alternatif.

### Cek apakah HP support Docker

```bash
# Di dalam proot Ubuntu
proot-distro login ubuntu -- bash -c "
    cat /proc/sys/kernel/dmesg_restrict
    ls /sys/fs/cgroup/
"
```

---

## BACKUP & RESTORE DATABASE

```bash
# Backup
pg_dump supabase > ~/supabase-backup-$(date +%Y%m%d).sql

# Restore
psql supabase < ~/supabase-backup-2024xxxx.sql

# Backup otomatis (tambah ke crontab)
echo "0 2 * * * pg_dump supabase > ~/backups/supabase-\$(date +\%Y\%m\%d).sql" >> ~/.bashrc
```

---

## OTOMATIS START SAAT TERMUX DIBUKA

```bash
# Tambah ke ~/.bashrc
echo 'bash ~/supabase-start.sh' >> ~/.bashrc

# Atau buat shortcut
cat > ~/.termux/shortcuts/start-supabase.sh << 'EOF'
bash ~/supabase-start.sh
EOF
chmod +x ~/.termux/shortcuts/start-supabase.sh
```

---

## STRUKTUR FILE

```
termux/
├── install-supabase-termux.sh    # Installer utama
├── supabase-termux-manager.sh    # Menu manager interaktif
├── supabase-client-android.py    # Python client untuk Supabase
└── PANDUAN-SUPABASE-TERMUX.md    # Panduan ini
```

---

## REFERENSI

- Supabase Docs: https://supabase.com/docs
- Supabase GitHub: https://github.com/supabase/supabase
- Termux Wiki: https://wiki.termux.com
- PostgREST Docs: https://postgrest.org/en/stable/

---

> **Catatan:** Supabase di Termux cocok untuk development dan testing.
> Untuk production, gunakan Supabase Cloud (supabase.com) atau VPS.
