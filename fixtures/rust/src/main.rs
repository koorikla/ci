//! Serves `ci_selftest_rust::route` over HTTP/1.1 on $PORT (default 8080).

use std::io::{BufRead, BufReader, Write};
use std::net::{TcpListener, TcpStream};
use std::{env, thread};

fn handle(stream: TcpStream, version: &str) -> std::io::Result<()> {
    let mut reader = BufReader::new(stream.try_clone()?);
    let mut request_line = String::new();
    reader.read_line(&mut request_line)?;
    let target = request_line.split_whitespace().nth(1).unwrap_or("/");
    let (status, content_type, body) = ci_selftest_rust::route(target, version);
    let mut stream = stream;
    write!(
        stream,
        "HTTP/1.1 {status}\r\nContent-Type: {content_type}\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{body}",
        body.len()
    )
}

fn main() -> std::io::Result<()> {
    let port = env::var("PORT").unwrap_or_else(|_| "8080".to_string());
    let version = env::var("VERSION").unwrap_or_else(|_| env!("CARGO_PKG_VERSION").to_string());
    let listener = TcpListener::bind(("0.0.0.0", port.parse().unwrap_or(8080)))?;
    eprintln!("listening on :{port}");
    for stream in listener.incoming() {
        let stream = stream?;
        let version = version.clone();
        thread::spawn(move || {
            if let Err(e) = handle(stream, &version) {
                eprintln!("request failed: {e}");
            }
        });
    }
    Ok(())
}
