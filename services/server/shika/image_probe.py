"""Image decoder subprocess: bounded memory/CPU, no network or source path input."""

import json
import os
import resource
import sys
import warnings

from PIL import Image, ImageOps, UnidentifiedImageError

MAX_PIXELS = 80_000_000
MAX_SOURCE_PIXELS = 512_000_000


def decode(fd, target):
    # JPEG can reduce pixels inside the decoder before allocating a full frame.
    # Keep a separate header ceiling; enforce the working-size budget after draft.
    Image.MAX_IMAGE_PIXELS = MAX_SOURCE_PIXELS
    warnings.simplefilter("error", Image.DecompressionBombWarning)
    with os.fdopen(os.dup(fd), "rb") as stream:
        stream.seek(0)
        with Image.open(stream, formats=("JPEG", "PNG", "WEBP")) as image:
            if getattr(image, "n_frames", 1) != 1:
                return {"error": "animated_image_unsupported"}
            width, height = image.size
            if width * height > MAX_PIXELS and image.format != "JPEG":
                return {"error": "image_too_large"}
            metadata = {"width": width, "height": height, "format": image.format}
            image.verify()
        stream.seek(0)
        with Image.open(stream, formats=("JPEG", "PNG", "WEBP")) as image:
            if image.getexif().get(274, 1) in (5, 6, 7, 8):
                metadata["width"], metadata["height"] = height, width
            # Fully decode once so truncated JPEGs do not enter a reading manifest.
            image.draft("RGB", (768, 768))
            if image.width * image.height > MAX_PIXELS:
                return {"error": "image_too_large"}
            image.load()
            ImageOps.exif_transpose(image, in_place=True)
            image.thumbnail((512, 768), Image.Resampling.LANCZOS, reducing_gap=3)
            try:
                if "A" in image.getbands() or "transparency" in image.info:
                    rgba = image.convert("RGBA")
                    preview = Image.new("RGB", rgba.size, "white")
                    preview.paste(rgba, mask=rgba.getchannel("A"))
                else:
                    preview = image.convert("RGB")
                with open(target, "xb") as output:
                    preview.save(output, "JPEG", quality=82, exif=b"")
                metadata["thumbnail"] = True
            except OSError:
                metadata["thumbnail_warning"] = "thumbnail_unavailable"
            return metadata


def main():
    # Decoding a corrupt/huge image must not take down the HTTP process.
    resource.setrlimit(resource.RLIMIT_AS, (1200 * 1024**2, 1200 * 1024**2))
    resource.setrlimit(resource.RLIMIT_CPU, (15, 16))
    try:
        result = decode(int(sys.argv[1]), sys.argv[2])
    except (Image.DecompressionBombError, Image.DecompressionBombWarning, MemoryError):
        result = {"error": "image_too_large"}
    except (UnidentifiedImageError, OSError, ValueError, SyntaxError, RuntimeError):
        result = {"error": "invalid_image"}
    result["peak_rss_kib"] = resource.getrusage(resource.RUSAGE_SELF).ru_maxrss
    print(json.dumps(result))


if __name__ == "__main__":
    main()
