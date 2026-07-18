#!/usr/bin/env python3
"""DJ Mixer backend — stdlib only: http.server + sqlite3."""
import http.server, json, sqlite3, os, mimetypes, uuid, io, subprocess, urllib.parse

DB = os.path.join(os.path.dirname(__file__), 'dj.db')
SAMPLES = os.path.join(os.path.dirname(__file__), 'samples')
os.makedirs(SAMPLES, exist_ok=True)

def get_db():
    conn = sqlite3.connect(DB)
    conn.row_factory = sqlite3.Row
    conn.execute('''CREATE TABLE IF NOT EXISTS tracks(
        id TEXT PRIMARY KEY, name TEXT, path TEXT, duration REAL, format TEXT, created TEXT DEFAULT CURRENT_TIMESTAMP
    )''')
    conn.execute('''CREATE TABLE IF NOT EXISTS playlists(
        id TEXT PRIMARY KEY, name TEXT, created TEXT DEFAULT CURRENT_TIMESTAMP
    )''')
    conn.execute('''CREATE TABLE IF NOT EXISTS playlist_tracks(
        playlist_id TEXT, track_id TEXT, position INTEGER,
        FOREIGN KEY(playlist_id) REFERENCES playlists(id),
        FOREIGN KEY(track_id) REFERENCES tracks(id)
    )''')
    return conn

def extract_duration(path):
    try:
        r = subprocess.run(['ffprobe','-v','error','-show_entries','format=duration',
            '-of','default=noprint_wrappers=1:nokey=1', path], capture_output=True, text=True, timeout=10)
        if r.returncode == 0 and r.stdout.strip():
            return float(r.stdout.strip())
    except: pass
    return 0.0

class Handler(http.server.SimpleHTTPRequestHandler):
    def do_OPTIONS(self):
        self.send_response(204)
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Access-Control-Allow-Methods', 'GET,POST,DELETE,OPTIONS')
        self.send_header('Access-Control-Allow-Headers', 'Content-Type')
        self.end_headers()

    def do_GET(self):
        parsed = urllib.parse.urlparse(self.path)
        path = parsed.path.rstrip('/') or '/'

        if path == '/api/tracks':
            conn = get_db()
            rows = conn.execute('SELECT id,name,duration,format,created FROM tracks ORDER BY created DESC').fetchall()
            conn.close()
            return self._json([dict(r) for r in rows])

        if path == '/api/playlists':
            conn = get_db()
            pls = conn.execute('SELECT * FROM playlists ORDER BY created DESC').fetchall()
            result = []
            for pl in pls:
                tracks = conn.execute('''SELECT t.id,t.name,t.duration,t.format FROM playlist_tracks pt
                    JOIN tracks t ON pt.track_id=t.id WHERE pt.playlist_id=? ORDER BY pt.position''', (pl['id'],)).fetchall()
                result.append({**dict(pl), 'tracks': [dict(t) for t in tracks]})
            conn.close()
            return self._json(result)

        if path.startswith('/api/tracks/stream/'):
            track_id = path.split('/')[-1]
            conn = get_db()
            row = conn.execute('SELECT path FROM tracks WHERE id=?', (track_id,)).fetchone()
            conn.close()
            if not row or not os.path.exists(row['path']):
                return self.send_error(404)
            filepath = row['path']
            filesize = os.path.getsize(filepath)
            self.send_response(200)
            self.send_header('Content-Type', mimetypes.guess_type(filepath)[0] or 'audio/mpeg')
            self.send_header('Content-Length', str(filesize))
            self.send_header('Accept-Ranges', 'bytes')
            self.end_headers()
            with open(filepath, 'rb') as f:
                self.wfile.write(f.read())
            return

        return super().do_GET()

    def do_POST(self):
        parsed = urllib.parse.urlparse(self.path)
        path = parsed.path.rstrip('/')
        content_len = int(self.headers.get('Content-Length', 0))
        body = self.rfile.read(content_len) if content_len else b''

        if path == '/api/upload':
            content_type = self.headers.get('Content-Type', '')
            if 'multipart/form-data' in content_type:
                import cgi
                env = {'REQUEST_METHOD':'POST','CONTENT_TYPE':content_type}
                fs = cgi.FieldStorage(fp=io.BytesIO(body), headers=self.headers, environ=env)
                item = fs['file']
                orig_name = item.filename or 'unknown'
                ext = os.path.splitext(orig_name)[1] or '.mp3'
                track_id = str(uuid.uuid4())
                dest = os.path.join(SAMPLES, f'{track_id}{ext}')
                with open(dest, 'wb') as f:
                    f.write(item.file.read())
            else:
                orig_name = self.headers.get('X-Filename', 'unknown')
                ext = os.path.splitext(orig_name)[1] or '.mp3'
                track_id = str(uuid.uuid4())
                dest = os.path.join(SAMPLES, f'{track_id}{ext}')
                with open(dest, 'wb') as f:
                    f.write(body)

            duration = extract_duration(dest)
            conn = get_db()
            conn.execute('INSERT INTO tracks (id,name,path,duration,format) VALUES (?,?,?,?,?)',
                (track_id, orig_name, dest, duration, ext[1:]))
            pl = conn.execute('SELECT id FROM playlists WHERE name=?', ('All tracks',)).fetchone()
            if not pl:
                pl_id = str(uuid.uuid4())
                conn.execute('INSERT INTO playlists (id,name) VALUES (?,?)', (pl_id, 'All tracks'))
                pl = {'id': pl_id}
            max_pos = conn.execute('SELECT COALESCE(MAX(position),-1) FROM playlist_tracks WHERE playlist_id=?', (pl['id'],)).fetchone()[0]
            conn.execute('INSERT OR IGNORE INTO playlist_tracks (playlist_id,track_id,position) VALUES (?,?,?)',
                (pl['id'], track_id, max_pos + 1))
            conn.commit()
            conn.close()
            return self._json({'id': track_id, 'name': orig_name, 'duration': duration, 'format': ext[1:]})

        if path == '/api/tracks':
            data = json.loads(body.decode())
            track_id, new_name = data.get('id'), data.get('name')
            if track_id and new_name:
                conn = get_db()
                conn.execute('UPDATE tracks SET name=? WHERE id=?', (new_name, track_id))
                conn.commit(); conn.close()
                return self._json({'ok': True})

        if path == '/api/playlists':
            data = json.loads(body.decode())
            name = data.get('name', 'New Playlist')
            pl_id = str(uuid.uuid4())
            conn = get_db()
            conn.execute('INSERT INTO playlists (id,name) VALUES (?,?)', (pl_id, name))
            conn.commit(); conn.close()
            return self._json({'id': pl_id, 'name': name})

        if path == '/api/playlist/add':
            data = json.loads(body.decode())
            pl_id, track_id = data.get('playlist_id'), data.get('track_id')
            if pl_id and track_id:
                conn = get_db()
                max_pos = conn.execute('SELECT COALESCE(MAX(position),-1) FROM playlist_tracks WHERE playlist_id=?', (pl_id,)).fetchone()[0]
                conn.execute('INSERT OR IGNORE INTO playlist_tracks (playlist_id,track_id,position) VALUES (?,?,?)',
                    (pl_id, track_id, max_pos + 1))
                conn.commit(); conn.close()
                return self._json({'ok': True})

        if path == '/api/playlist/remove':
            data = json.loads(body.decode())
            pl_id, track_id = data.get('playlist_id'), data.get('track_id')
            if pl_id and track_id:
                conn = get_db()
                conn.execute('DELETE FROM playlist_tracks WHERE playlist_id=? AND track_id=?', (pl_id, track_id))
                conn.commit(); conn.close()
                return self._json({'ok': True})

        self.send_error(405)

    def do_DELETE(self):
        parsed = urllib.parse.urlparse(self.path)
        path = parsed.path.rstrip('/')
        if path.startswith('/api/tracks/'):
            track_id = path.split('/')[-1]
            conn = get_db()
            row = conn.execute('SELECT path FROM tracks WHERE id=?', (track_id,)).fetchone()
            if row:
                conn.execute('DELETE FROM playlist_tracks WHERE track_id=?', (track_id,))
                conn.execute('DELETE FROM tracks WHERE id=?', (track_id,))
                conn.commit()
                try: os.remove(row['path'])
                except: pass
            conn.close()
            return self._json({'ok': True})
        self.send_error(405)

    def _json(self, data, status=200):
        body = json.dumps(data).encode()
        self.send_response(status)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, format, *args):
        pass

if __name__ == '__main__':
    port = int(os.environ.get('PORT', 8765))
    server = http.server.HTTPServer(('0.0.0.0', port), Handler)
    print(f'DJ Mixer backend at http://localhost:{port}')
    print(f'API: GET  /api/tracks  GET /api/playlists  POST /api/upload')
    print(f'     POST /api/tracks  DELETE /api/tracks/<id>')
    server.serve_forever()
