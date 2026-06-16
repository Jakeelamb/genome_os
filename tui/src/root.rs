use crate::floating_text::FloatingText;

#[cfg(unix)]
use nix::unistd::Uid;

const ROOT_WARNING: &str = "WARNING: Open Genome is running as root!\n
Most setup and analysis helpers are designed to run as your normal user and prompt for privileges only when needed.\n
Running as root can write manifests, conda environments, outputs, and downloaded data with ownership that later workflows cannot use.";

#[cfg(unix)]
pub fn check_root_status(bypass_root: bool) -> Option<FloatingText<'static>> {
    if bypass_root {
        return None;
    }

    Uid::effective().is_root().then_some(FloatingText::new(
        ROOT_WARNING.into(),
        "Open Genome Root Warning",
        true,
    ))
}
