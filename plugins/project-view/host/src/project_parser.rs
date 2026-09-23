use std::cell::RefCell;
use std::path::Path;
use std::rc::Rc;

use mpxj::mpp::mpp_reader::MPPReader;
use mpxj::mpx::mpx_reader::MPXReader;
use mpxj::mspdi::mspdi_reader::MSPDIReader;
use mpxj::reader::project_reader::ProjectReader;
use mpxj::{Duration, ProjectFile, Relation, Task};
use serde::Serialize;

const SCHEMA_VERSION: u32 = 1;

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ProjectData {
    schema_version: u32,
    file_name: String,
    title: String,
    tasks: Vec<TaskData>,
    warnings: Vec<String>,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
struct TaskData {
    id: String,
    uid: String,
    parent_id: Option<String>,
    wbs: String,
    name: String,
    outline_level: i32,
    start: Option<String>,
    finish: Option<String>,
    duration: String,
    percent_complete: f64,
    summary: bool,
    milestone: bool,
    predecessors: Vec<DependencyData>,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
struct DependencyData {
    task_id: String,
    r#type: String,
    lag: String,
}

pub fn read_project(path: &Path) -> Result<ProjectData, String> {
    let extension = path
        .extension()
        .and_then(|value| value.to_str())
        .unwrap_or_default()
        .to_ascii_lowercase();
    let project = match extension.as_str() {
        "mpp" | "mpt" => MPPReader::new().read_file(path),
        "mpx" => MPXReader::new().read_file(path),
        "xml" | "mspdi" => MSPDIReader::new().read_file(path),
        _ => {
            let format = if extension.is_empty() {
                "a file without an extension".to_owned()
            } else {
                format!(".{extension}")
            };
            return Err(format!(
                "unsupported project format {format}; expected MPP, MPT, MPX, or MSPDI XML"
            ));
        }
    }
    .map_err(|error| format!("failed to read {}: {error}", path.display()))?;

    project_data(path, &project)
}

fn project_data(path: &Path, project: &Rc<RefCell<ProjectFile>>) -> Result<ProjectData, String> {
    let file_name = path
        .file_name()
        .map(|value| value.to_string_lossy().into_owned())
        .unwrap_or_default();
    let fallback_title = path
        .file_stem()
        .map(|value| value.to_string_lossy().into_owned())
        .filter(|value| !value.is_empty())
        .unwrap_or_else(|| file_name.clone());

    let (title, task_handles, warnings) = {
        let project = project
            .try_borrow()
            .map_err(|_| "project data is already borrowed".to_owned())?;
        let title = project
            .get_project_properties()
            .get_project_title()
            .filter(|value| !value.trim().is_empty())
            .unwrap_or(fallback_title);
        let tasks = project.get_tasks().iter().cloned().collect::<Vec<_>>();
        let warnings = project
            .get_ignored_errors()
            .iter()
            .map(ToString::to_string)
            .collect();
        (title, tasks, warnings)
    };

    let tasks = task_handles
        .iter()
        .filter_map(task_data)
        .collect::<Vec<_>>();

    Ok(ProjectData {
        schema_version: SCHEMA_VERSION,
        file_name,
        title,
        tasks,
        warnings,
    })
}

fn task_data(task: &Rc<RefCell<Task>>) -> Option<TaskData> {
    let (
        id,
        uid,
        parent,
        wbs,
        name,
        outline_level,
        start,
        finish,
        duration,
        percent_complete,
        summary,
        milestone,
        relations,
    ) = {
        let task = task.try_borrow().ok()?;
        let name = task.get_name().unwrap_or_default();
        if name.trim().is_empty() {
            return None;
        }
        let id = identifier(task.get_id(), task.get_unique_id());
        let uid = identifier(task.get_unique_id(), task.get_id());
        let duration = task
            .get_duration_text()
            .filter(|value| !value.trim().is_empty())
            .or_else(|| task.get_duration().map(format_duration))
            .unwrap_or_default();

        let percent_complete = task.get_percentage_complete().unwrap_or(0.0);
        let percent_complete = if percent_complete.is_finite() {
            percent_complete.clamp(0.0, 100.0)
        } else {
            0.0
        };

        (
            id,
            uid,
            task.get_parent_task(),
            task.get_wbs().unwrap_or_default(),
            name,
            task.get_outline_level().unwrap_or(1),
            task.get_start().map(format_date),
            task.get_finish().map(format_date),
            duration,
            percent_complete,
            task.get_summary(),
            task.get_milestone(),
            task.get_predecessors(),
        )
    };

    let parent_id = parent.and_then(|parent| {
        let parent = parent.try_borrow().ok()?;
        Some(identifier(parent.get_unique_id(), parent.get_id()))
    });
    let predecessors = relations
        .iter()
        .filter_map(dependency_data)
        .collect::<Vec<_>>();

    Some(TaskData {
        id,
        uid,
        parent_id,
        wbs,
        name,
        outline_level,
        start,
        finish,
        duration,
        percent_complete,
        summary,
        milestone,
        predecessors,
    })
}

fn dependency_data(relation: &Rc<RefCell<Relation>>) -> Option<DependencyData> {
    let (predecessor, relation_type, lag) = {
        let relation = relation.try_borrow().ok()?;
        (
            relation.get_predecessor_task()?,
            relation.get_type().to_string(),
            relation.get_lag().map(format_duration).unwrap_or_default(),
        )
    };
    let predecessor = predecessor.try_borrow().ok()?;
    Some(DependencyData {
        task_id: identifier(predecessor.get_unique_id(), predecessor.get_id()),
        r#type: relation_type,
        lag,
    })
}

fn identifier(primary: Option<i32>, fallback: Option<i32>) -> String {
    match primary {
        Some(value) if value != 0 => value.to_string(),
        _ => fallback.map(|value| value.to_string()).unwrap_or_default(),
    }
}

fn format_date(value: impl ToString) -> String {
    value.to_string().replacen(' ', "T", 1)
}

fn format_duration(value: Duration) -> String {
    let number = value.get_duration();
    // mpxj-rs 0.1.1 omits the decimal for whole values; preserve MPXJ's "8.0h" contract.
    let amount = if number.is_finite() && number.fract() == 0.0 {
        format!("{number:.1}")
    } else {
        number.to_string()
    };
    format!("{amount}{}", value.get_units())
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::time::{SystemTime, UNIX_EPOCH};

    fn temporary_file(extension: &str, contents: &[u8]) -> std::path::PathBuf {
        let nonce = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .expect("clock is after Unix epoch")
            .as_nanos();
        let path = std::env::temp_dir().join(format!(
            "inf-dir-project-view-{}-{nonce}.{extension}",
            std::process::id()
        ));
        std::fs::write(&path, contents).expect("write test project");
        path
    }

    #[test]
    fn reads_mpx_into_the_viewer_contract() {
        let mpx = b"MPX,Microsoft Project for Windows,4.0,ANSI\r\n\
10,$,1,2,\",\",.\r\n\
11,2,0,1,8.00,40.00,,,1,0\r\n\
12,1,0,480,/,:,am,pm,20,20\r\n\
30,Inf-Dir self-test,,,,,,0,01/01/2026,,,,,,,,,,,,,,,,,0d,0d\r\n\
60,Name,WBS,Outline Level,Fixed,ID,Unique ID,Outline Number\r\n\
61,1,2,3,80,90,98,99\r\n\
70,Preview task,1,1,No,1,1,1\r\n";
        let path = temporary_file("mpx", mpx);

        let project = read_project(&path).expect("parse MPX");
        std::fs::remove_file(path).expect("remove test project");

        assert_eq!(project.schema_version, SCHEMA_VERSION);
        assert_eq!(project.title, "Inf-Dir self-test");
        assert_eq!(project.tasks.len(), 1);
        assert_eq!(project.tasks[0].name, "Preview task");
    }

    #[test]
    fn reads_mspdi_into_the_viewer_contract() {
        let xml = br#"<?xml version="1.0" encoding="UTF-8"?>
<Project xmlns="http://schemas.microsoft.com/project">
  <Title>XML plan</Title>
  <Tasks><Task><UID>1</UID><ID>1</ID><Name>XML task</Name><OutlineLevel>1</OutlineLevel></Task></Tasks>
</Project>"#;
        let path = temporary_file("xml", xml);

        let project = read_project(&path).expect("parse MSPDI");
        std::fs::remove_file(path).expect("remove test project");

        assert_eq!(project.title, "XML plan");
        assert_eq!(project.tasks.len(), 1);
        assert_eq!(project.tasks[0].uid, "1");
    }

    #[test]
    #[ignore = "requires PROJECT_VIEW_TEST_MPP to point to an MPXJ regression fixture"]
    fn reads_an_external_mpp_regression_fixture() {
        let path = std::env::var_os("PROJECT_VIEW_TEST_MPP")
            .map(std::path::PathBuf::from)
            .expect("PROJECT_VIEW_TEST_MPP is set");
        let project = read_project(&path).expect("parse MPP regression fixture");
        assert!(!project.tasks.is_empty());
    }

    #[test]
    fn rejects_unknown_formats_before_reading() {
        let path = temporary_file("txt", b"not a project");
        let error = read_project(&path).expect_err("reject unsupported extension");
        std::fs::remove_file(path).expect("remove test project");
        assert!(error.contains("unsupported project format .txt"));
    }

    #[test]
    fn formats_java_style_whole_number_durations() {
        let duration = Duration::get_instance(8.0, mpxj::TimeUnit::Hours);
        assert_eq!(format_duration(duration), "8.0h");
    }

    #[test]
    fn identifiers_match_the_previous_parser_fallback_rules() {
        assert_eq!(identifier(Some(7), Some(9)), "7");
        assert_eq!(identifier(Some(0), Some(9)), "9");
        assert_eq!(identifier(None, None), "");
    }
}
