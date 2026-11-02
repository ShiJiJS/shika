"""Local-only standalone reference preview; not part of the App or NAS service."""

import argparse
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import unquote, urlsplit


class ReferenceHandler(SimpleHTTPRequestHandler):
    def translate_path(self, path):
        clean = unquote(urlsplit(path).path)
        if clean.startswith("/_shared/"):
            assets = Path(__file__).resolve().parents[2] / "apps/mobile/assets"
            target = (assets / clean.removeprefix("/_shared/")).resolve()
            if target.is_relative_to(assets.resolve()):
                return str(target)
            return str(assets / "__missing__")
        return super().translate_path(path)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", type=int, default=8767)
    args = parser.parse_args()
    server = ThreadingHTTPServer(
        ("127.0.0.1", args.port),
        partial(ReferenceHandler, directory=str(Path(__file__).resolve().parent)),
    )
    print(f"Reference only: http://127.0.0.1:{args.port}/library-first/", flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()
