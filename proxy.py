"""
CNC UI Proxy Server
- Serves static files on port 8888
- Proxies /websocket  → ws://192.168.1.130/websocket
- Proxies /api/*      → http://192.168.1.130/api/*
Tornado blocks cross-origin WebSockets, so we proxy from same origin.
"""

import asyncio
import os
import io
import json
import mimetypes
import zipfile
from aiohttp import web, ClientSession, WSMsgType

CNC_HOST    = os.environ.get('CNC_HOST', '192.168.1.130')
STATIC_DIR  = os.path.dirname(os.path.abspath(__file__))
PORT        = int(os.environ.get('PORT', 8888))
SETTINGS_FILE = os.path.join(STATIC_DIR, 'ui-settings.json')
UI_LOG_FILE   = os.path.join(STATIC_DIR, 'ui-actions.log')

NTFY_TOPIC  = os.environ.get('NTFY_TOPIC', 'alienwoodshop-cnc')
NTFY_URL    = f'https://ntfy.sh/{NTFY_TOPIC}'

# Keywords in ui-log lines that trigger a push notification
# Format: (match_string, title, priority, tags)
_NTFY_RULES = [
    ('START job',        'CNC Job Started',   'default', 'white_check_mark'),
    ('STOP job',         'CNC Job Stopped',   'default', 'stop_sign'),
    ('ESTOP TRIGGERED',  '🚨 E-STOP',         'urgent',  'rotating_light'),
    ('ESTOP CLEAR',      'E-Stop Cleared',    'low',     'green_circle'),
    ('CNC ERROR:',       'CNC Error',         'high',    'warning'),
    ('job complete',     'CNC Job Complete',  'high',    'tada'),
]

async def ntfy_send(title, message, priority='default', tags=''):
    """Fire-and-forget push notification via ntfy.sh."""
    try:
        async with ClientSession() as session:
            await session.post(
                NTFY_URL,
                data=message.encode('utf-8'),
                headers={
                    'Title':    title,
                    'Priority': priority,
                    'Tags':     tags,
                },
                timeout=5,
            )
    except Exception:
        pass  # never let notification failure affect the proxy


async def check_update(request):
    """Proxy GitHub releases to avoid CORS / SSL issues in older browsers.
    ?channel=nightly returns the full releases list (includes pre-releases).
    Default returns /releases/latest (stable only)."""
    nightly = request.query.get('channel') == 'nightly'
    url = ('https://api.github.com/repos/DRSwanger/rift-cnc-ui/releases'
           if nightly else
           'https://api.github.com/repos/DRSwanger/rift-cnc-ui/releases/latest')
    try:
        async with ClientSession() as session:
            async with session.get(
                url,
                headers={'Accept': 'application/vnd.github+json'},
                timeout=10,
            ) as resp:
                data = await resp.json()
                return web.json_response(data)
    except Exception as e:
        return web.json_response({'error': str(e)}, status=502)


async def download_update(request):
    """Download a GitHub release asset server-side and stream it back to the browser."""
    url = request.query.get('url', '')
    if not url.startswith('https://github.com/') and not url.startswith('https://objects.githubusercontent.com/'):
        return web.Response(status=400, text='Invalid URL')
    try:
        async with ClientSession() as session:
            async with session.get(url, timeout=120) as resp:
                if resp.status != 200:
                    return web.Response(status=resp.status, text='Upstream error')
                data = await resp.read()
                return web.Response(
                    body=data,
                    content_type='application/x-bzip2',
                    headers={'Content-Disposition': 'attachment; filename="firmware.tar.bz2"'}
                )
    except Exception as e:
        return web.Response(status=502, text=str(e))


async def handle(request):
    path = request.path

    # ── WebSocket proxy ──
    if path == '/websocket':
        ws_client = web.WebSocketResponse()
        await ws_client.prepare(request)
        async with ClientSession() as session:
            async with session.ws_connect(f'ws://{CNC_HOST}/websocket') as ws_server:
                async def to_server():
                    async for msg in ws_client:
                        if msg.type == WSMsgType.TEXT:
                            await ws_server.send_str(msg.data)
                        elif msg.type == WSMsgType.BINARY:
                            await ws_server.send_bytes(msg.data)
                        elif msg.type in (WSMsgType.CLOSE, WSMsgType.ERROR):
                            break

                async def to_client():
                    async for msg in ws_server:
                        if ws_client.closed:
                            break
                        if msg.type == WSMsgType.TEXT:
                            try:
                                await ws_client.send_str(msg.data)
                            except Exception:
                                break
                        elif msg.type == WSMsgType.BINARY:
                            try:
                                await ws_client.send_bytes(msg.data)
                            except Exception:
                                break
                        elif msg.type in (WSMsgType.CLOSE, WSMsgType.ERROR):
                            break

                await asyncio.gather(to_server(), to_client())
        return ws_client

    # ── UI Settings (shared across all browsers) ──
    if path == '/ui-settings':
        if request.method == 'GET':
            if os.path.isfile(SETTINGS_FILE):
                with open(SETTINGS_FILE, 'r') as f:
                    data = f.read()
            else:
                data = '{}'
            return web.Response(body=data, content_type='application/json',
                                headers={'Access-Control-Allow-Origin': '*'})
        elif request.method == 'POST':
            body = await request.read()
            # Validate it's JSON before saving
            json.loads(body)
            with open(SETTINGS_FILE, 'wb') as f:
                f.write(body)
            return web.Response(text='ok', headers={'Access-Control-Allow-Origin': '*'})

    # ── UI Action Log ──
    # POST /ui-log  body: plain-text line (already timestamped by JS)
    if path == '/ui-log':
        if request.method == 'POST':
            body = await request.read()
            line = body.decode('utf-8', errors='replace').strip()
            with open(UI_LOG_FILE, 'a', encoding='utf-8') as f:
                f.write(line + '\n')
            # Push notification for key events
            for keyword, title, priority, tags in _NTFY_RULES:
                if keyword.lower() in line.lower():
                    asyncio.ensure_future(ntfy_send(title, line, priority, tags))
                    break
            return web.Response(text='ok', headers={'Access-Control-Allow-Origin': '*'})
        return web.Response(status=405, headers={'Access-Control-Allow-Origin': '*'})

    # ── Full backup (bbctrl zip + ui-settings.json) ──
    # GET /api/backup-full  →  downloads bbctrl config zip with ui-settings.json injected
    if path == '/api/backup-full':
        async with ClientSession() as session:
            async with session.get(f'http://{CNC_HOST}/api/config/download') as resp:
                ctrl_zip = await resp.read()
        # Build new zip: copy everything from the controller zip, add ui-settings.json
        buf = io.BytesIO()
        with zipfile.ZipFile(io.BytesIO(ctrl_zip), 'r') as src, \
             zipfile.ZipFile(buf, 'w', zipfile.ZIP_DEFLATED) as dst:
            for item in src.infolist():
                dst.writestr(item, src.read(item.filename))
        # Add UI settings
        ui_data = b'{}'
        if os.path.isfile(SETTINGS_FILE):
            with open(SETTINGS_FILE, 'rb') as f:
                ui_data = f.read()
        with zipfile.ZipFile(buf, 'a', zipfile.ZIP_DEFLATED) as dst:
            dst.writestr('ui-settings.json', ui_data)
        return web.Response(
            body=buf.getvalue(),
            headers={
                'Content-Type': 'application/zip',
                'Content-Disposition': 'attachment; filename="cnc-backup.zip"',
                'Access-Control-Allow-Origin': '*',
            }
        )

    # ── Full restore (bbctrl zip + optional ui-settings.json) ──
    # POST /api/restore-full  multipart field: backup (zip or json)
    if path == '/api/restore-full':
        reader = await request.multipart()
        field = await reader.next()
        file_data = await field.read()
        filename  = field.filename or ''
        ui_settings = None
        ctrl_restored = False

        if filename.endswith('.zip') or file_data[:2] == b'PK':
            # It's a zip — extract config.json and optionally ui-settings.json
            try:
                with zipfile.ZipFile(io.BytesIO(file_data)) as zf:
                    names = zf.namelist()
                    if 'ui-settings.json' in names:
                        ui_settings = json.loads(zf.read('ui-settings.json'))
                    # Forward the zip to bbctrl restore endpoint
                    async with ClientSession() as session:
                        form = {'config': (filename, file_data, 'application/zip')}
                        async with session.put(
                            f'http://{CNC_HOST}/api/config/restore',
                            data={'config': file_data},
                        ) as resp:
                            ctrl_restored = resp.status < 300
            except Exception as e:
                return web.Response(
                    text=json.dumps({'error': str(e)}),
                    content_type='application/json', status=400,
                    headers={'Access-Control-Allow-Origin': '*'}
                )
        else:
            # Legacy JSON format — extract and push
            try:
                backup = json.loads(file_data)
                ui_settings = backup.get('uiSettings')
                ctrl_cfg = backup.get('controllerConfig')
                if ctrl_cfg:
                    async with ClientSession() as session:
                        async with session.put(
                            f'http://{CNC_HOST}/api/config/save',
                            json=ctrl_cfg,
                        ) as resp:
                            ctrl_restored = resp.status < 300
            except Exception as e:
                return web.Response(
                    text=json.dumps({'error': str(e)}),
                    content_type='application/json', status=400,
                    headers={'Access-Control-Allow-Origin': '*'}
                )

        # Save UI settings if present
        if ui_settings:
            with open(SETTINGS_FILE, 'w') as f:
                json.dump(ui_settings, f)

        msg = 'Backup imported'
        if ctrl_restored and ui_settings:  msg = 'Controller config + UI settings restored'
        elif ctrl_restored:                 msg = 'Controller config restored'
        elif ui_settings:                   msg = 'UI settings restored'

        return web.Response(
            text=json.dumps({'message': msg, 'controllerRestored': ctrl_restored,
                             'uiSettings': ui_settings}),
            content_type='application/json',
            headers={'Access-Control-Allow-Origin': '*'}
        )

    # ── Log-tail helper ──
    # /api/log-since?pos=N  →  returns only bytes from position N onward.
    # Keeps the browser fetch tiny (a few hundred bytes) instead of the full 1MB+ log.
    # The proxy does the heavy fetch from the controller; the browser gets only new content.
    if path == '/api/log-since':
        pos = int(request.query.get('pos', 0))
        async with ClientSession() as session:
            async with session.get(f'http://{CNC_HOST}/api/log') as resp:
                content = await resp.read()
        tail = content[pos:]
        return web.Response(
            body=tail,
            status=200,
            headers={
                'Content-Type': 'text/plain',
                'X-Log-Total': str(len(content)),
                'Access-Control-Allow-Origin': '*',
            }
        )

    # ── API / upload proxy ──
    if path.startswith('/api/') or path.startswith('/upload/'):
        target = f'http://{CNC_HOST}{path}'
        if request.query_string:
            target += '?' + request.query_string
        body = await request.read()
        headers = {k: v for k, v in request.headers.items()
                   if k.lower() not in ('host', 'origin', 'referer', 'content-length')}
        async with ClientSession() as session:
            async with session.request(
                request.method, target, headers=headers, data=body or None
            ) as resp:
                content = await resp.read()
                resp_headers = {k: v for k, v in resp.headers.items()
                                if k.lower() not in ('content-encoding', 'transfer-encoding',
                                                      'content-length')}
                return web.Response(body=content, status=resp.status, headers=resp_headers)

    # ── Static files ──
    if path == '/' or path == '':
        filepath = os.path.join(STATIC_DIR, 'index.html')
    else:
        filepath = os.path.join(STATIC_DIR, path.lstrip('/'))
        filepath = os.path.realpath(filepath)
        if not filepath.startswith(os.path.realpath(STATIC_DIR)):
            raise web.HTTPForbidden()
        if not os.path.isfile(filepath):
            filepath = os.path.join(STATIC_DIR, 'index.html')

    mime, _ = mimetypes.guess_type(filepath)
    with open(filepath, 'rb') as f:
        return web.Response(body=f.read(), content_type=mime or 'text/html')


def main():
    app = web.Application()
    app.router.add_get('/api/check-update', check_update)
    app.router.add_get('/api/download-update', download_update)
    app.router.add_route('*', '/{path_info:.*}', handle)

    print(f'CNC Proxy running on http://0.0.0.0:{PORT}')
    print(f'Proxying WebSocket and API to http://{CNC_HOST}')
    web.run_app(app, host='0.0.0.0', port=PORT, access_log=None)


if __name__ == '__main__':
    main()
