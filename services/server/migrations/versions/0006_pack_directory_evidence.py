"""Persist directory evidence so recycled NAS inode numbers cannot steal identity."""

import sqlalchemy as sa
from alembic import op

revision = "0006"
down_revision = "0005"


def upgrade():
    op.add_column(
        "packs", sa.Column("directory_signature", sa.JSON(), nullable=False, server_default="[]")
    )


def downgrade():
    op.drop_column("packs", "directory_signature")
