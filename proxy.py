"""
CNC UI Proxy Server
- Serves static files on port 8888
- Proxies /websocket  → ws://192.168.1.130/websocket
- Proxies /api/*      → http://192.168.1.130/api/*
Tornado blocks cross-origin WebSockets, so we proxy from same origin.
"""

import asyncio
import os
import mimetypes
from aiohttp import web, ClientSession, WSMsgType

CNC_HOST = os.environ.get('CNC_HOST', '192.168.1.130')
STATIC_DIR = os.path.dirname(os.path.abspath(__file__))
PORT = int(os.environ.get('PORT', 8888))


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
    app.router.add_route('*', '/{path_info:.*}', handle)

    print(f'CNC Proxy running on http://0.0.0.0:{PORT}')
    print(f'Proxying WebSocket and API to http://{CNC_HOST}')
    web.run_app(app, host='0.0.0.0', port=PORT, access_log=None)


if __name__ == '__main__':
    main()
