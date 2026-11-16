"""WSGI application: GET /healthz and GET /?name=<name>."""

import json
import os
from collections.abc import Callable, Iterable
from urllib.parse import parse_qs

StartResponse = Callable[[str, list[tuple[str, str]]], object]


def greet(name: str = "") -> str:
    return f"hello, {name.strip() or 'world'}"


def application(environ: dict, start_response: StartResponse) -> Iterable[bytes]:
    path = environ.get("PATH_INFO", "/")
    if path == "/healthz":
        body = b"ok"
        content_type = "text/plain"
    elif path == "/":
        name = parse_qs(environ.get("QUERY_STRING", "")).get("name", [""])[0]
        payload = {"message": greet(name), "version": os.environ.get("VERSION", "dev")}
        body = json.dumps(payload).encode()
        content_type = "application/json"
    else:
        start_response("404 Not Found", [("Content-Type", "text/plain")])
        return [b"not found"]
    start_response("200 OK", [("Content-Type", content_type), ("Content-Length", str(len(body)))])
    return [body]
