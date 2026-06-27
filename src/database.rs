use flutter_rust_bridge::frb;
use rusqlite::{params, types::ValueRef, Connection, OptionalExtension, Params};
use std::collections::HashSet;
use std::env;
use std::path::{Path, PathBuf};

const DATABASE_FILE_NAME: &str = "AnnotationConfig.db";

#[frb(ignore)]
#[derive(Debug, Clone)]
struct DbClass {
    id: i64,
    name: String,
    color: i64,
}

#[frb(ignore)]
#[derive(Debug, Clone)]
struct DbImage {
    path: String,
    name: String,
    split: String,
    width: f64,
    height: f64,
    sort_index: i64,
}

#[frb(ignore)]
#[derive(Debug, Clone)]
struct DbAnnotation {
    image_path: String,
    id: String,
    kind: String,
    class_id: i64,
    left: f64,
    top: f64,
    right: f64,
    bottom: f64,
    rotation: f64,
    points: String,
    source: String,
    confidence: f64,
    author_id: String,
    author_name: String,
    author_color: i64,
}

#[frb(ignore)]
#[derive(Debug, Clone)]
struct DbCollaborationPermission {
    user_id: String,
    user_name: String,
    color: i64,
    can_edit_others: bool,
    can_delete_others: bool,
    can_change_class: bool,
    assignment_start: i64,
    assignment_end: i64,
}

#[frb(ignore)]
#[derive(Debug, Default)]
struct SnapshotPayload {
    project_key: String,
    classes: Vec<DbClass>,
    images: Vec<DbImage>,
    annotations: Vec<DbAnnotation>,
    collaboration_permissions: Vec<DbCollaborationPermission>,
}

#[frb(ignore)]
pub fn save_snapshot(payload: &str) -> Result<String, String> {
    let snapshot = parse_payload(payload);
    let db_path = database_path()?;
    let mut connection = open_database(&db_path)?;
    init_schema(&connection)?;
    let tx = connection
        .transaction()
        .map_err(|error| error.to_string())?;
    let project_id = ensure_project(&tx, &snapshot.project_key)?;
    reconcile_images(&tx, project_id, &snapshot.images)?;
    save_classes(&tx, project_id, &snapshot.classes)?;
    save_images(&tx, project_id, &snapshot.images)?;
    save_annotations(&tx, project_id, &snapshot.images, &snapshot.annotations)?;
    save_collaboration_permissions(&tx, project_id, &snapshot.collaboration_permissions)?;
    delete_images_not_in_snapshot(&tx, project_id, &snapshot.images)?;
    tx.commit().map_err(|error| error.to_string())?;
    Ok(format!(
        "{{\"ok\":true,\"dbPath\":\"{}\",\"images\":{},\"classes\":{},\"annotations\":{}}}",
        json_escape(&db_path.to_string_lossy()),
        snapshot.images.len(),
        snapshot.classes.len(),
        snapshot.annotations.len()
    ))
}

#[frb(ignore)]
pub fn load_snapshot(payload: &str) -> Result<String, String> {
    let snapshot = parse_payload(payload);
    let db_path = database_path()?;
    let mut connection = open_database(&db_path)?;
    init_schema(&connection)?;
    let tx = connection
        .transaction()
        .map_err(|error| error.to_string())?;
    let project_id = ensure_project(&tx, &snapshot.project_key)?;
    reconcile_images(&tx, project_id, &snapshot.images)?;
    save_images(&tx, project_id, &snapshot.images)?;
    delete_images_not_in_snapshot(&tx, project_id, &snapshot.images)?;
    tx.commit().map_err(|error| error.to_string())?;

    let current_paths: HashSet<String> = snapshot
        .images
        .iter()
        .map(|image| path_key(&image.path))
        .collect();
    let classes = load_classes(&connection, project_id)?;
    let annotations = load_annotations(&connection, project_id, &current_paths)?;
    Ok(snapshot_json(&db_path, &classes, &annotations))
}

#[frb(ignore)]
pub fn save_config_value(key: &str, value: &str) -> Result<String, String> {
    let db_path = database_path()?;
    let connection = open_database(&db_path)?;
    init_schema(&connection)?;
    connection
        .execute(
            r#"
            INSERT INTO app_config(key, value, updated_at)
            VALUES (?, ?, CURRENT_TIMESTAMP)
            ON CONFLICT(key) DO UPDATE SET
                value=excluded.value,
                updated_at=CURRENT_TIMESTAMP
            "#,
            params![key, value],
        )
        .map_err(|error| error.to_string())?;
    Ok(format!(
        "{{\"ok\":true,\"dbPath\":\"{}\"}}",
        json_escape(&db_path.to_string_lossy())
    ))
}

#[frb(ignore)]
pub fn load_config_value(key: &str) -> Result<String, String> {
    let db_path = database_path()?;
    let connection = open_database(&db_path)?;
    init_schema(&connection)?;
    let value = connection
        .query_row(
            "SELECT value FROM app_config WHERE key=?",
            params![key],
            |row| row.get::<_, String>(0),
        )
        .ok();
    Ok(format!(
        "{{\"ok\":true,\"dbPath\":\"{}\",\"value\":\"{}\"}}",
        json_escape(&db_path.to_string_lossy()),
        json_escape(&value.unwrap_or_default())
    ))
}

#[frb(ignore)]
pub fn delete_config_value(key: &str) -> Result<String, String> {
    let db_path = database_path()?;
    let connection = open_database(&db_path)?;
    init_schema(&connection)?;
    let deleted = connection
        .execute("DELETE FROM app_config WHERE key=?", params![key])
        .map_err(|error| error.to_string())?;
    Ok(format!(
        "{{\"ok\":true,\"dbPath\":\"{}\",\"deleted\":{}}}",
        json_escape(&db_path.to_string_lossy()),
        deleted
    ))
}

#[frb(ignore)]
pub fn append_log_lines(lines: &str) -> Result<String, String> {
    let db_path = database_path()?;
    let mut connection = open_database(&db_path)?;
    init_schema(&connection)?;
    let tx = connection
        .transaction()
        .map_err(|error| error.to_string())?;
    let mut inserted = 0usize;
    {
        let mut stmt = tx
            .prepare(
                r#"
                INSERT INTO app_logs(created_at, log_date, level, tag, line)
                VALUES (?, ?, ?, ?, ?)
                "#,
            )
            .map_err(|error| error.to_string())?;
        for raw_line in lines.lines() {
            let line = raw_line.trim_end_matches('\r');
            if line.trim().is_empty() {
                continue;
            }
            let (created_at, log_date, level, tag) = parse_log_line_metadata(line);
            stmt.execute(params![created_at, log_date, level, tag, line])
                .map_err(|error| error.to_string())?;
            inserted += 1;
        }
    }
    tx.commit().map_err(|error| error.to_string())?;
    Ok(format!(
        "{{\"ok\":true,\"dbPath\":\"{}\",\"inserted\":{}}}",
        json_escape(&db_path.to_string_lossy()),
        inserted
    ))
}

#[frb(ignore)]
pub fn log_dates() -> Result<String, String> {
    let db_path = database_path()?;
    let connection = open_database(&db_path)?;
    init_schema(&connection)?;
    let mut stmt = connection
        .prepare("SELECT DISTINCT log_date FROM app_logs ORDER BY log_date DESC")
        .map_err(|error| error.to_string())?;
    let rows = stmt
        .query_map([], |row| row.get::<_, String>(0))
        .map_err(|error| error.to_string())?;
    let mut dates = Vec::new();
    for row in rows {
        dates.push(row.map_err(|error| error.to_string())?);
    }
    Ok(string_array_json(&db_path, "dates", &dates))
}

#[frb(ignore)]
pub fn read_logs_for_date(date: &str) -> Result<String, String> {
    let db_path = database_path()?;
    let connection = open_database(&db_path)?;
    init_schema(&connection)?;
    let mut stmt = connection
        .prepare("SELECT line FROM app_logs WHERE log_date=? ORDER BY id")
        .map_err(|error| error.to_string())?;
    let rows = stmt
        .query_map(params![date], |row| row.get::<_, String>(0))
        .map_err(|error| error.to_string())?;
    let mut lines = Vec::new();
    for row in rows {
        lines.push(row.map_err(|error| error.to_string())?);
    }
    Ok(format!(
        "{{\"ok\":true,\"dbPath\":\"{}\",\"date\":\"{}\",\"text\":\"{}\"}}",
        json_escape(&db_path.to_string_lossy()),
        json_escape(date),
        json_escape(&lines.join("\n"))
    ))
}

#[frb(ignore)]
pub fn delete_logs_by_date_range(start_date: &str, end_date: &str) -> Result<String, String> {
    let db_path = database_path()?;
    let connection = open_database(&db_path)?;
    init_schema(&connection)?;
    let (start, end) = if start_date <= end_date {
        (start_date, end_date)
    } else {
        (end_date, start_date)
    };
    let deleted = connection
        .execute(
            "DELETE FROM app_logs WHERE log_date >= ? AND log_date <= ?",
            params![start, end],
        )
        .map_err(|error| error.to_string())?;
    Ok(format!(
        "{{\"ok\":true,\"dbPath\":\"{}\",\"deleted\":{}}}",
        json_escape(&db_path.to_string_lossy()),
        deleted
    ))
}

#[frb(ignore)]
pub fn database_overview() -> Result<String, String> {
    let db_path = database_path()?;
    let connection = open_database(&db_path)?;
    init_schema(&connection)?;
    let (deleted_images, deleted_projects) = cleanup_missing_label_data(&connection)?;
    let file_size = std::fs::metadata(&db_path)
        .map(|metadata| metadata.len())
        .unwrap_or(0);
    let table_names = [
        "projects",
        "images",
        "classes",
        "annotations",
        "collaboration_permissions",
        "app_config",
        "app_logs",
    ];
    let mut output = format!(
        "{{\"ok\":true,\"dbPath\":\"{}\",\"fileSizeBytes\":{},\"cleanupDeletedImages\":{},\"cleanupDeletedProjects\":{},\"tables\":[",
        json_escape(&db_path.to_string_lossy()),
        file_size,
        deleted_images,
        deleted_projects
    );
    for (index, table_name) in table_names.iter().enumerate() {
        if index > 0 {
            output.push(',');
        }
        output.push_str(&format!(
            "{{\"name\":\"{}\",\"rows\":{}}}",
            json_escape(table_name),
            count_rows(&connection, table_name)?
        ));
    }
    output.push_str("],\"configKeys\":[");
    let mut stmt = connection
        .prepare("SELECT key, updated_at FROM app_config ORDER BY key")
        .map_err(|error| error.to_string())?;
    let rows = stmt
        .query_map([], |row| {
            Ok((row.get::<_, String>(0)?, row.get::<_, String>(1)?))
        })
        .map_err(|error| error.to_string())?;
    for (index, row) in rows.enumerate() {
        let (key, updated_at) = row.map_err(|error| error.to_string())?;
        if index > 0 {
            output.push(',');
        }
        output.push_str(&format!(
            "{{\"key\":\"{}\",\"updatedAt\":\"{}\"}}",
            json_escape(&key),
            json_escape(&updated_at)
        ));
    }
    output.push_str("]}");
    Ok(output)
}

#[frb(ignore)]
pub fn database_table(
    table: &str,
    project_id: &str,
    image_id: &str,
    limit: &str,
    offset: &str,
) -> Result<String, String> {
    let db_path = database_path()?;
    let connection = open_database(&db_path)?;
    init_schema(&connection)?;
    cleanup_missing_label_data(&connection)?;
    let project_id = parse_optional_i64(project_id);
    let image_id = parse_optional_i64(image_id);
    let limit = parse_page_limit(limit);
    let offset = parse_nonnegative_i64(offset);
    match table {
        "projects" => query_table_json(
            &connection,
            &db_path,
            "projects",
            &[
                "id",
                "name",
                "root_path",
                "data_yaml_path",
                "image_count",
                "class_count",
                "annotation_count",
                "updated_at",
            ],
            r#"
            SELECT p.id, p.name, p.root_path, p.data_yaml_path,
                   COUNT(DISTINCT i.id) AS image_count,
                   COUNT(DISTINCT c.id) AS class_count,
                   COUNT(DISTINCT a.id) AS annotation_count,
                   p.updated_at
            FROM projects p
            LEFT JOIN images i ON i.project_id = p.id
            LEFT JOIN classes c ON c.project_id = p.id
            LEFT JOIN annotations a ON a.image_id = i.id
            GROUP BY p.id
            ORDER BY p.updated_at DESC, p.id DESC
            LIMIT ? OFFSET ?
            "#,
            params![limit, offset],
        ),
        "images" => {
            if let Some(project_id) = project_id {
                query_table_json(
                    &connection,
                    &db_path,
                    "images",
                    &[
                        "id",
                        "project_id",
                        "file_name",
                        "path",
                        "split",
                        "width",
                        "height",
                        "sort_index",
                        "annotation_count",
                        "file_exists",
                        "updated_at",
                    ],
                    r#"
                    SELECT i.id, i.project_id, i.file_name, i.path, i.split,
                           i.width, i.height, i.sort_index,
                           COUNT(a.id) AS annotation_count,
                           CASE WHEN i.path <> '' THEN 'yes' ELSE 'no' END AS file_exists,
                           i.updated_at
                    FROM images i
                    LEFT JOIN annotations a ON a.image_id = i.id
                    WHERE i.project_id = ?
                    GROUP BY i.id
                    ORDER BY i.sort_index, i.file_name
                    LIMIT ? OFFSET ?
                    "#,
                    params![project_id, limit, offset],
                )
            } else {
                query_table_json(
                    &connection,
                    &db_path,
                    "images",
                    &[
                        "id",
                        "project_id",
                        "file_name",
                        "path",
                        "split",
                        "width",
                        "height",
                        "sort_index",
                        "annotation_count",
                        "file_exists",
                        "updated_at",
                    ],
                    r#"
                    SELECT i.id, i.project_id, i.file_name, i.path, i.split,
                           i.width, i.height, i.sort_index,
                           COUNT(a.id) AS annotation_count,
                           CASE WHEN i.path <> '' THEN 'yes' ELSE 'no' END AS file_exists,
                           i.updated_at
                    FROM images i
                    LEFT JOIN annotations a ON a.image_id = i.id
                    GROUP BY i.id
                    ORDER BY i.project_id, i.sort_index, i.file_name
                    LIMIT ? OFFSET ?
                    "#,
                    params![limit, offset],
                )
            }
        }
        "classes" => {
            if let Some(project_id) = project_id {
                query_table_json(
                    &connection,
                    &db_path,
                    "classes",
                    &[
                        "id",
                        "project_id",
                        "class_id",
                        "name",
                        "color",
                        "color_hex",
                        "annotation_count",
                        "updated_at",
                    ],
                    r#"
                    SELECT c.id, c.project_id, c.class_id, c.name, c.color,
                           printf('#%06X', c.color & 16777215) AS color_hex,
                           COUNT(a.id) AS annotation_count,
                           c.updated_at
                    FROM classes c
                    LEFT JOIN annotations a
                        ON a.class_id = c.class_id
                       AND a.image_id IN (SELECT id FROM images WHERE project_id = c.project_id)
                    WHERE c.project_id = ?
                    GROUP BY c.id
                    ORDER BY c.class_id
                    LIMIT ? OFFSET ?
                    "#,
                    params![project_id, limit, offset],
                )
            } else {
                query_table_json(
                    &connection,
                    &db_path,
                    "classes",
                    &[
                        "id",
                        "project_id",
                        "class_id",
                        "name",
                        "color",
                        "color_hex",
                        "annotation_count",
                        "updated_at",
                    ],
                    r#"
                    SELECT c.id, c.project_id, c.class_id, c.name, c.color,
                           printf('#%06X', c.color & 16777215) AS color_hex,
                           COUNT(a.id) AS annotation_count,
                           c.updated_at
                    FROM classes c
                    LEFT JOIN annotations a
                        ON a.class_id = c.class_id
                       AND a.image_id IN (SELECT id FROM images WHERE project_id = c.project_id)
                    GROUP BY c.id
                    ORDER BY c.project_id, c.class_id
                    LIMIT ? OFFSET ?
                    "#,
                    params![limit, offset],
                )
            }
        }
        "annotations" => {
            if let Some(image_id) = image_id {
                query_table_json(
                    &connection,
                    &db_path,
                    "annotations",
                    annotation_columns(),
                    annotation_sql("a.image_id = ?"),
                    params![image_id, limit, offset],
                )
            } else if let Some(project_id) = project_id {
                query_table_json(
                    &connection,
                    &db_path,
                    "annotations",
                    annotation_columns(),
                    annotation_sql("i.project_id = ?"),
                    params![project_id, limit, offset],
                )
            } else {
                query_table_json(
                    &connection,
                    &db_path,
                    "annotations",
                    annotation_columns(),
                    annotation_sql("1 = 1"),
                    params![limit, offset],
                )
            }
        }
        "collaboration_permissions" => query_table_json(
            &connection,
            &db_path,
            "collaboration_permissions",
            &[
                "id",
                "project_id",
                "project_name",
                "user_id",
                "user_name",
                "color",
                "can_edit_others",
                "can_delete_others",
                "can_change_class",
                "assignment_start",
                "assignment_end",
                "updated_at",
            ],
            r#"
            SELECT cp.id, cp.project_id, p.name AS project_name, cp.user_id,
                   cp.user_name, cp.color, cp.can_edit_others,
                   cp.can_delete_others, cp.can_change_class,
                   cp.assignment_start, cp.assignment_end, cp.updated_at
            FROM collaboration_permissions cp
            INNER JOIN projects p ON p.id = cp.project_id
            WHERE (? = 0 OR cp.project_id = ?)
            ORDER BY p.name, cp.user_name, cp.user_id
            LIMIT ? OFFSET ?
            "#,
            params![project_id.unwrap_or(0), project_id.unwrap_or(0), limit, offset],
        ),
        "app_config" => query_table_json(
            &connection,
            &db_path,
            "app_config",
            &["key", "value", "created_at", "updated_at"],
            "SELECT key, value, created_at, updated_at FROM app_config ORDER BY key LIMIT ? OFFSET ?",
            params![limit, offset],
        ),
        "app_logs" => query_table_json(
            &connection,
            &db_path,
            "app_logs",
            &["id", "created_at", "log_date", "level", "tag", "line"],
            r#"
            SELECT id, created_at, log_date, level, tag, line
            FROM app_logs
            ORDER BY id DESC
            LIMIT ? OFFSET ?
            "#,
            params![limit, offset],
        ),
        _ => Err(format!("Unsupported database table: {table}")),
    }
}

#[frb(ignore)]
pub fn database_sql_query(sql: &str) -> Result<String, String> {
    let db_path = database_path()?;
    let connection = open_database(&db_path)?;
    init_schema(&connection)?;
    cleanup_missing_label_data(&connection)?;
    let sql = readonly_sql(sql)?;
    query_sql_json(&connection, &db_path, &sql, 5_000)
}

fn database_path() -> Result<PathBuf, String> {
    let root = application_root()?;
    Ok(root.join(DATABASE_FILE_NAME))
}

fn application_root() -> Result<PathBuf, String> {
    if let Ok(exe) = env::current_exe() {
        if let Some(parent) = exe.parent() {
            return Ok(parent.to_path_buf());
        }
    }

    env::current_dir().map_err(|error| format!("current dir: {error}"))
}

fn open_database(path: &Path) -> Result<Connection, String> {
    Connection::open(path).map_err(|error| format!("open database {}: {error}", path.display()))
}

fn count_rows(connection: &Connection, table_name: &str) -> Result<i64, String> {
    let sql = format!("SELECT COUNT(*) FROM {table_name}");
    connection
        .query_row(&sql, [], |row| row.get::<_, i64>(0))
        .map_err(|error| error.to_string())
}

fn cleanup_missing_label_data(connection: &Connection) -> Result<(usize, usize), String> {
    let mut stmt = connection
        .prepare("SELECT id, path FROM images")
        .map_err(|error| error.to_string())?;
    let rows = stmt
        .query_map([], |row| {
            Ok((row.get::<_, i64>(0)?, row.get::<_, String>(1)?))
        })
        .map_err(|error| error.to_string())?;
    let mut missing_image_ids = Vec::new();
    for row in rows {
        let (image_id, path) = row.map_err(|error| error.to_string())?;
        if !Path::new(&path).exists() {
            missing_image_ids.push(image_id);
        }
    }
    drop(stmt);

    for image_id in &missing_image_ids {
        connection
            .execute(
                "DELETE FROM annotations WHERE image_id=?",
                params![image_id],
            )
            .map_err(|error| error.to_string())?;
        connection
            .execute("DELETE FROM images WHERE id=?", params![image_id])
            .map_err(|error| error.to_string())?;
    }

    let mut project_stmt = connection
        .prepare(
            r#"
            SELECT p.id
            FROM projects p
            LEFT JOIN images i ON i.project_id = p.id
            WHERE p.id <> 1
            GROUP BY p.id
            HAVING COUNT(i.id) = 0
            "#,
        )
        .map_err(|error| error.to_string())?;
    let project_rows = project_stmt
        .query_map([], |row| row.get::<_, i64>(0))
        .map_err(|error| error.to_string())?;
    let mut remove_project_ids = Vec::new();
    for row in project_rows {
        remove_project_ids.push(row.map_err(|error| error.to_string())?);
    }
    drop(project_stmt);

    for project_id in &remove_project_ids {
        connection
            .execute(
                "DELETE FROM classes WHERE project_id=?",
                params![project_id],
            )
            .map_err(|error| error.to_string())?;
        connection
            .execute("DELETE FROM projects WHERE id=?", params![project_id])
            .map_err(|error| error.to_string())?;
    }

    Ok((missing_image_ids.len(), remove_project_ids.len()))
}

fn query_table_json<P: Params, S: AsRef<str>>(
    connection: &Connection,
    db_path: &Path,
    table: &str,
    columns: &[&str],
    sql: S,
    params: P,
) -> Result<String, String> {
    let mut stmt = connection
        .prepare(sql.as_ref())
        .map_err(|error| error.to_string())?;
    let column_count = stmt.column_count();
    let rows = stmt
        .query_map(params, |row| {
            let mut values = Vec::with_capacity(column_count);
            for index in 0..column_count {
                let value = row.get_ref(index)?;
                values.push(sql_value_to_string(value));
            }
            Ok(values)
        })
        .map_err(|error| error.to_string())?;
    let mut output = format!(
        "{{\"ok\":true,\"dbPath\":\"{}\",\"table\":\"{}\",\"columns\":[",
        json_escape(&db_path.to_string_lossy()),
        json_escape(table)
    );
    for (index, column) in columns.iter().enumerate() {
        if index > 0 {
            output.push(',');
        }
        output.push('"');
        output.push_str(&json_escape(column));
        output.push('"');
    }
    output.push_str("],\"rows\":[");
    for (row_index, row) in rows.enumerate() {
        let values = row.map_err(|error| error.to_string())?;
        if row_index > 0 {
            output.push(',');
        }
        output.push('{');
        for (index, column) in columns.iter().enumerate() {
            if index > 0 {
                output.push(',');
            }
            let value = values.get(index).map(String::as_str).unwrap_or_default();
            output.push_str(&format!(
                "\"{}\":\"{}\"",
                json_escape(column),
                json_escape(value)
            ));
        }
        output.push('}');
    }
    output.push_str("]}");
    Ok(output)
}

fn query_sql_json(
    connection: &Connection,
    db_path: &Path,
    sql: &str,
    max_rows: usize,
) -> Result<String, String> {
    let mut stmt = connection.prepare(sql).map_err(|error| error.to_string())?;
    let columns = stmt
        .column_names()
        .iter()
        .map(|name| name.to_string())
        .collect::<Vec<_>>();
    let column_count = stmt.column_count();
    let mut rows = stmt.query([]).map_err(|error| error.to_string())?;
    let mut output = format!(
        "{{\"ok\":true,\"dbPath\":\"{}\",\"sql\":\"{}\",\"columns\":[",
        json_escape(&db_path.to_string_lossy()),
        json_escape(sql)
    );
    for (index, column) in columns.iter().enumerate() {
        if index > 0 {
            output.push(',');
        }
        output.push('"');
        output.push_str(&json_escape(column));
        output.push('"');
    }
    output.push_str("],\"rows\":[");
    let mut row_count = 0usize;
    let mut truncated = false;
    while let Some(row) = rows.next().map_err(|error| error.to_string())? {
        if row_count >= max_rows {
            truncated = true;
            break;
        }
        if row_count > 0 {
            output.push(',');
        }
        output.push('{');
        for (index, column) in columns.iter().enumerate().take(column_count) {
            if index > 0 {
                output.push(',');
            }
            let value = row
                .get_ref(index)
                .map(sql_value_to_string)
                .map_err(|error| error.to_string())?;
            output.push_str(&format!(
                "\"{}\":\"{}\"",
                json_escape(column),
                json_escape(&value)
            ));
        }
        output.push('}');
        row_count += 1;
    }
    output.push_str(&format!(
        "],\"rowCount\":{},\"truncated\":{}}}",
        row_count, truncated
    ));
    Ok(output)
}

fn readonly_sql(sql: &str) -> Result<String, String> {
    let trimmed = sql.trim().trim_end_matches(';').trim();
    if trimmed.is_empty() {
        return Err("SQL is empty".to_string());
    }
    if trimmed.contains(';') {
        return Err("Only one read-only SQL statement is allowed".to_string());
    }
    let without_comments = strip_leading_sql_comments(trimmed);
    let normalized = without_comments
        .split_whitespace()
        .collect::<Vec<_>>()
        .join(" ")
        .to_lowercase();
    let padded = format!(" {normalized} ");
    for forbidden in [
        " insert ",
        " update ",
        " delete ",
        " drop ",
        " alter ",
        " create ",
        " replace ",
        " attach ",
        " detach ",
        " vacuum ",
        " reindex ",
    ] {
        if padded.contains(forbidden) {
            return Err("Write and schema-changing SQL statements are not allowed".to_string());
        }
    }
    let allowed = normalized.starts_with("select ")
        || normalized == "select"
        || normalized.starts_with("with ")
        || normalized.starts_with("pragma table_info(")
        || normalized.starts_with("pragma index_list(")
        || normalized.starts_with("pragma index_info(")
        || normalized.starts_with("pragma foreign_key_list(");
    if !allowed {
        return Err(
            "Only read-only SELECT/WITH queries and table structure PRAGMA queries are allowed"
                .to_string(),
        );
    }
    Ok(without_comments.trim().to_string())
}

fn strip_leading_sql_comments(mut sql: &str) -> &str {
    loop {
        let trimmed = sql.trim_start();
        if let Some(rest) = trimmed.strip_prefix("--") {
            if let Some(newline) = rest.find('\n') {
                sql = &rest[newline + 1..];
                continue;
            }
            return "";
        }
        if let Some(rest) = trimmed.strip_prefix("/*") {
            if let Some(end) = rest.find("*/") {
                sql = &rest[end + 2..];
                continue;
            }
            return "";
        }
        return trimmed;
    }
}

fn sql_value_to_string(value: ValueRef<'_>) -> String {
    match value {
        ValueRef::Null => String::new(),
        ValueRef::Integer(value) => value.to_string(),
        ValueRef::Real(value) => finite_json_number(value),
        ValueRef::Text(value) => String::from_utf8_lossy(value).into_owned(),
        ValueRef::Blob(value) => format!("<blob {} bytes>", value.len()),
    }
}

fn annotation_columns() -> &'static [&'static str] {
    &[
        "id",
        "image_id",
        "project_id",
        "file_name",
        "image_path",
        "kind",
        "class_id",
        "class_name",
        "left",
        "top",
        "right",
        "bottom",
        "rotation",
        "points",
        "source",
        "confidence",
        "author_id",
        "author_name",
        "author_color",
        "updated_at",
    ]
}

fn annotation_sql(where_clause: &str) -> String {
    format!(
        r#"
        SELECT a.id, a.image_id, i.project_id, i.file_name, i.path,
               a.kind, a.class_id, COALESCE(c.name, '') AS class_name,
               a.left, a.top, a.right, a.bottom, a.rotation,
               a.points, a.source, a.confidence, a.author_id,
               a.author_name, a.author_color, a.updated_at
        FROM annotations a
        INNER JOIN images i ON i.id = a.image_id
        LEFT JOIN classes c ON c.project_id = i.project_id AND c.class_id = a.class_id
        WHERE {where_clause}
        ORDER BY i.sort_index, a.created_at, a.id
        LIMIT ? OFFSET ?
        "#
    )
}

fn parse_optional_i64(value: &str) -> Option<i64> {
    let trimmed = value.trim();
    if trimmed.is_empty() {
        None
    } else {
        trimmed.parse::<i64>().ok()
    }
}

fn parse_page_limit(value: &str) -> i64 {
    value.trim().parse::<i64>().unwrap_or(50).clamp(1, 200)
}

fn parse_nonnegative_i64(value: &str) -> i64 {
    value.trim().parse::<i64>().unwrap_or(0).max(0)
}

fn parse_payload(payload: &str) -> SnapshotPayload {
    let mut result = SnapshotPayload::default();
    for raw_line in payload.lines() {
        let line = raw_line.trim_end_matches('\r');
        if line.trim().is_empty() {
            continue;
        }
        let fields: Vec<&str> = line.split('\t').collect();
        match fields.first().copied() {
            Some("PROJECT") if fields.len() >= 2 => {
                result.project_key = fields[1].to_string();
            }
            Some("CLASS") if fields.len() >= 4 => result.classes.push(DbClass {
                id: parse_i64(fields[1]),
                name: fields[2].to_string(),
                color: parse_i64(fields[3]),
            }),
            Some("IMAGE") if fields.len() >= 7 => result.images.push(DbImage {
                path: fields[1].to_string(),
                name: fields[2].to_string(),
                split: fields[3].to_string(),
                width: parse_f64(fields[4]),
                height: parse_f64(fields[5]),
                sort_index: parse_i64(fields[6]),
            }),
            Some("ANNOTATION") if fields.len() >= 13 => result.annotations.push(DbAnnotation {
                image_path: fields[1].to_string(),
                id: fields[2].to_string(),
                kind: fields[3].to_string(),
                class_id: parse_i64(fields[4]),
                left: parse_f64(fields[5]),
                top: parse_f64(fields[6]),
                right: parse_f64(fields[7]),
                bottom: parse_f64(fields[8]),
                rotation: parse_f64(fields[9]),
                points: fields[10].to_string(),
                source: fields[11].to_string(),
                confidence: parse_f64(fields[12]),
                author_id: fields.get(13).copied().unwrap_or("").to_string(),
                author_name: fields.get(14).copied().unwrap_or("").to_string(),
                author_color: fields.get(15).map_or(0, |value| parse_i64(value)),
            }),
            Some("COLLAB_USER") if fields.len() >= 7 => {
                result
                    .collaboration_permissions
                    .push(DbCollaborationPermission {
                        user_id: fields[1].to_string(),
                        user_name: fields[2].to_string(),
                        color: parse_i64(fields[3]),
                        can_edit_others: parse_bool(fields[4]),
                        can_delete_others: parse_bool(fields[5]),
                        can_change_class: parse_bool(fields[6]),
                        assignment_start: fields.get(7).map_or(1, |value| parse_i64(value)),
                        assignment_end: fields.get(8).map_or(1, |value| parse_i64(value)),
                    })
            }
            _ => {}
        }
    }
    result
}

fn parse_bool(value: &str) -> bool {
    matches!(
        value.trim().to_ascii_lowercase().as_str(),
        "1" | "true" | "yes" | "y"
    )
}

fn project_key(value: &str) -> String {
    let trimmed = value.trim();
    if trimmed.is_empty() {
        "default".to_string()
    } else {
        trimmed.to_string()
    }
}

fn ensure_project(connection: &Connection, key: &str) -> Result<i64, String> {
    let name = project_key(key);
    connection
        .execute(
            r#"
            INSERT INTO projects(name, updated_at)
            VALUES (?, CURRENT_TIMESTAMP)
            ON CONFLICT(name) DO UPDATE SET updated_at=CURRENT_TIMESTAMP
            "#,
            params![name],
        )
        .map_err(|error| error.to_string())?;
    connection
        .query_row(
            "SELECT id FROM projects WHERE name=?",
            params![project_key(key)],
            |row| row.get::<_, i64>(0),
        )
        .map_err(|error| error.to_string())
}

fn init_schema(connection: &Connection) -> Result<(), String> {
    connection
        .execute_batch(
            r#"
            PRAGMA foreign_keys = ON;
            PRAGMA journal_mode = WAL;
            CREATE TABLE IF NOT EXISTS projects (
                id INTEGER PRIMARY KEY,
                name TEXT NOT NULL UNIQUE,
                root_path TEXT NOT NULL DEFAULT '',
                data_yaml_path TEXT NOT NULL DEFAULT '',
                created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
                updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
            );
            CREATE TABLE IF NOT EXISTS images (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                project_id INTEGER NOT NULL,
                path TEXT NOT NULL,
                file_name TEXT NOT NULL,
                width REAL NOT NULL DEFAULT 0,
                height REAL NOT NULL DEFAULT 0,
                split TEXT NOT NULL DEFAULT 'train',
                sort_index INTEGER NOT NULL DEFAULT 0,
                created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
                updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
                UNIQUE(project_id, path),
                FOREIGN KEY(project_id) REFERENCES projects(id) ON DELETE CASCADE
            );
            CREATE INDEX IF NOT EXISTS idx_images_project_file_name
                ON images(project_id, file_name);
            CREATE INDEX IF NOT EXISTS idx_images_project_path
                ON images(project_id, path);
            CREATE TABLE IF NOT EXISTS classes (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                project_id INTEGER NOT NULL,
                class_id INTEGER NOT NULL,
                name TEXT NOT NULL,
                color INTEGER NOT NULL DEFAULT 0,
                created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
                updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
                UNIQUE(project_id, class_id),
                FOREIGN KEY(project_id) REFERENCES projects(id) ON DELETE CASCADE
            );
            CREATE UNIQUE INDEX IF NOT EXISTS idx_classes_project_class
                ON classes(project_id, class_id);
            CREATE TABLE IF NOT EXISTS annotations (
                id TEXT NOT NULL,
                image_id INTEGER NOT NULL,
                class_id INTEGER NOT NULL,
                kind TEXT NOT NULL,
                left REAL NOT NULL DEFAULT 0,
                top REAL NOT NULL DEFAULT 0,
                right REAL NOT NULL DEFAULT 0,
                bottom REAL NOT NULL DEFAULT 0,
                rotation REAL NOT NULL DEFAULT 0,
                points TEXT NOT NULL DEFAULT '',
                source TEXT NOT NULL DEFAULT 'manual',
                confidence REAL NOT NULL DEFAULT 0,
                author_id TEXT NOT NULL DEFAULT '',
                author_name TEXT NOT NULL DEFAULT '',
                author_color INTEGER NOT NULL DEFAULT 0,
                created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
                updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
                PRIMARY KEY(image_id, id),
                FOREIGN KEY(image_id) REFERENCES images(id) ON DELETE CASCADE
            );
            CREATE INDEX IF NOT EXISTS idx_annotations_class_id
                ON annotations(class_id);
            CREATE INDEX IF NOT EXISTS idx_annotations_kind
                ON annotations(kind);
            CREATE INDEX IF NOT EXISTS idx_annotations_class_kind
                ON annotations(class_id, kind);
            CREATE TABLE IF NOT EXISTS collaboration_permissions (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                project_id INTEGER NOT NULL,
                user_id TEXT NOT NULL,
                user_name TEXT NOT NULL DEFAULT '',
                color INTEGER NOT NULL DEFAULT 0,
                can_edit_others INTEGER NOT NULL DEFAULT 0,
                can_delete_others INTEGER NOT NULL DEFAULT 0,
                can_change_class INTEGER NOT NULL DEFAULT 0,
                assignment_start INTEGER NOT NULL DEFAULT 1,
                assignment_end INTEGER NOT NULL DEFAULT 1,
                created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
                updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
                UNIQUE(project_id, user_id),
                FOREIGN KEY(project_id) REFERENCES projects(id) ON DELETE CASCADE
            );
            CREATE INDEX IF NOT EXISTS idx_collab_permissions_project
                ON collaboration_permissions(project_id, user_id);
            CREATE TABLE IF NOT EXISTS app_config (
                key TEXT PRIMARY KEY,
                value TEXT NOT NULL,
                created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
                updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
            );
            CREATE TABLE IF NOT EXISTS app_logs (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                created_at TEXT NOT NULL,
                log_date TEXT NOT NULL,
                level TEXT NOT NULL,
                tag TEXT NOT NULL,
                line TEXT NOT NULL
            );
            CREATE INDEX IF NOT EXISTS idx_app_logs_date_id
                ON app_logs(log_date, id);
            INSERT OR IGNORE INTO projects(id, name) VALUES (1, 'default');
            PRAGMA user_version = 1;
            "#,
        )
        .map_err(|error| error.to_string())?;
    ensure_column(
        connection,
        "annotations",
        "author_id",
        "TEXT NOT NULL DEFAULT ''",
    )?;
    ensure_column(
        connection,
        "annotations",
        "author_name",
        "TEXT NOT NULL DEFAULT ''",
    )?;
    ensure_column(
        connection,
        "annotations",
        "author_color",
        "INTEGER NOT NULL DEFAULT 0",
    )?;
    ensure_column(
        connection,
        "collaboration_permissions",
        "assignment_start",
        "INTEGER NOT NULL DEFAULT 1",
    )?;
    ensure_column(
        connection,
        "collaboration_permissions",
        "assignment_end",
        "INTEGER NOT NULL DEFAULT 1",
    )?;
    Ok(())
}

fn ensure_column(
    connection: &Connection,
    table_name: &str,
    column_name: &str,
    definition: &str,
) -> Result<(), String> {
    let mut stmt = connection
        .prepare(&format!("PRAGMA table_info({table_name})"))
        .map_err(|error| error.to_string())?;
    let rows = stmt
        .query_map([], |row| row.get::<_, String>(1))
        .map_err(|error| error.to_string())?;
    for row in rows {
        if row.map_err(|error| error.to_string())? == column_name {
            return Ok(());
        }
    }
    connection
        .execute(
            &format!("ALTER TABLE {table_name} ADD COLUMN {column_name} {definition}"),
            [],
        )
        .map_err(|error| error.to_string())?;
    Ok(())
}

fn save_classes(
    connection: &Connection,
    project_id: i64,
    classes: &[DbClass],
) -> Result<(), String> {
    let keep: HashSet<i64> = classes.iter().map(|class_item| class_item.id).collect();
    let mut existing_stmt = connection
        .prepare("SELECT class_id FROM classes WHERE project_id=?")
        .map_err(|error| error.to_string())?;
    let existing_rows = existing_stmt
        .query_map(params![project_id], |row| row.get::<_, i64>(0))
        .map_err(|error| error.to_string())?;
    let mut remove_ids = Vec::new();
    for row in existing_rows {
        let class_id = row.map_err(|error| error.to_string())?;
        if !keep.contains(&class_id) {
            remove_ids.push(class_id);
        }
    }
    drop(existing_stmt);
    for class_id in remove_ids {
        connection
            .execute(
                "DELETE FROM classes WHERE project_id=? AND class_id=?",
                params![project_id, class_id],
            )
            .map_err(|error| error.to_string())?;
    }

    let mut stmt = connection
        .prepare(
            r#"
            INSERT INTO classes(project_id, class_id, name, color, updated_at)
            VALUES (?, ?, ?, ?, CURRENT_TIMESTAMP)
            ON CONFLICT(project_id, class_id) DO UPDATE SET
                name=excluded.name,
                color=excluded.color,
                updated_at=CURRENT_TIMESTAMP
            "#,
        )
        .map_err(|error| error.to_string())?;
    for class_item in classes {
        stmt.execute(params![
            project_id,
            class_item.id,
            class_item.name,
            class_item.color
        ])
        .map_err(|error| error.to_string())?;
    }
    Ok(())
}

fn reconcile_images(
    connection: &Connection,
    project_id: i64,
    images: &[DbImage],
) -> Result<(), String> {
    for image in images {
        if image_id_by_path(connection, project_id, &image.path)?.is_some() {
            continue;
        }
        let candidates = image_ids_by_file_name(connection, project_id, &image.name)?;
        for (image_id, old_path) in candidates {
            if path_key(&old_path) != path_key(&image.path) && !Path::new(&old_path).exists() {
                connection
                    .execute(
                        "UPDATE images SET path=?, updated_at=CURRENT_TIMESTAMP WHERE id=?",
                        params![image.path, image_id],
                    )
                    .map_err(|error| error.to_string())?;
                break;
            }
        }
    }
    Ok(())
}

fn save_images(connection: &Connection, project_id: i64, images: &[DbImage]) -> Result<(), String> {
    let mut stmt = connection
        .prepare(
            r#"
            INSERT INTO images(project_id, path, file_name, width, height, split, sort_index, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, CURRENT_TIMESTAMP)
            ON CONFLICT(project_id, path) DO UPDATE SET
                file_name=excluded.file_name,
                width=excluded.width,
                height=excluded.height,
                split=excluded.split,
                sort_index=excluded.sort_index,
                updated_at=CURRENT_TIMESTAMP
            "#,
        )
        .map_err(|error| error.to_string())?;
    for image in images {
        stmt.execute(params![
            project_id,
            image.path,
            image.name,
            finite_f64(image.width),
            finite_f64(image.height),
            normalize_split(&image.split),
            image.sort_index
        ])
        .map_err(|error| error.to_string())?;
    }
    Ok(())
}

fn save_annotations(
    connection: &Connection,
    project_id: i64,
    images: &[DbImage],
    annotations: &[DbAnnotation],
) -> Result<(), String> {
    for image in images {
        if let Some(image_id) = image_id_by_path(connection, project_id, &image.path)? {
            connection
                .execute(
                    "DELETE FROM annotations WHERE image_id=?",
                    params![image_id],
                )
                .map_err(|error| error.to_string())?;
        }
    }

    let mut stmt = connection
        .prepare(
            r#"
            INSERT INTO annotations(
                id, image_id, class_id, kind, left, top, right, bottom,
                rotation, points, source, confidence, author_id, author_name,
                author_color, updated_at
            )
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, CURRENT_TIMESTAMP)
            ON CONFLICT(image_id, id) DO UPDATE SET
                class_id=excluded.class_id,
                kind=excluded.kind,
                left=excluded.left,
                top=excluded.top,
                right=excluded.right,
                bottom=excluded.bottom,
                rotation=excluded.rotation,
                points=excluded.points,
                source=excluded.source,
                confidence=excluded.confidence,
                author_id=excluded.author_id,
                author_name=excluded.author_name,
                author_color=excluded.author_color,
                updated_at=CURRENT_TIMESTAMP
            "#,
        )
        .map_err(|error| error.to_string())?;
    for annotation in annotations {
        let Some(image_id) = image_id_by_path(connection, project_id, &annotation.image_path)?
        else {
            continue;
        };
        stmt.execute(params![
            annotation.id,
            image_id,
            annotation.class_id,
            annotation.kind,
            finite_f64(annotation.left),
            finite_f64(annotation.top),
            finite_f64(annotation.right),
            finite_f64(annotation.bottom),
            finite_f64(annotation.rotation),
            annotation.points,
            annotation.source,
            finite_f64(annotation.confidence),
            annotation.author_id,
            annotation.author_name,
            annotation.author_color,
        ])
        .map_err(|error| error.to_string())?;
    }
    Ok(())
}

fn save_collaboration_permissions(
    connection: &Connection,
    project_id: i64,
    permissions: &[DbCollaborationPermission],
) -> Result<(), String> {
    if permissions.is_empty() {
        return Ok(());
    }
    let mut stmt = connection
        .prepare(
            r#"
            INSERT INTO collaboration_permissions(
                project_id, user_id, user_name, color, can_edit_others,
                can_delete_others, can_change_class, assignment_start,
                assignment_end, updated_at
            )
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, CURRENT_TIMESTAMP)
            ON CONFLICT(project_id, user_id) DO UPDATE SET
                user_name=excluded.user_name,
                color=excluded.color,
                can_edit_others=excluded.can_edit_others,
                can_delete_others=excluded.can_delete_others,
                can_change_class=excluded.can_change_class,
                assignment_start=excluded.assignment_start,
                assignment_end=excluded.assignment_end,
                updated_at=CURRENT_TIMESTAMP
            "#,
        )
        .map_err(|error| error.to_string())?;
    for permission in permissions {
        if permission.user_id.trim().is_empty() {
            continue;
        }
        stmt.execute(params![
            project_id,
            permission.user_id,
            permission.user_name,
            permission.color,
            if permission.can_edit_others {
                1_i64
            } else {
                0_i64
            },
            if permission.can_delete_others {
                1_i64
            } else {
                0_i64
            },
            if permission.can_change_class {
                1_i64
            } else {
                0_i64
            },
            permission.assignment_start.max(1),
            permission
                .assignment_end
                .max(permission.assignment_start.max(1)),
        ])
        .map_err(|error| error.to_string())?;
    }
    Ok(())
}

fn delete_images_not_in_snapshot(
    connection: &Connection,
    project_id: i64,
    images: &[DbImage],
) -> Result<(), String> {
    let keep: HashSet<String> = images.iter().map(|image| path_key(&image.path)).collect();
    let mut stmt = connection
        .prepare("SELECT id, path FROM images WHERE project_id=?")
        .map_err(|error| error.to_string())?;
    let rows = stmt
        .query_map(params![project_id], |row| {
            Ok((row.get::<_, i64>(0)?, row.get::<_, String>(1)?))
        })
        .map_err(|error| error.to_string())?;
    let mut remove_ids = Vec::new();
    for row in rows {
        let (id, path) = row.map_err(|error| error.to_string())?;
        if !keep.contains(&path_key(&path)) {
            remove_ids.push(id);
        }
    }
    drop(stmt);

    for image_id in remove_ids {
        connection
            .execute(
                "DELETE FROM annotations WHERE image_id=?",
                params![image_id],
            )
            .map_err(|error| error.to_string())?;
        connection
            .execute("DELETE FROM images WHERE id=?", params![image_id])
            .map_err(|error| error.to_string())?;
    }
    Ok(())
}

fn load_classes(connection: &Connection, project_id: i64) -> Result<Vec<DbClass>, String> {
    let mut stmt = connection
        .prepare("SELECT class_id, name, color FROM classes WHERE project_id=? ORDER BY class_id")
        .map_err(|error| error.to_string())?;
    let rows = stmt
        .query_map(params![project_id], |row| {
            Ok(DbClass {
                id: row.get(0)?,
                name: row.get(1)?,
                color: row.get(2)?,
            })
        })
        .map_err(|error| error.to_string())?;
    rows.collect::<Result<Vec<_>, _>>()
        .map_err(|error| error.to_string())
}

fn load_annotations(
    connection: &Connection,
    project_id: i64,
    current_paths: &HashSet<String>,
) -> Result<Vec<DbAnnotation>, String> {
    let mut stmt = connection
        .prepare(
            r#"
            SELECT i.path, a.id, a.kind, a.class_id, a.left, a.top, a.right,
                   a.bottom, a.rotation, a.points, a.source, a.confidence,
                   a.author_id, a.author_name, a.author_color
            FROM annotations a
            INNER JOIN images i ON i.id = a.image_id
            WHERE i.project_id=?
            ORDER BY i.sort_index, a.created_at, a.id
            "#,
        )
        .map_err(|error| error.to_string())?;
    let rows = stmt
        .query_map(params![project_id], |row| {
            Ok(DbAnnotation {
                image_path: row.get(0)?,
                id: row.get(1)?,
                kind: row.get(2)?,
                class_id: row.get(3)?,
                left: row.get(4)?,
                top: row.get(5)?,
                right: row.get(6)?,
                bottom: row.get(7)?,
                rotation: row.get(8)?,
                points: row.get(9)?,
                source: row.get(10)?,
                confidence: row.get(11)?,
                author_id: row.get(12)?,
                author_name: row.get(13)?,
                author_color: row.get(14)?,
            })
        })
        .map_err(|error| error.to_string())?;
    let mut annotations = Vec::new();
    for row in rows {
        let annotation = row.map_err(|error| error.to_string())?;
        if current_paths.is_empty() || current_paths.contains(&path_key(&annotation.image_path)) {
            annotations.push(annotation);
        }
    }
    Ok(annotations)
}

fn image_id_by_path(
    connection: &Connection,
    project_id: i64,
    path: &str,
) -> Result<Option<i64>, String> {
    let exact = connection
        .query_row(
            "SELECT id FROM images WHERE project_id=? AND path=?",
            params![project_id, path],
            |row| row.get::<_, i64>(0),
        )
        .optional()
        .map_err(|error| error.to_string())?;
    if exact.is_some() {
        return Ok(exact);
    }
    image_id_by_path_key(connection, project_id, &path_key(path))
}

fn image_id_by_path_key(
    connection: &Connection,
    project_id: i64,
    key: &str,
) -> Result<Option<i64>, String> {
    let mut stmt = connection
        .prepare("SELECT id, path FROM images WHERE project_id=?")
        .map_err(|error| error.to_string())?;
    let rows = stmt
        .query_map(params![project_id], |row| {
            Ok((row.get::<_, i64>(0)?, row.get::<_, String>(1)?))
        })
        .map_err(|error| error.to_string())?;
    for row in rows {
        let (id, path) = row.map_err(|error| error.to_string())?;
        if path_key(&path) == key {
            return Ok(Some(id));
        }
    }
    Ok(None)
}

fn image_ids_by_file_name(
    connection: &Connection,
    project_id: i64,
    file_name: &str,
) -> Result<Vec<(i64, String)>, String> {
    let mut stmt = connection
        .prepare(
            "SELECT id, path FROM images WHERE project_id=? AND file_name=? ORDER BY updated_at DESC",
        )
        .map_err(|error| error.to_string())?;
    let rows = stmt
        .query_map(params![project_id, file_name], |row| {
            Ok((row.get(0)?, row.get(1)?))
        })
        .map_err(|error| error.to_string())?;
    rows.collect::<Result<Vec<_>, _>>()
        .map_err(|error| error.to_string())
}

fn snapshot_json(path: &Path, classes: &[DbClass], annotations: &[DbAnnotation]) -> String {
    let mut output = format!(
        "{{\"ok\":true,\"dbPath\":\"{}\",\"classes\":[",
        json_escape(&path.to_string_lossy())
    );
    for (index, class_item) in classes.iter().enumerate() {
        if index > 0 {
            output.push(',');
        }
        output.push_str(&format!(
            "{{\"id\":{},\"name\":\"{}\",\"color\":{}}}",
            class_item.id,
            json_escape(&class_item.name),
            class_item.color
        ));
    }
    output.push_str("],\"annotations\":[");
    for (index, annotation) in annotations.iter().enumerate() {
        if index > 0 {
            output.push(',');
        }
        output.push_str(&format!(
            "{{\"imagePath\":\"{}\",\"id\":\"{}\",\"kind\":\"{}\",\"classId\":{},\"left\":{},\"top\":{},\"right\":{},\"bottom\":{},\"rotation\":{},\"points\":\"{}\",\"source\":\"{}\",\"confidence\":{},\"authorId\":\"{}\",\"authorName\":\"{}\",\"authorColor\":{}}}",
            json_escape(&annotation.image_path),
            json_escape(&annotation.id),
            json_escape(&annotation.kind),
            annotation.class_id,
            finite_json_number(annotation.left),
            finite_json_number(annotation.top),
            finite_json_number(annotation.right),
            finite_json_number(annotation.bottom),
            finite_json_number(annotation.rotation),
            json_escape(&annotation.points),
            json_escape(&annotation.source),
            finite_json_number(annotation.confidence),
            json_escape(&annotation.author_id),
            json_escape(&annotation.author_name),
            annotation.author_color,
        ));
    }
    output.push_str("]}");
    output
}

fn string_array_json(path: &Path, key: &str, values: &[String]) -> String {
    let mut output = format!(
        "{{\"ok\":true,\"dbPath\":\"{}\",\"{}\":[",
        json_escape(&path.to_string_lossy()),
        json_escape(key)
    );
    for (index, value) in values.iter().enumerate() {
        if index > 0 {
            output.push(',');
        }
        output.push('"');
        output.push_str(&json_escape(value));
        output.push('"');
    }
    output.push_str("]}");
    output
}

fn parse_log_line_metadata(line: &str) -> (String, String, String, String) {
    let created_at = if line.len() >= 21 && line.starts_with('[') && &line[20..21] == "]" {
        line[1..20].to_string()
    } else {
        current_timestamp()
    };
    let log_date = if created_at.len() >= 10 {
        created_at[..10].to_string()
    } else {
        current_date()
    };
    let level = bracket_token_after(line, 21).unwrap_or_else(|| "INFO".to_string());
    let tag_start = 21 + level.len() + 3;
    let tag = bracket_token_after(line, tag_start).unwrap_or_default();
    (created_at, log_date, level, tag)
}

fn bracket_token_after(line: &str, start: usize) -> Option<String> {
    let rest = line.get(start..)?.trim_start();
    if !rest.starts_with('[') {
        return None;
    }
    let end = rest.find(']')?;
    Some(rest[1..end].to_string())
}

fn current_timestamp() -> String {
    // SQLite can generate local-ish timestamps for storage without adding a Rust time crate.
    // The exact display timestamp is kept in the original log line.
    "1970-01-01 00:00:00".to_string()
}

fn current_date() -> String {
    "1970-01-01".to_string()
}

fn normalize_split(value: &str) -> &str {
    match value {
        "train" | "val" | "test" => value,
        _ => "train",
    }
}

fn parse_i64(value: &str) -> i64 {
    value.parse::<i64>().unwrap_or(0)
}

fn parse_f64(value: &str) -> f64 {
    value.parse::<f64>().unwrap_or(0.0)
}

fn finite_f64(value: f64) -> f64 {
    if value.is_finite() {
        value
    } else {
        0.0
    }
}

fn path_key(path: &str) -> String {
    path.replace('/', "\\").to_lowercase()
}

fn finite_json_number(value: f64) -> String {
    if value.is_finite() {
        format!("{value:.6}")
    } else {
        "0".to_string()
    }
}

fn json_escape(value: &str) -> String {
    let mut out = String::with_capacity(value.len() + 8);
    for ch in value.chars() {
        match ch {
            '"' => out.push_str("\\\""),
            '\\' => out.push_str("\\\\"),
            '\n' => out.push_str("\\n"),
            '\r' => out.push_str("\\r"),
            '\t' => out.push_str("\\t"),
            ch if ch.is_control() => out.push_str(&format!("\\u{:04x}", ch as u32)),
            ch => out.push(ch),
        }
    }
    out
}
