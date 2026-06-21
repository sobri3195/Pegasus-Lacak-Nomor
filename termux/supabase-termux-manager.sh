#!/data/data/com.termux/files/usr/bin/bash

# ============================================================
# SUPABASE TERMUX MANAGER - Menu interaktif untuk kelola Supabase
# ============================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

PROOT_MODE=false
NATIVE_MODE=false

detect_mode() {
    if command -v proot-distro &>/dev/null && proot-distro list 2>/dev/null | grep -q "ubuntu.*installed"; then
        PROOT_MODE=true
    fi
    if command -v pg_ctl &>/dev/null || pkg list-installed 2>/dev/null | grep -q "postgresql"; then
        NATIVE_MODE=true
    fi
}

banner() {
    clear
    echo -e "${BLUE}"
    echo "╔══════════════════════════════════════════════════════╗"
    echo "║        SUPABASE TERMUX MANAGER                      ║"
    echo "╠══════════════════════════════════════════════════════╣"
    if $PROOT_MODE; then
        echo -e "║  Mode: ${GREEN}proot-distro + Docker${BLUE}                        ║"
    fi
    if $NATIVE_MODE; then
        echo -e "║  Mode: ${GREEN}Native PostgreSQL${BLUE}                            ║"
    fi
    echo "╚══════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

status_services() {
    echo -e "${CYAN}=== Status Services ===${NC}"
    echo ""

    # PostgreSQL
    if command -v pg_isready &>/dev/null; then
        if pg_isready -q 2>/dev/null; then
            echo -e "  PostgreSQL  : ${GREEN}RUNNING${NC} (port 5432)"
        else
            echo -e "  PostgreSQL  : ${RED}STOPPED${NC}"
        fi
    fi

    # PostgREST
    if [ -f "$HOME/postgrest.pid" ]; then
        PID=$(cat "$HOME/postgrest.pid")
        if kill -0 "$PID" 2>/dev/null; then
            echo -e "  PostgREST   : ${GREEN}RUNNING${NC} (port 3001, PID: $PID)"
        else
            echo -e "  PostgREST   : ${RED}STOPPED${NC} (stale PID file)"
            rm "$HOME/postgrest.pid"
        fi
    else
        echo -e "  PostgREST   : ${YELLOW}NOT STARTED${NC}"
    fi

    # Docker (via proot)
    if $PROOT_MODE; then
        DOCKER_STATUS=$(proot-distro login ubuntu -- docker info &>/dev/null && echo "RUNNING" || echo "STOPPED")
        if [ "$DOCKER_STATUS" = "RUNNING" ]; then
            echo -e "  Docker      : ${GREEN}RUNNING${NC}"
            echo ""
            echo -e "  ${CYAN}Supabase containers:${NC}"
            proot-distro login ubuntu -- docker compose -f /opt/supabase/docker-compose.yml ps 2>/dev/null | \
                grep -E "supabase|studio|kong" | \
                awk '{printf "    %-20s %s\n", $1, $NF}' || echo "    (tidak ada container aktif)"
        else
            echo -e "  Docker      : ${RED}STOPPED${NC}"
        fi
    fi

    echo ""
}

start_native() {
    echo -e "${GREEN}Memulai Supabase Native...${NC}"

    # PostgreSQL
    if ! pg_isready -q 2>/dev/null; then
        echo "  Starting PostgreSQL..."
        pg_ctl -D "$PREFIX/var/lib/postgresql" start \
            -l "$PREFIX/var/log/postgresql.log" -o "-k /data/data/com.termux/files/usr/tmp" &
        sleep 3
        if pg_isready -q 2>/dev/null; then
            echo -e "  PostgreSQL ${GREEN}OK${NC}"
        else
            echo -e "  PostgreSQL ${RED}GAGAL${NC} - cek log: $PREFIX/var/log/postgresql.log"
        fi
    else
        echo -e "  PostgreSQL sudah ${GREEN}berjalan${NC}"
    fi

    # PostgREST
    if [ -f "$HOME/.local/bin/postgrest" ] && [ -f "$HOME/postgrest.conf" ]; then
        if [ ! -f "$HOME/postgrest.pid" ] || ! kill -0 "$(cat "$HOME/postgrest.pid")" 2>/dev/null; then
            echo "  Starting PostgREST..."
            nohup "$HOME/.local/bin/postgrest" "$HOME/postgrest.conf" \
                > "$HOME/postgrest.log" 2>&1 &
            echo $! > "$HOME/postgrest.pid"
            sleep 2
            echo -e "  PostgREST ${GREEN}OK${NC} → http://localhost:3001"
        else
            echo -e "  PostgREST sudah ${GREEN}berjalan${NC}"
        fi
    else
        echo -e "  PostgREST ${YELLOW}tidak terinstall${NC} (jalankan installer dulu)"
    fi

    echo ""
    echo -e "${GREEN}API URL: http://localhost:3001${NC}"
    echo -e "${GREEN}DB    : postgresql://localhost:5432/supabase${NC}"
}

stop_native() {
    echo -e "${YELLOW}Menghentikan Supabase Native...${NC}"

    if [ -f "$HOME/postgrest.pid" ]; then
        kill "$(cat "$HOME/postgrest.pid")" 2>/dev/null
        rm "$HOME/postgrest.pid"
        echo -e "  PostgREST ${GREEN}dihentikan${NC}"
    fi

    pg_ctl -D "$PREFIX/var/lib/postgresql" stop -m fast 2>/dev/null
    echo -e "  PostgreSQL ${GREEN}dihentikan${NC}"
}

start_docker() {
    echo -e "${GREEN}Memulai Supabase via Docker...${NC}"
    echo "  (Ini membutuhkan beberapa menit pertama kali)"
    proot-distro login ubuntu -- bash -c "
        if ! docker info &>/dev/null; then
            echo '  Starting Docker daemon...'
            nohup dockerd > /tmp/docker.log 2>&1 &
            sleep 8
        fi
        cd /opt/supabase
        docker compose up -d
        echo ''
        echo 'Supabase containers:'
        docker compose ps
    "
    echo ""
    echo -e "${GREEN}Studio  : http://localhost:3000${NC}"
    echo -e "${GREEN}API     : http://localhost:8000${NC}"
}

stop_docker() {
    echo -e "${YELLOW}Menghentikan Supabase Docker...${NC}"
    proot-distro login ubuntu -- bash -c "
        cd /opt/supabase
        docker compose down
    "
    echo -e "  Docker services ${GREEN}dihentikan${NC}"
}

show_credentials() {
    echo -e "${CYAN}=== Credentials ===${NC}"
    echo ""

    if [ -f "$HOME/.supabase-env" ]; then
        echo -e "${YELLOW}Native Mode:${NC}"
        cat "$HOME/.supabase-env"
        echo ""
    fi

    if $PROOT_MODE; then
        echo -e "${YELLOW}Docker Mode:${NC}"
        proot-distro login ubuntu -- cat /opt/supabase/credentials.txt 2>/dev/null || \
            echo "  (credentials belum dibuat, jalankan installer)"
    fi
}

open_psql() {
    echo -e "${CYAN}Membuka PostgreSQL console...${NC}"
    if pg_isready -q 2>/dev/null; then
        psql -d supabase
    else
        echo -e "${RED}PostgreSQL tidak berjalan. Start dulu!${NC}"
    fi
}

test_api() {
    echo -e "${CYAN}=== Test API Connection ===${NC}"
    echo ""

    # Test native PostgREST
    echo "Testing PostgREST (port 3001)..."
    if curl -sf http://localhost:3001/ -o /dev/null 2>/dev/null; then
        echo -e "  PostgREST : ${GREEN}OK${NC}"
        echo "  Response:"
        curl -s http://localhost:3001/ | python3 -m json.tool 2>/dev/null | head -20
    else
        echo -e "  PostgREST : ${RED}tidak merespons${NC}"
    fi

    echo ""

    # Test Docker Supabase API
    echo "Testing Supabase Docker API (port 8000)..."
    if curl -sf http://localhost:8000/rest/v1/ -o /dev/null 2>/dev/null; then
        echo -e "  Supabase API : ${GREEN}OK${NC}"
    else
        echo -e "  Supabase API : ${RED}tidak merespons${NC}"
    fi
}

create_test_table() {
    echo -e "${CYAN}Membuat tabel test di database...${NC}"
    if pg_isready -q 2>/dev/null; then
        psql -d supabase << 'SQL'
CREATE TABLE IF NOT EXISTS public.test_table (
    id SERIAL PRIMARY KEY,
    nama VARCHAR(100),
    created_at TIMESTAMPTZ DEFAULT NOW()
);

INSERT INTO public.test_table (nama) VALUES
    ('Test Data 1'),
    ('Test Data 2'),
    ('Supabase on Termux OK!');

SELECT * FROM public.test_table;
SQL
        echo ""
        echo -e "${GREEN}Tabel test berhasil dibuat!${NC}"
        echo "Akses via API: curl http://localhost:3001/test_table"
    else
        echo -e "${RED}PostgreSQL tidak berjalan${NC}"
    fi
}

show_logs() {
    echo -e "${CYAN}=== Logs ===${NC}"
    echo ""
    echo "[PostgreSQL]"
    tail -20 "$PREFIX/var/log/postgresql.log" 2>/dev/null || echo "  (tidak ada log)"
    echo ""
    echo "[PostgREST]"
    tail -20 "$HOME/postgrest.log" 2>/dev/null || echo "  (tidak ada log)"
}

update_supabase() {
    echo -e "${YELLOW}Update Supabase...${NC}"
    if $PROOT_MODE; then
        proot-distro login ubuntu -- bash -c "
            cd /opt/supabase
            docker compose pull
            docker compose up -d
        "
        echo -e "${GREEN}Supabase Docker diupdate${NC}"
    fi

    # Update Supabase CLI
    if [ -f "$HOME/.local/bin/supabase" ]; then
        echo "Update Supabase CLI..."
        ARCH=$(uname -m)
        case "$ARCH" in
            aarch64|arm64) CLI_ARCH="arm64" ;;
            x86_64) CLI_ARCH="amd64" ;;
        esac
        CLI_VER=$(curl -s https://api.github.com/repos/supabase/cli/releases/latest 2>/dev/null | grep '"tag_name"' | cut -d'"' -f4)
        curl -fsSL "https://github.com/supabase/cli/releases/download/${CLI_VER}/supabase_linux_${CLI_ARCH}.tar.gz" \
            -o /tmp/supabase-cli.tar.gz && \
            tar -xzf /tmp/supabase-cli.tar.gz -C "$HOME/.local/bin/" supabase && \
            rm /tmp/supabase-cli.tar.gz
        echo -e "${GREEN}Supabase CLI diupdate ke ${CLI_VER}${NC}"
    fi
}

main_menu() {
    detect_mode
    while true; do
        banner
        status_services
        echo -e "${CYAN}=== MENU ===${NC}"
        echo ""
        echo "  KONTROL:"
        echo "  [1] Start Supabase (Native PostgreSQL)"
        echo "  [2] Stop Supabase (Native)"
        if $PROOT_MODE; then
            echo "  [3] Start Supabase (Docker/Full)"
            echo "  [4] Stop Supabase (Docker)"
        fi
        echo ""
        echo "  DATABASE:"
        echo "  [5] Buka PostgreSQL console (psql)"
        echo "  [6] Buat tabel test"
        echo ""
        echo "  INFO:"
        echo "  [7] Tampilkan credentials"
        echo "  [8] Test koneksi API"
        echo "  [9] Tampilkan logs"
        echo "  [u] Update Supabase"
        echo "  [q] Keluar"
        echo ""
        read -r -p "Pilihan: " opt

        case "$opt" in
            1) start_native; read -r -p "Tekan Enter..." ;;
            2) stop_native; read -r -p "Tekan Enter..." ;;
            3) $PROOT_MODE && start_docker || echo "proot-distro tidak tersedia"; read -r -p "Tekan Enter..." ;;
            4) $PROOT_MODE && stop_docker || echo "proot-distro tidak tersedia"; read -r -p "Tekan Enter..." ;;
            5) open_psql ;;
            6) create_test_table; read -r -p "Tekan Enter..." ;;
            7) show_credentials; read -r -p "Tekan Enter..." ;;
            8) test_api; read -r -p "Tekan Enter..." ;;
            9) show_logs; read -r -p "Tekan Enter..." ;;
            u|U) update_supabase; read -r -p "Tekan Enter..." ;;
            q|Q) echo "Keluar."; exit 0 ;;
            *) echo "Pilihan tidak valid" ;;
        esac
    done
}

main_menu
