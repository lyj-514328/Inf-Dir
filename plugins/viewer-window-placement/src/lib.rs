use serde::Deserialize;

pub const ARGUMENT: &str = "--window-placement";
const PROTOCOL_VERSION: u32 = 2;
const MINIMUM_EXTENT: u32 = 64;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct WindowPlacement {
    pub x: i32,
    pub y: i32,
    pub client_width: u32,
    pub client_height: u32,
    pub maximized: bool,
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct WirePlacement {
    version: u32,
    x: i32,
    y: i32,
    #[serde(rename = "clientWidth")]
    client_width: u32,
    #[serde(rename = "clientHeight")]
    client_height: u32,
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
        if wire.client_width < MINIMUM_EXTENT || wire.client_height < MINIMUM_EXTENT {
            return Err(format!(
                "window placement must be at least {MINIMUM_EXTENT}x{MINIMUM_EXTENT}"
            ));
        }
        Ok(Self {
            x: wire.x,
            y: wire.y,
            client_width: wire.client_width,
            client_height: wire.client_height,
            maximized: wire.maximized,
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_complete_v2_placement() {
        assert_eq!(
            WindowPlacement::from_json(
                r#"{"version":2,"x":1024,"y":0,"clientWidth":1008,"clientHeight":1113,"maximized":false}"#,
            ),
            Ok(WindowPlacement {
                x: 1024,
                y: 0,
                client_width: 1008,
                client_height: 1113,
                maximized: false,
            })
        );
    }

    #[test]
    fn rejects_unknown_versions_and_incomplete_payloads() {
        assert!(WindowPlacement::from_json(
            r#"{"version":1,"x":0,"y":0,"width":960,"height":720,"maximized":false}"#,
        )
        .is_err());
        assert!(WindowPlacement::from_json(
            r#"{"version":2,"x":0,"y":0,"clientWidth":960,"clientHeight":720}"#,
        )
        .is_err());
    }
}
