"""Optional folder-name presentation; never an identity or filesystem mutation."""

import re
from dataclasses import dataclass
from functools import lru_cache


@dataclass(frozen=True)
class PackPresentation:
    title: str
    author: str | None = None
    number: str | None = None


# Require an explicit volume marker and separator. A bare bracket, dash,
# date, resolution, or numeric prefix does not reliably identify an author.
_NUMBERED = re.compile(
    r"^([^\r\n]{1,100}?)\s+NO[.．]?\s*([0-9]{1,8})\s+[-–—]\s+(\S[^\r\n]*)$",
    re.IGNORECASE,
)


@lru_cache(maxsize=4096)
def presentation(name: str) -> PackPresentation:
    match = _NUMBERED.fullmatch(name.strip())
    if not match:
        return PackPresentation(name)
    author, number, title = (part.strip() for part in match.groups())
    if (author.startswith("[") and author.endswith("]")) or (
        author.startswith("【") and author.endswith("】")
    ):
        author = author[1:-1].strip()
    if not author or not title:
        return PackPresentation(name)
    return PackPresentation(title, author, number)
