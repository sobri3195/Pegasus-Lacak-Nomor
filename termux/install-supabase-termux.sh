#!/data/data/com.termux/files/usr/bin/bash

# ============================================================
# SUPABASE INSTALLER FOR ANDROID TERMUX
# Mendukung 2 metode: proot-distro (Docker) & Native Termux
# ============================================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

SUPABASE_DIR="$HOME/supabase"
LOG_FILE="$HOME/supabase-install.log"

log() { echo -e "${GREEN}[INFO]${NC} $1" | tee -a "$LOG_FILE"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1" | tee -a "$LOG_FILE"; }
error() { echo -e "${RED}[ERROR]${NC} $1" | tee -a "$LOG_FILE"; exit 1; }
info() { echo -e "${CYAN}[>>>]${NC} $1"; }

banner() {
    echo -e "${BLUE}"
    echo "╔══════════════════════════════════════════════════════╗"
    echo "║     SUPABASE INSTALLER - ANDROID TERMUX              ║"
    echo "║     Backend as a Service untuk Android               ║"
    echo "╚══════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

check_termux() {
    if [ ! -d "/data/data/com.termux" ]; then
        error "Skrip ini harus dijalankan di Termux Android!"
    fi
    log "Termux terdeteksi OK"
}

check_storage() {
    if [ ! -d "$HOME/storage" ]; then
        warn "Storage permission belum disetup"
        info "Menjalankan: termux-setup-storage"
        termux-setup-storage
        sleep 2
    fi
}

update_packages() {
    log "Update package Termux..."
    pkg update -y 2>&1 | tail -5
    pkg upgrade -y 2>&1 | tail -5
}

install_dependencies() {
    log "Install dependensi dasar..."
    local pkgs="curl wget git openssl python nodejs-lts binutils make clang"
    for pkg in $pkgs; do
        if ! pkg list-installed 2>/dev/null | grep -q "^$pkg"; then
            info "Install: $pkg"
            pkg install -y "$pkg" 2>&1 | tail -3
        else
            info "Sudah terinstall: $pkg"
        fi
    done
}

# ============================
# METODE 1: proot-distro + Docker
# ============================
setup_proot_method() {
    log "=== METODE 1: proot-distro (Ubuntu + Docker) ==="

    # Install proot-distro
    if ! command -v proot-distro &>/dev/null; then
        info "Install proot-distro..."
        pkg install -y proot-distro
    fi

    # Install Ubuntu jika belum ada
    if ! proot-distro list 2>/dev/null | grep -q "ubuntu.*installed"; then
        info "Install Ubuntu via proot-distro (proses ini memakan waktu ~5-10 menit)..."
        proot-distro install ubuntu
    else
        info "Ubuntu sudah terinstall"
    fi

    # Buat skrip setup di dalam Ubuntu
    cat > "$HOME/setup-ubuntu-supabase.sh" << 'UBUNTU_SCRIPT'
#!/bin/bash
set -e

GREEN='\033[0;32m'
NC='\033[0m'
log() { echo -e "${GREEN}[Ubuntu]${NC} $1"; }

log "Update Ubuntu packages..."
apt-get update -qq
apt-get install -y curl wget git ca-certificates gnupg lsb-release 2>&1 | tail -5

# Install Docker
log "Install Docker..."
if ! command -v docker &>/dev/null; then
    curl -fsSL https://get.docker.com -o /tmp/get-docker.sh
    sh /tmp/get-docker.sh 2>&1 | tail -10
    rm /tmp/get-docker.sh
fi

# Install Docker Compose
log "Install Docker Compose..."
if ! command -v docker compose &>/dev/null; then
    COMPOSE_VER=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | grep '"tag_name"' | cut -d'"' -f4)
    ARCH=$(uname -m)
    curl -SL "https://github.com/docker/compose/releases/download/${COMPOSE_VER}/docker-compose-linux-${ARCH}" \
        -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose
    ln -sf /usr/local/bin/docker-compose /usr/local/bin/docker compose
fi

# Download Supabase
log "Download Supabase..."
mkdir -p /opt/supabase
cd /opt/supabase

if [ ! -f "docker-compose.yml" ]; then
    curl -fsSL https://raw.githubusercontent.com/supabase/supabase/master/docker/docker-compose.yml \
        -o docker-compose.yml

    curl -fsSL https://raw.githubusercontent.com/supabase/supabase/master/docker/.env.example \
        -o .env
fi

# Generate secrets
log "Generate JWT secrets..."
JWT_SECRET=$(openssl rand -base64 32)
ANON_KEY=$(node -e "
const jwt = require('jsonwebtoken') || null;
// Fallback: generate random key
const crypto = require('crypto');
console.log(crypto.randomBytes(32).toString('hex'));
")
SERVICE_KEY=$(openssl rand -base64 48)
POSTGRES_PASSWORD=$(openssl rand -base64 24)
DASHBOARD_PASSWORD=$(openssl rand -base64 16 | tr -d '/+=' | head -c 16)

# Update .env
sed -i "s/POSTGRES_PASSWORD=.*/POSTGRES_PASSWORD=${POSTGRES_PASSWORD}/" .env
sed -i "s/JWT_SECRET=.*/JWT_SECRET=${JWT_SECRET}/" .env
sed -i "s/ANON_KEY=.*/ANON_KEY=${ANON_KEY}/" .env
sed -i "s/SERVICE_ROLE_KEY=.*/SERVICE_ROLE_KEY=${SERVICE_KEY}/" .env
sed -i "s/DASHBOARD_PASSWORD=.*/DASHBOARD_PASSWORD=${DASHBOARD_PASSWORD}/" .env

# Simpan credentials
cat > /opt/supabase/credentials.txt << EOF
============================
SUPABASE CREDENTIALS
============================
Postgres Password : ${POSTGRES_PASSWORD}
JWT Secret        : ${JWT_SECRET}
Anon Key          : ${ANON_KEY}
Service Role Key  : ${SERVICE_KEY}
Dashboard Password: ${DASHBOARD_PASSWORD}
============================
API URL           : http://localhost:8000
Studio URL        : http://localhost:3000
============================
EOF

log "Credentials disimpan di /opt/supabase/credentials.txt"
cat /opt/supabase/credentials.txt

log "Setup Ubuntu selesai!"
log "Jalankan 'start-docker.sh' untuk memulai Supabase"
UBUNTU_SCRIPT

    chmod +x "$HOME/setup-ubuntu-supabase.sh"

    # Jalankan setup di dalam Ubuntu
    info "Jalankan setup di dalam Ubuntu proot..."
    proot-distro login ubuntu -- bash "$HOME/setup-ubuntu-supabase.sh"

    # Buat skrip untuk start/stop via proot
    create_proot_scripts
}

create_proot_scripts() {
    # Script start Supabase (via proot)
    cat > "$HOME/supabase-start.sh" << 'EOF'
#!/data/data/com.termux/files/usr/bin/bash
echo "[Supabase] Memulai Docker daemon..."
proot-distro login ubuntu -- bash -c "
    # Start Docker daemon
    nohup dockerd > /tmp/docker.log 2>&1 &
    sleep 5

    echo 'Docker daemon dimulai'

    # Start Supabase
    cd /opt/supabase
    docker compose up -d

    echo ''
    echo '========================================='
    echo ' Supabase berhasil dimulai!'
    echo '========================================='
    echo ' Studio  : http://localhost:3000'
    echo ' API     : http://localhost:8000'
    echo ' Creds   : cat /opt/supabase/credentials.txt'
    echo '========================================='
"
EOF
    chmod +x "$HOME/supabase-start.sh"

    # Script stop Supabase
    cat > "$HOME/supabase-stop.sh" << 'EOF'
#!/data/data/com.termux/files/usr/bin/bash
echo "[Supabase] Menghentikan services..."
proot-distro login ubuntu -- bash -c "
    cd /opt/supabase
    docker compose down
    echo 'Supabase dihentikan'
"
EOF
    chmod +x "$HOME/supabase-stop.sh"

    # Script status
    cat > "$HOME/supabase-status.sh" << 'EOF'
#!/data/data/com.termux/files/usr/bin/bash
echo "[Supabase] Status services..."
proot-distro login ubuntu -- bash -c "
    cd /opt/supabase
    docker compose ps
"
EOF
    chmod +x "$HOME/supabase-status.sh"

    log "Scripts dibuat: supabase-start.sh, supabase-stop.sh, supabase-status.sh"
}

# ============================
# METODE 2: Native (PostgreSQL + PostgREST)
# ============================
setup_native_method() {
    log "=== METODE 2: Native Termux (PostgreSQL + PostgREST) ==="

    # Install PostgreSQL
    info "Install PostgreSQL..."
    pkg install -y postgresql

    # Install Node.js untuk Supabase CLI
    info "Install Node.js..."
    pkg install -y nodejs-lts npm

    # Setup PostgreSQL
    setup_postgresql

    # Install Supabase CLI
    setup_supabase_cli

    # Install PostgREST
    setup_postgrest

    create_native_scripts
}

setup_postgresql() {
    log "Setup PostgreSQL..."

    # Init database jika belum
    if [ ! -d "$PREFIX/var/lib/postgresql" ]; then
        initdb "$PREFIX/var/lib/postgresql"
        log "PostgreSQL database initialized"
    fi

    # Start PostgreSQL
    pg_ctl -D "$PREFIX/var/lib/postgresql" start -l "$PREFIX/var/log/postgresql.log" 2>/dev/null || true
    sleep 2

    # Buat database supabase
    createdb supabase 2>/dev/null || true
    createuser supabase_admin --superuser 2>/dev/null || true

    # Password untuk user
    POSTGRES_PASS=$(openssl rand -base64 16 | tr -d '/+=')
    psql -c "ALTER USER supabase_admin PASSWORD '${POSTGRES_PASS}';" 2>/dev/null || true
    psql -c "ALTER USER postgres PASSWORD '${POSTGRES_PASS}';" 2>/dev/null || true

    # Install ekstensi yang dibutuhkan Supabase
    psql -d supabase << 'PSQL'
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";
CREATE EXTENSION IF NOT EXISTS "pgjwt";

-- Buat schema dasar Supabase
CREATE SCHEMA IF NOT EXISTS auth;
CREATE SCHEMA IF NOT EXISTS storage;
CREATE SCHEMA IF NOT EXISTS extensions;
CREATE SCHEMA IF NOT EXISTS realtime;

-- Tabel users dasar
CREATE TABLE IF NOT EXISTS auth.users (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    email VARCHAR(255) UNIQUE NOT NULL,
    encrypted_password TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    email_confirmed_at TIMESTAMPTZ,
    last_sign_in_at TIMESTAMPTZ,
    raw_app_meta_data JSONB DEFAULT '{}',
    raw_user_meta_data JSONB DEFAULT '{}',
    is_super_admin BOOLEAN DEFAULT FALSE,
    role VARCHAR(255) DEFAULT 'authenticated'
);

-- Schema public untuk user data
CREATE SCHEMA IF NOT EXISTS public;
GRANT ALL ON SCHEMA public TO postgres;
GRANT ALL ON SCHEMA public TO public;
PSQL

    echo "POSTGRES_PASSWORD=${POSTGRES_PASS}" > "$HOME/.supabase-env"
    log "PostgreSQL dikonfigurasi. Password disimpan di ~/.supabase-env"
}

setup_supabase_cli() {
    log "Install Supabase CLI..."
    # Deteksi arsitektur
    ARCH=$(uname -m)
    case "$ARCH" in
        aarch64|arm64) CLI_ARCH="arm64" ;;
        x86_64) CLI_ARCH="amd64" ;;
        *) warn "Arsitektur $ARCH mungkin tidak didukung CLI"; return ;;
    esac

    # Download Supabase CLI binary
    CLI_VER=$(curl -s https://api.github.com/repos/supabase/cli/releases/latest 2>/dev/null | grep '"tag_name"' | cut -d'"' -f4 || echo "v1.166.7")
    CLI_URL="https://github.com/supabase/cli/releases/download/${CLI_VER}/supabase_linux_${CLI_ARCH}.tar.gz"

    info "Download Supabase CLI ${CLI_VER} untuk ${CLI_ARCH}..."
    mkdir -p "$HOME/.local/bin"

    if curl -fsSL "$CLI_URL" -o /tmp/supabase-cli.tar.gz 2>/dev/null; then
        tar -xzf /tmp/supabase-cli.tar.gz -C "$HOME/.local/bin/" supabase 2>/dev/null || \
        tar -xzf /tmp/supabase-cli.tar.gz -C "$HOME/.local/bin/" 2>/dev/null
        chmod +x "$HOME/.local/bin/supabase"
        rm /tmp/supabase-cli.tar.gz
        log "Supabase CLI terinstall: $(supabase --version 2>/dev/null || echo 'OK')"
    else
        warn "Gagal download Supabase CLI, skip..."
    fi

    # Tambah ke PATH
    if ! grep -q '.local/bin' "$HOME/.bashrc" 2>/dev/null; then
        echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.bashrc"
    fi
}

setup_postgrest() {
    log "Install PostgREST (API otomatis dari PostgreSQL)..."
    ARCH=$(uname -m)

    case "$ARCH" in
        aarch64|arm64)
            PGREST_URL="https://github.com/PostgREST/postgrest/releases/download/v12.0.2/postgrest-v12.0.2-linux-static-arm64.tar.xz"
            ;;
        x86_64)
            PGREST_URL="https://github.com/PostgREST/postgrest/releases/download/v12.0.2/postgrest-v12.0.2-linux-static-x64.tar.xz"
            ;;
        *)
            warn "PostgREST tidak tersedia untuk $ARCH"
            return
            ;;
    esac

    mkdir -p "$HOME/.local/bin"
    info "Download PostgREST..."

    if curl -fsSL "$PGREST_URL" -o /tmp/postgrest.tar.xz 2>/dev/null; then
        tar -xJf /tmp/postgrest.tar.xz -C "$HOME/.local/bin/" 2>/dev/null || true
        chmod +x "$HOME/.local/bin/postgrest" 2>/dev/null || true
        rm /tmp/postgrest.tar.xz
        log "PostgREST terinstall"
    else
        warn "Gagal download PostgREST"
    fi

    # Buat konfigurasi PostgREST
    source "$HOME/.supabase-env" 2>/dev/null || POSTGRES_PASSWORD="postgres"
    cat > "$HOME/postgrest.conf" << EOF
db-uri = "postgres://postgres:${POSTGRES_PASSWORD}@localhost:5432/supabase"
db-schemas = "public,auth,storage"
db-anon-role = "anon"
server-port = 3001
server-host = "127.0.0.1"
jwt-secret = "$(openssl rand -base64 32)"
log-level = "info"
EOF
    log "Konfigurasi PostgREST: ~/postgrest.conf"
}

create_native_scripts() {
    # Start script
    cat > "$HOME/supabase-start.sh" << 'EOF'
#!/data/data/com.termux/files/usr/bin/bash
echo "=============================="
echo " Memulai Supabase (Native)"
echo "=============================="

# Start PostgreSQL
if ! pg_isready -q 2>/dev/null; then
    echo "[1/3] Memulai PostgreSQL..."
    pg_ctl -D $PREFIX/var/lib/postgresql start \
        -l $PREFIX/var/log/postgresql.log
    sleep 2
fi

# Start PostgREST
if [ -f "$HOME/.local/bin/postgrest" ] && [ -f "$HOME/postgrest.conf" ]; then
    echo "[2/3] Memulai PostgREST API..."
    nohup postgrest "$HOME/postgrest.conf" > "$HOME/postgrest.log" 2>&1 &
    echo $! > "$HOME/postgrest.pid"
    sleep 1
fi

# Start simple HTTP server untuk Studio (opsional)
echo "[3/3] Setup selesai"

echo ""
echo "====================================="
echo " Supabase Native berhasil dimulai!"
echo "====================================="
echo " PostgreSQL : localhost:5432"
echo " PostgREST  : http://localhost:3001"
echo " Database   : supabase"
echo ""
echo " Credentials: cat ~/.supabase-env"
echo "====================================="
EOF
    chmod +x "$HOME/supabase-start.sh"

    # Stop script
    cat > "$HOME/supabase-stop.sh" << 'EOF'
#!/data/data/com.termux/files/usr/bin/bash
echo "Menghentikan Supabase..."

# Stop PostgREST
if [ -f "$HOME/postgrest.pid" ]; then
    kill $(cat "$HOME/postgrest.pid") 2>/dev/null && echo "PostgREST dihentikan"
    rm "$HOME/postgrest.pid"
fi

# Stop PostgreSQL
pg_ctl -D $PREFIX/var/lib/postgresql stop -m fast 2>/dev/null && echo "PostgreSQL dihentikan"
echo "Semua service dihentikan."
EOF
    chmod +x "$HOME/supabase-stop.sh"

    log "Scripts dibuat di $HOME/"
}

# ============================
# MENU UTAMA
# ============================
show_menu() {
    echo ""
    echo -e "${CYAN}Pilih metode instalasi:${NC}"
    echo ""
    echo "  [1] proot-distro + Docker  (Rekomendasi: fitur lengkap, butuh ~3GB ruang)"
    echo "      └─ Menjalankan Supabase resmi dengan semua komponen"
    echo ""
    echo "  [2] Native Termux           (Ringan: PostgreSQL + PostgREST, ~500MB)"
    echo "      └─ Database + REST API tanpa Docker"
    echo ""
    echo "  [3] Keduanya"
    echo "  [q] Keluar"
    echo ""
    read -r -p "Pilihan [1/2/3/q]: " choice
    echo "$choice"
}

main() {
    banner
    check_termux
    check_storage
    update_packages
    install_dependencies

    choice=$(show_menu)

    case "$choice" in
        1)
            setup_proot_method
            ;;
        2)
            setup_native_method
            ;;
        3)
            setup_proot_method
            setup_native_method
            ;;
        q|Q)
            echo "Keluar."
            exit 0
            ;;
        *)
            warn "Pilihan tidak valid, menggunakan metode native..."
            setup_native_method
            ;;
    esac

    echo ""
    echo -e "${GREEN}╔══════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║   INSTALASI SELESAI!                     ║${NC}"
    echo -e "${GREEN}╠══════════════════════════════════════════╣${NC}"
    echo -e "${GREEN}║  Mulai  : bash ~/supabase-start.sh       ║${NC}"
    echo -e "${GREEN}║  Stop   : bash ~/supabase-stop.sh        ║${NC}"
    echo -e "${GREEN}║  Status : bash ~/supabase-status.sh      ║${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════╝${NC}"
    echo ""
    log "Log tersimpan di: $LOG_FILE"
}

main "$@"
