-- LF0 frozen synthetic migration fixture; never run against a real library.
BEGIN TRANSACTION;
CREATE TABLE access_tokens (
	digest VARCHAR NOT NULL, 
	expires_at FLOAT NOT NULL, 
	PRIMARY KEY (digest)
);
CREATE TABLE alembic_version (
	version_num VARCHAR(32) NOT NULL, 
	CONSTRAINT alembic_version_pkc PRIMARY KEY (version_num)
);
INSERT INTO "alembic_version" VALUES('0004');
CREATE TABLE directories (
	id VARCHAR NOT NULL, 
	root_id VARCHAR NOT NULL, 
	path TEXT NOT NULL, 
	name VARCHAR NOT NULL, 
	seen_scan VARCHAR, 
	PRIMARY KEY (id), 
	FOREIGN KEY(root_id) REFERENCES roots (id), 
	UNIQUE (path)
);
INSERT INTO "directories" VALUES('lf0-dir','lf0-root','/media/lf0','lf0',NULL);
CREATE TABLE file_operations (
	id VARCHAR NOT NULL, 
	request_key VARCHAR NOT NULL, 
	request_hash VARCHAR NOT NULL, 
	kind VARCHAR NOT NULL, 
	undo_of VARCHAR, 
	round_snapshot JSON NOT NULL, 
	historical BOOLEAN NOT NULL, 
	PRIMARY KEY (id), 
	FOREIGN KEY(id) REFERENCES tasks (id), 
	UNIQUE (request_key)
);
INSERT INTO "file_operations" VALUES('lf0-logical','files:lf0-logical','fixture','trash',NULL,'{"id": "lf0-round", "cursor": 1}',0);
INSERT INTO "file_operations" VALUES('lf0-physical','files:lf0-physical','fixture','trash',NULL,'{"id": "lf0-round", "cursor": 1}',0);
INSERT INTO "file_operations" VALUES('lf0-pending','files:lf0-pending','fixture','trash',NULL,'{"id": "lf0-round", "cursor": 1}',0);
CREATE TABLE file_steps (
	id VARCHAR NOT NULL, 
	operation_id VARCHAR NOT NULL, 
	requested_id VARCHAR NOT NULL, 
	video_id VARCHAR, 
	trash_id VARCHAR, 
	original_status VARCHAR NOT NULL, 
	root_path TEXT NOT NULL, 
	original_path TEXT NOT NULL, 
	source TEXT NOT NULL, 
	destination TEXT NOT NULL, 
	staging TEXT NOT NULL, 
	copy_path TEXT NOT NULL, 
	expected_hash VARCHAR NOT NULL, 
	expected_size INTEGER NOT NULL, 
	source_signature JSON NOT NULL, 
	claimed_identity JSON NOT NULL, 
	published_identity JSON NOT NULL, 
	copy_identity JSON NOT NULL, 
	phase VARCHAR NOT NULL, 
	outcome VARCHAR NOT NULL, 
	error VARCHAR, 
	PRIMARY KEY (id), 
	FOREIGN KEY(operation_id) REFERENCES file_operations (id), 
	FOREIGN KEY(video_id) REFERENCES videos (id)
);
INSERT INTO "file_steps" VALUES('lf0-step-logical','lf0-logical','lf0-v2','lf0-v2',NULL,'available','/media/lf0','/media/lf0/2.mp4','/media/lf0/2.mp4','/media/lf0/2.mp4','','','',0,'[]','[]','[]','[]','done','success',NULL);
INSERT INTO "file_steps" VALUES('lf0-step-physical','lf0-physical','lf0-v3','lf0-v3',NULL,'available','/media/lf0','/media/lf0/3.mp4','/media/lf0/3.mp4','/media/lf0/.video-viewer-trash/physical/3.mp4','','','',0,'[]','[]','[]','[]','done','success',NULL);
INSERT INTO "file_steps" VALUES('lf0-step-pending','lf0-pending','lf0-v4','lf0-v4',NULL,'available','/media/lf0','/media/lf0/4.mp4','/media/lf0/4.mp4','/media/lf0/.video-viewer-trash/pending/4.mp4','','','',0,'[]','[]','[]','[]','prepared','pending',NULL);
CREATE TABLE observations (
	path TEXT NOT NULL, 
	signature JSON NOT NULL, 
	stable_since FLOAT NOT NULL, 
	PRIMARY KEY (path)
);
CREATE TABLE playback_rounds (
	id VARCHAR NOT NULL, 
	request_id VARCHAR NOT NULL, 
	request_hash VARCHAR NOT NULL, 
	"order" VARCHAR NOT NULL, 
	scope JSON NOT NULL, 
	cursor INTEGER NOT NULL, 
	revision INTEGER NOT NULL, 
	finished BOOLEAN NOT NULL, 
	candidate_count INTEGER NOT NULL, 
	created_at FLOAT NOT NULL, 
	PRIMARY KEY (id), 
	UNIQUE (request_id)
);
INSERT INTO "playback_rounds" VALUES('lf0-round','lf0-round-request','fixture','random','{}',1,3,0,2,1.0);
CREATE TABLE request_records (
	id VARCHAR NOT NULL, 
	fingerprint VARCHAR NOT NULL, 
	result JSON NOT NULL, 
	created_at FLOAT NOT NULL, 
	PRIMARY KEY (id)
);
CREATE TABLE roots (
	id VARCHAR NOT NULL, 
	name VARCHAR NOT NULL, 
	path TEXT NOT NULL, 
	mount_id VARCHAR NOT NULL, 
	available BOOLEAN NOT NULL, 
	error VARCHAR, 
	last_scan FLOAT, 
	PRIMARY KEY (id), 
	UNIQUE (path)
);
INSERT INTO "roots" VALUES('lf0-root','Synthetic legacy videos','/media/lf0','fixture',1,NULL,1.0);
CREATE TABLE round_entries (
	round_id VARCHAR NOT NULL, 
	ordinal INTEGER NOT NULL, 
	video_id VARCHAR NOT NULL, 
	PRIMARY KEY (round_id, ordinal), 
	FOREIGN KEY(round_id) REFERENCES playback_rounds (id) ON DELETE CASCADE, 
	FOREIGN KEY(video_id) REFERENCES videos (id)
);
INSERT INTO "round_entries" VALUES('lf0-round',0,'lf0-v4');
INSERT INTO "round_entries" VALUES('lf0-round',1,'lf0-v1');
CREATE TABLE settings (
	"key" VARCHAR NOT NULL, 
	value TEXT NOT NULL, 
	PRIMARY KEY ("key")
);
INSERT INTO "settings" VALUES('active_round','lf0-round');
INSERT INTO "settings" VALUES('last_delete_operation','lf0-logical');
CREATE TABLE tags (
	id VARCHAR NOT NULL, 
	name VARCHAR NOT NULL, 
	created_at FLOAT NOT NULL, 
	PRIMARY KEY (id), 
	UNIQUE (name)
);
INSERT INTO "tags" VALUES('lf0-tag','旧标签',1.0);
CREATE TABLE tasks (
	id VARCHAR NOT NULL, 
	kind VARCHAR NOT NULL, 
	status VARCHAR NOT NULL, 
	phase VARCHAR NOT NULL, 
	created_at FLOAT NOT NULL, 
	finished_at FLOAT, 
	result JSON NOT NULL, 
	error VARCHAR, 
	PRIMARY KEY (id)
);
INSERT INTO "tasks" VALUES('lf0-logical','file_operation','completed','done',1.0,NULL,'{}',NULL);
INSERT INTO "tasks" VALUES('lf0-physical','file_operation','completed','done',1.0,NULL,'{}',NULL);
INSERT INTO "tasks" VALUES('lf0-pending','file_operation','queued','prepared',1.0,NULL,'{}',NULL);
CREATE TABLE trash_items (
	id VARCHAR NOT NULL, 
	video_id VARCHAR NOT NULL, 
	operation_id VARCHAR NOT NULL, 
	root_path TEXT NOT NULL, 
	original_path TEXT NOT NULL, 
	trash_path TEXT NOT NULL, 
	sha256 VARCHAR NOT NULL, 
	size INTEGER NOT NULL, 
	status VARCHAR NOT NULL, 
	deleted_at FLOAT NOT NULL, 
	PRIMARY KEY (id), 
	FOREIGN KEY(video_id) REFERENCES videos (id), 
	FOREIGN KEY(operation_id) REFERENCES file_operations (id)
);
INSERT INTO "trash_items" VALUES('lf0-trash-logical','lf0-v2','lf0-logical','/media/lf0','/media/lf0/2.mp4','/media/lf0/2.mp4','2222222222222222222222222222222222222222222222222222222222222222',2,'active',1.0);
INSERT INTO "trash_items" VALUES('lf0-trash-physical','lf0-v3','lf0-physical','/media/lf0','/media/lf0/3.mp4','/media/lf0/.video-viewer-trash/physical/3.mp4','3333333333333333333333333333333333333333333333333333333333333333',3,'active',1.0);
CREATE TABLE video_tags (
	video_id VARCHAR NOT NULL, 
	tag_id VARCHAR NOT NULL, 
	PRIMARY KEY (video_id, tag_id), 
	FOREIGN KEY(video_id) REFERENCES videos (id) ON DELETE CASCADE, 
	FOREIGN KEY(tag_id) REFERENCES tags (id) ON DELETE CASCADE
);
INSERT INTO "video_tags" VALUES('lf0-v1','lf0-tag');
INSERT INTO "video_tags" VALUES('lf0-v2','lf0-tag');
CREATE TABLE videos (
	id VARCHAR NOT NULL, 
	root_id VARCHAR NOT NULL, 
	path TEXT NOT NULL, 
	location_key TEXT, 
	name VARCHAR NOT NULL, 
	status VARCHAR NOT NULL, 
	error VARCHAR, 
	size INTEGER NOT NULL, 
	device VARCHAR NOT NULL, 
	inode VARCHAR NOT NULL, 
	mtime_ns VARCHAR NOT NULL, 
	ctime_ns VARCHAR NOT NULL, 
	sha256 VARCHAR NOT NULL, 
	quick_hash VARCHAR NOT NULL, 
	duration FLOAT NOT NULL, 
	width INTEGER NOT NULL, 
	height INTEGER NOT NULL, 
	rotation INTEGER NOT NULL, 
	type VARCHAR NOT NULL, 
	video_codec VARCHAR NOT NULL, 
	audio_codec VARCHAR, 
	container VARCHAR NOT NULL, 
	thumbnail VARCHAR, 
	seen_scan VARCHAR NOT NULL, 
	created_at FLOAT NOT NULL, generation INTEGER DEFAULT '0' NOT NULL, 
	PRIMARY KEY (id), 
	FOREIGN KEY(root_id) REFERENCES roots (id), 
	UNIQUE (location_key)
);
INSERT INTO "videos" VALUES('lf0-v1','lf0-root','/media/lf0/1.mp4','location-1','1.mp4','available',NULL,1,'1','1','1','1','1111111111111111111111111111111111111111111111111111111111111111','1111111111111111111111111111111111111111111111111111111111111111',5.0,720,1280,0,'MP4','h264',NULL,'mp4',NULL,'lf0-scan',1.0,0);
INSERT INTO "videos" VALUES('lf0-v2','lf0-root','/media/lf0/2.mp4','location-2','2.mp4','trash',NULL,2,'1','2','1','1','2222222222222222222222222222222222222222222222222222222222222222','2222222222222222222222222222222222222222222222222222222222222222',5.0,720,1280,0,'MP4','h264',NULL,'mp4',NULL,'lf0-scan',1.0,0);
INSERT INTO "videos" VALUES('lf0-v3','lf0-root','/media/lf0/3.mp4','location-3','3.mp4','trash',NULL,3,'1','3','1','1','3333333333333333333333333333333333333333333333333333333333333333','3333333333333333333333333333333333333333333333333333333333333333',5.0,720,1280,0,'MP4','h264',NULL,'mp4',NULL,'lf0-scan',1.0,0);
INSERT INTO "videos" VALUES('lf0-v4','lf0-root','/media/lf0/4.mp4','location-4','4.mp4','available',NULL,4,'1','4','1','1','4444444444444444444444444444444444444444444444444444444444444444','4444444444444444444444444444444444444444444444444444444444444444',5.0,720,1280,0,'MP4','h264',NULL,'mp4',NULL,'lf0-scan',1.0,0);
CREATE INDEX ix_directories_root_id ON directories (root_id);
CREATE INDEX ix_videos_root_id ON videos (root_id);
CREATE INDEX ix_videos_path ON videos (path);
CREATE INDEX ix_videos_status ON videos (status);
CREATE INDEX ix_videos_sha256 ON videos (sha256);
CREATE INDEX ix_videos_quick_hash ON videos (quick_hash);
CREATE INDEX videos_order ON videos (path, id);
CREATE INDEX ix_tasks_status ON tasks (status);
CREATE INDEX ix_round_entries_video_id ON round_entries (video_id);
CREATE INDEX video_tags_tag_video ON video_tags (tag_id, video_id);
CREATE INDEX ix_file_steps_operation_id ON file_steps (operation_id);
CREATE INDEX ix_file_steps_video_id ON file_steps (video_id);
CREATE INDEX ix_file_steps_phase ON file_steps (phase);
CREATE INDEX ix_trash_items_video_id ON trash_items (video_id);
CREATE INDEX ix_trash_items_status ON trash_items (status);
CREATE UNIQUE INDEX trash_active_video ON trash_items (video_id) WHERE status='active';
COMMIT;
