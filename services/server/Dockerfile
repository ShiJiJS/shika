FROM python:3.13-slim-bookworm@sha256:a1165e272e578941b84abc79e4ab38a0305cd12803a5c4247979ac7655f4d641 AS runtime
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1 PIP_DISABLE_PIP_VERSION_CHECK=1
ARG FFMPEG_VERSION=7:5.1.9-0+deb12u1
RUN apt-get update && apt-get install -y --no-install-recommends ffmpeg=${FFMPEG_VERSION} && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY requirements.lock ./
RUN pip install --no-cache-dir --require-hashes -r requirements.lock
COPY video_viewer ./video_viewer
COPY migrations ./migrations
COPY alembic.ini ./
RUN groupadd --gid 1000 viewer && useradd --uid 1000 --gid 1000 --no-create-home viewer && mkdir /data && chown 1000:1000 /data
USER 1000:1000
EXPOSE 8760
HEALTHCHECK --interval=15s --timeout=3s --start-period=20s CMD ["python", "-c", "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8760/health', timeout=2)"]
CMD ["uvicorn", "video_viewer.app:create_app", "--factory", "--host", "0.0.0.0", "--port", "8760", "--workers", "1", "--no-access-log"]

FROM runtime AS test
ENV PYTEST_ADDOPTS="-o cache_dir=/tmp/video-viewer-pytest-cache" RUFF_CACHE_DIR=/tmp/video-viewer-ruff-cache
USER root
COPY requirements-test.lock ./
RUN pip install --no-cache-dir --require-hashes -r requirements-test.lock
COPY tests ./tests
COPY pyproject.toml ./
USER 1000:1000
CMD ["python", "-m", "pytest", "-q"]
