import torch

class MunsellLuminanceGrayscale:
    @classmethod
    def INPUT_TYPES(s):
        return {"required": {"image": ("IMAGE",),}}

    RETURN_TYPES = ("IMAGE",)
    FUNCTION = "convert"
    CATEGORY = "image/filters"

    def convert(self, image):
        # image tensor shape is [B, H, W, C]
        # Apply standard ITU-R BT.601 perceptual luminance weights
        r = image[..., 0]
        g = image[..., 1]
        b = image[..., 2]

        luminance = 0.299 * r + 0.587 * g + 0.114 * b

        # Replicate the single luminance channel back to 3-channel RGB [B, H, W, 3]
        grayscale_image = torch.stack([luminance, luminance, luminance], dim=-1)
        return (grayscale_image,)

NODE_CLASS_MAPPINGS = {"MunsellLuminanceGrayscale": MunsellLuminanceGrayscale}
NODE_DISPLAY_NAME_MAPPINGS = {"MunsellLuminanceGrayscale": "Perceptual Munsell Grayscale"}
