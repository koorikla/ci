"""Entry point: python -m ci_selftest_python (serves on $PORT, default 8080)."""

import os

from waitress import serve

from ci_selftest_python.app import application


def main() -> None:
    host = os.environ.get("HOST", "0.0.0.0")  # noqa: S104 - container listens on all interfaces
    serve(application, host=host, port=int(os.environ.get("PORT", "8080")))


if __name__ == "__main__":
    main()
