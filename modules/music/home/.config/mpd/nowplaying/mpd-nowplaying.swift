// mpd-nowplaying — macOS "Now Playing" bridge for mpd.
//
// Registers mpd as a Now Playing source so the keyboard media keys (F7/F8/F9,
// AirPods taps, Control Center) drive it, and publishes title/artist/album/
// artwork/position to Control Center. One process, one mpd connection, 1 Hz.
//
// Build:  swiftc -O -framework MediaPlayer -framework AppKit -o ~/.local/bin/mpd-nowplaying mpd-nowplaying.swift
// Run:    mpd-nowplaying [socket-path]   (default ~/.local/share/mpd/socket)
//
// macOS routes media keys to the most recent app that declared itself playing,
// so Spotify/Music still take over when they start — this only claims the keys
// while mpd is the thing that last played.

import AppKit
import MediaPlayer

let socketPath = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : NSHomeDirectory() + "/.local/share/mpd/socket"

func log(_ s: String) { FileHandle.standardError.write((s + "\n").data(using: .utf8)!) }

// --- mpd client -------------------------------------------------------------
final class MPD {
    private var fd: Int32 = -1

    private func connect() -> Bool {
        if fd >= 0 { return true }
        let s = socket(AF_UNIX, SOCK_STREAM, 0)
        guard s >= 0 else { return false }
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let capacity = MemoryLayout.size(ofValue: addr.sun_path)
        let fits = socketPath.withCString { path -> Bool in
            guard strlen(path) < capacity else { return false }
            withUnsafeMutablePointer(to: &addr.sun_path) {
                $0.withMemoryRebound(to: CChar.self, capacity: capacity) { _ = strcpy($0, path) }
            }
            return true
        }
        guard fits else { close(s); return false }
        let ok = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(s, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard ok == 0 else { close(s); return false }
        var tv = timeval(tv_sec: 2, tv_usec: 0)
        setsockopt(s, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        fd = s
        _ = readLine()  // "OK MPD x.y.z"
        return true
    }

    private func drop() { if fd >= 0 { close(fd); fd = -1 } }

    private var buffer = Data()

    private func fill() -> Bool {
        var chunk = [UInt8](repeating: 0, count: 65536)
        let n = read(fd, &chunk, chunk.count)
        guard n > 0 else { drop(); return false }
        buffer.append(contentsOf: chunk[0..<n])
        return true
    }

    private func readLine() -> String? {
        while true {
            if let nl = buffer.firstIndex(of: 0x0A) {
                let line = String(decoding: buffer[buffer.startIndex..<nl], as: UTF8.self)
                buffer.removeSubrange(buffer.startIndex...nl)
                return line
            }
            guard fill() else { return nil }
        }
    }

    private func readBytes(_ count: Int) -> Data? {
        while buffer.count < count { guard fill() else { return nil } }
        let out = buffer.prefix(count)
        buffer.removeFirst(count)
        return Data(out)
    }

    /// Key/value reply; first occurrence of a repeated key wins (multi-artist tags).
    /// `binary:` payloads are returned under "_binary".
    func command(_ cmd: String) -> [String: Any]? {
        guard connect() else { return nil }
        guard write(fd, cmd + "\n", cmd.utf8.count + 1) > 0 else { drop(); return nil }
        var out: [String: Any] = [:]
        while let line = readLine() {
            if line == "OK" { return out }
            if line.hasPrefix("ACK ") { out["_ack"] = line; return out }
            guard let r = line.range(of: ": ") else { continue }
            let key = String(line[line.startIndex..<r.lowerBound])
            let value = String(line[r.upperBound...])
            if key == "binary", let n = Int(value) {
                guard let bytes = readBytes(n) else { return nil }
                out["_binary"] = bytes
                _ = readLine()  // the newline after the payload
                continue
            }
            if out[key] == nil { out[key] = value }
        }
        return nil
    }

    /// Whole embedded picture for `file` via `readpicture`, chunk by chunk.
    func picture(_ file: String) -> Data? {
        var data = Data()
        let quoted = "\"" + file.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
        while true {
            guard let reply = command("readpicture \(quoted) \(data.count)"),
                  reply["_ack"] == nil,
                  let total = (reply["size"] as? String).flatMap(Int.init),
                  let chunk = reply["_binary"] as? Data, !chunk.isEmpty else { return data.isEmpty ? nil : data }
            data.append(chunk)
            if data.count >= total { return data }
        }
    }
}

let mpd = MPD()

// --- Now Playing publishing ---------------------------------------------------
struct Track: Equatable {
    var file = ""
    var title = ""
    var artist = ""
    var album = ""
    var duration: Double = 0
}

var lastTrack = Track()
var lastState = ""
var artwork: MPMediaItemArtwork?
let center = MPNowPlayingInfoCenter.default()

func publish() {
    guard let status = mpd.command("status"), let state = status["state"] as? String else {
        if lastState != "" { center.nowPlayingInfo = nil; center.playbackState = .stopped; lastState = "" }
        return
    }
    guard state == "play" || state == "pause", let song = mpd.command("currentsong") else {
        if lastState != "stop" { center.nowPlayingInfo = nil; center.playbackState = .stopped; lastState = "stop" }
        return
    }
    var track = Track()
    track.file = song["file"] as? String ?? ""
    track.title = song["Title"] as? String ?? (track.file as NSString).lastPathComponent
    track.artist = song["Artist"] as? String ?? ""
    track.album = song["Album"] as? String ?? ""
    track.duration = Double(status["duration"] as? String ?? "") ?? 0
    if track != lastTrack {
        lastTrack = track
        artwork = nil
        // readpicture on a stream URL makes MPD open the stream on its event-loop
        // thread and block until it is ready; a stalled stream hangs MPD for every client.
        if !track.file.contains("://"), let bytes = mpd.picture(track.file), let image = NSImage(data: bytes) {
            artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
        }
        log("track \(track.artist) — \(track.title)" + (artwork == nil ? "" : " (art)"))
    }
    var info: [String: Any] = [
        MPMediaItemPropertyTitle: track.title,
        MPMediaItemPropertyArtist: track.artist,
        MPMediaItemPropertyAlbumTitle: track.album,
        MPMediaItemPropertyPlaybackDuration: track.duration,
        MPNowPlayingInfoPropertyElapsedPlaybackTime: Double(status["elapsed"] as? String ?? "") ?? 0,
        MPNowPlayingInfoPropertyPlaybackRate: state == "play" ? 1.0 : 0.0,
        MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue,
    ]
    if let artwork { info[MPMediaItemPropertyArtwork] = artwork }
    center.nowPlayingInfo = info
    let playback: MPNowPlayingPlaybackState = state == "play" ? .playing : .paused
    if lastState != state { center.playbackState = playback; lastState = state; log("state \(state)") }
}

// --- remote commands ---------------------------------------------------------
func send(_ cmd: String) {
    let reply = mpd.command(cmd)
    log("key \(cmd) -> \(reply?["_ack"] as? String ?? (reply == nil ? "no connection" : "OK"))")
    publish()
}

let commands = MPRemoteCommandCenter.shared()
commands.playCommand.addTarget { _ in send("pause 0"); return .success }
commands.pauseCommand.addTarget { _ in send("pause 1"); return .success }
commands.togglePlayPauseCommand.addTarget { _ in
    let playing = (mpd.command("status")?["state"] as? String) == "play"
    send(playing ? "pause 1" : "pause 0"); return .success
}
commands.stopCommand.addTarget { _ in send("stop"); return .success }
commands.nextTrackCommand.addTarget { _ in send("next"); return .success }
commands.previousTrackCommand.addTarget { _ in send("previous"); return .success }
commands.changePlaybackPositionCommand.addTarget { event in
    guard let e = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
    send(String(format: "seekcur %.1f", e.positionTime)); return .success
}
for c in [commands.skipForwardCommand, commands.skipBackwardCommand, commands.seekForwardCommand,
          commands.seekBackwardCommand, commands.likeCommand, commands.dislikeCommand] { c.isEnabled = false }

// --- run ---------------------------------------------------------------------
// An NSApplication (accessory, no Dock icon) is what gives the process a place
// in the Now Playing arbitration; a bare RunLoop never receives the commands.
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
publish()
Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in publish() }
signal(SIGTERM) { _ in exit(0) }
log("mpd-nowplaying up, socket \(socketPath)")
app.run()
