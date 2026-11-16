//! koorikla/ci selftest fixture: request handling for a tiny HTTP service.

/// Greeting for `name`; blank names greet the world.
///
/// ```
/// assert_eq!(ci_selftest_rust::greet("ci"), "hello, ci");
/// ```
pub fn greet(name: &str) -> String {
    let n = name.trim();
    format!("hello, {}", if n.is_empty() { "world" } else { n })
}

/// Status line, content type and body for a request target such as `/?name=x`.
pub fn route(target: &str, version: &str) -> (&'static str, &'static str, String) {
    let (path, query) = target.split_once('?').unwrap_or((target, ""));
    match path {
        "/healthz" => ("200 OK", "text/plain", "ok".to_string()),
        "/" => {
            let name = query
                .split('&')
                .find_map(|kv| kv.strip_prefix("name="))
                .unwrap_or("");
            let body = format!(
                "{{\"message\":\"{}\",\"version\":\"{}\"}}",
                greet(name).replace('"', ""),
                version
            );
            ("200 OK", "application/json", body)
        }
        _ => ("404 Not Found", "text/plain", "not found".to_string()),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn greets() {
        assert_eq!(greet("koorikla"), "hello, koorikla");
        assert_eq!(greet("  "), "hello, world");
    }

    #[test]
    fn routes() {
        assert_eq!(route("/healthz", "dev").2, "ok");
        assert!(route("/?name=ci", "dev").2.contains("hello, ci"));
        assert_eq!(route("/nope", "dev").0, "404 Not Found");
    }
}
