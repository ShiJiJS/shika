"""Preserve fixed video membership and its original sequential order."""

import sqlalchemy as sa
from alembic import op

revision = "0007"
down_revision = "0006"


def upgrade():
    for name, default in (("membership", "legacy"), ("source", "library"), ("sort", "path")):
        op.add_column(
            "playback_rounds",
            sa.Column(name, sa.String(), nullable=False, server_default=default),
        )
    op.add_column("round_entries", sa.Column("source_ordinal", sa.Integer(), nullable=True))


def downgrade():
    op.drop_column("round_entries", "source_ordinal")
    for name in ("sort", "source", "membership"):
        op.drop_column("playback_rounds", name)
