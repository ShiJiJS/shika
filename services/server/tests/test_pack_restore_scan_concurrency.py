"""Deterministic scan/whole-restore interleavings, not timing-dependent retries."""

import pytest
from sqlalchemy import select

from video_viewer.models import ImagePack
from video_viewer.pack_scanner import PackScanner

from .test_pack_purge_plans import fixture
from .test_pack_restore_plans import wait
from .test_packs import sync


@pytest.mark.parametrize("boundary", ["tick", "reconcile"])
def test_scan_snapshot_cannot_replace_or_mark_missing_packs_restored_during_its_lifetime(
    library, monkeypatch, boundary
):
    client, media = library
    _, catalog, rows = fixture(client, media, 4)
    plans = client.app.state.pack_restore_plans
    plans.batch_size = 2
    original = getattr(PackScanner, boundary)
    accepted = []

    def interleave(scanner, *args, **kwargs):
        if not accepted:
            identity = plans.submit([r["id"] for r in rows], "during-scan")
            accepted.append(identity)
            plans.futures[identity].result(timeout=10)
        return original(scanner, *args, **kwargs)

    monkeypatch.setattr(PackScanner, boundary, interleave)
    task = sync(client)
    assert task["status"] == "completed"
    assert task["result"]["packs"]["missing"] == 0
    assert task["result"]["packs"]["failed"] == 0
    assert wait(client, accepted[0])["result"]["succeeded"] == 4
    with client.app.state.db.read() as session:
        rows = list(session.scalars(select(ImagePack)))
        assert {p.id for p in rows} == {p["id"] for p in catalog}
        assert {p.generation for p in rows} == {3}
        assert {p.status for p in rows} == {"available"}
