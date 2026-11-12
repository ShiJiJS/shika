"""Image decoder subprocess: bounded memory/CPU, no network or source path input."""

import json
import os
import resource
import sys

from PIL import Image, ImageOps, UnidentifiedImageError

# This budget applies only to thumbnail working pixels, never to source admission.
MAX_PREVIEW_PIXELS = 80_000_000


def decode(fd, target, metadata_ready):
    # Header inspection must not reject a source solely for its dimensions.
    # Memory/CPU limits still contain decoder allocations, including open().
    Image.MAX_IMAGE_PIXELS = None
    with os.fdopen(os.dup(fd), "rb") as stream:
        stream.seek(0)
        with Image.open(stream, formats=("JPEG", "PNG", "WEBP")) as image:
            if getattr(image, "n_frames", 1) != 1:
                return {"error": "animated_image_unsupported"}
            width, height = image.size
            metadata = {"width": width, "height": height, "format": image.format}
            # PNG.getexif() may load the entire image. Read only metadata already
            # available in its header before publishing the fallback receipt.
            exif = Image.Exif()
            if image.info.get("exif"):
                exif.load(image.info["exif"])
            if exif.get(274, 1) in (5, 6, 7, 8):
                metadata["width"], metadata["height"] = height, width
            metadata_ready(metadata)
            image.verify()
        stream.seek(0)
        with Image.open(stream, formats=("JPEG", "PNG", "WEBP")) as image:
            image.draft("RGB", (768, 768))
            if image.width * image.height > MAX_PREVIEW_PIXELS:
                return {**metadata, "thumbnail_warning": "thumbnail_resource_limit"}
            # Decoding errors still identify genuinely unreadable sources. A
            # resource failure instead leaves the original available to readers.
            image.load()
            if image.getexif().get(274, 1) in (5, 6, 7, 8):
                metadata["width"], metadata["height"] = height, width
            # Resize first to avoid copying a full-resolution rotated frame.
            image.thumbnail((768, 768), Image.Resampling.LANCZOS, reducing_gap=3)
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
    # Stay below the 768 MiB service container budget, leaving room for HTTP and
    # authentication. The parent can recover a header receipt if this worker dies.
    resource.setrlimit(resource.RLIMIT_AS, (512 * 1024**2, 512 * 1024**2))
    resource.setrlimit(resource.RLIMIT_CPU, (15, 16))
    metadata = {}

    def ready(value):
        metadata.update(value)
        print(json.dumps({"metadata": value}), flush=True)

    try:
        result = decode(int(sys.argv[1]), sys.argv[2], ready)
    except (Image.DecompressionBombError, Image.DecompressionBombWarning, MemoryError):
        result = (
            {**metadata, "thumbnail_warning": "thumbnail_resource_limit"}
            if metadata
            else {"error": "image_probe_failed"}
        )
    except (UnidentifiedImageError, OSError, ValueError, SyntaxError, RuntimeError):
        result = {"error": "invalid_image"}
    result["peak_rss_kib"] = resource.getrusage(resource.RUSAGE_SELF).ru_maxrss
    print(json.dumps(result), flush=True)


if __name__ == "__main__":
    main()
