#!/usr/bin/env python3
"""
Supabase Client untuk Android Termux
Menggunakan REST API langsung (tanpa SDK resmi yang butuh npm install)
"""

import json
import urllib.request
import urllib.error
import urllib.parse
import os
import sys
from datetime import datetime


class SupabaseTermux:
    """Client Supabase ringan untuk Termux Android."""

    def __init__(self, url: str = None, anon_key: str = None):
        self.url = (url or os.getenv("SUPABASE_URL", "http://localhost:8000")).rstrip("/")
        self.anon_key = anon_key or os.getenv("SUPABASE_ANON_KEY", "")
        self.auth_token = None
        self.headers = {
            "Content-Type": "application/json",
            "apikey": self.anon_key,
        }

    def _request(self, method: str, path: str, data=None, extra_headers=None):
        url = f"{self.url}{path}"
        headers = {**self.headers}

        if self.auth_token:
            headers["Authorization"] = f"Bearer {self.auth_token}"

        if extra_headers:
            headers.update(extra_headers)

        body = json.dumps(data).encode() if data else None
        req = urllib.request.Request(url, data=body, headers=headers, method=method)

        try:
            with urllib.request.urlopen(req, timeout=10) as resp:
                content = resp.read().decode()
                return json.loads(content) if content else {}
        except urllib.error.HTTPError as e:
            err_body = e.read().decode()
            raise Exception(f"HTTP {e.code}: {err_body}")
        except urllib.error.URLError as e:
            raise Exception(f"Koneksi gagal: {e.reason}\nPastikan Supabase sudah berjalan!")

    # =============================
    # AUTH
    # =============================
    def sign_up(self, email: str, password: str) -> dict:
        """Daftar user baru."""
        result = self._request("POST", "/auth/v1/signup", {
            "email": email,
            "password": password
        })
        if result.get("access_token"):
            self.auth_token = result["access_token"]
        return result

    def sign_in(self, email: str, password: str) -> dict:
        """Login user."""
        result = self._request("POST", "/auth/v1/token?grant_type=password", {
            "email": email,
            "password": password
        })
        if result.get("access_token"):
            self.auth_token = result["access_token"]
            print(f"Login berhasil sebagai: {email}")
        return result

    def sign_out(self):
        """Logout user."""
        self._request("POST", "/auth/v1/logout")
        self.auth_token = None
        print("Logout berhasil")

    def get_user(self) -> dict:
        """Ambil data user yang login."""
        return self._request("GET", "/auth/v1/user")

    # =============================
    # DATABASE (PostgREST)
    # =============================
    def from_table(self, table: str) -> "QueryBuilder":
        """Mulai query ke tabel."""
        return QueryBuilder(self, table)

    # =============================
    # STORAGE
    # =============================
    def upload_file(self, bucket: str, path: str, file_path: str) -> dict:
        """Upload file ke Supabase Storage."""
        with open(file_path, "rb") as f:
            content = f.read()

        headers = {**self.headers, "Content-Type": "application/octet-stream"}
        if self.auth_token:
            headers["Authorization"] = f"Bearer {self.auth_token}"

        url = f"{self.url}/storage/v1/object/{bucket}/{path}"
        req = urllib.request.Request(url, data=content, headers=headers, method="POST")

        with urllib.request.urlopen(req, timeout=30) as resp:
            return json.loads(resp.read().decode())

    def get_public_url(self, bucket: str, path: str) -> str:
        """Dapatkan URL publik file."""
        return f"{self.url}/storage/v1/object/public/{bucket}/{path}"

    # =============================
    # REALTIME (polling sederhana)
    # =============================
    def subscribe_table(self, table: str, callback, interval: float = 2.0):
        """Subscribe perubahan tabel dengan polling."""
        import time
        print(f"Subscribe ke tabel '{table}' (polling setiap {interval}s)...")
        last_data = None
        try:
            while True:
                current = self.from_table(table).select("*").execute()
                if current != last_data:
                    callback(current)
                    last_data = current
                time.sleep(interval)
        except KeyboardInterrupt:
            print("\nSubscription dihentikan")


class QueryBuilder:
    """Builder untuk query database."""

    def __init__(self, client: SupabaseTermux, table: str):
        self.client = client
        self.table = table
        self._select = "*"
        self._filters = []
        self._order = None
        self._limit = None
        self._offset = None
        self._method = "GET"
        self._data = None

    def select(self, columns: str = "*") -> "QueryBuilder":
        self._select = columns
        return self

    def eq(self, column: str, value) -> "QueryBuilder":
        self._filters.append(f"{column}=eq.{value}")
        return self

    def neq(self, column: str, value) -> "QueryBuilder":
        self._filters.append(f"{column}=neq.{value}")
        return self

    def gt(self, column: str, value) -> "QueryBuilder":
        self._filters.append(f"{column}=gt.{value}")
        return self

    def lt(self, column: str, value) -> "QueryBuilder":
        self._filters.append(f"{column}=lt.{value}")
        return self

    def like(self, column: str, pattern: str) -> "QueryBuilder":
        self._filters.append(f"{column}=like.{pattern}")
        return self

    def ilike(self, column: str, pattern: str) -> "QueryBuilder":
        self._filters.append(f"{column}=ilike.{pattern}")
        return self

    def order(self, column: str, desc: bool = False) -> "QueryBuilder":
        self._order = f"{column}.{'desc' if desc else 'asc'}"
        return self

    def limit(self, count: int) -> "QueryBuilder":
        self._limit = count
        return self

    def offset(self, start: int) -> "QueryBuilder":
        self._offset = start
        return self

    def insert(self, data: dict) -> "QueryBuilder":
        self._method = "POST"
        self._data = data
        return self

    def update(self, data: dict) -> "QueryBuilder":
        self._method = "PATCH"
        self._data = data
        return self

    def delete(self) -> "QueryBuilder":
        self._method = "DELETE"
        return self

    def upsert(self, data: dict) -> "QueryBuilder":
        self._method = "POST"
        self._data = data
        self._headers_extra = {"Prefer": "resolution=merge-duplicates"}
        return self

    def execute(self):
        params = [f"select={self._select}"]
        params.extend(self._filters)
        if self._order:
            params.append(f"order={self._order}")
        if self._limit is not None:
            params.append(f"limit={self._limit}")
        if self._offset is not None:
            params.append(f"offset={self._offset}")

        query = "&".join(params)
        path = f"/rest/v1/{self.table}?{query}"

        extra = getattr(self, "_headers_extra", None)
        if self._method in ("POST", "PATCH"):
            extra = (extra or {})
            extra["Prefer"] = extra.get("Prefer", "return=representation")

        return self.client._request(self._method, path, self._data, extra)


# =============================
# DEMO / TEST
# =============================
def demo():
    print("=" * 50)
    print("  SUPABASE TERMUX CLIENT - DEMO")
    print("=" * 50)
    print()

    # Coba koneksi ke localhost
    sb_url = os.getenv("SUPABASE_URL", "http://localhost:3001")
    sb_key = os.getenv("SUPABASE_ANON_KEY", "")

    print(f"Koneksi ke: {sb_url}")
    sb = SupabaseTermux(url=sb_url, anon_key=sb_key)

    # Test koneksi
    try:
        result = sb.from_table("test_table").select("*").limit(5).execute()
        print(f"\nData dari test_table:")
        if isinstance(result, list):
            for row in result:
                print(f"  {row}")
        else:
            print(f"  {result}")
    except Exception as e:
        print(f"\nKoneksi gagal: {e}")
        print("\nPastikan:")
        print("  1. Jalankan: bash ~/supabase-start.sh")
        print("  2. Set SUPABASE_URL=http://localhost:3001")
        print("  3. Atau gunakan URL Supabase cloud")
        return

    # Insert data
    print("\nInsert data baru...")
    try:
        result = sb.from_table("test_table").insert({
            "nama": f"Test dari Android {datetime.now().strftime('%H:%M:%S')}"
        }).execute()
        print(f"  Inserted: {result}")
    except Exception as e:
        print(f"  Insert gagal: {e}")

    print("\nDemo selesai!")


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "demo":
        demo()
    else:
        print("Supabase Termux Client")
        print("Penggunaan: python3 supabase-client-android.py demo")
        print()
        print("Atau import sebagai modul:")
        print("  from supabase_client_android import SupabaseTermux")
        print("  sb = SupabaseTermux('http://localhost:3001', 'your-anon-key')")
        print("  data = sb.from_table('users').select('*').execute()")
