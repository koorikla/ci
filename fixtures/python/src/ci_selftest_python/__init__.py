"""koorikla/ci selftest fixture: a dependency-light WSGI service."""

from ci_selftest_python.app import application, greet

__all__ = ["application", "greet"]
