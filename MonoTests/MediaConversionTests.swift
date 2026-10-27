import AVFoundation
import Foundation
import XCTest
@testable import FFmpegSwiftSDK

final class MediaConversionTests: XCTestCase {
    func testSpeakerRecordingFilterChainRendersReadableVoice() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MonoSpeakerTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let source = directory.appendingPathComponent("speaker-source.wav")
        let output = directory.appendingPathComponent("speaker-voice.m4a")
        try makeTone(at: source)

        _ = try await FFmpegAudioTranscoder().transcode(
            inputURL: source,
            outputURL: output,
            muxerName: "ipod",
            encoderName: "aac",
            bitRate: 256_000,
            sampleRate: 48_000,
            channelCount: 1,
            filterDescription: "highpass=f=85:p=2,afftdn=nr=12:nf=-30:tn=1,equalizer=f=240:t=q:w=1.1:g=-2,equalizer=f=3000:t=q:w=1:g=2,acompressor=threshold=0.18:ratio=2.5:attack=15:release=220:makeup=1.35,alimiter=limit=0.94:attack=5:release=70:latency=1"
        )

        let info = try await FFmpegMediaInspector().inspect(url: output)
        XCTAssertTrue(info.hasAudio)
        XCTAssertGreaterThan(info.duration, 0.8)
        XCTAssertLessThan(info.duration, 1.2)
        XCTAssertEqual(info.sampleRate, 48_000)
        XCTAssertEqual(info.channelCount, 1)
    }

    func testAudioEffectFilterChainRendersReadableAudio() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MonoEffectTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let source = directory.appendingPathComponent("source.wav")
        let output = directory.appendingPathComponent("effect.m4a")
        try makeTone(at: source)

        _ = try await FFmpegAudioTranscoder().transcode(
            inputURL: source,
            outputURL: output,
            muxerName: "ipod",
            encoderName: "aac",
            bitRate: 256_000,
            filterDescription: [
                "afftdn=nr=12:nf=-25:tn=1",
                "bass=g=2:f=110:w=0.6",
                "equalizer=f=1200:t=q:w=1:g=2.5",
                "treble=g=2:f=6500:w=0.6",
                "asetrate=53876",
                "aresample=48000",
                "atempo=0.890899"
            ].joined(separator: ",")
        )

        let attributes = try FileManager.default.attributesOfItem(atPath: output.path)
        XCTAssertGreaterThan((attributes[.size] as? NSNumber)?.intValue ?? 0, 0)
        let info = try await FFmpegMediaInspector().inspect(url: output)
        XCTAssertTrue(info.hasAudio)
        XCTAssertGreaterThan(info.duration, 0.8)
        XCTAssertLessThan(info.duration, 1.2)
        XCTAssertEqual(info.sampleRate, 48_000)
        XCTAssertEqual(info.channelCount, 2)
    }

    func testCommonAudioOutputsAreRealAndReadable() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MonoTranscodeTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let source = directory.appendingPathComponent("source.wav")
        try makeTone(at: source)

        let catalog = CodecCapabilities.runtimeCatalog()
        var cases: [(fileExtension: String, muxer: String, encoder: String, bitRate: Int)] = [
            ("flac", "flac", "flac", 0),
            ("opus", "ogg", "opus", 192_000)
        ]
        if catalog.encoders.contains("libmp3lame") {
            cases.insert(("mp3", "mp3", "libmp3lame", 320_000), at: 0)
        }
#if arch(arm64)
        XCTAssertTrue(catalog.encoders.contains("libmp3lame"))
#endif
        let transcoder = FFmpegAudioTranscoder()
        let inspector = FFmpegMediaInspector()

        for item in cases {
            let output = directory.appendingPathComponent("output.\(item.fileExtension)")
            _ = try await transcoder.transcode(
                inputURL: source,
                outputURL: output,
                muxerName: item.muxer,
                encoderName: item.encoder,
                bitRate: item.bitRate
            )
            let attributes = try FileManager.default.attributesOfItem(atPath: output.path)
            XCTAssertGreaterThan((attributes[.size] as? NSNumber)?.intValue ?? 0, 0)
            let info = try await inspector.inspect(url: output)
            XCTAssertTrue(info.hasAudio)
            XCTAssertGreaterThan(info.duration, 0.5)
        }
    }

    func testHighResolutionMultichannelFLACConvertsToCommonFormats() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MonoFLACTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let pcm = directory.appendingPathComponent("source-96k-6ch.wav")
        let flac = directory.appendingPathComponent("source-96k-6ch.flac")
        try makeTone(at: pcm, sampleRate: 96_000, channelCount: 6)

        let transcoder = FFmpegAudioTranscoder()
        _ = try await transcoder.transcode(
            inputURL: pcm,
            outputURL: flac,
            muxerName: "flac",
            encoderName: "flac",
            bitRate: 0
        )

        let catalog = CodecCapabilities.runtimeCatalog()
        var cases: [(name: String, muxer: String, encoder: String, bitRate: Int)] = [
            ("m4a", "ipod", "aac", 256_000),
            ("aac", "adts", "aac", 256_000),
            ("ogg", "ogg", "opus", 192_000),
            ("wav", "wav", "pcm_s24le", 0),
            ("flac", "flac", "flac", 0)
        ]
        if catalog.encoders.contains("libmp3lame") {
            cases.append(("mp3", "mp3", "libmp3lame", 320_000))
        }

        let inspector = FFmpegMediaInspector()
        for (index, item) in cases.enumerated() {
            let output = directory.appendingPathComponent("output-\(index).\(item.name)")
            _ = try await transcoder.transcode(
                inputURL: flac,
                outputURL: output,
                muxerName: item.muxer,
                encoderName: item.encoder,
                bitRate: item.bitRate,
                sampleRate: 48_000,
                channelCount: 2
            )
            let info = try await inspector.inspect(url: output)
            XCTAssertTrue(info.hasAudio, "\(item.name) should contain audio")
            XCTAssertGreaterThan(info.duration, 0.5, "\(item.name) should be readable")
            XCTAssertEqual(info.sampleRate, 48_000, "\(item.name) should be resampled")
            XCTAssertEqual(info.channelCount, 2, "\(item.name) should be stereo")
        }
    }

    func testEveryAvailableAudioTargetAcceptsFLACInput() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MonoAllAudioTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let pcm = directory.appendingPathComponent("source.wav")
        let flac = directory.appendingPathComponent("source.flac")
        try makeTone(at: pcm, sampleRate: 96_000, channelCount: 6)
        let transcoder = FFmpegAudioTranscoder()
        _ = try await transcoder.transcode(
            inputURL: pcm, outputURL: flac, muxerName: "flac",
            encoderName: "flac", bitRate: 0
        )

        typealias AudioCase = (
            ext: String, muxer: String, encoders: [String], bitRate: Int,
            sampleRate: Int, channels: Int
        )
        let cases: [AudioCase] = [
            ("m4a", "ipod", ["aac"], 256_000, 48_000, 2),
            ("aac", "adts", ["aac"], 256_000, 48_000, 2),
            ("latm", "latm", ["aac"], 256_000, 48_000, 2),
            ("mp3", "mp3", ["libmp3lame", "mp3"], 320_000, 48_000, 2),
            ("flac", "flac", ["flac"], 0, 0, 0),
            ("vorbis.ogg", "ogg", ["libvorbis", "vorbis"], 256_000, 48_000, 2),
            ("opus.ogg", "ogg", ["libopus", "opus"], 192_000, 48_000, 2),
            ("alac.m4a", "ipod", ["alac"], 0, 0, 0),
            ("s16.wav", "wav", ["pcm_s16le"], 0, 0, 0),
            ("s24.wav", "wav", ["pcm_s24le"], 0, 0, 0),
            ("s32.wav", "wav", ["pcm_s32le"], 0, 0, 0),
            ("f32.wav", "wav", ["pcm_f32le"], 0, 0, 0),
            ("f64.wav", "wav", ["pcm_f64le"], 0, 0, 0),
            ("aiff", "aiff", ["pcm_s16be"], 0, 0, 0),
            ("alac.caf", "caf", ["alac"], 0, 0, 0),
            ("pcm.caf", "caf", ["pcm_s24le"], 0, 0, 0),
            ("pcm.au", "au", ["pcm_s16be"], 0, 0, 0),
            ("mulaw.au", "au", ["pcm_mulaw"], 64_000, 0, 0),
            ("alaw.au", "au", ["pcm_alaw"], 64_000, 0, 0),
            ("w64", "w64", ["pcm_s24le"], 0, 0, 0),
            ("voc", "voc", ["pcm_s16le"], 0, 0, 0),
            ("wv", "wv", ["wavpack"], 0, 0, 0),
            ("tta", "tta", ["tta"], 0, 0, 0),
            ("ac3", "ac3", ["ac3", "ac3_fixed"], 640_000, 0, 0),
            ("eac3", "eac3", ["eac3"], 640_000, 0, 0),
            ("mp2", "mp2", ["mp2", "mp2fixed"], 320_000, 0, 0),
            ("g722", "g722", ["adpcm_g722"], 64_000, 16_000, 1),
            ("g726", "g726", ["adpcm_g726"], 32_000, 8_000, 1),
            ("aptx", "aptx", ["aptx"], 352_800, 48_000, 2),
            ("aptxhd", "aptx_hd", ["aptx_hd"], 576_000, 48_000, 2),
            ("thd", "truehd", ["truehd"], 0, 48_000, 2),
            ("mlp", "mlp", ["mlp"], 0, 48_000, 2),
            ("dts", "dts", ["dca"], 768_000, 48_000, 2)
        ]

        let catalog = CodecCapabilities.runtimeCatalog()
        let inspector = FFmpegMediaInspector()
        for (index, item) in cases.enumerated() {
            guard catalog.muxers.contains(item.muxer),
                  let encoder = item.encoders.first(where: catalog.encoders.contains) else { continue }
            let output = directory.appendingPathComponent("output-\(index).\(item.ext)")
            _ = try await transcoder.transcode(
                inputURL: flac,
                outputURL: output,
                muxerName: item.muxer,
                encoderName: encoder,
                bitRate: item.bitRate,
                sampleRate: item.sampleRate,
                channelCount: item.channels
            )
            let info = try await inspector.inspect(url: output)
            XCTAssertTrue(info.hasAudio, "\(item.ext) should contain audio")
            XCTAssertGreaterThan(
                (try output.resourceValues(forKeys: [.fileSizeKey])).fileSize ?? 0,
                0,
                "\(item.ext) should not be empty"
            )
        }
    }

    private func makeTone(
        at url: URL,
        sampleRate: Double = 48_000,
        channelCount: AVAudioChannelCount = 2
    ) throws {
        let frames = Int(sampleRate)
        let bytesPerSample = 2
        let dataSize = frames * Int(channelCount) * bytesPerSample
        var wave = Data(capacity: 44 + dataSize)
        wave.append(contentsOf: "RIFF".utf8)
        wave.appendLittleEndian(UInt32(36 + dataSize))
        wave.append(contentsOf: "WAVEfmt ".utf8)
        wave.appendLittleEndian(UInt32(16))
        wave.appendLittleEndian(UInt16(1))
        wave.appendLittleEndian(UInt16(channelCount))
        wave.appendLittleEndian(UInt32(sampleRate))
        wave.appendLittleEndian(UInt32(Int(sampleRate) * Int(channelCount) * bytesPerSample))
        wave.appendLittleEndian(UInt16(Int(channelCount) * bytesPerSample))
        wave.appendLittleEndian(UInt16(bytesPerSample * 8))
        wave.append(contentsOf: "data".utf8)
        wave.appendLittleEndian(UInt32(dataSize))

        for frame in 0..<frames {
            let value = sin(2 * .pi * 440 * Double(frame) / sampleRate) * 0.25
            let sample = Int16((value * Double(Int16.max)).rounded())
            for _ in 0..<Int(channelCount) {
                wave.appendLittleEndian(sample)
            }
        }
        try wave.write(to: url, options: .atomic)
    }
}

private extension Data {
    mutating func appendLittleEndian<T: FixedWidthInteger>(_ value: T) {
        var littleEndian = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndian) { append(contentsOf: $0) }
    }
}
