import json

from ci_selftest_python import application, greet


def call(path: str, query: str = "") -> tuple[str, bytes]:
    captured: dict[str, str] = {}

    def start_response(status: str, headers: list[tuple[str, str]]) -> None:
        captured["status"] = status

    body = b"".join(application({"PATH_INFO": path, "QUERY_STRING": query}, start_response))
    return captured["status"], body


def test_greet() -> None:
    assert greet("koorikla") == "hello, koorikla"
    assert greet("  ") == "hello, world"


def test_root() -> None:
    status, body = call("/", "name=ci")
    assert status == "200 OK"
    assert json.loads(body)["message"] == "hello, ci"


def test_healthz_and_404() -> None:
    assert call("/healthz") == ("200 OK", b"ok")
    assert call("/nope")[0] == "404 Not Found"
