use once_cell::sync::Lazy;
use std::collections::{HashMap, VecDeque};
use std::io::{BufRead, BufReader, ErrorKind, Write};
use std::net::{Ipv4Addr, Shutdown, TcpListener, TcpStream, UdpSocket};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex};
use std::thread::{self, JoinHandle};
use std::time::{Duration, SystemTime, UNIX_EPOCH};

const PROTOCOL: &str = "rustlabel_collab_v1";
const MAX_EVENTS: usize = 500;

static EVENTS: Lazy<Mutex<VecDeque<String>>> = Lazy::new(|| Mutex::new(VecDeque::new()));
static DISCOVERY: Lazy<Mutex<Option<Runtime>>> = Lazy::new(|| Mutex::new(None));
static HOST: Lazy<Mutex<Option<Runtime>>> = Lazy::new(|| Mutex::new(None));
static CLIENT: Lazy<Mutex<Option<Runtime>>> = Lazy::new(|| Mutex::new(None));

struct Runtime {
    stop: Arc<AtomicBool>,
    handles: Vec<JoinHandle<()>>,
    clients: Arc<Mutex<HashMap<String, Arc<Mutex<TcpStream>>>>>,
    client_stream: Option<Arc<Mutex<TcpStream>>>,
}

impl Runtime {
    fn new(stop: Arc<AtomicBool>) -> Self {
        Self {
            stop,
            handles: Vec::new(),
            clients: Arc::new(Mutex::new(HashMap::new())),
            client_stream: None,
        }
    }

    fn stop(mut self) {
        self.stop.store(true, Ordering::SeqCst);
        if let Some(stream) = self.client_stream.take() {
            shutdown_stream(&stream);
        }
        if let Ok(clients) = self.clients.lock() {
            for stream in clients.values() {
                shutdown_stream(stream);
            }
        }
        for handle in self.handles.drain(..) {
            let _ = handle.join();
        }
    }
}

pub fn command_json(request: &str) -> Result<String, String> {
    let action = required_json_string(request, "action")?;
    match action.as_str() {
        "start_discovery" => {
            let port = json_u16_field(request, "port").unwrap_or(8765);
            start_discovery(port)?;
            Ok(ok_message("discovery_started"))
        }
        "start_host" => {
            let config = HostConfig {
                host_id: required_json_string(request, "hostId")?,
                host_name: json_string_field(request, "hostName")
                    .unwrap_or_else(|| "RustLabel Host".to_string()),
                user_id: required_json_string(request, "userId")?,
                user_name: json_string_field(request, "userName")
                    .unwrap_or_else(|| "Host".to_string()),
                port: json_u16_field(request, "port").unwrap_or(8765),
                project_id: json_string_field(request, "projectId").unwrap_or_default(),
                image_count: json_u32_field(request, "imageCount").unwrap_or(0),
            };
            start_host(config)?;
            Ok(ok_message("host_started"))
        }
        "join_host" => {
            let config = ClientConfig {
                host_id: required_json_string(request, "hostId")?,
                address: required_json_string(request, "address")?,
                port: json_u16_field(request, "port").unwrap_or(8765),
                user_id: required_json_string(request, "userId")?,
                user_name: json_string_field(request, "userName")
                    .unwrap_or_else(|| "Client".to_string()),
                color_value: json_u32_field(request, "colorValue").unwrap_or(0),
            };
            join_host(config)?;
            Ok(ok_message("join_requested"))
        }
        "host_accept" => {
            let user_id = required_json_string(request, "userId")?;
            let host_id = required_json_string(request, "hostId")?;
            let start = json_u32_field(request, "assignmentStart").unwrap_or(1);
            let end = json_u32_field(request, "assignmentEnd").unwrap_or(start);
            let can_edit = json_bool_field(request, "canEditOthers").unwrap_or(false);
            let can_delete = json_bool_field(request, "canDeleteOthers").unwrap_or(false);
            let can_class = json_bool_field(request, "canChangeClass").unwrap_or(false);
            let message = format!(
                "{{\"type\":\"join_accepted\",\"hostId\":\"{}\",\"assignmentStart\":{},\"assignmentEnd\":{},\"permissions\":{{\"canEditOthers\":{},\"canDeleteOthers\":{},\"canChangeClass\":{}}}}}",
                json_escape(&host_id),
                start,
                end,
                can_edit,
                can_delete,
                can_class
            );
            send_to_peer(&user_id, &message)?;
            Ok(ok_message("host_accepted"))
        }
        "host_reject" => {
            let user_id = required_json_string(request, "userId")?;
            let reason = json_string_field(request, "reason").unwrap_or_default();
            let message = format!(
                "{{\"type\":\"join_rejected\",\"reason\":\"{}\"}}",
                json_escape(&reason)
            );
            let _ = send_to_peer(&user_id, &message);
            remove_host_client(&user_id);
            Ok(ok_message("host_rejected"))
        }
        "send_host" => {
            let message = required_json_string(request, "message")?;
            send_to_host(&message)?;
            Ok(ok_message("sent_host"))
        }
        "send_peer" => {
            let user_id = required_json_string(request, "userId")?;
            let message = required_json_string(request, "message")?;
            send_to_peer(&user_id, &message)?;
            Ok(ok_message("sent_peer"))
        }
        "broadcast" => {
            let message = required_json_string(request, "message")?;
            broadcast_to_peers(&message)?;
            Ok(ok_message("broadcast_sent"))
        }
        "stop" => {
            stop_all();
            push_event("{\"type\":\"stopped\"}".to_string());
            Ok(ok_message("stopped"))
        }
        _ => Err(format!("Unknown collaboration action: {action}")),
    }
}

pub fn poll_events_json(max_events: usize) -> Result<String, String> {
    let limit = max_events.clamp(1, 200);
    let mut events = EVENTS
        .lock()
        .map_err(|_| "Collaboration event queue is poisoned".to_string())?;
    let mut output = String::from("{\"ok\":true,\"events\":[");
    let mut first = true;
    for _ in 0..limit {
        let Some(event) = events.pop_front() else {
            break;
        };
        if !first {
            output.push(',');
        }
        first = false;
        output.push_str(&event);
    }
    output.push_str("]}");
    Ok(output)
}

struct HostConfig {
    host_id: String,
    host_name: String,
    user_id: String,
    user_name: String,
    port: u16,
    project_id: String,
    image_count: u32,
}

struct ClientConfig {
    host_id: String,
    address: String,
    port: u16,
    user_id: String,
    user_name: String,
    color_value: u32,
}

fn start_discovery(port: u16) -> Result<(), String> {
    stop_runtime(&DISCOVERY);
    let stop = Arc::new(AtomicBool::new(false));
    let mut runtime = Runtime::new(stop.clone());
    runtime.handles.push(thread::spawn(move || {
        if let Err(error) = run_discovery_listener(port, stop) {
            push_event(format!(
                "{{\"type\":\"network_error\",\"scope\":\"discovery\",\"error\":\"{}\"}}",
                json_escape(&error)
            ));
        }
    }));
    *DISCOVERY
        .lock()
        .map_err(|_| "Discovery runtime lock is poisoned".to_string())? = Some(runtime);
    Ok(())
}

fn start_host(config: HostConfig) -> Result<(), String> {
    stop_runtime(&DISCOVERY);
    stop_runtime(&CLIENT);
    stop_runtime(&HOST);

    let listener = TcpListener::bind(("0.0.0.0", config.port))
        .map_err(|error| format!("Failed to bind TCP host on port {}: {error}", config.port))?;
    listener
        .set_nonblocking(true)
        .map_err(|error| format!("Failed to set TCP listener nonblocking: {error}"))?;

    let stop = Arc::new(AtomicBool::new(false));
    let mut runtime = Runtime::new(stop.clone());
    let clients = runtime.clients.clone();

    let broadcast_config = HostConfig {
        host_id: config.host_id.clone(),
        host_name: config.host_name.clone(),
        user_id: config.user_id.clone(),
        user_name: config.user_name.clone(),
        port: config.port,
        project_id: config.project_id.clone(),
        image_count: config.image_count,
    };
    let broadcast_stop = stop.clone();
    runtime.handles.push(thread::spawn(move || {
        if let Err(error) = run_host_broadcast(broadcast_config, broadcast_stop) {
            push_event(format!(
                "{{\"type\":\"network_error\",\"scope\":\"broadcast\",\"error\":\"{}\"}}",
                json_escape(&error)
            ));
        }
    }));

    let server_stop = stop.clone();
    let server_clients = clients.clone();
    runtime.handles.push(thread::spawn(move || {
        if let Err(error) = run_tcp_host(listener, server_stop, server_clients) {
            push_event(format!(
                "{{\"type\":\"network_error\",\"scope\":\"host_tcp\",\"error\":\"{}\"}}",
                json_escape(&error)
            ));
        }
    }));

    *HOST
        .lock()
        .map_err(|_| "Host runtime lock is poisoned".to_string())? = Some(runtime);
    push_event(format!(
        "{{\"type\":\"host_started\",\"hostId\":\"{}\",\"port\":{}}}",
        json_escape(&config.host_id),
        config.port
    ));
    Ok(())
}

fn join_host(config: ClientConfig) -> Result<(), String> {
    stop_runtime(&DISCOVERY);
    stop_runtime(&CLIENT);

    let address = format!("{}:{}", config.address, config.port);
    let stream = TcpStream::connect(&address)
        .map_err(|error| format!("Failed to connect to host {address}: {error}"))?;
    stream
        .set_nodelay(true)
        .map_err(|error| format!("Failed to configure TCP stream: {error}"))?;
    stream
        .set_read_timeout(Some(Duration::from_millis(500)))
        .map_err(|error| format!("Failed to configure TCP read timeout: {error}"))?;

    let writer =
        Arc::new(Mutex::new(stream.try_clone().map_err(|error| {
            format!("Failed to clone TCP stream: {error}")
        })?));
    let stop = Arc::new(AtomicBool::new(false));
    let mut runtime = Runtime::new(stop.clone());
    runtime.client_stream = Some(writer.clone());

    let reader_stop = stop.clone();
    let host_id = config.host_id.clone();
    runtime.handles.push(thread::spawn(move || {
        run_client_reader(stream, reader_stop, host_id);
    }));

    let join_message = format!(
        "{{\"type\":\"join_request\",\"protocol\":\"{}\",\"hostId\":\"{}\",\"userId\":\"{}\",\"userName\":\"{}\",\"colorValue\":{}}}",
        PROTOCOL,
        json_escape(&config.host_id),
        json_escape(&config.user_id),
        json_escape(&config.user_name),
        config.color_value
    );
    write_json_line(&writer, &join_message)?;

    *CLIENT
        .lock()
        .map_err(|_| "Client runtime lock is poisoned".to_string())? = Some(runtime);
    push_event(format!(
        "{{\"type\":\"join_sent\",\"hostId\":\"{}\",\"address\":\"{}\",\"port\":{}}}",
        json_escape(&config.host_id),
        json_escape(&config.address),
        config.port
    ));
    Ok(())
}

fn run_discovery_listener(port: u16, stop: Arc<AtomicBool>) -> Result<(), String> {
    let socket = UdpSocket::bind(("0.0.0.0", port))
        .map_err(|error| format!("Failed to bind UDP discovery on port {port}: {error}"))?;
    socket
        .set_read_timeout(Some(Duration::from_millis(500)))
        .map_err(|error| format!("Failed to configure UDP discovery timeout: {error}"))?;
    let mut buffer = [0_u8; 4096];
    while !stop.load(Ordering::SeqCst) {
        match socket.recv_from(&mut buffer) {
            Ok((len, address)) => {
                let packet = String::from_utf8_lossy(&buffer[..len]);
                if json_string_field(&packet, "protocol").as_deref() != Some(PROTOCOL) {
                    continue;
                }
                if json_string_field(&packet, "type").as_deref() != Some("rustlabel_host") {
                    continue;
                }
                let host_id = json_string_field(&packet, "hostId").unwrap_or_default();
                let host_name = json_string_field(&packet, "hostName").unwrap_or_default();
                let advertised_port = json_u16_field(&packet, "port").unwrap_or(port);
                let project_id = json_string_field(&packet, "projectId").unwrap_or_default();
                let image_count = json_u32_field(&packet, "imageCount").unwrap_or(0);
                push_event(format!(
                    "{{\"type\":\"host_found\",\"hostId\":\"{}\",\"hostName\":\"{}\",\"address\":\"{}\",\"port\":{},\"projectId\":\"{}\",\"imageCount\":{},\"timestamp\":{}}}",
                    json_escape(&host_id),
                    json_escape(&host_name),
                    json_escape(&address.ip().to_string()),
                    advertised_port,
                    json_escape(&project_id),
                    image_count,
                    now_millis()
                ));
            }
            Err(error)
                if matches!(
                    error.kind(),
                    ErrorKind::WouldBlock | ErrorKind::TimedOut | ErrorKind::Interrupted
                ) => {}
            Err(error) => return Err(format!("UDP discovery receive failed: {error}")),
        }
    }
    Ok(())
}

fn run_host_broadcast(config: HostConfig, stop: Arc<AtomicBool>) -> Result<(), String> {
    let socket = UdpSocket::bind(("0.0.0.0", 0))
        .map_err(|error| format!("Failed to bind UDP broadcast socket: {error}"))?;
    socket
        .set_broadcast(true)
        .map_err(|error| format!("Failed to enable UDP broadcast: {error}"))?;
    let packet = format!(
        "{{\"type\":\"rustlabel_host\",\"protocol\":\"{}\",\"hostId\":\"{}\",\"hostName\":\"{}\",\"userId\":\"{}\",\"userName\":\"{}\",\"port\":{},\"projectId\":\"{}\",\"imageCount\":{}}}",
        PROTOCOL,
        json_escape(&config.host_id),
        json_escape(&config.host_name),
        json_escape(&config.user_id),
        json_escape(&config.user_name),
        config.port,
        json_escape(&config.project_id),
        config.image_count
    );
    let targets = broadcast_targets(config.port);
    while !stop.load(Ordering::SeqCst) {
        for target in &targets {
            let _ = socket.send_to(packet.as_bytes(), target);
        }
        for _ in 0..10 {
            if stop.load(Ordering::SeqCst) {
                return Ok(());
            }
            thread::sleep(Duration::from_millis(100));
        }
    }
    Ok(())
}

fn broadcast_targets(port: u16) -> Vec<String> {
    let mut targets = vec![format!("255.255.255.255:{port}")];
    if let Some(local_ip) = primary_local_ipv4() {
        let octets = local_ip.octets();
        if !local_ip.is_loopback() && !local_ip.is_unspecified() {
            targets.push(format!(
                "{}.{}.{}.255:{port}",
                octets[0], octets[1], octets[2]
            ));
        }
    }
    targets.sort();
    targets.dedup();
    targets
}

fn primary_local_ipv4() -> Option<Ipv4Addr> {
    let socket = UdpSocket::bind(("0.0.0.0", 0)).ok()?;
    socket.connect(("8.8.8.8", 80)).ok()?;
    match socket.local_addr().ok()?.ip() {
        std::net::IpAddr::V4(ip) => Some(ip),
        std::net::IpAddr::V6(_) => None,
    }
}

fn run_tcp_host(
    listener: TcpListener,
    stop: Arc<AtomicBool>,
    clients: Arc<Mutex<HashMap<String, Arc<Mutex<TcpStream>>>>>,
) -> Result<(), String> {
    while !stop.load(Ordering::SeqCst) {
        match listener.accept() {
            Ok((stream, address)) => {
                stream
                    .set_read_timeout(Some(Duration::from_millis(500)))
                    .ok();
                stream.set_nodelay(true).ok();
                let client_stop = stop.clone();
                let client_map = clients.clone();
                thread::spawn(move || {
                    run_host_client_reader(stream, address.to_string(), client_stop, client_map);
                });
            }
            Err(error) if error.kind() == ErrorKind::WouldBlock => {
                thread::sleep(Duration::from_millis(100));
            }
            Err(error) => return Err(format!("TCP accept failed: {error}")),
        }
    }
    Ok(())
}

fn run_host_client_reader(
    stream: TcpStream,
    address: String,
    stop: Arc<AtomicBool>,
    clients: Arc<Mutex<HashMap<String, Arc<Mutex<TcpStream>>>>>,
) {
    let writer = match stream.try_clone() {
        Ok(stream) => Arc::new(Mutex::new(stream)),
        Err(error) => {
            push_event(format!(
                "{{\"type\":\"network_error\",\"scope\":\"client_clone\",\"error\":\"{}\"}}",
                json_escape(&error.to_string())
            ));
            return;
        }
    };
    let mut reader = BufReader::new(stream);
    let mut line = String::new();
    let mut user_id = String::new();
    while !stop.load(Ordering::SeqCst) {
        line.clear();
        match reader.read_line(&mut line) {
            Ok(0) => break,
            Ok(_) => {
                let message = line.trim();
                if message.is_empty() {
                    continue;
                }
                let message_type = json_string_field(message, "type").unwrap_or_default();
                if message_type == "join_request" {
                    user_id = json_string_field(message, "userId").unwrap_or_default();
                    let user_name = json_string_field(message, "userName").unwrap_or_default();
                    let color_value = json_u32_field(message, "colorValue").unwrap_or(0);
                    if !user_id.is_empty() {
                        if let Ok(mut map) = clients.lock() {
                            map.insert(user_id.clone(), writer.clone());
                        }
                    }
                    push_event(format!(
                        "{{\"type\":\"join_request\",\"userId\":\"{}\",\"userName\":\"{}\",\"colorValue\":{},\"address\":\"{}\",\"timestamp\":{}}}",
                        json_escape(&user_id),
                        json_escape(&user_name),
                        color_value,
                        json_escape(&address),
                        now_millis()
                    ));
                } else {
                    push_tcp_message(&user_id, &address, message);
                }
            }
            Err(error)
                if matches!(
                    error.kind(),
                    ErrorKind::WouldBlock | ErrorKind::TimedOut | ErrorKind::Interrupted
                ) => {}
            Err(_) => break,
        }
    }
    if !user_id.is_empty() {
        if let Ok(mut map) = clients.lock() {
            map.remove(&user_id);
        }
        push_event(format!(
            "{{\"type\":\"client_disconnected\",\"userId\":\"{}\",\"address\":\"{}\"}}",
            json_escape(&user_id),
            json_escape(&address)
        ));
    }
}

fn run_client_reader(stream: TcpStream, stop: Arc<AtomicBool>, host_id: String) {
    let address = stream
        .peer_addr()
        .map(|value| value.to_string())
        .unwrap_or_default();
    let mut reader = BufReader::new(stream);
    let mut line = String::new();
    while !stop.load(Ordering::SeqCst) {
        line.clear();
        match reader.read_line(&mut line) {
            Ok(0) => break,
            Ok(_) => {
                let message = line.trim();
                if !message.is_empty() {
                    push_tcp_message(&host_id, &address, message);
                }
            }
            Err(error)
                if matches!(
                    error.kind(),
                    ErrorKind::WouldBlock | ErrorKind::TimedOut | ErrorKind::Interrupted
                ) => {}
            Err(_) => break,
        }
    }
    push_event(format!(
        "{{\"type\":\"host_disconnected\",\"hostId\":\"{}\",\"address\":\"{}\"}}",
        json_escape(&host_id),
        json_escape(&address)
    ));
}

fn send_to_host(message: &str) -> Result<(), String> {
    let guard = CLIENT
        .lock()
        .map_err(|_| "Client runtime lock is poisoned".to_string())?;
    let runtime = guard
        .as_ref()
        .ok_or_else(|| "Client is not connected to a host".to_string())?;
    let stream = runtime
        .client_stream
        .as_ref()
        .ok_or_else(|| "Client TCP stream is not available".to_string())?;
    write_json_line(stream, message)
}

fn send_to_peer(user_id: &str, message: &str) -> Result<(), String> {
    let guard = HOST
        .lock()
        .map_err(|_| "Host runtime lock is poisoned".to_string())?;
    let runtime = guard
        .as_ref()
        .ok_or_else(|| "Host is not running".to_string())?;
    let clients = runtime
        .clients
        .lock()
        .map_err(|_| "Host client map is poisoned".to_string())?;
    let stream = clients
        .get(user_id)
        .ok_or_else(|| format!("Client {user_id} is not connected"))?;
    write_json_line(stream, message)
}

fn broadcast_to_peers(message: &str) -> Result<(), String> {
    let guard = HOST
        .lock()
        .map_err(|_| "Host runtime lock is poisoned".to_string())?;
    let runtime = guard
        .as_ref()
        .ok_or_else(|| "Host is not running".to_string())?;
    let clients = runtime
        .clients
        .lock()
        .map_err(|_| "Host client map is poisoned".to_string())?;
    for stream in clients.values() {
        let _ = write_json_line(stream, message);
    }
    Ok(())
}

fn remove_host_client(user_id: &str) {
    if let Ok(guard) = HOST.lock() {
        if let Some(runtime) = guard.as_ref() {
            if let Ok(mut clients) = runtime.clients.lock() {
                if let Some(stream) = clients.remove(user_id) {
                    shutdown_stream(&stream);
                }
            }
        }
    }
}

fn write_json_line(stream: &Arc<Mutex<TcpStream>>, message: &str) -> Result<(), String> {
    let mut guard = stream
        .lock()
        .map_err(|_| "TCP stream lock is poisoned".to_string())?;
    guard
        .write_all(message.trim().as_bytes())
        .map_err(|error| format!("TCP write failed: {error}"))?;
    guard
        .write_all(b"\n")
        .map_err(|error| format!("TCP newline write failed: {error}"))?;
    guard
        .flush()
        .map_err(|error| format!("TCP flush failed: {error}"))
}

fn shutdown_stream(stream: &Arc<Mutex<TcpStream>>) {
    if let Ok(stream) = stream.lock() {
        let _ = stream.shutdown(Shutdown::Both);
    }
}

fn stop_all() {
    stop_runtime(&DISCOVERY);
    stop_runtime(&CLIENT);
    stop_runtime(&HOST);
}

fn stop_runtime(slot: &Lazy<Mutex<Option<Runtime>>>) {
    if let Ok(mut guard) = slot.lock() {
        if let Some(runtime) = guard.take() {
            runtime.stop();
        }
    }
}

fn push_tcp_message(from_user_id: &str, address: &str, message: &str) {
    let message_type = json_string_field(message, "type").unwrap_or_else(|| "message".to_string());
    push_event(format!(
        "{{\"type\":\"tcp_message\",\"messageType\":\"{}\",\"fromUserId\":\"{}\",\"address\":\"{}\",\"message\":{}}}",
        json_escape(&message_type),
        json_escape(from_user_id),
        json_escape(address),
        json_object_or_string(message)
    ));
}

fn push_event(event: String) {
    if let Ok(mut events) = EVENTS.lock() {
        events.push_back(event);
        while events.len() > MAX_EVENTS {
            events.pop_front();
        }
    }
}

fn json_object_or_string(value: &str) -> String {
    let trimmed = value.trim();
    if trimmed.starts_with('{') && trimmed.ends_with('}') {
        trimmed.to_string()
    } else {
        format!("\"{}\"", json_escape(trimmed))
    }
}

fn ok_message(message: &str) -> String {
    format!("{{\"ok\":true,\"message\":\"{}\"}}", json_escape(message))
}

fn now_millis() -> u128 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|duration| duration.as_millis())
        .unwrap_or(0)
}

fn required_json_string(request: &str, key: &str) -> Result<String, String> {
    json_string_field(request, key)
        .filter(|value| !value.trim().is_empty())
        .ok_or_else(|| format!("Missing {key}"))
}

fn json_string_field(input: &str, key: &str) -> Option<String> {
    let mut index = json_value_start(input, key)?;
    let chars: Vec<char> = input.chars().collect();
    if chars.get(index) != Some(&'"') {
        return None;
    }
    index += 1;
    let mut value = String::new();
    while index < chars.len() {
        match chars[index] {
            '"' => return Some(value),
            '\\' => {
                index += 1;
                let escaped = *chars.get(index)?;
                match escaped {
                    '"' => value.push('"'),
                    '\\' => value.push('\\'),
                    '/' => value.push('/'),
                    'b' => value.push('\u{0008}'),
                    'f' => value.push('\u{000c}'),
                    'n' => value.push('\n'),
                    'r' => value.push('\r'),
                    't' => value.push('\t'),
                    'u' => {
                        let hex: String = chars.get(index + 1..index + 5)?.iter().collect();
                        let code = u32::from_str_radix(&hex, 16).ok()?;
                        value.push(char::from_u32(code)?);
                        index += 4;
                    }
                    other => value.push(other),
                }
            }
            ch => value.push(ch),
        }
        index += 1;
    }
    None
}

fn json_bool_field(input: &str, key: &str) -> Option<bool> {
    match json_raw_scalar(input, key)?.to_ascii_lowercase().as_str() {
        "true" => Some(true),
        "false" => Some(false),
        _ => None,
    }
}

fn json_u16_field(input: &str, key: &str) -> Option<u16> {
    json_u32_field(input, key).and_then(|value| u16::try_from(value).ok())
}

fn json_u32_field(input: &str, key: &str) -> Option<u32> {
    let value = json_raw_scalar(input, key)?;
    value.parse::<u32>().ok().or_else(|| {
        value
            .parse::<f64>()
            .ok()
            .filter(|number| number.is_finite() && *number >= 0.0)
            .map(|number| number.round() as u32)
    })
}

fn json_raw_scalar(input: &str, key: &str) -> Option<String> {
    let start = json_value_start(input, key)?;
    let chars: Vec<char> = input.chars().collect();
    let mut end = start;
    while end < chars.len() && !matches!(chars[end], ',' | '}' | ']') {
        end += 1;
    }
    let value: String = chars[start..end].iter().collect();
    Some(value.trim().trim_matches('"').to_string())
}

fn json_value_start(input: &str, key: &str) -> Option<usize> {
    let needle = format!("\"{}\"", key);
    let key_byte_index = input.find(&needle)?;
    let after_key = key_byte_index + needle.len();
    let colon_byte_offset = input[after_key..].find(':')?;
    let value_byte_index = after_key + colon_byte_offset + 1;
    let char_index = input[..value_byte_index].chars().count();
    let chars: Vec<char> = input.chars().collect();
    let mut index = char_index;
    while index < chars.len() && chars[index].is_whitespace() {
        index += 1;
    }
    Some(index)
}

fn json_escape(value: &str) -> String {
    let mut escaped = String::with_capacity(value.len());
    for ch in value.chars() {
        match ch {
            '"' => escaped.push_str("\\\""),
            '\\' => escaped.push_str("\\\\"),
            '\n' => escaped.push_str("\\n"),
            '\r' => escaped.push_str("\\r"),
            '\t' => escaped.push_str("\\t"),
            ch if ch.is_control() => escaped.push_str(&format!("\\u{:04x}", ch as u32)),
            ch => escaped.push(ch),
        }
    }
    escaped
}
