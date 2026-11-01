"""Bind tokens to their issuing management generation without exporting it."""

import sqlalchemy as sa
from alembic import op

revision = "0014"
down_revision = "0013"


def upgrade():
    # Authentication binds legacy blanks and creates the authority together in
    # one startup transaction. Existing management table rows stay untouched.
    op.add_column(
        "access_tokens", sa.Column("issued_epoch", sa.String(), nullable=False, server_default="")
    )


def downgrade():
    op.drop_column("access_tokens", "issued_epoch")
