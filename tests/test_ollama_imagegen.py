"""Unit tests for the Ollama image-generation ComfyUI node."""

import base64
import io
import json
import sys
import threading
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path

import numpy
import pytest
from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "custom_nodes" / "ollama_imagegen"))
import ollama_imagegen as mod


def png_b64() -> str:
    """Create a small RGB PNG fixture encoded as base64."""
    image = Image.new("RGB", (4, 6), (10, 20, 30))
    image.putpixel((1, 2), (255, 128, 0))
    buffer = io.BytesIO()
    image.save(buffer, format="PNG")
    return base64.b64encode(buffer.getvalue()).decode("ascii")


def test_build_request_body() -> None:
    """The request body preserves the model, dimensions, and seed."""
    body = mod.build_request_body("x/z-image-turbo", "a sunset", 1024, 768, 42)

    assert body["model"] == "x/z-image-turbo"
    assert body["size"] == "1024x768"
    assert body["response_format"] == "b64_json"
    assert body["seed"] == 42


def test_decode_b64_png_roundtrip() -> None:
    """A base64 PNG decodes to the expected normalised float32 array."""
    decoded = mod.decode_b64_png_to_array(png_b64())

    assert decoded.shape == (6, 4, 3)
    assert decoded.dtype == numpy.float32
    assert numpy.all((decoded >= 0) & (decoded <= 1))
    assert numpy.allclose(decoded[2, 1], [1.0, 128 / 255, 0.0])


def test_request_image_http() -> None:
    """The client posts to the image endpoint and returns its base64 payload."""
    expected_b64 = png_b64()

    class Handler(BaseHTTPRequestHandler):
        def do_POST(self) -> None:  # noqa: N802 - HTTPServer callback name
            assert self.path == "/v1/images/generations"
            content_length = int(self.headers["Content-Length"])
            request_body = json.loads(self.rfile.read(content_length))
            assert request_body["model"] == "x/z-image-turbo"

            response = json.dumps({"data": [{"b64_json": expected_b64}]}).encode()
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(response)))
            self.end_headers()
            self.wfile.write(response)

        def log_message(self, _format: str, *_args: object) -> None:
            """Suppress expected HTTP request logging during tests."""

    server = HTTPServer(("127.0.0.1", 0), Handler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()

    try:
        body = mod.build_request_body("x/z-image-turbo", "test", 64, 64, 0)
        received_b64 = mod.request_image(f"http://127.0.0.1:{server.server_port}", body, 5)
    finally:
        server.shutdown()
        thread.join()
        server.server_close()

    assert received_b64 == expected_b64


def test_request_image_unreachable() -> None:
    """An unavailable endpoint gives the tunnel-specific connection guidance."""
    with pytest.raises(RuntimeError, match="unreachable"):
        mod.request_image("http://127.0.0.1:1", {}, 1)
