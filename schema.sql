-- ============================================================================
-- Timetabling Requests Management - Database Schema
-- NTU Project (Mohid Nadeem, N1433045)
--
-- Safe to re-run ONLY IF you want to drop everything (children first) 
-- and rebuilds from scratch, then reseeds all reference + demo data.
-- ============================================================================

CREATE DATABASE IF NOT EXISTS timetabling_requests
    CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

USE timetabling_requests;

-- ----------------------------------------------------------------------------
-- Dropping in child-to-parent order
-- ----------------------------------------------------------------------------
DROP TABLE IF EXISTS notifications;
DROP TABLE IF EXISTS activity_log;
DROP TABLE IF EXISTS email_log;
DROP TABLE IF EXISTS comment_attachments;
DROP TABLE IF EXISTS request_comments;
DROP TABLE IF EXISTS request_unavailable_days;
DROP TABLE IF EXISTS request_weeks;
DROP TABLE IF EXISTS request_rooms;
DROP TABLE IF EXISTS request_groups;
DROP TABLE IF EXISTS request_merge_sessions;
DROP TABLE IF EXISTS request_modules;
DROP TABLE IF EXISTS session_override_weeks;
DROP TABLE IF EXISTS session_overrides;
DROP TABLE IF EXISTS session_cancelled_weeks;
DROP TABLE IF EXISTS requests;
DROP TABLE IF EXISTS session_courses;
DROP TABLE IF EXISTS timetable_sessions;
DROP TABLE IF EXISTS module_courses;
DROP TABLE IF EXISTS rooms;
DROP TABLE IF EXISTS modules;
DROP TABLE IF EXISTS academic_year_settings;
DROP TABLE IF EXISTS courses;
DROP TABLE IF EXISTS users;

-- ----------------------------------------------------------------------------
-- USERS
-- ----------------------------------------------------------------------------
CREATE TABLE users (
    id                     BIGINT AUTO_INCREMENT PRIMARY KEY,
    username               VARCHAR(50)  NOT NULL UNIQUE,
    email                  VARCHAR(255) NOT NULL UNIQUE,
    password_hash          VARCHAR(255) NOT NULL,
    full_name              VARCHAR(150) NOT NULL,
    role                   ENUM('ADMIN', 'LECTURER', 'TIMETABLING_TEAM', 'STUDENT') NOT NULL,
    -- LEAVER applies to staff (Lecturer/Timetabling Team/Admin), 
    -- ALUMNI to students 
    -- both block login.
    account_status         ENUM('ACTIVE', 'LEAVER', 'ALUMNI') NOT NULL DEFAULT 'ACTIVE',
    -- students only - which programme they're enrolled in.
    course_id              BIGINT NULL,
    -- students only - which lab/seminar group they're in 
    group_label             VARCHAR(50) NULL,
    must_change_password   BOOLEAN NOT NULL DEFAULT TRUE,
    created_at             TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at             TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
                               ON UPDATE CURRENT_TIMESTAMP
);

-- ----------------------------------------------------------------------------
-- COURSES  (such as: CS / SE / DS / CC)
-- ----------------------------------------------------------------------------
CREATE TABLE courses (
    id      BIGINT AUTO_INCREMENT PRIMARY KEY,
    code    VARCHAR(10)  NOT NULL UNIQUE,
    name    VARCHAR(150) NOT NULL
);

-- ----------------------------------------------------------------------------
-- ACADEMIC_YEAR_SETTINGS
-- (single system-wide setting, editable only by the Timetabling Team - e.g. "2026/27".)
-- ----------------------------------------------------------------------------
CREATE TABLE academic_year_settings (
    id                  BIGINT AUTO_INCREMENT PRIMARY KEY,
    current_year_label  VARCHAR(20) NOT NULL,
    updated_by          BIGINT NULL,
    updated_at          TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

    CONSTRAINT fk_yearsettings_updated_by FOREIGN KEY (updated_by) REFERENCES users(id)
);

-- ----------------------------------------------------------------------------
-- MODULES
-- ----------------------------------------------------------------------------
CREATE TABLE modules (
    id          BIGINT AUTO_INCREMENT PRIMARY KEY,
    code        VARCHAR(20)  NOT NULL UNIQUE,
    name        VARCHAR(150) NOT NULL
);

-- ----------------------------------------------------------------------------
-- MODULE_COURSES
-- ----------------------------------------------------------------------------
CREATE TABLE module_courses (
    module_id   BIGINT NOT NULL,
    course_id   BIGINT NOT NULL,
    PRIMARY KEY (module_id, course_id),

    CONSTRAINT fk_modcourse_module FOREIGN KEY (module_id) REFERENCES modules(id) ON DELETE CASCADE,
    CONSTRAINT fk_modcourse_course FOREIGN KEY (course_id) REFERENCES courses(id) ON DELETE CASCADE
);

-- ----------------------------------------------------------------------------
-- ROOMS
-- ----------------------------------------------------------------------------
CREATE TABLE rooms (
    id          BIGINT AUTO_INCREMENT PRIMARY KEY,
    name        VARCHAR(50)  NOT NULL UNIQUE,
    building    VARCHAR(100) NOT NULL,
    capacity    INT NOT NULL
);

-- ----------------------------------------------------------------------------
-- TIMETABLE_SESSIONS
-- ----------------------------------------------------------------------------
CREATE TABLE timetable_sessions (
    id                  BIGINT AUTO_INCREMENT PRIMARY KEY,
    module_id           BIGINT NOT NULL,
    room_id             BIGINT NOT NULL,
    lecturer_id         BIGINT NOT NULL,
    session_type        ENUM('LECTURE', 'SEMINAR', 'LAB', 'TUTORIAL', 'SURGERY', 'PROJECT',
                              'WORKSHOP', 'ASSESSMENT', 'DROP_IN', 'OTHER') NOT NULL,
    day_of_week         ENUM('MON','TUE','WED','THU','FRI') NOT NULL,
    start_time          TIME NOT NULL,
    end_time            TIME NOT NULL,
    block               TINYINT NOT NULL,
    part_number         TINYINT NULL,
    session_label       VARCHAR(100) NULL,
    related_request_id  BIGINT NULL,
    -- soft cancellation (Session Removal category)
    cancelled_at             TIMESTAMP NULL,
    cancelled_by_request_id  BIGINT NULL,
    created_at          TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT fk_session_module   FOREIGN KEY (module_id)   REFERENCES modules(id),
    CONSTRAINT fk_session_room     FOREIGN KEY (room_id)     REFERENCES rooms(id),
    CONSTRAINT fk_session_lecturer FOREIGN KEY (lecturer_id) REFERENCES users(id)
);

-- ----------------------------------------------------------------------------
-- SESSION_CANCELLED_WEEKS  
-- (Session Removal category, partial cancellation:
-- when only specific weeks are being removed rather than the whole session
-- mirrors request_weeks' simple pair-table pattern. A whole-session cancellation 
-- uses timetable_sessions.cancelled_at instead and doesn't need rows here.)
-- ----------------------------------------------------------------------------
CREATE TABLE session_cancelled_weeks (
    session_id     BIGINT NOT NULL,
    week_in_block  TINYINT NOT NULL,
    PRIMARY KEY (session_id, week_in_block),

    CONSTRAINT fk_cancelledweek_session FOREIGN KEY (session_id) REFERENCES timetable_sessions(id)
);

-- ----------------------------------------------------------------------------
-- SESSION_COURSES
-- ----------------------------------------------------------------------------
CREATE TABLE session_courses (
    session_id  BIGINT NOT NULL,
    course_id   BIGINT NOT NULL,
    PRIMARY KEY (session_id, course_id),

    CONSTRAINT fk_sesscourse_session FOREIGN KEY (session_id) REFERENCES timetable_sessions(id) ON DELETE CASCADE,
    CONSTRAINT fk_sesscourse_course  FOREIGN KEY (course_id)  REFERENCES courses(id)
);

-- ----------------------------------------------------------------------------
-- REQUESTS
-- ----------------------------------------------------------------------------
CREATE TABLE requests (
    id                        BIGINT AUTO_INCREMENT PRIMARY KEY,
    type                      ENUM('CONSTRAINT', 'CHANGE') NOT NULL,
    constraint_kind           ENUM('MODULE', 'PERSONAL') NULL,
    requester_id              BIGINT NOT NULL,
    session_id                BIGINT NULL,

    status                    ENUM('AWAITING_DECISION', 'DRAFT_COMPLETE', 'IN_PROGRESS',
                                    'ACCEPTED', 'REJECTED', 'COMPLETE')
                                  NOT NULL DEFAULT 'AWAITING_DECISION',

    is_firm                   BOOLEAN NULL,
    category                  VARCHAR(50) NULL,
    description               TEXT NULL,
    reason                    TEXT NULL,
    reason_comment            TEXT NULL,

    department_id             BIGINT NULL,
    primary_module_id         BIGINT NULL,
    linked_module_id          BIGINT NULL,
    additional_linked_modules TEXT NULL,
    block                     TINYINT NULL,
    week_mode                 ENUM('ALL_REMAINING', 'SINGLE', 'MULTIPLE') NULL,
    day_of_week               ENUM('MON','TUE','WED','THU','FRI') NULL,
    start_time                TIME NULL,
    duration_hours            TINYINT NULL,
    learning_activity         VARCHAR(100) NULL,
    personal_tutor_detail     VARCHAR(255) NULL,
    activity_detail           TEXT NULL,
    title_technical           VARCHAR(255) NULL,
    campus                    VARCHAR(50) NOT NULL DEFAULT 'Clifton',
    room_type                 ENUM('OFFSITE', 'POOLED', 'RESTRICTED', 'ONLINE', 'NO_ROOM_REQ') NULL,
    preferred_room_layout     ENUM('NONE','OFFSITE','COLLABORATIVE','IT','RESTRICTED_STUDIO','ROWS',
                                    'RESTRICTED_OTHER','RESTRICTED_IT','TIERED_FIXED_ROWS','GROUP_TECHNOLOGY',
                                    'SMALL_GROUP','FLAT_FIXED_ROWS','RESTRICTED_LABORATORY','SCALE_UP',
                                    'HORSESHOE','TERCO_GROUP_TECHNOLOGY','RESTRICTED_WORKSHOP','HYFLEARNING',
                                    'INDEPENDENT_MS_TEAMS_LINK')
                                  NULL DEFAULT 'NONE',
    specific_room_id          BIGINT NULL,
    feature                   ENUM('NONE','STEP_FREE_ACCESS','BLACKOUT','PODIUM_AT_FRONT','SINK',
                                    'HEIGHT_ADJUSTABLE_DESK','NO_CATERING','STAGE')
                                  NULL DEFAULT 'NONE',
    software                  VARCHAR(255) NULL,
    support_team_staff        VARCHAR(255) NULL,
    lecture_capture           BOOLEAN NULL,
    note                      TEXT NULL,

    -- PERSONAL-constraint fields
    unavailable_from_date     DATE NULL,
    unavailable_to_date       DATE NULL,
    unavailable_from_time     TIME NULL,
    unavailable_to_time       TIME NULL,

    -- CHANGE-request fields
    end_time                  TIME NULL,
    room_booking_needed       BOOLEAN NULL,
    preferred_room_answer     ENUM('YES', 'NO', 'ONLINE') NULL,
    change_category           ENUM('SESSION_TIME','CLASHES','ROOM_TYPE','ADDITIONAL_SESSION',
                                    'ROOM_BOOKING','STUDENT_ALLOCATION','STAFF_CHANGE','SESSION_DATE',
                                    'SESSION_REMOVAL','MERGE_SESSIONS_GROUPS','OTHER')
                                  NULL,
    rationale                 TEXT NULL,
    benefit_to_students       TEXT NULL,
    academic_period           ENUM('HALF_YEAR_1', 'HALF_YEAR_2', 'FULL_YEAR') NULL,
    -- snapshotting the year label at submission time (e.g. "2026/27") 
    academic_year_label       VARCHAR(20) NULL,

    -- category-specific fields (Increment 2 category-first redesign)
    clashing_session_id       BIGINT NULL,
    preferred_new_lecturer_id BIGINT NULL,

    created_at                TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at                TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
                                  ON UPDATE CURRENT_TIMESTAMP,

    CONSTRAINT fk_request_requester           FOREIGN KEY (requester_id)             REFERENCES users(id),
    CONSTRAINT fk_request_session             FOREIGN KEY (session_id)               REFERENCES timetable_sessions(id),
    CONSTRAINT fk_request_department          FOREIGN KEY (department_id)            REFERENCES courses(id),
    CONSTRAINT fk_request_primary_module      FOREIGN KEY (primary_module_id)        REFERENCES modules(id),
    CONSTRAINT fk_request_linked_module       FOREIGN KEY (linked_module_id)         REFERENCES modules(id),
    CONSTRAINT fk_request_specific_room       FOREIGN KEY (specific_room_id)         REFERENCES rooms(id),
    CONSTRAINT fk_request_clashing_session    FOREIGN KEY (clashing_session_id)      REFERENCES timetable_sessions(id),
    CONSTRAINT fk_request_preferred_lecturer  FOREIGN KEY (preferred_new_lecturer_id) REFERENCES users(id)
);

-- ----------------------------------------------------------------------------
-- REQUEST_WEEKS
-- ----------------------------------------------------------------------------
CREATE TABLE request_weeks (
    request_id      BIGINT NOT NULL,
    week_in_block    TINYINT NOT NULL,
    PRIMARY KEY (request_id, week_in_block),

    CONSTRAINT fk_reqweek_request FOREIGN KEY (request_id) REFERENCES requests(id) ON DELETE CASCADE
);

-- ----------------------------------------------------------------------------
-- REQUEST_ROOMS  
-- (module-based constraints: several acceptable rooms rather than pinning to one specific room).
-- ----------------------------------------------------------------------------
CREATE TABLE request_rooms (
    request_id  BIGINT NOT NULL,
    room_id     BIGINT NOT NULL,
    PRIMARY KEY (request_id, room_id),

    CONSTRAINT fk_reqroom_request FOREIGN KEY (request_id) REFERENCES requests(id) ON DELETE CASCADE,
    CONSTRAINT fk_reqroom_room    FOREIGN KEY (room_id)    REFERENCES rooms(id)
);

-- ----------------------------------------------------------------------------
-- REQUEST_GROUPS
-- (module-based constraints: one request can cover several
-- lab/seminar groups at once, each optionally naming a different intended teacher)
-- ----------------------------------------------------------------------------
CREATE TABLE request_groups (
    id                    BIGINT AUTO_INCREMENT PRIMARY KEY,
    request_id            BIGINT NOT NULL,
    group_label           VARCHAR(100) NOT NULL,
    preferred_lecturer_id BIGINT NULL,

    CONSTRAINT fk_reqgroup_request  FOREIGN KEY (request_id)            REFERENCES requests(id) ON DELETE CASCADE,
    CONSTRAINT fk_reqgroup_lecturer FOREIGN KEY (preferred_lecturer_id) REFERENCES users(id)
);

-- ----------------------------------------------------------------------------
-- REQUEST_MERGE_SESSIONS  (CHANGE requests, "Merge sessions/groups" category:
-- which existing sessions the lecturer wants combined into one. At least 2
-- rows expected for a real merge request.)
-- ----------------------------------------------------------------------------
CREATE TABLE request_merge_sessions (
    request_id  BIGINT NOT NULL,
    session_id  BIGINT NOT NULL,
    PRIMARY KEY (request_id, session_id),

    CONSTRAINT fk_reqmerge_request FOREIGN KEY (request_id) REFERENCES requests(id) ON DELETE CASCADE,
    CONSTRAINT fk_reqmerge_session FOREIGN KEY (session_id) REFERENCES timetable_sessions(id)
);

-- ----------------------------------------------------------------------------
-- REQUEST_UNAVAILABLE_DAYS  (PERSONAL constraints: which day(s) of the week
-- the lecturer is unavailable - separate from request_weeks, which is a
-- MODULE-constraint concept scoped to a specific block)
-- ----------------------------------------------------------------------------
CREATE TABLE request_unavailable_days (
    request_id   BIGINT NOT NULL,
    day_of_week  ENUM('MON','TUE','WED','THU','FRI') NOT NULL,
    PRIMARY KEY (request_id, day_of_week),

    CONSTRAINT fk_requnavail_request FOREIGN KEY (request_id) REFERENCES requests(id) ON DELETE CASCADE
);

-- ----------------------------------------------------------------------------
-- SESSION_OVERRIDES  (Timetabling Team's "Update Session" feature)
--
-- Every timetable_sessions row recurs identically every week within its block.
-- To move just one or a few weeks without touching the recurring pattern,
-- TT creates an override here instead - the base session stays as
-- the "normal" pattern, and any week listed in session_override_weeks uses
-- this override's day/time/room instead.
--
-- "All weeks ahead in this block" scope does NOT use this table 
-- ----------------------------------------------------------------------------
CREATE TABLE session_overrides (
    id                  BIGINT AUTO_INCREMENT PRIMARY KEY,
    session_id          BIGINT NOT NULL,
    new_day_of_week     ENUM('MON','TUE','WED','THU','FRI') NOT NULL,
    new_start_time      TIME NOT NULL,
    new_end_time        TIME NOT NULL,
    new_room_id         BIGINT NULL,          -- NULL = keep the base session's room
    related_request_id  BIGINT NULL,
    reason              TEXT NULL,
    created_by           BIGINT NOT NULL,
    created_at          TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT fk_override_session         FOREIGN KEY (session_id)         REFERENCES timetable_sessions(id) ON DELETE CASCADE,
    CONSTRAINT fk_override_room            FOREIGN KEY (new_room_id)        REFERENCES rooms(id),
    CONSTRAINT fk_override_request         FOREIGN KEY (related_request_id) REFERENCES requests(id),
    CONSTRAINT fk_override_created_by      FOREIGN KEY (created_by)         REFERENCES users(id)
);

-- ----------------------------------------------------------------------------
-- SESSION_OVERRIDE_WEEKS  (which week(s) in the block a given override applies to)
-- ----------------------------------------------------------------------------
CREATE TABLE session_override_weeks (
    override_id     BIGINT NOT NULL,
    week_in_block    TINYINT NOT NULL,
    PRIMARY KEY (override_id, week_in_block),

    CONSTRAINT fk_overrideweek_override FOREIGN KEY (override_id) REFERENCES session_overrides(id) ON DELETE CASCADE
);

-- ----------------------------------------------------------------------------
-- REQUEST_MODULES (legacy, kept for possible Increment 2 use)
-- ----------------------------------------------------------------------------
CREATE TABLE request_modules (
    request_id  BIGINT NOT NULL,
    module_id   BIGINT NOT NULL,
    PRIMARY KEY (request_id, module_id),

    CONSTRAINT fk_reqmod_request FOREIGN KEY (request_id) REFERENCES requests(id) ON DELETE CASCADE,
    CONSTRAINT fk_reqmod_module  FOREIGN KEY (module_id)  REFERENCES modules(id)
);

-- ----------------------------------------------------------------------------
-- REQUEST_COMMENTS
-- ----------------------------------------------------------------------------
CREATE TABLE request_comments (
    id          BIGINT AUTO_INCREMENT PRIMARY KEY,
    request_id  BIGINT NOT NULL,
    user_id     BIGINT NOT NULL,
    comment     TEXT NOT NULL,
    created_at  TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT fk_comment_request FOREIGN KEY (request_id) REFERENCES requests(id) ON DELETE CASCADE,
    CONSTRAINT fk_comment_user    FOREIGN KEY (user_id)    REFERENCES users(id)
);

-- ----------------------------------------------------------------------------
-- COMMENT_ATTACHMENTS  (one optional file per comment - PDF/DOC/DOCX/PNG/JPEG only,
-- 10MB cap enforced at the application layer. 
-- Stored as a BLOB directly in MySQL rather than on the filesystem)
-- ----------------------------------------------------------------------------
CREATE TABLE comment_attachments (
    id            BIGINT AUTO_INCREMENT PRIMARY KEY,
    comment_id    BIGINT NOT NULL,
    file_name     VARCHAR(255) NOT NULL,
    content_type  VARCHAR(100) NOT NULL,
    file_size     BIGINT NOT NULL,
    file_data     MEDIUMBLOB NOT NULL,
    uploaded_at   TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT fk_attachment_comment FOREIGN KEY (comment_id) REFERENCES request_comments(id) ON DELETE CASCADE
);

-- ----------------------------------------------------------------------------
-- NOTIFICATIONS
-- ----------------------------------------------------------------------------
CREATE TABLE notifications (
    id                   BIGINT AUTO_INCREMENT PRIMARY KEY,
    recipient_id         BIGINT NOT NULL,
    type                 VARCHAR(50) NOT NULL,  -- e.g. REQUEST_STATUS_CHANGED, AWAITING_DECISION, VIOLATION, CHANGE_IN_QUEUE
    message              TEXT NOT NULL,
    related_request_id   BIGINT NULL,
    related_session_id   BIGINT NULL,
    is_read              BOOLEAN NOT NULL DEFAULT FALSE,
    created_at           TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT fk_notification_recipient FOREIGN KEY (recipient_id)       REFERENCES users(id),
    CONSTRAINT fk_notification_request   FOREIGN KEY (related_request_id) REFERENCES requests(id),
    CONSTRAINT fk_notification_session   FOREIGN KEY (related_session_id) REFERENCES timetable_sessions(id)
);

-- ----------------------------------------------------------------------------
-- ACTIVITY_LOG
-- ----------------------------------------------------------------------------
CREATE TABLE activity_log (
    id                     BIGINT AUTO_INCREMENT PRIMARY KEY,
    event_type             VARCHAR(50) NOT NULL,  -- SESSION_CREATED, SESSION_UPDATED, SESSION_CANCELLED, REQUEST_SUBMITTED, REQUEST_STATUS_CHANGED
    description            TEXT NOT NULL,
    actor_id               BIGINT NULL,            -- who performed the action (null if not meaningfully attributable)
    affected_lecturer_id   BIGINT NULL,             -- whose session/request this concerns - drives Lecturer-scoped visibility
    related_session_id     BIGINT NULL,             -- drives Student-scoped visibility (via this session's courses/group)
    related_request_id     BIGINT NULL,
    created_at              TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT fk_activitylog_actor    FOREIGN KEY (actor_id)             REFERENCES users(id),
    CONSTRAINT fk_activitylog_lecturer FOREIGN KEY (affected_lecturer_id) REFERENCES users(id),
    CONSTRAINT fk_activitylog_session  FOREIGN KEY (related_session_id)   REFERENCES timetable_sessions(id),
    CONSTRAINT fk_activitylog_request  FOREIGN KEY (related_request_id)   REFERENCES requests(id)
);

-- ----------------------------------------------------------------------------
-- EMAIL_LOG  (audit trail of every email actually sent through SMTP)
-- ----------------------------------------------------------------------------
CREATE TABLE email_log (
    id                   BIGINT AUTO_INCREMENT PRIMARY KEY,
    recipient_email      VARCHAR(255) NOT NULL,
    subject              VARCHAR(255) NOT NULL,
    body                 TEXT NOT NULL,
    related_course_id    BIGINT NULL,
    related_session_id   BIGINT NULL,
    status               ENUM('SENT', 'FAILED') NOT NULL,
    error_message        TEXT NULL,
    sent_at              TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT fk_emaillog_course  FOREIGN KEY (related_course_id)  REFERENCES courses(id),
    CONSTRAINT fk_emaillog_session FOREIGN KEY (related_session_id) REFERENCES timetable_sessions(id)
);


-- ============================================================================
-- SEED DATA
-- ============================================================================

INSERT INTO users (username, email, password_hash, full_name, role, must_change_password) VALUES
    ('neil.s',    'neil.sculthorpe@ntu.ac.uk',    '$2b$10$UjLWB.N1yJ.zx/qYWIk2DuA2So2YnXGJkxxwrMJRMyIvJfr6a0OLe', 'Neil Sculthorpe',        'LECTURER', TRUE),
    ('thomas.h',  'thomas.hughesroberts@ntu.ac.uk', '$2b$10$UjLWB.N1yJ.zx/qYWIk2DuA2So2YnXGJkxxwrMJRMyIvJfr6a0OLe', 'Thomas Hughes-Roberts',  'LECTURER', TRUE),
    ('pedro.m',   'pedro.machado@ntu.ac.uk',      '$2b$10$UjLWB.N1yJ.zx/qYWIk2DuA2So2YnXGJkxxwrMJRMyIvJfr6a0OLe', 'Pedro Machado',          'LECTURER', TRUE),
    ('taha.o',    'taha.osman@ntu.ac.uk',         '$2b$10$UjLWB.N1yJ.zx/qYWIk2DuA2So2YnXGJkxxwrMJRMyIvJfr6a0OLe', 'Taha Osman',             'LECTURER', TRUE),
    ('brad.p',    'brad.patrick@ntu.ac.uk',       '$2b$10$UjLWB.N1yJ.zx/qYWIk2DuA2So2YnXGJkxxwrMJRMyIvJfr6a0OLe', 'Brad Patrick',           'LECTURER', TRUE),
    ('david.a',   'david.adama@ntu.ac.uk',        '$2b$10$UjLWB.N1yJ.zx/qYWIk2DuA2So2YnXGJkxxwrMJRMyIvJfr6a0OLe', 'David Adama',            'LECTURER', TRUE),
    ('jo.h',      'jo.hartley@ntu.ac.uk',         '$2b$10$UjLWB.N1yJ.zx/qYWIk2DuA2So2YnXGJkxxwrMJRMyIvJfr6a0OLe', 'Jo Hartley',             'LECTURER', TRUE),
    ('mohid.n',   'malikmohidnadeem@gmail.com',   '$2b$10$UjLWB.N1yJ.zx/qYWIk2DuA2So2YnXGJkxxwrMJRMyIvJfr6a0OLe', 'Mohid Nadeem',           'LECTURER', TRUE),
    ('craig.w',   'craig.webster@ntu.ac.uk',      '$2b$10$UjLWB.N1yJ.zx/qYWIk2DuA2So2YnXGJkxxwrMJRMyIvJfr6a0OLe', 'Craig Webster',          'LECTURER', TRUE),
    ('aria.b.acd',  'aria.bennett@ntu.ac.uk',  '$2b$10$UjLWB.N1yJ.zx/qYWIk2DuA2So2YnXGJkxxwrMJRMyIvJfr6a0OLe', 'Aria Bennett',  'TIMETABLING_TEAM', TRUE),
    ('sam.w.acd',   'sam.whitfield@ntu.ac.uk', '$2b$10$UjLWB.N1yJ.zx/qYWIk2DuA2So2YnXGJkxxwrMJRMyIvJfr6a0OLe', 'Sam Whitfield', 'TIMETABLING_TEAM', TRUE),
    ('leo.c.acd',   'leo.carter@ntu.ac.uk',    '$2b$10$UjLWB.N1yJ.zx/qYWIk2DuA2So2YnXGJkxxwrMJRMyIvJfr6a0OLe', 'Leo Carter',    'TIMETABLING_TEAM', TRUE),
    ('admin.a',     'admin@ntu.ac.uk',         '$2b$10$UjLWB.N1yJ.zx/qYWIk2DuA2So2YnXGJkxxwrMJRMyIvJfr6a0OLe', 'Alex Admin',    'ADMIN', TRUE);

INSERT INTO courses (code, name) VALUES
    ('CS', 'MSc Computer Science'),
    ('SE', 'MSc Software Engineering'),
    ('DS', 'MSc Data Science'),
    ('CC', 'MSc Cloud Computing');

INSERT INTO users (username, email, password_hash, full_name, role, must_change_password, course_id)
SELECT 'dihom.nadeem', 'malikmohidnadeem04@gmail.com', '$2b$10$UjLWB.N1yJ.zx/qYWIk2DuA2So2YnXGJkxxwrMJRMyIvJfr6a0OLe', 'Dihom Nadeem', 'STUDENT', TRUE, id FROM courses WHERE code = 'SE';
INSERT INTO users (username, email, password_hash, full_name, role, must_change_password, course_id)
SELECT 'ali.jodat', 'alijodat16@gmail.com', '$2b$10$UjLWB.N1yJ.zx/qYWIk2DuA2So2YnXGJkxxwrMJRMyIvJfr6a0OLe', 'Ali Jodat', 'STUDENT', TRUE, id FROM courses WHERE code = 'DS';
INSERT INTO users (username, email, password_hash, full_name, role, must_change_password, course_id)
SELECT 'roma.nadeem', 'romaisanadeem19@gmail.com', '$2b$10$UjLWB.N1yJ.zx/qYWIk2DuA2So2YnXGJkxxwrMJRMyIvJfr6a0OLe', 'Roma Nadeem', 'STUDENT', TRUE, id FROM courses WHERE code = 'CC';
INSERT INTO users (username, email, password_hash, full_name, role, must_change_password, course_id)
SELECT 'aiman.mahadik', 'aimanmahadik10@gmail.com', '$2b$10$UjLWB.N1yJ.zx/qYWIk2DuA2So2YnXGJkxxwrMJRMyIvJfr6a0OLe', 'Aiman Mahadik', 'STUDENT', TRUE, id FROM courses WHERE code = 'CS';

INSERT INTO academic_year_settings (current_year_label) VALUES ('2026/27');

INSERT INTO modules (code, name) VALUES
    ('CS4001', 'Advanced Software Engineering'),
    ('CS4002', 'Systems Analysis and Design'),
    ('CS4003', 'Mobile Interactive Systems'),
    ('CS4004', 'Service-Oriented Cloud Technologies'),
    ('CS4005', 'Applied Artificial Intelligence'),
    ('CS4006', 'Research Methods'),
    ('CS4007', 'Major Project'),
    ('SE7001', 'Fundamentals of Software Programming'),
    ('SE7002', 'Software Design and Development'),
    ('SE7003', 'Software Project Management'),
    ('DS5001', 'Fundamentals of Big Data and Its Infrastructure'),
    ('DS5002', 'Introduction to Computer Programming'),
    ('DS5003', 'Statistical Data Analysis and Visualisation'),
    ('DS5004', 'Deriving Business Value from Data Analytics'),
    ('CC9001', 'Entrepreneurial Leadership and Project Management'),
    ('CC9002', 'Enterprise and Cloud Systems Management'),
    ('CC9003', 'Network and Cloud Security');

INSERT INTO module_courses (module_id, course_id)
SELECT m.id, c.id FROM modules m, courses c WHERE
    (m.code = 'CS4001' AND c.code IN ('CS','CC')) OR
    (m.code = 'CS4002' AND c.code IN ('CS','SE')) OR
    (m.code = 'CS4003' AND c.code IN ('CS','SE')) OR
    (m.code = 'CS4004' AND c.code IN ('CS','CC')) OR
    (m.code = 'CS4005' AND c.code IN ('CS','DS')) OR
    (m.code = 'CS4006' AND c.code IN ('CS','SE','DS','CC')) OR
    (m.code = 'CS4007' AND c.code IN ('CS','SE','DS','CC')) OR
    (m.code = 'SE7001' AND c.code = 'SE') OR
    (m.code = 'SE7002' AND c.code = 'SE') OR
    (m.code = 'SE7003' AND c.code = 'SE') OR
    (m.code = 'DS5001' AND c.code = 'DS') OR
    (m.code = 'DS5002' AND c.code = 'DS') OR
    (m.code = 'DS5003' AND c.code = 'DS') OR
    (m.code = 'DS5004' AND c.code = 'DS') OR
    (m.code = 'CC9001' AND c.code = 'CC') OR
    (m.code = 'CC9002' AND c.code = 'CC') OR
    (m.code = 'CC9003' AND c.code = 'CC');

INSERT INTO rooms (name, building, capacity) VALUES
    ('ERD105', 'Erasmus Darwin',      120),
    ('ERD106', 'Erasmus Darwin',      120),
    ('ERD107', 'Erasmus Darwin',      100),
    ('MAE205', 'Mary Ann Evans',       24),
    ('MAE206', 'Mary Ann Evans',       24),
    ('ISC005', 'ISTEC',                24),
    ('ISC026', 'ISTEC',                24),
    ('ISC030', 'ISTEC',                24),
    ('AB10',   'Ada Byron King',       20),
    ('AB12',   'Ada Byron King',       20),
    ('AB14',   'Ada Byron King',       20),
    ('JC005',  'John Clare',          150),
    ('JC006',  'John Clare',          150),
    ('ONLINE', 'Online',             9999);


-- ============================================================================
-- TIMETABLE SESSIONS (around 46 sessions)
-- ============================================================================

INSERT INTO timetable_sessions (module_id, room_id, lecturer_id, session_type, day_of_week, start_time, end_time, block)
SELECT m.id, r.id, u.id, 'LECTURE', 'MON', '11:00', '13:00', 1 FROM modules m, rooms r, users u WHERE m.code='CC9001' AND r.name='ERD105' AND u.full_name='Jo Hartley' AND NOT EXISTS (SELECT 1 FROM timetable_sessions x WHERE x.module_id=m.id AND x.day_of_week='MON' AND x.start_time='11:00:00' AND x.room_id=r.id);
INSERT INTO timetable_sessions (module_id, room_id, lecturer_id, session_type, day_of_week, start_time, end_time, block)
SELECT m.id, r.id, u.id, 'SEMINAR', 'WED', '09:00', '11:00', 1 FROM modules m, rooms r, users u WHERE m.code='CC9001' AND r.name='AB14' AND u.full_name='Jo Hartley' AND NOT EXISTS (SELECT 1 FROM timetable_sessions x WHERE x.module_id=m.id AND x.day_of_week='WED' AND x.start_time='09:00:00' AND x.room_id=r.id);
INSERT INTO timetable_sessions (module_id, room_id, lecturer_id, session_type, day_of_week, start_time, end_time, block)
SELECT m.id, r.id, u.id, 'LECTURE', 'MON', '09:00', '10:00', 1 FROM modules m, rooms r, users u WHERE m.code='CS4001' AND r.name='ERD105' AND u.full_name='Pedro Machado' AND NOT EXISTS (SELECT 1 FROM timetable_sessions x WHERE x.module_id=m.id AND x.day_of_week='MON' AND x.start_time='09:00:00' AND x.room_id=r.id);
INSERT INTO timetable_sessions (module_id, room_id, lecturer_id, session_type, day_of_week, start_time, end_time, block)
SELECT m.id, r.id, u.id, 'LAB', 'MON', '14:00', '16:00', 1 FROM modules m, rooms r, users u WHERE m.code='CS4001' AND r.name='MAE206' AND u.full_name='Brad Patrick' AND NOT EXISTS (SELECT 1 FROM timetable_sessions x WHERE x.module_id=m.id AND x.day_of_week='MON' AND x.start_time='14:00:00' AND x.room_id=r.id);
INSERT INTO timetable_sessions (module_id, room_id, lecturer_id, session_type, day_of_week, start_time, end_time, block)
SELECT m.id, r.id, u.id, 'LAB', 'MON', '16:00', '18:00', 1 FROM modules m, rooms r, users u WHERE m.code='CS4001' AND r.name='MAE206' AND u.full_name='Pedro Machado' AND NOT EXISTS (SELECT 1 FROM timetable_sessions x WHERE x.module_id=m.id AND x.day_of_week='MON' AND x.start_time='16:00:00' AND x.room_id=r.id);
INSERT INTO timetable_sessions (module_id, room_id, lecturer_id, session_type, day_of_week, start_time, end_time, block)
SELECT m.id, r.id, u.id, 'SURGERY', 'TUE', '09:00', '10:00', 1 FROM modules m, rooms r, users u WHERE m.code='CS4001' AND r.name='AB10' AND u.full_name='Pedro Machado' AND NOT EXISTS (SELECT 1 FROM timetable_sessions x WHERE x.module_id=m.id AND x.day_of_week='TUE' AND x.start_time='09:00:00' AND x.room_id=r.id);
INSERT INTO timetable_sessions (module_id, room_id, lecturer_id, session_type, day_of_week, start_time, end_time, block)
SELECT m.id, r.id, u.id, 'LECTURE', 'TUE', '11:00', '13:00', 1 FROM modules m, rooms r, users u WHERE m.code='CS4002' AND r.name='ERD106' AND u.full_name='Mohid Nadeem' AND NOT EXISTS (SELECT 1 FROM timetable_sessions x WHERE x.module_id=m.id AND x.day_of_week='TUE' AND x.start_time='11:00:00' AND x.room_id=r.id);
INSERT INTO timetable_sessions (module_id, room_id, lecturer_id, session_type, day_of_week, start_time, end_time, block)
SELECT m.id, r.id, u.id, 'SEMINAR', 'WED', '11:00', '13:00', 1 FROM modules m, rooms r, users u WHERE m.code='CS4002' AND r.name='AB12' AND u.full_name='Mohid Nadeem' AND NOT EXISTS (SELECT 1 FROM timetable_sessions x WHERE x.module_id=m.id AND x.day_of_week='WED' AND x.start_time='11:00:00' AND x.room_id=r.id);
INSERT INTO timetable_sessions (module_id, room_id, lecturer_id, session_type, day_of_week, start_time, end_time, block)
SELECT m.id, r.id, u.id, 'LECTURE', 'WED', '09:00', '11:00', 1 FROM modules m, rooms r, users u WHERE m.code='DS5001' AND r.name='ERD106' AND u.full_name='Craig Webster' AND NOT EXISTS (SELECT 1 FROM timetable_sessions x WHERE x.module_id=m.id AND x.day_of_week='WED' AND x.start_time='09:00:00' AND x.room_id=r.id);
INSERT INTO timetable_sessions (module_id, room_id, lecturer_id, session_type, day_of_week, start_time, end_time, block)
SELECT m.id, r.id, u.id, 'LAB', 'WED', '11:00', '13:00', 1 FROM modules m, rooms r, users u WHERE m.code='DS5001' AND r.name='ISC005' AND u.full_name='Craig Webster' AND NOT EXISTS (SELECT 1 FROM timetable_sessions x WHERE x.module_id=m.id AND x.day_of_week='WED' AND x.start_time='11:00:00' AND x.room_id=r.id);
INSERT INTO timetable_sessions (module_id, room_id, lecturer_id, session_type, day_of_week, start_time, end_time, block)
SELECT m.id, r.id, u.id, 'LECTURE', 'THU', '09:00', '11:00', 1 FROM modules m, rooms r, users u WHERE m.code='DS5002' AND r.name='ERD105' AND u.full_name='Pedro Machado' AND NOT EXISTS (SELECT 1 FROM timetable_sessions x WHERE x.module_id=m.id AND x.day_of_week='THU' AND x.start_time='09:00:00' AND x.room_id=r.id);
INSERT INTO timetable_sessions (module_id, room_id, lecturer_id, session_type, day_of_week, start_time, end_time, block)
SELECT m.id, r.id, u.id, 'LAB', 'THU', '11:00', '13:00', 1 FROM modules m, rooms r, users u WHERE m.code='DS5002' AND r.name='ISC030' AND u.full_name='Pedro Machado' AND NOT EXISTS (SELECT 1 FROM timetable_sessions x WHERE x.module_id=m.id AND x.day_of_week='THU' AND x.start_time='11:00:00' AND x.room_id=r.id);
INSERT INTO timetable_sessions (module_id, room_id, lecturer_id, session_type, day_of_week, start_time, end_time, block)
SELECT m.id, r.id, u.id, 'LECTURE', 'MON', '09:00', '11:00', 1 FROM modules m, rooms r, users u WHERE m.code='SE7001' AND r.name='ERD107' AND u.full_name='Neil Sculthorpe' AND NOT EXISTS (SELECT 1 FROM timetable_sessions x WHERE x.module_id=m.id AND x.day_of_week='MON' AND x.start_time='09:00:00' AND x.room_id=r.id);
INSERT INTO timetable_sessions (module_id, room_id, lecturer_id, session_type, day_of_week, start_time, end_time, block)
SELECT m.id, r.id, u.id, 'LAB', 'MON', '11:00', '13:00', 1 FROM modules m, rooms r, users u WHERE m.code='SE7001' AND r.name='MAE205' AND u.full_name='Neil Sculthorpe' AND NOT EXISTS (SELECT 1 FROM timetable_sessions x WHERE x.module_id=m.id AND x.day_of_week='MON' AND x.start_time='11:00:00' AND x.room_id=r.id);
INSERT INTO timetable_sessions (module_id, room_id, lecturer_id, session_type, day_of_week, start_time, end_time, block)
SELECT m.id, r.id, u.id, 'LECTURE', 'WED', '09:00', '11:00', 2 FROM modules m, rooms r, users u WHERE m.code='CC9002' AND r.name='ERD107' AND u.full_name='Taha Osman' AND NOT EXISTS (SELECT 1 FROM timetable_sessions x WHERE x.module_id=m.id AND x.day_of_week='WED' AND x.start_time='09:00:00' AND x.room_id=r.id);
INSERT INTO timetable_sessions (module_id, room_id, lecturer_id, session_type, day_of_week, start_time, end_time, block)
SELECT m.id, r.id, u.id, 'SEMINAR', 'TUE', '14:00', '16:00', 2 FROM modules m, rooms r, users u WHERE m.code='CC9002' AND r.name='AB12' AND u.full_name='Taha Osman' AND NOT EXISTS (SELECT 1 FROM timetable_sessions x WHERE x.module_id=m.id AND x.day_of_week='TUE' AND x.start_time='14:00:00' AND x.room_id=r.id);
INSERT INTO timetable_sessions (module_id, room_id, lecturer_id, session_type, day_of_week, start_time, end_time, block)
SELECT m.id, r.id, u.id, 'LECTURE', 'MON', '09:00', '10:00', 2 FROM modules m, rooms r, users u WHERE m.code='CS4003' AND r.name='ERD105' AND u.full_name='Brad Patrick' AND NOT EXISTS (SELECT 1 FROM timetable_sessions x WHERE x.module_id=m.id AND x.day_of_week='MON' AND x.start_time='09:00:00' AND x.room_id=r.id);
INSERT INTO timetable_sessions (module_id, room_id, lecturer_id, session_type, day_of_week, start_time, end_time, block)
SELECT m.id, r.id, u.id, 'LAB', 'MON', '14:00', '16:00', 2 FROM modules m, rooms r, users u WHERE m.code='CS4003' AND r.name='MAE206' AND u.full_name='Brad Patrick' AND NOT EXISTS (SELECT 1 FROM timetable_sessions x WHERE x.module_id=m.id AND x.day_of_week='MON' AND x.start_time='14:00:00' AND x.room_id=r.id);
INSERT INTO timetable_sessions (module_id, room_id, lecturer_id, session_type, day_of_week, start_time, end_time, block)
SELECT m.id, r.id, u.id, 'LAB', 'MON', '16:00', '18:00', 2 FROM modules m, rooms r, users u WHERE m.code='CS4003' AND r.name='MAE206' AND u.full_name='Brad Patrick' AND NOT EXISTS (SELECT 1 FROM timetable_sessions x WHERE x.module_id=m.id AND x.day_of_week='MON' AND x.start_time='16:00:00' AND x.room_id=r.id);
INSERT INTO timetable_sessions (module_id, room_id, lecturer_id, session_type, day_of_week, start_time, end_time, block)
SELECT m.id, r.id, u.id, 'SURGERY', 'TUE', '09:00', '10:00', 2 FROM modules m, rooms r, users u WHERE m.code='CS4003' AND r.name='AB10' AND u.full_name='Brad Patrick' AND NOT EXISTS (SELECT 1 FROM timetable_sessions x WHERE x.module_id=m.id AND x.day_of_week='TUE' AND x.start_time='09:00:00' AND x.room_id=r.id);
INSERT INTO timetable_sessions (module_id, room_id, lecturer_id, session_type, day_of_week, start_time, end_time, block)
SELECT m.id, r.id, u.id, 'LECTURE', 'TUE', '11:00', '13:00', 2 FROM modules m, rooms r, users u WHERE m.code='CS4004' AND r.name='ERD106' AND u.full_name='Taha Osman' AND NOT EXISTS (SELECT 1 FROM timetable_sessions x WHERE x.module_id=m.id AND x.day_of_week='TUE' AND x.start_time='11:00:00' AND x.room_id=r.id);
INSERT INTO timetable_sessions (module_id, room_id, lecturer_id, session_type, day_of_week, start_time, end_time, block)
SELECT m.id, r.id, u.id, 'LAB', 'MON', '11:00', '13:00', 2 FROM modules m, rooms r, users u WHERE m.code='CS4004' AND r.name='MAE205' AND u.full_name='Taha Osman' AND NOT EXISTS (SELECT 1 FROM timetable_sessions x WHERE x.module_id=m.id AND x.day_of_week='MON' AND x.start_time='11:00:00' AND x.room_id=r.id);
INSERT INTO timetable_sessions (module_id, room_id, lecturer_id, session_type, day_of_week, start_time, end_time, block)
SELECT m.id, r.id, u.id, 'LAB', 'WED', '14:00', '16:00', 2 FROM modules m, rooms r, users u WHERE m.code='CS4004' AND r.name='MAE205' AND u.full_name='Craig Webster' AND NOT EXISTS (SELECT 1 FROM timetable_sessions x WHERE x.module_id=m.id AND x.day_of_week='WED' AND x.start_time='14:00:00' AND x.room_id=r.id);
INSERT INTO timetable_sessions (module_id, room_id, lecturer_id, session_type, day_of_week, start_time, end_time, block)
SELECT m.id, r.id, u.id, 'LECTURE', 'THU', '09:00', '11:00', 2 FROM modules m, rooms r, users u WHERE m.code='DS5003' AND r.name='ERD105' AND u.full_name='Brad Patrick' AND NOT EXISTS (SELECT 1 FROM timetable_sessions x WHERE x.module_id=m.id AND x.day_of_week='THU' AND x.start_time='09:00:00' AND x.room_id=r.id);
INSERT INTO timetable_sessions (module_id, room_id, lecturer_id, session_type, day_of_week, start_time, end_time, block)
SELECT m.id, r.id, u.id, 'LAB', 'THU', '11:00', '13:00', 2 FROM modules m, rooms r, users u WHERE m.code='DS5003' AND r.name='ISC005' AND u.full_name='Brad Patrick' AND NOT EXISTS (SELECT 1 FROM timetable_sessions x WHERE x.module_id=m.id AND x.day_of_week='THU' AND x.start_time='11:00:00' AND x.room_id=r.id);
INSERT INTO timetable_sessions (module_id, room_id, lecturer_id, session_type, day_of_week, start_time, end_time, block)
SELECT m.id, r.id, u.id, 'LECTURE', 'MON', '09:00', '11:00', 2 FROM modules m, rooms r, users u WHERE m.code='DS5004' AND r.name='ERD107' AND u.full_name='Jo Hartley' AND NOT EXISTS (SELECT 1 FROM timetable_sessions x WHERE x.module_id=m.id AND x.day_of_week='MON' AND x.start_time='09:00:00' AND x.room_id=r.id);
INSERT INTO timetable_sessions (module_id, room_id, lecturer_id, session_type, day_of_week, start_time, end_time, block)
SELECT m.id, r.id, u.id, 'SEMINAR', 'MON', '11:00', '13:00', 2 FROM modules m, rooms r, users u WHERE m.code='DS5004' AND r.name='AB12' AND u.full_name='Jo Hartley' AND NOT EXISTS (SELECT 1 FROM timetable_sessions x WHERE x.module_id=m.id AND x.day_of_week='MON' AND x.start_time='11:00:00' AND x.room_id=r.id);
INSERT INTO timetable_sessions (module_id, room_id, lecturer_id, session_type, day_of_week, start_time, end_time, block)
SELECT m.id, r.id, u.id, 'LECTURE', 'WED', '09:00', '11:00', 2 FROM modules m, rooms r, users u WHERE m.code='SE7002' AND r.name='ERD105' AND u.full_name='Neil Sculthorpe' AND NOT EXISTS (SELECT 1 FROM timetable_sessions x WHERE x.module_id=m.id AND x.day_of_week='WED' AND x.start_time='09:00:00' AND x.room_id=r.id);
INSERT INTO timetable_sessions (module_id, room_id, lecturer_id, session_type, day_of_week, start_time, end_time, block)
SELECT m.id, r.id, u.id, 'SEMINAR', 'WED', '11:00', '13:00', 2 FROM modules m, rooms r, users u WHERE m.code='SE7002' AND r.name='AB14' AND u.full_name='Neil Sculthorpe' AND NOT EXISTS (SELECT 1 FROM timetable_sessions x WHERE x.module_id=m.id AND x.day_of_week='WED' AND x.start_time='11:00:00' AND x.room_id=r.id);
INSERT INTO timetable_sessions (module_id, room_id, lecturer_id, session_type, day_of_week, start_time, end_time, block)
SELECT m.id, r.id, u.id, 'LECTURE', 'MON', '11:00', '13:00', 3 FROM modules m, rooms r, users u WHERE m.code='CC9003' AND r.name='ERD107' AND u.full_name='David Adama' AND NOT EXISTS (SELECT 1 FROM timetable_sessions x WHERE x.module_id=m.id AND x.day_of_week='MON' AND x.start_time='11:00:00' AND x.room_id=r.id);
INSERT INTO timetable_sessions (module_id, room_id, lecturer_id, session_type, day_of_week, start_time, end_time, block)
SELECT m.id, r.id, u.id, 'LAB', 'WED', '11:00', '13:00', 3 FROM modules m, rooms r, users u WHERE m.code='CC9003' AND r.name='ISC026' AND u.full_name='David Adama' AND NOT EXISTS (SELECT 1 FROM timetable_sessions x WHERE x.module_id=m.id AND x.day_of_week='WED' AND x.start_time='11:00:00' AND x.room_id=r.id);
INSERT INTO timetable_sessions (module_id, room_id, lecturer_id, session_type, day_of_week, start_time, end_time, block)
SELECT m.id, r.id, u.id, 'LECTURE', 'TUE', '11:00', '13:00', 3 FROM modules m, rooms r, users u WHERE m.code='CS4005' AND r.name='ERD106' AND u.full_name='David Adama' AND NOT EXISTS (SELECT 1 FROM timetable_sessions x WHERE x.module_id=m.id AND x.day_of_week='TUE' AND x.start_time='11:00:00' AND x.room_id=r.id);
INSERT INTO timetable_sessions (module_id, room_id, lecturer_id, session_type, day_of_week, start_time, end_time, block)
SELECT m.id, r.id, u.id, 'LAB', 'TUE', '14:00', '16:00', 3 FROM modules m, rooms r, users u WHERE m.code='CS4005' AND r.name='MAE206' AND u.full_name='David Adama' AND NOT EXISTS (SELECT 1 FROM timetable_sessions x WHERE x.module_id=m.id AND x.day_of_week='TUE' AND x.start_time='14:00:00' AND x.room_id=r.id);
INSERT INTO timetable_sessions (module_id, room_id, lecturer_id, session_type, day_of_week, start_time, end_time, block)
SELECT m.id, r.id, u.id, 'LAB', 'WED', '14:00', '16:00', 3 FROM modules m, rooms r, users u WHERE m.code='CS4005' AND r.name='ISC005' AND u.full_name='Jo Hartley' AND NOT EXISTS (SELECT 1 FROM timetable_sessions x WHERE x.module_id=m.id AND x.day_of_week='WED' AND x.start_time='14:00:00' AND x.room_id=r.id);
INSERT INTO timetable_sessions (module_id, room_id, lecturer_id, session_type, day_of_week, start_time, end_time, block)
SELECT m.id, r.id, u.id, 'LECTURE', 'MON', '09:00', '10:00', 3 FROM modules m, rooms r, users u WHERE m.code='CS4006' AND r.name='JC005' AND u.full_name='Thomas Hughes-Roberts' AND NOT EXISTS (SELECT 1 FROM timetable_sessions x WHERE x.module_id=m.id AND x.day_of_week='MON' AND x.start_time='09:00:00' AND x.room_id=r.id);
INSERT INTO timetable_sessions (module_id, room_id, lecturer_id, session_type, day_of_week, start_time, end_time, block)
SELECT m.id, r.id, u.id, 'SEMINAR', 'WED', '09:00', '10:00', 3 FROM modules m, rooms r, users u WHERE m.code='CS4006' AND r.name='JC006' AND u.full_name='Thomas Hughes-Roberts' AND NOT EXISTS (SELECT 1 FROM timetable_sessions x WHERE x.module_id=m.id AND x.day_of_week='WED' AND x.start_time='09:00:00' AND x.room_id=r.id);
INSERT INTO timetable_sessions (module_id, room_id, lecturer_id, session_type, day_of_week, start_time, end_time, block)
SELECT m.id, r.id, u.id, 'LECTURE', 'TUE', '09:00', '11:00', 3 FROM modules m, rooms r, users u WHERE m.code='SE7003' AND r.name='ERD105' AND u.full_name='Mohid Nadeem' AND NOT EXISTS (SELECT 1 FROM timetable_sessions x WHERE x.module_id=m.id AND x.day_of_week='TUE' AND x.start_time='09:00:00' AND x.room_id=r.id);
INSERT INTO timetable_sessions (module_id, room_id, lecturer_id, session_type, day_of_week, start_time, end_time, block)
SELECT m.id, r.id, u.id, 'SEMINAR', 'THU', '14:00', '16:00', 3 FROM modules m, rooms r, users u WHERE m.code='SE7003' AND r.name='AB12' AND u.full_name='Mohid Nadeem' AND NOT EXISTS (SELECT 1 FROM timetable_sessions x WHERE x.module_id=m.id AND x.day_of_week='THU' AND x.start_time='14:00:00' AND x.room_id=r.id);
INSERT INTO timetable_sessions (module_id, room_id, lecturer_id, session_type, day_of_week, start_time, end_time, block, session_label)
SELECT m.id, r.id, u.id, 'PROJECT', 'MON', '09:00', '10:00', 4, 'Project Briefing' FROM modules m, rooms r, users u WHERE m.code='CS4007' AND r.name='JC005' AND u.full_name='Thomas Hughes-Roberts' AND NOT EXISTS (SELECT 1 FROM timetable_sessions x WHERE x.module_id=m.id AND x.day_of_week='MON' AND x.start_time='09:00:00' AND x.room_id=r.id);
INSERT INTO timetable_sessions (module_id, room_id, lecturer_id, session_type, day_of_week, start_time, end_time, block, session_label)
SELECT m.id, r.id, u.id, 'PROJECT', 'WED', '09:00', '10:00', 4, 'Supervision Session' FROM modules m, rooms r, users u WHERE m.code='CS4007' AND r.name='JC006' AND u.full_name='Thomas Hughes-Roberts' AND NOT EXISTS (SELECT 1 FROM timetable_sessions x WHERE x.module_id=m.id AND x.day_of_week='WED' AND x.start_time='09:00:00' AND x.room_id=r.id);
INSERT INTO timetable_sessions (module_id, room_id, lecturer_id, session_type, day_of_week, start_time, end_time, block)
SELECT m.id, r.id, u.id, 'LAB', 'THU', '14:00', '16:00', 1 FROM modules m, rooms r, users u WHERE m.code='CS4001' AND r.name='MAE205' AND u.full_name='Mohid Nadeem' AND NOT EXISTS (SELECT 1 FROM timetable_sessions x WHERE x.module_id=m.id AND x.day_of_week='THU' AND x.start_time='14:00:00' AND x.room_id=r.id);
INSERT INTO timetable_sessions (module_id, room_id, lecturer_id, session_type, day_of_week, start_time, end_time, block)
SELECT m.id, r.id, u.id, 'LAB', 'WED', '14:00', '16:00', 1 FROM modules m, rooms r, users u WHERE m.code='DS5002' AND r.name='ISC030' AND u.full_name='Craig Webster' AND NOT EXISTS (SELECT 1 FROM timetable_sessions x WHERE x.module_id=m.id AND x.day_of_week='WED' AND x.start_time='14:00:00' AND x.room_id=r.id);
INSERT INTO timetable_sessions (module_id, room_id, lecturer_id, session_type, day_of_week, start_time, end_time, block)
SELECT m.id, r.id, u.id, 'LAB', 'FRI', '09:00', '11:00', 1 FROM modules m, rooms r, users u WHERE m.code='DS5002' AND r.name='ISC030' AND u.full_name='Jo Hartley' AND NOT EXISTS (SELECT 1 FROM timetable_sessions x WHERE x.module_id=m.id AND x.day_of_week='FRI' AND x.start_time='09:00:00' AND x.room_id=r.id);
INSERT INTO timetable_sessions (module_id, room_id, lecturer_id, session_type, day_of_week, start_time, end_time, block)
SELECT m.id, r.id, u.id, 'LAB', 'THU', '14:00', '16:00', 2 FROM modules m, rooms r, users u WHERE m.code='CS4003' AND r.name='MAE205' AND u.full_name='David Adama' AND NOT EXISTS (SELECT 1 FROM timetable_sessions x WHERE x.module_id=m.id AND x.day_of_week='THU' AND x.start_time='14:00:00' AND x.room_id=r.id);
INSERT INTO timetable_sessions (module_id, room_id, lecturer_id, session_type, day_of_week, start_time, end_time, block)
SELECT m.id, r.id, u.id, 'LAB', 'FRI', '11:00', '13:00', 2 FROM modules m, rooms r, users u WHERE m.code='CS4004' AND r.name='MAE206' AND u.full_name='Neil Sculthorpe' AND NOT EXISTS (SELECT 1 FROM timetable_sessions x WHERE x.module_id=m.id AND x.day_of_week='FRI' AND x.start_time='11:00:00' AND x.room_id=r.id);
INSERT INTO timetable_sessions (module_id, room_id, lecturer_id, session_type, day_of_week, start_time, end_time, block)
SELECT m.id, r.id, u.id, 'LAB', 'FRI', '11:00', '13:00', 3 FROM modules m, rooms r, users u WHERE m.code='CS4005' AND r.name='ISC005' AND u.full_name='Neil Sculthorpe' AND NOT EXISTS (SELECT 1 FROM timetable_sessions x WHERE x.module_id=m.id AND x.day_of_week='FRI' AND x.start_time='11:00:00' AND x.room_id=r.id);

-- ============================================================================
-- SESSION_COURSES
-- ============================================================================

INSERT INTO session_courses (session_id, course_id) SELECT ts.id, co.id FROM timetable_sessions ts JOIN modules m ON m.id=ts.module_id JOIN rooms r ON r.id=ts.room_id, courses co WHERE m.code='CC9001' AND ts.day_of_week='MON' AND ts.start_time='11:00:00' AND r.name='ERD105' AND co.code='CC' AND NOT EXISTS (SELECT 1 FROM session_courses sc2 WHERE sc2.session_id=ts.id AND sc2.course_id=co.id);
INSERT INTO session_courses (session_id, course_id) SELECT ts.id, co.id FROM timetable_sessions ts JOIN modules m ON m.id=ts.module_id JOIN rooms r ON r.id=ts.room_id, courses co WHERE m.code='CC9001' AND ts.day_of_week='WED' AND ts.start_time='09:00:00' AND r.name='AB14' AND co.code='CC' AND NOT EXISTS (SELECT 1 FROM session_courses sc2 WHERE sc2.session_id=ts.id AND sc2.course_id=co.id);
INSERT INTO session_courses (session_id, course_id) SELECT ts.id, co.id FROM timetable_sessions ts JOIN modules m ON m.id=ts.module_id JOIN rooms r ON r.id=ts.room_id, courses co WHERE m.code='CS4001' AND ts.day_of_week='MON' AND ts.start_time='09:00:00' AND r.name='ERD105' AND co.code='CC' AND NOT EXISTS (SELECT 1 FROM session_courses sc2 WHERE sc2.session_id=ts.id AND sc2.course_id=co.id);
INSERT INTO session_courses (session_id, course_id) SELECT ts.id, co.id FROM timetable_sessions ts JOIN modules m ON m.id=ts.module_id JOIN rooms r ON r.id=ts.room_id, courses co WHERE m.code='CS4001' AND ts.day_of_week='MON' AND ts.start_time='09:00:00' AND r.name='ERD105' AND co.code='CS' AND NOT EXISTS (SELECT 1 FROM session_courses sc2 WHERE sc2.session_id=ts.id AND sc2.course_id=co.id);
INSERT INTO session_courses (session_id, course_id) SELECT ts.id, co.id FROM timetable_sessions ts JOIN modules m ON m.id=ts.module_id JOIN rooms r ON r.id=ts.room_id, courses co WHERE m.code='CS4001' AND ts.day_of_week='MON' AND ts.start_time='14:00:00' AND r.name='MAE206' AND co.code='CS' AND NOT EXISTS (SELECT 1 FROM session_courses sc2 WHERE sc2.session_id=ts.id AND sc2.course_id=co.id);
INSERT INTO session_courses (session_id, course_id) SELECT ts.id, co.id FROM timetable_sessions ts JOIN modules m ON m.id=ts.module_id JOIN rooms r ON r.id=ts.room_id, courses co WHERE m.code='CS4001' AND ts.day_of_week='MON' AND ts.start_time='16:00:00' AND r.name='MAE206' AND co.code='CC' AND NOT EXISTS (SELECT 1 FROM session_courses sc2 WHERE sc2.session_id=ts.id AND sc2.course_id=co.id);
INSERT INTO session_courses (session_id, course_id) SELECT ts.id, co.id FROM timetable_sessions ts JOIN modules m ON m.id=ts.module_id JOIN rooms r ON r.id=ts.room_id, courses co WHERE m.code='CS4001' AND ts.day_of_week='TUE' AND ts.start_time='09:00:00' AND r.name='AB10' AND co.code='CC' AND NOT EXISTS (SELECT 1 FROM session_courses sc2 WHERE sc2.session_id=ts.id AND sc2.course_id=co.id);
INSERT INTO session_courses (session_id, course_id) SELECT ts.id, co.id FROM timetable_sessions ts JOIN modules m ON m.id=ts.module_id JOIN rooms r ON r.id=ts.room_id, courses co WHERE m.code='CS4001' AND ts.day_of_week='TUE' AND ts.start_time='09:00:00' AND r.name='AB10' AND co.code='CS' AND NOT EXISTS (SELECT 1 FROM session_courses sc2 WHERE sc2.session_id=ts.id AND sc2.course_id=co.id);
INSERT INTO session_courses (session_id, course_id) SELECT ts.id, co.id FROM timetable_sessions ts JOIN modules m ON m.id=ts.module_id JOIN rooms r ON r.id=ts.room_id, courses co WHERE m.code='CS4002' AND ts.day_of_week='TUE' AND ts.start_time='11:00:00' AND r.name='ERD106' AND co.code='CS' AND NOT EXISTS (SELECT 1 FROM session_courses sc2 WHERE sc2.session_id=ts.id AND sc2.course_id=co.id);
INSERT INTO session_courses (session_id, course_id) SELECT ts.id, co.id FROM timetable_sessions ts JOIN modules m ON m.id=ts.module_id JOIN rooms r ON r.id=ts.room_id, courses co WHERE m.code='CS4002' AND ts.day_of_week='TUE' AND ts.start_time='11:00:00' AND r.name='ERD106' AND co.code='SE' AND NOT EXISTS (SELECT 1 FROM session_courses sc2 WHERE sc2.session_id=ts.id AND sc2.course_id=co.id);
INSERT INTO session_courses (session_id, course_id) SELECT ts.id, co.id FROM timetable_sessions ts JOIN modules m ON m.id=ts.module_id JOIN rooms r ON r.id=ts.room_id, courses co WHERE m.code='CS4002' AND ts.day_of_week='WED' AND ts.start_time='11:00:00' AND r.name='AB12' AND co.code='CS' AND NOT EXISTS (SELECT 1 FROM session_courses sc2 WHERE sc2.session_id=ts.id AND sc2.course_id=co.id);
INSERT INTO session_courses (session_id, course_id) SELECT ts.id, co.id FROM timetable_sessions ts JOIN modules m ON m.id=ts.module_id JOIN rooms r ON r.id=ts.room_id, courses co WHERE m.code='CS4002' AND ts.day_of_week='WED' AND ts.start_time='11:00:00' AND r.name='AB12' AND co.code='SE' AND NOT EXISTS (SELECT 1 FROM session_courses sc2 WHERE sc2.session_id=ts.id AND sc2.course_id=co.id);
INSERT INTO session_courses (session_id, course_id) SELECT ts.id, co.id FROM timetable_sessions ts JOIN modules m ON m.id=ts.module_id JOIN rooms r ON r.id=ts.room_id, courses co WHERE m.code='DS5001' AND ts.day_of_week='WED' AND ts.start_time='09:00:00' AND r.name='ERD106' AND co.code='DS' AND NOT EXISTS (SELECT 1 FROM session_courses sc2 WHERE sc2.session_id=ts.id AND sc2.course_id=co.id);
INSERT INTO session_courses (session_id, course_id) SELECT ts.id, co.id FROM timetable_sessions ts JOIN modules m ON m.id=ts.module_id JOIN rooms r ON r.id=ts.room_id, courses co WHERE m.code='DS5001' AND ts.day_of_week='WED' AND ts.start_time='11:00:00' AND r.name='ISC005' AND co.code='DS' AND NOT EXISTS (SELECT 1 FROM session_courses sc2 WHERE sc2.session_id=ts.id AND sc2.course_id=co.id);
INSERT INTO session_courses (session_id, course_id) SELECT ts.id, co.id FROM timetable_sessions ts JOIN modules m ON m.id=ts.module_id JOIN rooms r ON r.id=ts.room_id, courses co WHERE m.code='DS5002' AND ts.day_of_week='THU' AND ts.start_time='09:00:00' AND r.name='ERD105' AND co.code='DS' AND NOT EXISTS (SELECT 1 FROM session_courses sc2 WHERE sc2.session_id=ts.id AND sc2.course_id=co.id);
INSERT INTO session_courses (session_id, course_id) SELECT ts.id, co.id FROM timetable_sessions ts JOIN modules m ON m.id=ts.module_id JOIN rooms r ON r.id=ts.room_id, courses co WHERE m.code='DS5002' AND ts.day_of_week='THU' AND ts.start_time='11:00:00' AND r.name='ISC030' AND co.code='DS' AND NOT EXISTS (SELECT 1 FROM session_courses sc2 WHERE sc2.session_id=ts.id AND sc2.course_id=co.id);
INSERT INTO session_courses (session_id, course_id) SELECT ts.id, co.id FROM timetable_sessions ts JOIN modules m ON m.id=ts.module_id JOIN rooms r ON r.id=ts.room_id, courses co WHERE m.code='SE7001' AND ts.day_of_week='MON' AND ts.start_time='09:00:00' AND r.name='ERD107' AND co.code='SE' AND NOT EXISTS (SELECT 1 FROM session_courses sc2 WHERE sc2.session_id=ts.id AND sc2.course_id=co.id);
INSERT INTO session_courses (session_id, course_id) SELECT ts.id, co.id FROM timetable_sessions ts JOIN modules m ON m.id=ts.module_id JOIN rooms r ON r.id=ts.room_id, courses co WHERE m.code='SE7001' AND ts.day_of_week='MON' AND ts.start_time='11:00:00' AND r.name='MAE205' AND co.code='SE' AND NOT EXISTS (SELECT 1 FROM session_courses sc2 WHERE sc2.session_id=ts.id AND sc2.course_id=co.id);
INSERT INTO session_courses (session_id, course_id) SELECT ts.id, co.id FROM timetable_sessions ts JOIN modules m ON m.id=ts.module_id JOIN rooms r ON r.id=ts.room_id, courses co WHERE m.code='CC9002' AND ts.day_of_week='WED' AND ts.start_time='09:00:00' AND r.name='ERD107' AND co.code='CC' AND NOT EXISTS (SELECT 1 FROM session_courses sc2 WHERE sc2.session_id=ts.id AND sc2.course_id=co.id);
INSERT INTO session_courses (session_id, course_id) SELECT ts.id, co.id FROM timetable_sessions ts JOIN modules m ON m.id=ts.module_id JOIN rooms r ON r.id=ts.room_id, courses co WHERE m.code='CC9002' AND ts.day_of_week='TUE' AND ts.start_time='14:00:00' AND r.name='AB12' AND co.code='CC' AND NOT EXISTS (SELECT 1 FROM session_courses sc2 WHERE sc2.session_id=ts.id AND sc2.course_id=co.id);
INSERT INTO session_courses (session_id, course_id) SELECT ts.id, co.id FROM timetable_sessions ts JOIN modules m ON m.id=ts.module_id JOIN rooms r ON r.id=ts.room_id, courses co WHERE m.code='CS4003' AND ts.day_of_week='MON' AND ts.start_time='09:00:00' AND r.name='ERD105' AND co.code='CS' AND NOT EXISTS (SELECT 1 FROM session_courses sc2 WHERE sc2.session_id=ts.id AND sc2.course_id=co.id);
INSERT INTO session_courses (session_id, course_id) SELECT ts.id, co.id FROM timetable_sessions ts JOIN modules m ON m.id=ts.module_id JOIN rooms r ON r.id=ts.room_id, courses co WHERE m.code='CS4003' AND ts.day_of_week='MON' AND ts.start_time='09:00:00' AND r.name='ERD105' AND co.code='SE' AND NOT EXISTS (SELECT 1 FROM session_courses sc2 WHERE sc2.session_id=ts.id AND sc2.course_id=co.id);
INSERT INTO session_courses (session_id, course_id) SELECT ts.id, co.id FROM timetable_sessions ts JOIN modules m ON m.id=ts.module_id JOIN rooms r ON r.id=ts.room_id, courses co WHERE m.code='CS4003' AND ts.day_of_week='MON' AND ts.start_time='14:00:00' AND r.name='MAE206' AND co.code='CS' AND NOT EXISTS (SELECT 1 FROM session_courses sc2 WHERE sc2.session_id=ts.id AND sc2.course_id=co.id);
INSERT INTO session_courses (session_id, course_id) SELECT ts.id, co.id FROM timetable_sessions ts JOIN modules m ON m.id=ts.module_id JOIN rooms r ON r.id=ts.room_id, courses co WHERE m.code='CS4003' AND ts.day_of_week='MON' AND ts.start_time='16:00:00' AND r.name='MAE206' AND co.code='SE' AND NOT EXISTS (SELECT 1 FROM session_courses sc2 WHERE sc2.session_id=ts.id AND sc2.course_id=co.id);
INSERT INTO session_courses (session_id, course_id) SELECT ts.id, co.id FROM timetable_sessions ts JOIN modules m ON m.id=ts.module_id JOIN rooms r ON r.id=ts.room_id, courses co WHERE m.code='CS4003' AND ts.day_of_week='TUE' AND ts.start_time='09:00:00' AND r.name='AB10' AND co.code='CS' AND NOT EXISTS (SELECT 1 FROM session_courses sc2 WHERE sc2.session_id=ts.id AND sc2.course_id=co.id);
INSERT INTO session_courses (session_id, course_id) SELECT ts.id, co.id FROM timetable_sessions ts JOIN modules m ON m.id=ts.module_id JOIN rooms r ON r.id=ts.room_id, courses co WHERE m.code='CS4003' AND ts.day_of_week='TUE' AND ts.start_time='09:00:00' AND r.name='AB10' AND co.code='SE' AND NOT EXISTS (SELECT 1 FROM session_courses sc2 WHERE sc2.session_id=ts.id AND sc2.course_id=co.id);
INSERT INTO session_courses (session_id, course_id) SELECT ts.id, co.id FROM timetable_sessions ts JOIN modules m ON m.id=ts.module_id JOIN rooms r ON r.id=ts.room_id, courses co WHERE m.code='CS4004' AND ts.day_of_week='TUE' AND ts.start_time='11:00:00' AND r.name='ERD106' AND co.code='CC' AND NOT EXISTS (SELECT 1 FROM session_courses sc2 WHERE sc2.session_id=ts.id AND sc2.course_id=co.id);
INSERT INTO session_courses (session_id, course_id) SELECT ts.id, co.id FROM timetable_sessions ts JOIN modules m ON m.id=ts.module_id JOIN rooms r ON r.id=ts.room_id, courses co WHERE m.code='CS4004' AND ts.day_of_week='TUE' AND ts.start_time='11:00:00' AND r.name='ERD106' AND co.code='CS' AND NOT EXISTS (SELECT 1 FROM session_courses sc2 WHERE sc2.session_id=ts.id AND sc2.course_id=co.id);
INSERT INTO session_courses (session_id, course_id) SELECT ts.id, co.id FROM timetable_sessions ts JOIN modules m ON m.id=ts.module_id JOIN rooms r ON r.id=ts.room_id, courses co WHERE m.code='CS4004' AND ts.day_of_week='MON' AND ts.start_time='11:00:00' AND r.name='MAE205' AND co.code='CS' AND NOT EXISTS (SELECT 1 FROM session_courses sc2 WHERE sc2.session_id=ts.id AND sc2.course_id=co.id);
INSERT INTO session_courses (session_id, course_id) SELECT ts.id, co.id FROM timetable_sessions ts JOIN modules m ON m.id=ts.module_id JOIN rooms r ON r.id=ts.room_id, courses co WHERE m.code='CS4004' AND ts.day_of_week='WED' AND ts.start_time='14:00:00' AND r.name='MAE205' AND co.code='CC' AND NOT EXISTS (SELECT 1 FROM session_courses sc2 WHERE sc2.session_id=ts.id AND sc2.course_id=co.id);
INSERT INTO session_courses (session_id, course_id) SELECT ts.id, co.id FROM timetable_sessions ts JOIN modules m ON m.id=ts.module_id JOIN rooms r ON r.id=ts.room_id, courses co WHERE m.code='DS5003' AND ts.day_of_week='THU' AND ts.start_time='09:00:00' AND r.name='ERD105' AND co.code='DS' AND NOT EXISTS (SELECT 1 FROM session_courses sc2 WHERE sc2.session_id=ts.id AND sc2.course_id=co.id);
INSERT INTO session_courses (session_id, course_id) SELECT ts.id, co.id FROM timetable_sessions ts JOIN modules m ON m.id=ts.module_id JOIN rooms r ON r.id=ts.room_id, courses co WHERE m.code='DS5003' AND ts.day_of_week='THU' AND ts.start_time='11:00:00' AND r.name='ISC005' AND co.code='DS' AND NOT EXISTS (SELECT 1 FROM session_courses sc2 WHERE sc2.session_id=ts.id AND sc2.course_id=co.id);
INSERT INTO session_courses (session_id, course_id) SELECT ts.id, co.id FROM timetable_sessions ts JOIN modules m ON m.id=ts.module_id JOIN rooms r ON r.id=ts.room_id, courses co WHERE m.code='DS5004' AND ts.day_of_week='MON' AND ts.start_time='09:00:00' AND r.name='ERD107' AND co.code='DS' AND NOT EXISTS (SELECT 1 FROM session_courses sc2 WHERE sc2.session_id=ts.id AND sc2.course_id=co.id);
INSERT INTO session_courses (session_id, course_id) SELECT ts.id, co.id FROM timetable_sessions ts JOIN modules m ON m.id=ts.module_id JOIN rooms r ON r.id=ts.room_id, courses co WHERE m.code='DS5004' AND ts.day_of_week='MON' AND ts.start_time='11:00:00' AND r.name='AB12' AND co.code='DS' AND NOT EXISTS (SELECT 1 FROM session_courses sc2 WHERE sc2.session_id=ts.id AND sc2.course_id=co.id);
INSERT INTO session_courses (session_id, course_id) SELECT ts.id, co.id FROM timetable_sessions ts JOIN modules m ON m.id=ts.module_id JOIN rooms r ON r.id=ts.room_id, courses co WHERE m.code='SE7002' AND ts.day_of_week='WED' AND ts.start_time='09:00:00' AND r.name='ERD105' AND co.code='SE' AND NOT EXISTS (SELECT 1 FROM session_courses sc2 WHERE sc2.session_id=ts.id AND sc2.course_id=co.id);
INSERT INTO session_courses (session_id, course_id) SELECT ts.id, co.id FROM timetable_sessions ts JOIN modules m ON m.id=ts.module_id JOIN rooms r ON r.id=ts.room_id, courses co WHERE m.code='SE7002' AND ts.day_of_week='WED' AND ts.start_time='11:00:00' AND r.name='AB14' AND co.code='SE' AND NOT EXISTS (SELECT 1 FROM session_courses sc2 WHERE sc2.session_id=ts.id AND sc2.course_id=co.id);
INSERT INTO session_courses (session_id, course_id) SELECT ts.id, co.id FROM timetable_sessions ts JOIN modules m ON m.id=ts.module_id JOIN rooms r ON r.id=ts.room_id, courses co WHERE m.code='CC9003' AND ts.day_of_week='MON' AND ts.start_time='11:00:00' AND r.name='ERD107' AND co.code='CC' AND NOT EXISTS (SELECT 1 FROM session_courses sc2 WHERE sc2.session_id=ts.id AND sc2.course_id=co.id);
INSERT INTO session_courses (session_id, course_id) SELECT ts.id, co.id FROM timetable_sessions ts JOIN modules m ON m.id=ts.module_id JOIN rooms r ON r.id=ts.room_id, courses co WHERE m.code='CC9003' AND ts.day_of_week='WED' AND ts.start_time='11:00:00' AND r.name='ISC026' AND co.code='CC' AND NOT EXISTS (SELECT 1 FROM session_courses sc2 WHERE sc2.session_id=ts.id AND sc2.course_id=co.id);
INSERT INTO session_courses (session_id, course_id) SELECT ts.id, co.id FROM timetable_sessions ts JOIN modules m ON m.id=ts.module_id JOIN rooms r ON r.id=ts.room_id, courses co WHERE m.code='CS4005' AND ts.day_of_week='TUE' AND ts.start_time='11:00:00' AND r.name='ERD106' AND co.code='CS' AND NOT EXISTS (SELECT 1 FROM session_courses sc2 WHERE sc2.session_id=ts.id AND sc2.course_id=co.id);
INSERT INTO session_courses (session_id, course_id) SELECT ts.id, co.id FROM timetable_sessions ts JOIN modules m ON m.id=ts.module_id JOIN rooms r ON r.id=ts.room_id, courses co WHERE m.code='CS4005' AND ts.day_of_week='TUE' AND ts.start_time='11:00:00' AND r.name='ERD106' AND co.code='DS' AND NOT EXISTS (SELECT 1 FROM session_courses sc2 WHERE sc2.session_id=ts.id AND sc2.course_id=co.id);
INSERT INTO session_courses (session_id, course_id) SELECT ts.id, co.id FROM timetable_sessions ts JOIN modules m ON m.id=ts.module_id JOIN rooms r ON r.id=ts.room_id, courses co WHERE m.code='CS4005' AND ts.day_of_week='TUE' AND ts.start_time='14:00:00' AND r.name='MAE206' AND co.code='CS' AND NOT EXISTS (SELECT 1 FROM session_courses sc2 WHERE sc2.session_id=ts.id AND sc2.course_id=co.id);
INSERT INTO session_courses (session_id, course_id) SELECT ts.id, co.id FROM timetable_sessions ts JOIN modules m ON m.id=ts.module_id JOIN rooms r ON r.id=ts.room_id, courses co WHERE m.code='CS4005' AND ts.day_of_week='WED' AND ts.start_time='14:00:00' AND r.name='ISC005' AND co.code='DS' AND NOT EXISTS (SELECT 1 FROM session_courses sc2 WHERE sc2.session_id=ts.id AND sc2.course_id=co.id);
INSERT INTO session_courses (session_id, course_id) SELECT ts.id, co.id FROM timetable_sessions ts JOIN modules m ON m.id=ts.module_id JOIN rooms r ON r.id=ts.room_id, courses co WHERE m.code='CS4006' AND ts.day_of_week='MON' AND ts.start_time='09:00:00' AND r.name='JC005' AND co.code='CC' AND NOT EXISTS (SELECT 1 FROM session_courses sc2 WHERE sc2.session_id=ts.id AND sc2.course_id=co.id);
INSERT INTO session_courses (session_id, course_id) SELECT ts.id, co.id FROM timetable_sessions ts JOIN modules m ON m.id=ts.module_id JOIN rooms r ON r.id=ts.room_id, courses co WHERE m.code='CS4006' AND ts.day_of_week='MON' AND ts.start_time='09:00:00' AND r.name='JC005' AND co.code='CS' AND NOT EXISTS (SELECT 1 FROM session_courses sc2 WHERE sc2.session_id=ts.id AND sc2.course_id=co.id);
INSERT INTO session_courses (session_id, course_id) SELECT ts.id, co.id FROM timetable_sessions ts JOIN modules m ON m.id=ts.module_id JOIN rooms r ON r.id=ts.room_id, courses co WHERE m.code='CS4006' AND ts.day_of_week='MON' AND ts.start_time='09:00:00' AND r.name='JC005' AND co.code='DS' AND NOT EXISTS (SELECT 1 FROM session_courses sc2 WHERE sc2.session_id=ts.id AND sc2.course_id=co.id);
INSERT INTO session_courses (session_id, course_id) SELECT ts.id, co.id FROM timetable_sessions ts JOIN modules m ON m.id=ts.module_id JOIN rooms r ON r.id=ts.room_id, courses co WHERE m.code='CS4006' AND ts.day_of_week='MON' AND ts.start_time='09:00:00' AND r.name='JC005' AND co.code='SE' AND NOT EXISTS (SELECT 1 FROM session_courses sc2 WHERE sc2.session_id=ts.id AND sc2.course_id=co.id);
INSERT INTO session_courses (session_id, course_id) SELECT ts.id, co.id FROM timetable_sessions ts JOIN modules m ON m.id=ts.module_id JOIN rooms r ON r.id=ts.room_id, courses co WHERE m.code='CS4006' AND ts.day_of_week='WED' AND ts.start_time='09:00:00' AND r.name='JC006' AND co.code='CC' AND NOT EXISTS (SELECT 1 FROM session_courses sc2 WHERE sc2.session_id=ts.id AND sc2.course_id=co.id);
INSERT INTO session_courses (session_id, course_id) SELECT ts.id, co.id FROM timetable_sessions ts JOIN modules m ON m.id=ts.module_id JOIN rooms r ON r.id=ts.room_id, courses co WHERE m.code='CS4006' AND ts.day_of_week='WED' AND ts.start_time='09:00:00' AND r.name='JC006' AND co.code='CS' AND NOT EXISTS (SELECT 1 FROM session_courses sc2 WHERE sc2.session_id=ts.id AND sc2.course_id=co.id);
INSERT INTO session_courses (session_id, course_id) SELECT ts.id, co.id FROM timetable_sessions ts JOIN modules m ON m.id=ts.module_id JOIN rooms r ON r.id=ts.room_id, courses co WHERE m.code='CS4006' AND ts.day_of_week='WED' AND ts.start_time='09:00:00' AND r.name='JC006' AND co.code='DS' AND NOT EXISTS (SELECT 1 FROM session_courses sc2 WHERE sc2.session_id=ts.id AND sc2.course_id=co.id);
INSERT INTO session_courses (session_id, course_id) SELECT ts.id, co.id FROM timetable_sessions ts JOIN modules m ON m.id=ts.module_id JOIN rooms r ON r.id=ts.room_id, courses co WHERE m.code='CS4006' AND ts.day_of_week='WED' AND ts.start_time='09:00:00' AND r.name='JC006' AND co.code='SE' AND NOT EXISTS (SELECT 1 FROM session_courses sc2 WHERE sc2.session_id=ts.id AND sc2.course_id=co.id);
INSERT INTO session_courses (session_id, course_id) SELECT ts.id, co.id FROM timetable_sessions ts JOIN modules m ON m.id=ts.module_id JOIN rooms r ON r.id=ts.room_id, courses co WHERE m.code='SE7003' AND ts.day_of_week='TUE' AND ts.start_time='09:00:00' AND r.name='ERD105' AND co.code='SE' AND NOT EXISTS (SELECT 1 FROM session_courses sc2 WHERE sc2.session_id=ts.id AND sc2.course_id=co.id);
INSERT INTO session_courses (session_id, course_id) SELECT ts.id, co.id FROM timetable_sessions ts JOIN modules m ON m.id=ts.module_id JOIN rooms r ON r.id=ts.room_id, courses co WHERE m.code='SE7003' AND ts.day_of_week='THU' AND ts.start_time='14:00:00' AND r.name='AB12' AND co.code='SE' AND NOT EXISTS (SELECT 1 FROM session_courses sc2 WHERE sc2.session_id=ts.id AND sc2.course_id=co.id);
INSERT INTO session_courses (session_id, course_id) SELECT ts.id, co.id FROM timetable_sessions ts JOIN modules m ON m.id=ts.module_id JOIN rooms r ON r.id=ts.room_id, courses co WHERE m.code='CS4007' AND ts.day_of_week='MON' AND ts.start_time='09:00:00' AND r.name='JC005' AND co.code='CC' AND NOT EXISTS (SELECT 1 FROM session_courses sc2 WHERE sc2.session_id=ts.id AND sc2.course_id=co.id);
INSERT INTO session_courses (session_id, course_id) SELECT ts.id, co.id FROM timetable_sessions ts JOIN modules m ON m.id=ts.module_id JOIN rooms r ON r.id=ts.room_id, courses co WHERE m.code='CS4007' AND ts.day_of_week='MON' AND ts.start_time='09:00:00' AND r.name='JC005' AND co.code='CS' AND NOT EXISTS (SELECT 1 FROM session_courses sc2 WHERE sc2.session_id=ts.id AND sc2.course_id=co.id);
INSERT INTO session_courses (session_id, course_id) SELECT ts.id, co.id FROM timetable_sessions ts JOIN modules m ON m.id=ts.module_id JOIN rooms r ON r.id=ts.room_id, courses co WHERE m.code='CS4007' AND ts.day_of_week='MON' AND ts.start_time='09:00:00' AND r.name='JC005' AND co.code='DS' AND NOT EXISTS (SELECT 1 FROM session_courses sc2 WHERE sc2.session_id=ts.id AND sc2.course_id=co.id);
INSERT INTO session_courses (session_id, course_id) SELECT ts.id, co.id FROM timetable_sessions ts JOIN modules m ON m.id=ts.module_id JOIN rooms r ON r.id=ts.room_id, courses co WHERE m.code='CS4007' AND ts.day_of_week='MON' AND ts.start_time='09:00:00' AND r.name='JC005' AND co.code='SE' AND NOT EXISTS (SELECT 1 FROM session_courses sc2 WHERE sc2.session_id=ts.id AND sc2.course_id=co.id);
INSERT INTO session_courses (session_id, course_id) SELECT ts.id, co.id FROM timetable_sessions ts JOIN modules m ON m.id=ts.module_id JOIN rooms r ON r.id=ts.room_id, courses co WHERE m.code='CS4007' AND ts.day_of_week='WED' AND ts.start_time='09:00:00' AND r.name='JC006' AND co.code='CC' AND NOT EXISTS (SELECT 1 FROM session_courses sc2 WHERE sc2.session_id=ts.id AND sc2.course_id=co.id);
INSERT INTO session_courses (session_id, course_id) SELECT ts.id, co.id FROM timetable_sessions ts JOIN modules m ON m.id=ts.module_id JOIN rooms r ON r.id=ts.room_id, courses co WHERE m.code='CS4007' AND ts.day_of_week='WED' AND ts.start_time='09:00:00' AND r.name='JC006' AND co.code='CS' AND NOT EXISTS (SELECT 1 FROM session_courses sc2 WHERE sc2.session_id=ts.id AND sc2.course_id=co.id);
INSERT INTO session_courses (session_id, course_id) SELECT ts.id, co.id FROM timetable_sessions ts JOIN modules m ON m.id=ts.module_id JOIN rooms r ON r.id=ts.room_id, courses co WHERE m.code='CS4007' AND ts.day_of_week='WED' AND ts.start_time='09:00:00' AND r.name='JC006' AND co.code='DS' AND NOT EXISTS (SELECT 1 FROM session_courses sc2 WHERE sc2.session_id=ts.id AND sc2.course_id=co.id);
INSERT INTO session_courses (session_id, course_id) SELECT ts.id, co.id FROM timetable_sessions ts JOIN modules m ON m.id=ts.module_id JOIN rooms r ON r.id=ts.room_id, courses co WHERE m.code='CS4007' AND ts.day_of_week='WED' AND ts.start_time='09:00:00' AND r.name='JC006' AND co.code='SE' AND NOT EXISTS (SELECT 1 FROM session_courses sc2 WHERE sc2.session_id=ts.id AND sc2.course_id=co.id);
INSERT INTO session_courses (session_id, course_id) SELECT ts.id, co.id FROM timetable_sessions ts JOIN modules m ON m.id=ts.module_id JOIN rooms r ON r.id=ts.room_id, courses co WHERE m.code='CS4001' AND ts.day_of_week='THU' AND ts.start_time='14:00:00' AND r.name='MAE205' AND co.code='CS' AND NOT EXISTS (SELECT 1 FROM session_courses sc2 WHERE sc2.session_id=ts.id AND sc2.course_id=co.id);
INSERT INTO session_courses (session_id, course_id) SELECT ts.id, co.id FROM timetable_sessions ts JOIN modules m ON m.id=ts.module_id JOIN rooms r ON r.id=ts.room_id, courses co WHERE m.code='DS5002' AND ts.day_of_week='WED' AND ts.start_time='14:00:00' AND r.name='ISC030' AND co.code='DS' AND NOT EXISTS (SELECT 1 FROM session_courses sc2 WHERE sc2.session_id=ts.id AND sc2.course_id=co.id);
INSERT INTO session_courses (session_id, course_id) SELECT ts.id, co.id FROM timetable_sessions ts JOIN modules m ON m.id=ts.module_id JOIN rooms r ON r.id=ts.room_id, courses co WHERE m.code='DS5002' AND ts.day_of_week='FRI' AND ts.start_time='09:00:00' AND r.name='ISC030' AND co.code='DS' AND NOT EXISTS (SELECT 1 FROM session_courses sc2 WHERE sc2.session_id=ts.id AND sc2.course_id=co.id);
INSERT INTO session_courses (session_id, course_id) SELECT ts.id, co.id FROM timetable_sessions ts JOIN modules m ON m.id=ts.module_id JOIN rooms r ON r.id=ts.room_id, courses co WHERE m.code='CS4003' AND ts.day_of_week='THU' AND ts.start_time='14:00:00' AND r.name='MAE205' AND co.code='CS' AND NOT EXISTS (SELECT 1 FROM session_courses sc2 WHERE sc2.session_id=ts.id AND sc2.course_id=co.id);
INSERT INTO session_courses (session_id, course_id) SELECT ts.id, co.id FROM timetable_sessions ts JOIN modules m ON m.id=ts.module_id JOIN rooms r ON r.id=ts.room_id, courses co WHERE m.code='CS4004' AND ts.day_of_week='FRI' AND ts.start_time='11:00:00' AND r.name='MAE206' AND co.code='CC' AND NOT EXISTS (SELECT 1 FROM session_courses sc2 WHERE sc2.session_id=ts.id AND sc2.course_id=co.id);
INSERT INTO session_courses (session_id, course_id) SELECT ts.id, co.id FROM timetable_sessions ts JOIN modules m ON m.id=ts.module_id JOIN rooms r ON r.id=ts.room_id, courses co WHERE m.code='CS4005' AND ts.day_of_week='FRI' AND ts.start_time='11:00:00' AND r.name='ISC005' AND co.code='DS' AND NOT EXISTS (SELECT 1 FROM session_courses sc2 WHERE sc2.session_id=ts.id AND sc2.course_id=co.id);

-- ----------------------------------------------------------------------------
-- LAB GROUP LABELS 
-- ----------------------------------------------------------------------------
UPDATE timetable_sessions ts JOIN modules m ON m.id = ts.module_id
SET ts.session_label = 'Lab — Group A'
WHERE m.code = 'CS4001' AND ts.session_type = 'LAB' AND ts.day_of_week = 'MON' AND ts.start_time = '14:00:00';
UPDATE timetable_sessions ts JOIN modules m ON m.id = ts.module_id
SET ts.session_label = 'Lab — Group B'
WHERE m.code = 'CS4001' AND ts.session_type = 'LAB' AND ts.day_of_week = 'MON' AND ts.start_time = '16:00:00';
UPDATE timetable_sessions ts JOIN modules m ON m.id = ts.module_id
SET ts.session_label = 'Lab — Group C'
WHERE m.code = 'CS4001' AND ts.session_type = 'LAB' AND ts.day_of_week = 'THU' AND ts.start_time = '14:00:00';

UPDATE timetable_sessions ts JOIN modules m ON m.id = ts.module_id
SET ts.session_label = 'Lab — Group A'
WHERE m.code = 'CS4003' AND ts.session_type = 'LAB' AND ts.day_of_week = 'MON' AND ts.start_time = '14:00:00';
UPDATE timetable_sessions ts JOIN modules m ON m.id = ts.module_id
SET ts.session_label = 'Lab — Group B'
WHERE m.code = 'CS4003' AND ts.session_type = 'LAB' AND ts.day_of_week = 'MON' AND ts.start_time = '16:00:00';
UPDATE timetable_sessions ts JOIN modules m ON m.id = ts.module_id
SET ts.session_label = 'Lab — Group C'
WHERE m.code = 'CS4003' AND ts.session_type = 'LAB' AND ts.day_of_week = 'THU' AND ts.start_time = '14:00:00';

UPDATE timetable_sessions ts JOIN modules m ON m.id = ts.module_id
SET ts.session_label = 'Lab — Group A'
WHERE m.code = 'CS4004' AND ts.session_type = 'LAB' AND ts.day_of_week = 'MON' AND ts.start_time = '11:00:00';
UPDATE timetable_sessions ts JOIN modules m ON m.id = ts.module_id
SET ts.session_label = 'Lab — Group B'
WHERE m.code = 'CS4004' AND ts.session_type = 'LAB' AND ts.day_of_week = 'WED' AND ts.start_time = '14:00:00';
UPDATE timetable_sessions ts JOIN modules m ON m.id = ts.module_id
SET ts.session_label = 'Lab — Group C'
WHERE m.code = 'CS4004' AND ts.session_type = 'LAB' AND ts.day_of_week = 'FRI' AND ts.start_time = '11:00:00';

UPDATE timetable_sessions ts JOIN modules m ON m.id = ts.module_id
SET ts.session_label = 'Lab — Group A'
WHERE m.code = 'CS4005' AND ts.session_type = 'LAB' AND ts.day_of_week = 'TUE' AND ts.start_time = '14:00:00';
UPDATE timetable_sessions ts JOIN modules m ON m.id = ts.module_id
SET ts.session_label = 'Lab — Group B'
WHERE m.code = 'CS4005' AND ts.session_type = 'LAB' AND ts.day_of_week = 'WED' AND ts.start_time = '14:00:00';
UPDATE timetable_sessions ts JOIN modules m ON m.id = ts.module_id
SET ts.session_label = 'Lab — Group C'
WHERE m.code = 'CS4005' AND ts.session_type = 'LAB' AND ts.day_of_week = 'FRI' AND ts.start_time = '11:00:00';

UPDATE timetable_sessions ts JOIN modules m ON m.id = ts.module_id
SET ts.session_label = 'Lab — Group A'
WHERE m.code = 'DS5002' AND ts.session_type = 'LAB' AND ts.day_of_week = 'WED' AND ts.start_time = '14:00:00';
UPDATE timetable_sessions ts JOIN modules m ON m.id = ts.module_id
SET ts.session_label = 'Lab — Group B'
WHERE m.code = 'DS5002' AND ts.session_type = 'LAB' AND ts.day_of_week = 'THU' AND ts.start_time = '11:00:00';
UPDATE timetable_sessions ts JOIN modules m ON m.id = ts.module_id
SET ts.session_label = 'Lab — Group C'
WHERE m.code = 'DS5002' AND ts.session_type = 'LAB' AND ts.day_of_week = 'FRI' AND ts.start_time = '09:00:00';


-- ============================================================================
-- SESSION OVERRIDES (week-varying schedule)
-- ============================================================================

-- CS4001 (Combined) weeks [2, 5, 10] -> MON 10:00-11:00 room ERD106
INSERT INTO session_overrides (session_id, new_day_of_week, new_start_time, new_end_time, new_room_id, reason, created_by) SELECT ts.id, 'MON', '10:00:00', '11:00:00', (SELECT id FROM rooms WHERE name='ERD106'), 'Planned variation per assignments sheet', u.id FROM timetable_sessions ts JOIN modules m ON m.id=ts.module_id JOIN rooms r ON r.id=ts.room_id, users u WHERE m.code='CS4001' AND ts.day_of_week='MON' AND ts.start_time='09:00:00' AND r.name='ERD105' AND u.username='aria.b.acd';
INSERT INTO session_override_weeks (override_id, week_in_block) VALUES (LAST_INSERT_ID(), 2), (LAST_INSERT_ID(), 5), (LAST_INSERT_ID(), 10);

-- CS4001 (CS) weeks [4, 10] -> MON 09:00-11:00 room MAE205
INSERT INTO session_overrides (session_id, new_day_of_week, new_start_time, new_end_time, new_room_id, reason, created_by) SELECT ts.id, 'MON', '09:00:00', '11:00:00', (SELECT id FROM rooms WHERE name='MAE205'), 'Planned variation per assignments sheet', u.id FROM timetable_sessions ts JOIN modules m ON m.id=ts.module_id JOIN rooms r ON r.id=ts.room_id, users u WHERE m.code='CS4001' AND ts.day_of_week='MON' AND ts.start_time='14:00:00' AND r.name='MAE206' AND u.username='aria.b.acd';
INSERT INTO session_override_weeks (override_id, week_in_block) VALUES (LAST_INSERT_ID(), 4), (LAST_INSERT_ID(), 10);

-- CS4002 (Combined) weeks [6, 7, 8, 9] -> MON 09:00-11:00 (room unchanged)
INSERT INTO session_overrides (session_id, new_day_of_week, new_start_time, new_end_time, new_room_id, reason, created_by) SELECT ts.id, 'MON', '09:00:00', '11:00:00', NULL, 'Planned variation per assignments sheet', u.id FROM timetable_sessions ts JOIN modules m ON m.id=ts.module_id JOIN rooms r ON r.id=ts.room_id, users u WHERE m.code='CS4002' AND ts.day_of_week='WED' AND ts.start_time='11:00:00' AND r.name='AB12' AND u.username='aria.b.acd';
INSERT INTO session_override_weeks (override_id, week_in_block) VALUES (LAST_INSERT_ID(), 6), (LAST_INSERT_ID(), 7), (LAST_INSERT_ID(), 8), (LAST_INSERT_ID(), 9);

-- DS5002 (Combined) weeks [10] -> MON 11:00-13:00 room ERD106
INSERT INTO session_overrides (session_id, new_day_of_week, new_start_time, new_end_time, new_room_id, reason, created_by) SELECT ts.id, 'MON', '11:00:00', '13:00:00', (SELECT id FROM rooms WHERE name='ERD106'), 'Planned variation per assignments sheet', u.id FROM timetable_sessions ts JOIN modules m ON m.id=ts.module_id JOIN rooms r ON r.id=ts.room_id, users u WHERE m.code='DS5002' AND ts.day_of_week='THU' AND ts.start_time='09:00:00' AND r.name='ERD105' AND u.username='aria.b.acd';
INSERT INTO session_override_weeks (override_id, week_in_block) VALUES (LAST_INSERT_ID(), 10);

-- SE7001 (Combined) weeks [8, 9, 10] -> MON 14:00-16:00 (room unchanged)
INSERT INTO session_overrides (session_id, new_day_of_week, new_start_time, new_end_time, new_room_id, reason, created_by) SELECT ts.id, 'MON', '14:00:00', '16:00:00', NULL, 'Planned variation per assignments sheet', u.id FROM timetable_sessions ts JOIN modules m ON m.id=ts.module_id JOIN rooms r ON r.id=ts.room_id, users u WHERE m.code='SE7001' AND ts.day_of_week='MON' AND ts.start_time='09:00:00' AND r.name='ERD107' AND u.username='aria.b.acd';
INSERT INTO session_override_weeks (override_id, week_in_block) VALUES (LAST_INSERT_ID(), 8), (LAST_INSERT_ID(), 9), (LAST_INSERT_ID(), 10);

-- SE7001 (Combined) weeks [5, 6, 7] -> MON 09:00-11:00 room MAE205
INSERT INTO session_overrides (session_id, new_day_of_week, new_start_time, new_end_time, new_room_id, reason, created_by) SELECT ts.id, 'MON', '09:00:00', '11:00:00', (SELECT id FROM rooms WHERE name='MAE205'), 'Planned variation per assignments sheet', u.id FROM timetable_sessions ts JOIN modules m ON m.id=ts.module_id JOIN rooms r ON r.id=ts.room_id, users u WHERE m.code='SE7001' AND ts.day_of_week='MON' AND ts.start_time='09:00:00' AND r.name='ERD107' AND u.username='aria.b.acd';
INSERT INTO session_override_weeks (override_id, week_in_block) VALUES (LAST_INSERT_ID(), 5), (LAST_INSERT_ID(), 6), (LAST_INSERT_ID(), 7);

-- CC9002 (Combined) weeks [2, 5, 6, 7] -> MON 14:00-16:00 (room unchanged)
INSERT INTO session_overrides (session_id, new_day_of_week, new_start_time, new_end_time, new_room_id, reason, created_by) SELECT ts.id, 'MON', '14:00:00', '16:00:00', NULL, 'Planned variation per assignments sheet', u.id FROM timetable_sessions ts JOIN modules m ON m.id=ts.module_id JOIN rooms r ON r.id=ts.room_id, users u WHERE m.code='CC9002' AND ts.day_of_week='WED' AND ts.start_time='09:00:00' AND r.name='ERD107' AND u.username='aria.b.acd';
INSERT INTO session_override_weeks (override_id, week_in_block) VALUES (LAST_INSERT_ID(), 2), (LAST_INSERT_ID(), 5), (LAST_INSERT_ID(), 6), (LAST_INSERT_ID(), 7);

-- CS4003 (CS - Group A) weeks [8, 9] -> MON 11:00-13:00 (room unchanged)
INSERT INTO session_overrides (session_id, new_day_of_week, new_start_time, new_end_time, new_room_id, reason, created_by) SELECT ts.id, 'MON', '11:00:00', '13:00:00', NULL, 'Planned variation per assignments sheet', u.id FROM timetable_sessions ts JOIN modules m ON m.id=ts.module_id JOIN rooms r ON r.id=ts.room_id, users u WHERE m.code='CS4003' AND ts.day_of_week='MON' AND ts.start_time='14:00:00' AND r.name='MAE206' AND u.username='aria.b.acd';
INSERT INTO session_override_weeks (override_id, week_in_block) VALUES (LAST_INSERT_ID(), 8), (LAST_INSERT_ID(), 9);

-- SE7002 (Combined) weeks [8, 9, 10] -> WED 09:00-11:00 room ERD106
INSERT INTO session_overrides (session_id, new_day_of_week, new_start_time, new_end_time, new_room_id, reason, created_by) SELECT ts.id, 'WED', '09:00:00', '11:00:00', (SELECT id FROM rooms WHERE name='ERD106'), 'Planned variation per assignments sheet', u.id FROM timetable_sessions ts JOIN modules m ON m.id=ts.module_id JOIN rooms r ON r.id=ts.room_id, users u WHERE m.code='SE7002' AND ts.day_of_week='WED' AND ts.start_time='09:00:00' AND r.name='ERD105' AND u.username='aria.b.acd';
INSERT INTO session_override_weeks (override_id, week_in_block) VALUES (LAST_INSERT_ID(), 8), (LAST_INSERT_ID(), 9), (LAST_INSERT_ID(), 10);

-- SE7003 (Combined) weeks [3, 4, 5] -> MON 09:00-11:00 (room unchanged)
INSERT INTO session_overrides (session_id, new_day_of_week, new_start_time, new_end_time, new_room_id, reason, created_by) SELECT ts.id, 'MON', '09:00:00', '11:00:00', NULL, 'Planned variation per assignments sheet', u.id FROM timetable_sessions ts JOIN modules m ON m.id=ts.module_id JOIN rooms r ON r.id=ts.room_id, users u WHERE m.code='SE7003' AND ts.day_of_week='TUE' AND ts.start_time='09:00:00' AND r.name='ERD105' AND u.username='aria.b.acd';
INSERT INTO session_override_weeks (override_id, week_in_block) VALUES (LAST_INSERT_ID(), 3), (LAST_INSERT_ID(), 4), (LAST_INSERT_ID(), 5);

-- SE7003 (Combined) weeks [8, 9, 10] -> THU 14:00-16:00 room ERD105
INSERT INTO session_overrides (session_id, new_day_of_week, new_start_time, new_end_time, new_room_id, reason, created_by) SELECT ts.id, 'THU', '14:00:00', '16:00:00', (SELECT id FROM rooms WHERE name='ERD105'), 'Planned variation per assignments sheet', u.id FROM timetable_sessions ts JOIN modules m ON m.id=ts.module_id JOIN rooms r ON r.id=ts.room_id, users u WHERE m.code='SE7003' AND ts.day_of_week='THU' AND ts.start_time='14:00:00' AND r.name='AB12' AND u.username='aria.b.acd';
INSERT INTO session_override_weeks (override_id, week_in_block) VALUES (LAST_INSERT_ID(), 8), (LAST_INSERT_ID(), 9), (LAST_INSERT_ID(), 10);

-- CS4004 (CC - Group B (NEW)) weeks [3, 4] -> MON 09:00-11:00 room ERD106
INSERT INTO session_overrides (session_id, new_day_of_week, new_start_time, new_end_time, new_room_id, reason, created_by) SELECT ts.id, 'MON', '09:00:00', '11:00:00', (SELECT id FROM rooms WHERE name='ERD106'), 'Planned variation per assignments sheet', u.id FROM timetable_sessions ts JOIN modules m ON m.id=ts.module_id JOIN rooms r ON r.id=ts.room_id, users u WHERE m.code='CS4004' AND ts.day_of_week='FRI' AND ts.start_time='11:00:00' AND r.name='MAE206' AND u.username='aria.b.acd';
INSERT INTO session_override_weeks (override_id, week_in_block) VALUES (LAST_INSERT_ID(), 3), (LAST_INSERT_ID(), 4);

-- CS4005 (DS - Group B (NEW)) weeks [7, 9, 10] -> MON 09:00-11:00 (room unchanged)
INSERT INTO session_overrides (session_id, new_day_of_week, new_start_time, new_end_time, new_room_id, reason, created_by) SELECT ts.id, 'MON', '09:00:00', '11:00:00', NULL, 'Planned variation per assignments sheet', u.id FROM timetable_sessions ts JOIN modules m ON m.id=ts.module_id JOIN rooms r ON r.id=ts.room_id, users u WHERE m.code='CS4005' AND ts.day_of_week='FRI' AND ts.start_time='11:00:00' AND r.name='ISC005' AND u.username='aria.b.acd';
INSERT INTO session_override_weeks (override_id, week_in_block) VALUES (LAST_INSERT_ID(), 7), (LAST_INSERT_ID(), 9), (LAST_INSERT_ID(), 10);
