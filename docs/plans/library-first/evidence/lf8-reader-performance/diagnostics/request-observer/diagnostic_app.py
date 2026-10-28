"""Owned-fixture observer: no headers, queries, bodies or response alterations."""
import itertools
import json
import time
from video_viewer.app import create_app as production_app

ids = itertools.count()


def record(value):
    with open('/trace/diagnostic-requests.jsonl', 'a') as stream:
        stream.write(json.dumps({'time': time.time(), **value}) + '\n')


def create_app():
    app = production_app()

    async def observed(scope, receive, send):
        if scope['type'] != 'http':
            return await app(scope, receive, send)
        identity = next(ids)
        data = {'id': identity, 'method': scope['method'], 'path': scope['path']}
        totals = {'received_bytes': 0, 'sent_bytes': 0, 'received_complete': False, 'sent_complete': False}
        record({**data, 'event': 'start'})

        async def receive_observed():
            message = await receive()
            if message['type'] == 'http.request':
                totals['received_bytes'] += len(message.get('body', b''))
                if not message.get('more_body', False):
                    totals['received_complete'] = True
                    record({**data, 'event': 'request_complete', 'bytes': totals['received_bytes']})
            elif message['type'] == 'http.disconnect':
                record({**data, 'event': 'disconnect'})
            return message

        async def send_observed(message):
            if message['type'] == 'http.response.start':
                record({**data, 'event': 'response_headers', 'status': message['status']})
            await send(message)
            if message['type'] == 'http.response.body':
                totals['sent_bytes'] += len(message.get('body', b''))
                totals['sent_complete'] = not message.get('more_body', False)

        try:
            await app(scope, receive_observed, send_observed)
        except BaseException as error:
            record({**data, 'event': 'exception', 'exception_type': type(error).__name__})
            raise
        finally:
            record({**data, 'event': 'end', **totals})

    return observed
