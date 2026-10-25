"""Persist whole restore selections and their bounded, uniquely owned batches."""

import sqlalchemy as sa
from alembic import op

revision = "0012"
down_revision = "0011"


def upgrade():
    op.create_table(
        "pack_restore_plans",
        sa.Column("id", sa.String(), sa.ForeignKey("tasks.id"), primary_key=True),
        sa.Column("request_key", sa.String(), nullable=False, unique=True),
        sa.Column("request_hash", sa.String(), nullable=False),
        sa.Column("historical", sa.Boolean(), nullable=False),
        sa.Column("stop_requested", sa.Boolean(), nullable=False),
        sa.Column("batch_size", sa.Integer(), nullable=False),
        sa.CheckConstraint("batch_size BETWEEN 1 AND 1000"),
    )
    op.create_table(
        "pack_restore_members",
        sa.Column("plan_id", sa.String(), sa.ForeignKey("pack_restore_plans.id"), primary_key=True),
        sa.Column("ordinal", sa.Integer(), primary_key=True),
        sa.Column("pack_id", sa.String(), sa.ForeignKey("packs.id"), nullable=False),
        sa.Column("trash_id", sa.String(), sa.ForeignKey("pack_trash_items.id"), nullable=False),
        sa.Column("name", sa.String(), nullable=False),
        sa.Column("path", sa.Text(), nullable=False),
        sa.Column("source", sa.JSON(), nullable=False),
        sa.Column("phase", sa.String(), nullable=False),
        sa.Column("outcome", sa.String(), nullable=False),
        sa.Column("error", sa.String(), nullable=True),
        sa.UniqueConstraint("plan_id", "trash_id"),
    )
    op.create_index("ix_pack_restore_members_pack_id", "pack_restore_members", ["pack_id"])
    op.create_index("ix_pack_restore_members_outcome", "pack_restore_members", ["outcome"])
    op.create_table(
        "pack_restore_batches",
        sa.Column("plan_id", sa.String(), sa.ForeignKey("pack_restore_plans.id"), primary_key=True),
        sa.Column("ordinal", sa.Integer(), primary_key=True),
        sa.Column(
            "operation_id",
            sa.String(),
            sa.ForeignKey("pack_file_operations.id"),
            nullable=False,
            unique=True,
        ),
    )


def downgrade():
    op.drop_table("pack_restore_batches")
    op.drop_table("pack_restore_members")
    op.drop_table("pack_restore_plans")
