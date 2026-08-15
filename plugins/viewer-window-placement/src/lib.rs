use serde::Deserialize;

pub const ARGUMENT: &str = "--window-placement";
const PROTOCOL_VERSION: u32 = 1;
const MINIMUM_EXTENT: u32 = 64;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct WindowPlacement {
    pub x: i32,
    pub y: i32,
    pub width: u32,
    pub height: u32,
    pub maximized: bool,
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct WirePlacement {
    version: u32,
    x: i32,
    y: i32,
    width: u32,
    height: u32,
    maximized: bool,
}

impl WindowPlacement {
    pub fn from_json(value: &str) -> Result<Self, String> {
        let wire: WirePlacement = serde_json::from_str(value)
            .map_err(|error| format!("invalid window placement: {error}"))?;
        if wire.version != PROTOCOL_VERSION {
            return Err(format!(
                "unsupported window placement version: {}",
                wire.version
            ));
        }
        if wire.width < MINIMUM_EXTENT || wire.height < MINIMUM_EXTENT {
            return Err(format!(
                "window placement must be at least {MINIMUM_EXTENT}x{MINIMUM_EXTENT}"
            ));
        }
        Ok(Self {
            x: wire.x,
            y: wire.y,
            width: wire.width,
            height: wire.height,
            maximized: wire.maximized,
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_complete_v1_placement() {
        assert_eq!(
            WindowPlacement::from_json(
                r#"{"version":1,"x":1024,"y":0,"width":1024,"height":1152,"maximized":false}"#,
            ),
            Ok(WindowPlacement {
                x: 1024,
                y: 0,
                width: 1024,
                height: 1152,
                maximized: false,
            })
        );
    }

    #[test]
    fn rejects_unknown_versions_and_incomplete_payloads() {
        assert!(WindowPlacement::from_json(
            r#"{"version":2,"x":0,"y":0,"width":960,"height":720,"maximized":false}"#,
        )
        .is_err());
        assert!(WindowPlacement::from_json(
            r#"{"version":1,"x":0,"y":0,"width":960,"height":720}"#,
        )
        .is_err());
    }
}
