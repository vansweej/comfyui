"""Generate ComfyUI images through an Ollama-compatible image endpoint."""

import base64
import io
import json
import os
import urllib.error
import urllib.request
from typing import Any

import numpy
from PIL import Image


def build_request_body(
    model: str, prompt: str, width: int, height: int, seed: int
) -> dict[str, Any]:
    """Build the OpenAI-compatible Ollama image-generation request body."""
    return {
        "model": model,
        "prompt": prompt,
        "size": f"{width}x{height}",
        "response_format": "b64_json",
        "seed": seed,
    }


def request_image(url: str, body: dict[str, Any], timeout: int) -> str:
    """Request a base64-encoded PNG from the configured Ollama endpoint."""
    request = urllib.request.Request(
        f"{url.rstrip('/')}/v1/images/generations",
        data=json.dumps(body).encode("utf-8"),
        headers={"Content-Type": "application/json"},
        method="POST",
    )

    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            payload = json.loads(response.read().decode("utf-8"))
    except urllib.error.URLError as exc:
        raise RuntimeError(
            f"Ollama on M5 unreachable at {url}: is the tunnel running "
            "(`ollama-tunnel start` with M5_HOST set) and Ollama up on M5?"
        ) from exc

    try:
        return payload["data"][0]["b64_json"]
    except (IndexError, KeyError, TypeError) as exc:
        raise RuntimeError(f"Ollama response missing data/b64_json: {payload!r}") from exc


def decode_b64_png_to_array(b64: str) -> numpy.ndarray[Any, Any]:
    """Decode a base64 PNG to an HxWx3 float32 array in the [0, 1] range."""
    png_bytes = base64.b64decode(b64)
    image = Image.open(io.BytesIO(png_bytes)).convert("RGB")
    return numpy.asarray(image, dtype=numpy.float32) / 255.0


class OllamaImageGen:
    """ComfyUI node that requests an image from Ollama running on M5."""

    @classmethod
    def INPUT_TYPES(cls) -> dict[str, dict[str, tuple[Any, ...]]]:
        """Return the configurable inputs exposed by ComfyUI."""
        return {
            "required": {
                "model": (["x/z-image-turbo", "x/flux2-klein"],),
                "prompt": ("STRING", {"multiline": True, "default": ""}),
                "width": (
                    "INT",
                    {"default": 1024, "min": 64, "max": 1024, "step": 8},
                ),
                "height": (
                    "INT",
                    {"default": 1024, "min": 64, "max": 1024, "step": 8},
                ),
                "seed": (
                    "INT",
                    {"default": 0, "min": 0, "max": 0xFFFFFFFF},
                ),
                "ollama_url": (
                    "STRING",
                    {
                        "default": os.environ.get(
                            "OLLAMA_IMAGEGEN_URL", "http://127.0.0.1:11435"
                        )
                    },
                ),
                "timeout": (
                    "INT",
                    {"default": 300, "min": 1, "max": 3600},
                ),
            }
        }

    RETURN_TYPES = ("IMAGE",)
    FUNCTION = "generate"
    CATEGORY = "image/ollama"

    def generate(
        self,
        model: str,
        prompt: str,
        width: int,
        height: int,
        seed: int,
        ollama_url: str,
        timeout: int,
    ) -> tuple[Any]:
        """Generate an image and return it as a ComfyUI IMAGE tensor."""
        import torch

        body = build_request_body(model, prompt, width, height, seed)
        b64_image = request_image(ollama_url, body, timeout)
        image_array = decode_b64_png_to_array(b64_image)
        tensor = torch.from_numpy(image_array)[None, ...]
        return (tensor,)


NODE_CLASS_MAPPINGS = {"OllamaImageGen": OllamaImageGen}
NODE_DISPLAY_NAME_MAPPINGS = {"OllamaImageGen": "Ollama Image Gen (M5)"}
