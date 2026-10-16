public import Foundation
import SQLite3
import os

private let syncStoreLog = Logger(subsystem: "", category: "SyncStore")

public actor SyncStore: SyncStoring {
    public static let currentSchemaVersion: Int32 = 1

    private let dbPath: String
    nonisolated private let db: SyncDatabase

    public static func defaultDatabaseURL(fileManager: FileManager = .default) throws -> URL {
        let appSupport = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let dir = appSupport.appendingPathComponent("muxctl", isDirectory: true)
        if !fileManager.fileExists(atPath: dir.path) {
            try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir.appendingPathComponent("muxctl-sync.sqlite3")
    }

    public init(databaseURL: URL) throws {
        self.dbPath = databaseURL.path
        self.db = try SyncDatabase(path: databaseURL.path)
    }

    public init() throws {
        try self.init(databaseURL: Self.defaultDatabaseURL())
    }

    deinit {
        db.close()
    }

    private var didMigrate = false

    private func ensureReady() throws {
        guard !didMigrate else { return }
        try runMigrations()
        didMigrate = true
    }

    private func runMigrations() throws {
        let version = try db.userVersion()
        switch version {
        case 0:
            try migrateToV1()
            try db.setUserVersion(1)
            fallthrough
        case 1:
            break
        default:
            throw CmuxSyncStoreError.unknownSchemaVersion(Int(version))
        }
    }

    private func migrateToV1() throws {
        try db.exec("""
            CREATE TABLE IF NOT EXISTS sync_records (
                team_id     TEXT    NOT NULL,
                collection  TEXT    NOT NULL,
                record_id   TEXT    NOT NULL,
                rev         INTEGER NOT NULL,
                updated_at  REAL    NOT NULL,
                sort_key    REAL    NOT NULL DEFAULT 0,
                deleted     INTEGER NOT NULL DEFAULT 0,
                payload     TEXT    NOT NULL,
                PRIMARY KEY (team_id, collection, record_id)
            );
        """)

        try db.exec("""
            CREATE INDEX IF NOT EXISTS idx_sync_records_render
                ON sync_records (team_id, collection, deleted, sort_key);
        """)

        try db.exec("""
            CREATE TABLE IF NOT EXISTS sync_cursors (
                team_id     TEXT    NOT NULL,
                collection  TEXT    NOT NULL,
                cursor_rev  INTEGER NOT NULL DEFAULT 0,
                epoch       INTEGER NOT NULL DEFAULT 0,
                synced_at   REAL    NOT NULL DEFAULT 0,
                PRIMARY KEY (team_id, collection)
                );
        """)

        try db.exec("""
            CREATE TABLE IF NOT EXISTS sync_meta (
                key   TEXT PRIMARY KEY NOT NULL,
                value TEXT NOT NULL
            );
        """)
    }

    public func liveRecords(teamID: String, collection: String) throws -> [StoredSyncRecord] {
        try ensureReady()
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        let sql = """
            SELECT record_id, rev, updated_at, sort_key, deleted, payload
            FROM sync_records
            WHERE team_id = ? AND collection = ? AND deleted = 0
            ORDER BY sort_key DESC;
        """
        statement = try db.prepare(sql)
        try db.bind(statement: statement, parameters: [.text(teamID), .text(collection)])
        var out: [StoredSyncRecord] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            out.append(readRecord(statement, teamID: teamID, collection: collection))
        }
        return out
    }

    public func cursor(teamID: String, collection: String) throws -> Int {
        try ensureReady()
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        let sql = "SELECT cursor_rev FROM sync_cursors WHERE team_id = ? AND collection = ?;"
        statement = try db.prepare(sql)
        try db.bind(statement: statement, parameters: [.text(teamID), .text(collection)])
        if sqlite3_step(statement) == SQLITE_ROW {
            return Int(sqlite3_column_int64(statement, 0))
        }
        return 0
    }

    public func epoch(teamID: String, collection: String) throws -> Int {
        try ensureReady()
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        let sql = "SELECT epoch FROM sync_cursors WHERE team_id = ? AND collection = ?;"
        statement = try db.prepare(sql)
        try db.bind(statement: statement, parameters: [.text(teamID), .text(collection)])
        if sqlite3_step(statement) == SQLITE_ROW {
            return Int(sqlite3_column_int64(statement, 0))
        }
        return 0
    }

    public func applyDelta(
        teamID: String,
        collection: String,
        frameRev: Int,
        records: [SyncWireRecord],
        sortKeyFor: @Sendable (SyncWireRecord) -> Double,
        now: Date
    ) throws {
        try ensureReady()
        try db.transaction {
            for record in records {
                try applyOneRecord(teamID: teamID, collection: collection, record: record, sortKey: sortKeyFor(record))
            }
            try setCursor(teamID: teamID, collection: collection, to: frameRev, now: now)
        }
    }

    public func applySnapshot(
        teamID: String,
        collection: String,
        snapshotRev: Int,
        epoch: Int,
        records: [SyncWireRecord],
        sortKeyFor: @Sendable (SyncWireRecord) -> Double,
        now: Date
    ) throws {
        try ensureReady()
        try db.transaction {
            let epochChanged = epoch != 0 && epoch != localEpoch
            let isReset = localCursor > snapshotRev || epochChanged

            var present = Set<String>()
            for record in records {
                if isReset {
                    try forceApplyRecord(teamID: teamID, collection: collection, record: record, sortKey: sortKeyFor(record))
                } else {
                    try applyOneRecord(teamID: teamID, collection: collection, record: record, sortKey: sortKeyFor(record))
                }
                present.insert(record.id)
            }

            let maxRev = isReset ? Int.max : snapshotRev
            let existing = try allRecordIDs(teamID: teamID, collection: collection, minRev: 1, maxRev: maxRev)
            for id in existing where !present.contains(id) {
                let localRev = try recordRev(teamID: teamID, collection: collection, recordID: id) ?? 0
                let tombRev = isReset ? max(snapshotRev, localRev) : snapshotRev
                try tombstoneAt(teamID: teamID, collection: collection, recordID: id, rev: tombRev, now: now)
            }

            if isReset {
                try forceCursor(teamID: teamID, collection: collection, to: snapshotRev, epoch: epoch, now: now)
            } else {
                try setCursor(teamID: teamID, collection: collection, to: snapshotRev, epoch: epoch, now: now)
            }
        }
    }

    private func forceApplyRecord(teamID: String, collection: String, record: SyncWireRecord, sortKey: Double) throws {
        let updatedAtSeconds = record.updatedAt / 1000.0
        try db.exec("""
            INSERT INTO sync_records (team_id, collection, record_id, rev, updated_at, sort_key, deleted, payload)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(team_id, collection, record_id) DO UPDATE SET
                rev = excluded.rev,
                updated_at = excluded.updated_at,
                sort_key = excluded.sort_key,
                deleted = excluded.deleted,
                payload = excluded.payload;
        """, binding: [
            .text(teamID),
            .text(collection),
            .text(record.id),
            .int(Int64(record.rev)),
            .real(updatedAtSeconds),
            .real(sortKey),
            .int(record.deleted ? 1 : 0),
            .text(record.deleted ? "{}" : jsonString(record.payloadJSON)),
        ])
    }

    private func applyOneRecord(teamID: String, collection: String, record: SyncWireRecord, sortKey: Double) throws {
        if let localRev = try recordRev(teamID: teamID, collection: collection, recordID: record.id),
           localRev >= record.rev {
            return 
        }
        let updatedAtSeconds = record.updatedAt / 1000.0
        try db.exec("""
            INSERT INTO sync_records (team_id, collection, record_id, rev, updated_at, sort_key, deleted, payload)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(team_id, collection, record_id) DO UPDATE SET
                rev = excluded.rev,
                updated_at = excluded.updated_at,
                sort_key = excluded.sort_key,
                deleted = excluded.deleted,
                payload = excluded.payload;
        """, binding: [
            .text(teamID),
            .text(collection),
            .text(record.id),
            .int(Int64(record.rev)),
            .real(updatedAtSeconds),
            .real(sortKey),
            .int(record.deleted ? 1 : 0),
            .text(record.deleted ? "{}" : jsonString(record.payloadJSON)),
        ])
    }

    public func seedProvisional(
        teamID: String,
        collection: String,
        recordID: String,
        payloadJSON: Data,
        sortKey: Double,
        now: Date
    ) throws {
        try ensureReady()
        try db.exec("""
            INSERT OR IGNORE INTO sync_records
                (team_id, collection, record_id, rev, updated_at, sort_key, deleted, payload)
            VALUES (?, ?, ?, 0, ?, ?, 0, ?);
        """, binding: [
            .text(teamID),
            .text(collection),
            .text(recordID),
            .real(now.timeIntervalSince1970),
            .real(sortKey),
            .text(jsonString(payloadJSON)),
        ])
    }

    public func migrationCompleted(accountID: String, teamID: String) throws -> Bool {
        try ensureReady()
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        statement = try db.prepare("SELECT value FROM sync_meta WHERE key = ?;")
        try db.bind(statement: statement, parameters: [.text(migrationKey(accountID: accountID, teamID: teamID))])
        return sqlite3_step(statement) == SQLITE_ROW
    }

    public func markMigrationCompleted(accountID: String, teamID: String) throws {
        try ensureReady()
        try db.exec("INSERT OR REPLACE INTO sync_meta (key, value) VALUES (?, '1');",
                 binding: [.text(migrationKey(accountID: accountID, teamID: teamID))])
    }

    public func clear(teamID: String) throws {
        try ensureReady()
        try db.transaction {
            try db.exec("DELETE FROM sync_records WHERE team_id = ?;", binding: [.text(teamID)])
            try db.exec("DELETE FROM sync_cursors WHERE team_id = ?;", binding: [.text(teamID)])

            try db.exec("DELETE FROM sync_meta WHERE key LIKE ? ESCAPE '\\';",
                    binding: [.text("\(escapeLike(migrationKeyPrefix(teamID: teamID)))%")])
        }
    }

    private func migrationKey(accountID: String, teamID: String) -> String {
        "\(migrationKeyPrefix(teamID: teamID))\(accountID)"
    }

    private func migrationKeyPrefix(teamID: String) -> String {
        "migrated:\(teamID):"
    }

    private func escapeLike(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "%", with: "\\%")
            .replacingOccurrences(of: "_", with: "\\_")
    }

    private func recordRev(teamID: String, collection: String, recordID: String) throws -> Int? {
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        let sql = "SELECT rev FROM sync_records WHERE team_id = ? AND collection = ? AND record_id = ?;"
        statement = try db.prepare(sql)
        try db.bind(statement: statement, parameters: [.text(teamID), .text(collection), .text(recordID)])
        if sqlite3_step(statement) == SQLITE_ROW {
            return Int(sqlite3_column_int64(statement, 0))
        }
        return nil
    }

    private func allRecordIDs(teamID: String, collection: String, minRev: Int, maxRev: Int) throws -> [String] {
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        let sql = """
            SELECT record_id FROM sync_records
            WHERE team_id = ? AND collection = ? AND rev >= ? AND rev <= ?;
        """
        statement = try db.prepare(sql)
        try db.bind(statement: statement, parameters: [
            .text(teamID), .text(collection), .int(Int64(minRev)), .int(Int64(maxRev)),
        ])
        var ids: [String] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            if let cString = sqlite3_column_text(statement, 0) {
                ids.append(String(cString: cString))
            }
        }
        return ids
    }

    private func tombstoneAt(teamID: String, collection: String, recordID: String, rev: Int, now: Date) throws {
        try db.exec("""
            INSERT INTO sync_records (team_id, collection, record_id, rev, updated_at, sort_key, deleted, payload)
            VALUES (?, ?, ?, ?, ?, 0, 1, '{}')
            ON CONFLICT(team_id, collection, record_id) DO UPDATE SET
                rev = excluded.rev,
                updated_at = excluded.updated_at,
                deleted = 1,
                payload = '{}';
        """, binding: [
            .text(teamID),
            .text(collection),
            .text(recordID),
            .int(Int64(rev)),
            .real(now.timeIntervalSince1970),
        ])
    }

    private func setCursor(teamID: String, collection: String, to rev: Int, epoch: Int? = nil, now: Date) throws {
        try db.exec("""
            INSERT INTO sync_cursors (team_id, collection, cursor_rev, epoch, synced_at)
            VALUES (?, ?, ?, ?, ?)
            ON CONFLICT(team_id, collection) DO UPDATE SET
                cursor_rev = MAX(cursor_rev, excluded.cursor_rev),
                epoch = CASE WHEN ? THEN excluded.epoch ELSE sync_cursors.epoch END,
                synced_at = excluded.synced_at;
        """, binding: [
            .text(teamID), .text(collection), .int(Int64(rev)), .int(Int64(epoch ?? 0)),
            .real(now.timeIntervalSince1970), .int(epoch != nil ? 1 : 0),
        ])
    }

    private func forceCursor(teamID: String, collection: String, to rev: Int, epoch: Int, now: Date) throws {
        try db.exec("""
            INSERT INTO sync_cursors (team_id, collection, cursor_rev, epoch, synced_at)
            VALUES (?, ?, ?, ?, ?)
            ON CONFLICT(team_id, collection) DO UPDATE SET
                cursor_rev = excluded.cursor_rev,
                epoch = excluded.epoch,
                synced_at = excluded.synced_at;
        """, binding: [
            .text(teamID), .text(collection), .int(Int64(rev)), .int(Int64(epoch)),
            .real(now.timeIntervalSince1970),
        ])
    }
}
