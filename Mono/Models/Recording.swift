import AVFoundation
import Foundation
import UIKit

struct Recording: Identifiable, Hashable {
    let id: UUID
    let url: URL
    let createdAt: Date
    let duration: TimeInterval
    let byteCount: Int64

    var title: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM.dd  HH:mm"
        return formatter.string(from: createdAt)
    }

    var durationText: String {
        let seconds = max(0, Int(duration.rounded()))
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    var sizeText: String {
        ByteCountFormatter.string(fromByteCount: byteCount, countStyle: .file)
    }
}

struct AudioRecording: Identifiable, Hashable {
    let id: UUID
    let url: URL
    let createdAt: Date
    let duration: TimeInterval
    let byteCount: Int64

    var title: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM.dd  HH:mm"
        return formatter.string(from: createdAt)
    }

    var durationText: String {
        let seconds = max(0, Int(duration.rounded()))
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    var sizeText: String {
        ByteCountFormatter.string(fromByteCount: byteCount, countStyle: .file)
    }

    var formatText: String { url.pathExtension.uppercased() }
}

enum SharedStorage {
    static let appGroup = "group.com.linchengbo.mono.screenaudio"

    static var broadcastDirectory: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroup)?
            .appendingPathComponent("Recordings", isDirectory: true)
    }

    static var localDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Recordings", isDirectory: true)
    }

    static var audioDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Audio", isDirectory: true)
    }

    static var transcodeDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Transcodes", isDirectory: true)
    }

    static var exportDirectory: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Exports", isDirectory: true)
    }

    static var accompanimentDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Accompaniments", isDirectory: true)
    }

    static var lyricDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Lyrics", isDirectory: true)
    }

    static var projectDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("VideoProjects", isDirectory: true)
    }

    static var studioMediaDirectory: URL {
        projectDirectory.appendingPathComponent("Media", isDirectory: true)
    }

    static func prepare() throws {
        try FileManager.default.createDirectory(at: localDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: audioDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: transcodeDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: exportDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: accompanimentDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: lyricDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: projectDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: studioMediaDirectory, withIntermediateDirectories: true)
        if let broadcastDirectory {
            try FileManager.default.createDirectory(at: broadcastDirectory, withIntermediateDirectories: true)
        }
    }
}
