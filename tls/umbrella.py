"""httpx transport that completes Cisco Umbrella's session handshake transparently.

On this network, Umbrella answers some huggingface.co paths (every /resolve/ file download)
with ``302 Server: Cisco Umbrella`` to an ``*.id.opendns.com`` URL. Following that chain sets an
``X-OpenDNS-Session`` cookie for the original host. Requests that carry the cookie then get
Hugging Face's real response.

huggingface_hub reads file metadata (``X-Repo-Commit``, ``X-Linked-Etag``) from a HEAD request
with redirects turned off, so the handshake has to happen below the client. This transport
detects the Umbrella redirect, walks the chain once, keeps the session cookie per host, and
replays the original request with it.
"""

from __future__ import annotations

import threading
import time
from urllib.parse import urljoin

import httpx

_COOKIE = "X-OpenDNS-Session"


def _is_umbrella_redirect(resp: httpx.Response) -> bool:
    return (
        resp.status_code in (301, 302, 303, 307, 308)
        and resp.headers.get("server", "").startswith("Cisco Umbrella")
        and "opendns.com" in resp.headers.get("location", "")
    )


class UmbrellaTransport(httpx.BaseTransport):
    def __init__(self, inner: httpx.BaseTransport | None = None, max_hops: int = 8) -> None:
        self.inner = inner or httpx.HTTPTransport()
        self.max_hops = max_hops
        self._sessions: dict[str, str] = {}
        self._lock = threading.Lock()

    def _with_cookie(self, request: httpx.Request) -> httpx.Request:
        token = self._sessions.get(request.url.host)
        if token and _COOKIE not in request.headers.get("cookie", ""):
            existing = request.headers.get("cookie")
            pair = f"{_COOKIE}={token}"
            request.headers["cookie"] = f"{existing}; {pair}" if existing else pair
        return request

    def _remember(self, url: str, resp: httpx.Response) -> None:
        for header in resp.headers.get_list("set-cookie"):
            name, _, rest = header.partition("=")
            if name.strip() == _COOKIE:
                self._sessions[httpx.URL(url).host] = rest.split(";", 1)[0]

    def _send(self, method: str, url: str) -> httpx.Response:
        # The per-session *.id.opendns.com hostnames take a few seconds to start resolving
        # (getaddrinfo fails with 11001 meanwhile), so connection errors are retried.
        delay = 0.5
        for attempt in range(8):
            try:
                resp = self.inner.handle_request(self._with_cookie(httpx.Request(method, url)))
                resp.read()
                resp.close()
                return resp
            except httpx.ConnectError:
                if attempt == 7:
                    raise
                time.sleep(delay)
                delay = min(delay * 2, 4.0)
        raise AssertionError("unreachable")

    def _handshake(self, url: str, first: httpx.Response) -> None:
        """Walk the chain the way a browser would: every hop carries the cookies earlier hops set
        (the first one arrives on the original host's 302), until a response that is not
        Umbrella's own redirect -- by then the original host's session is live."""
        resp = first
        for _ in range(self.max_hops):
            self._remember(url, resp)
            if not resp.headers.get("server", "").startswith("Cisco Umbrella"):
                return  # the origin answered (often its own redirect to a CDN): session is live
            nxt = resp.headers.get("location")
            if not nxt or resp.status_code not in (301, 302, 303, 307, 308):
                break
            url = urljoin(url, nxt)
            resp = self._send("HEAD", url)
        raise httpx.ConnectError("Cisco Umbrella handshake did not complete")

    def handle_request(self, request: httpx.Request) -> httpx.Response:
        resp = self.inner.handle_request(self._with_cookie(request))
        # A fresh session is not always live for the very next request, so the replay is
        # re-handshaken a few times before giving up.
        for attempt in range(3):
            if not _is_umbrella_redirect(resp):
                return resp
            resp.read()
            resp.close()
            with self._lock:
                self._handshake(str(request.url), resp)
            if attempt:
                time.sleep(attempt)
            request.headers.pop("cookie", None)
            resp = self.inner.handle_request(self._with_cookie(request))
        return resp

    def close(self) -> None:
        self.inner.close()


def install_for_huggingface_hub() -> None:
    """Route huggingface_hub's shared client through the Umbrella-aware transport."""
    from huggingface_hub import set_client_factory
    from huggingface_hub.utils._http import hf_request_event_hook

    def factory() -> httpx.Client:
        return httpx.Client(
            transport=UmbrellaTransport(),
            event_hooks={"request": [hf_request_event_hook]},
            follow_redirects=True,
            timeout=None,
        )

    set_client_factory(factory)
