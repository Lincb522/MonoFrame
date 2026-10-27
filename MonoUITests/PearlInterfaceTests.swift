import XCTest

final class PearlInterfaceTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.terminate()
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launchEnvironment["MONO_SCREENSHOT_SECTION"] = "capture"
        app.launchEnvironment["MONO_SCREENSHOT_STYLE"] = "light"
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func tap(_ identifier: String, timeout: TimeInterval = 15) {
        let target = app.buttons[identifier].firstMatch
        XCTAssertTrue(target.waitForExistence(timeout: timeout), identifier)
        for _ in 0..<4 {
            if target.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(target.isHittable, identifier)
        target.tap()
    }

    private func waitUntilHittable(_ element: XCUIElement, timeout: TimeInterval = 20) {
        let condition = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in element.isHittable }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [condition], timeout: timeout), .completed)
    }

    func testNavigationAppearanceAndSecondaryPages() {
        app.launchEnvironment.removeValue(forKey: "MONO_SCREENSHOT_STYLE")
        app.launch()
        tap("pearl.openSettings")
        let appearance = app.segmentedControls["pearl.settings.appearance"]
        XCTAssertTrue(appearance.waitForExistence(timeout: 10))
        appearance.buttons["浅色"].tap()
        XCTAssertTrue(appearance.buttons["浅色"].isSelected)
        capture("settings-light")
        appearance.buttons["深色"].tap()
        XCTAssertTrue(appearance.buttons["深色"].isSelected)
        capture("settings-dark")
        app.buttons["返回"].firstMatch.tap()
        capture("capture-dark")
        tap("pearl.openSettings")
        appearance.buttons["浅色"].tap()
        tap("pearl.settings.录制参数")
        XCTAssertTrue(app.staticTexts["录制参数"].waitForExistence(timeout: 5))
        capture("recording-parameters")
        app.buttons["返回"].firstMatch.tap()
        tap("pearl.settings.权限")
        capture("permissions")
        app.buttons["返回"].firstMatch.tap()
        app.swipeUp()
        tap("pearl.settings.用户协议")
        capture("legal")
        app.buttons["返回"].firstMatch.tap()
        app.buttons["返回"].firstMatch.tap()
        capture("capture-light")
        tap("pearl.capture.openAudio")
        XCTAssertTrue(app.buttons["pearl.audio.record"].waitForExistence(timeout: 10))
        capture("audio-recorder")
        app.buttons["返回"].firstMatch.tap()
        tap("pearl.tab.library")
        capture("library")
        tap("pearl.tab.studio")
        capture("studio")
        tap("pearl.tab.transcode")
        capture("transcode-empty")
        tap("pearl.tab.capture")
        XCTAssertTrue(app.buttons["pearl.capture.broadcastButton"].isHittable)
    }

    func testLivePhotoFromLibraryAndEditedVideo() {
        app.resetAuthorizationStatus(for: .photos)
        app.launchEnvironment["MONO_SCREENSHOT_SECTION"] = "library"
        app.launch()
        tap("pearl.library.filter.1")
        tap("pearl.media.more.video")
        XCTAssertTrue(app.buttons["pearl.media.livePhoto"].waitForExistence(timeout: 10))
        capture("live-photo-library-menu")
        tap("pearl.media.livePhoto")
        capture("live-photo-selection-editor")
        let keyPhoto = app.sliders["pearl.livePhoto.keyTime"]
        XCTAssertTrue(keyPhoto.waitForExistence(timeout: 15))
        keyPhoto.adjust(toNormalizedSliderPosition: 0.2)
        tap("pearl.livePhoto.save")
        respondToPhotosPermission(allow: true)
        let result = app.staticTexts["Live Photo 已保存到相册。"]
        XCTAssertTrue(result.waitForExistence(timeout: 90))
        capture("live-photo-library-saved")
        app.buttons["完成"].firstMatch.tap()

        let video = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "编辑视频")).firstMatch
        XCTAssertTrue(video.waitForExistence(timeout: 20))
        video.tap()
        tap("pearl.videoEditor.tool.音轨")
        let mute = app.switches["静音当前片段"].firstMatch
        XCTAssertTrue(mute.waitForExistence(timeout: 10))
        if mute.value as? String != "1" {
            waitUntilHittable(mute)
            // The SwiftUI switch's AX frame includes its full-width label.
            mute.coordinate(withNormalizedOffset: CGVector(dx: 0.94, dy: 0.5)).tap()
        }
        let muted = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "1"), object: mute)
        XCTAssertEqual(XCTWaiter.wait(for: [muted], timeout: 5), .completed)
        app.buttons["完成工具编辑"].firstMatch.tap()
        tap("pearl.videoEditor.openExport")
        XCTAssertTrue(app.buttons["pearl.videoEditor.livePhoto"].waitForExistence(timeout: 10))
        capture("live-photo-editor-export")
        tap("pearl.videoEditor.livePhoto")
        tap("pearl.livePhoto.save", timeout: 120)
        let saved = app.staticTexts["Live Photo 已保存到相册。"].firstMatch
        XCTAssertTrue(saved.waitForExistence(timeout: 120))
        XCTAssertTrue(app.buttons["pearl.livePhoto.save"].isEnabled)
        capture("live-photo-edited-video-saved")
    }

    func testLivePhotoIsNotOfferedForAudio() {
        app.launchEnvironment["MONO_SCREENSHOT_SECTION"] = "library"
        app.launch()
        tap("pearl.library.filter.2")
        tap("pearl.media.more.audio")
        // Native Menu actions are exposed as collection cells on iOS 26.4.
        let actions = app.collectionViews.cells
        XCTAssertTrue(actions.firstMatch.waitForExistence(timeout: 10))
        XCTAssertEqual(actions.count, 3) // Export, share, delete; no video actions.
        XCTAssertFalse(app.buttons["pearl.media.livePhoto"].exists)
        capture("audio-menu-without-live-photo")
    }

    // Deny the real system prompt, then verify visible failure and retry readiness.
    func testLivePhotoPhotoPermissionFailure() {
        app.resetAuthorizationStatus(for: .photos)
        app.launchEnvironment["MONO_SCREENSHOT_SECTION"] = "library"
        app.launch()
        tap("pearl.library.filter.1")
        tap("pearl.media.more.video")
        tap("pearl.media.livePhoto")
        tap("pearl.livePhoto.save")
        respondToPhotosPermission(allow: false)
        let result = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "保存失败：")).firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 90))
        XCTAssertFalse(app.staticTexts["Live Photo 已保存到相册。"].exists)
        capture("live-photo-permission-error")
        XCTAssertTrue(app.buttons["pearl.livePhoto.save"].isEnabled)
    }

    private func respondToPhotosPermission(allow: Bool) {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let choice = springboard.buttons[allow ? "允许完全访问" : "不允许"]
        XCTAssertTrue(choice.waitForExistence(timeout: 90), springboard.debugDescription)
        choice.tap()
    }

    func testVideoAndAudioEditorExport() {
        app.launchEnvironment["MONO_SCREENSHOT_SECTION"] = "library"
        app.launch()
        let video = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "编辑视频")).firstMatch
        XCTAssertTrue(video.waitForExistence(timeout: 20))
        video.tap()
        XCTAssertTrue(app.buttons["pearl.videoEditor.play"].waitForExistence(timeout: 20))
        capture("video-editor")
        tap("pearl.videoEditor.tool.剪切")
        capture("video-trim")
        if app.buttons["完成工具编辑"].exists { app.buttons["完成工具编辑"].tap() }
        tap("pearl.videoEditor.openExport")
        capture("video-export-options")
        app.buttons["返回"].firstMatch.tap()
        app.buttons["返回"].firstMatch.tap()
        tap("pearl.library.filter.2")
        let audio = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "编辑音频")).firstMatch
        XCTAssertTrue(audio.waitForExistence(timeout: 20))
        audio.tap()
        XCTAssertTrue(app.buttons["pearl.audioEditor.play"].waitForExistence(timeout: 20))
        capture("audio-editor")
        tap("pearl.audioEditor.openExport")
        capture("audio-export-options")
        tap("pearl.audioEditor.export")
        let save = app.buttons["pearl.audioEditor.saveFile"]
        XCTAssertTrue(save.waitForExistence(timeout: 90))
        if !save.isHittable { app.swipeUp() }
        save.tap()
        XCTAssertTrue(app.navigationBars.firstMatch.waitForExistence(timeout: 60))
        capture("audio-file-export")
        confirmFileExport()
        XCTAssertTrue(save.waitForExistence(timeout: 20))
        waitUntilHittable(save)
        capture("audio-after-save")
    }

    func testEditingDeskTimelineCaptionRedactionAndExport() {
        app.launchEnvironment["MONO_SCREENSHOT_SECTION"] = "library"
        app.launch()
        let video = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "编辑视频")).firstMatch
        XCTAssertTrue(video.waitForExistence(timeout: 20)); video.tap()
        let play = app.buttons["pearl.videoEditor.play"]
        XCTAssertTrue(play.waitForExistence(timeout: 30))
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: play)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 120), .completed, app.debugDescription)
        capture("editing-desk-main")
        tap("pearl.videoEditor.tool.字幕")
        let caption = app.textFields["输入字幕"]
        XCTAssertTrue(caption.waitForExistence(timeout: 10))
        caption.tap(); caption.typeText("MONO EDITING DESK\n")
        tap("添加")
        capture("editing-desk-caption")
        tap("pearl.videoEditor.autoCaptions")
        let speechNotice = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "本地语音转写能力")).firstMatch
        XCTAssertTrue(speechNotice.waitForExistence(timeout: 90), app.debugDescription)
        capture("editing-desk-speech-availability")
        tap("完成工具编辑")
        tap("pearl.videoEditor.tool.遮挡")
        tap("pearl.videoEditor.addMask")
        capture("editing-desk-mask")
        tap("完成工具编辑")
        tap("放大时间线")
        tap("缩小时间线")
        capture("editing-desk-tracks")
        tap("pearl.videoEditor.openExport")
        let limit = app.switches["pearl.videoEditor.limitSize"]
        XCTAssertTrue(limit.waitForExistence(timeout: 15))
        if !limit.isHittable { app.swipeUp() }
        limit.coordinate(withNormalizedOffset: CGVector(dx: 0.94, dy: 0.5)).tap()
        capture("editing-desk-compression")
        tap("pearl.videoEditor.export")
        let share = app.buttons["pearl.videoEditor.share"]
        XCTAssertTrue(share.waitForExistence(timeout: 180), app.debugDescription)
        capture("editing-desk-exported")
    }

    func testEditingDeskSubtitleFileAndMaskDelete() {
        app.launchEnvironment["MONO_SCREENSHOT_SECTION"] = "library"
        app.launch()
        tap("pearl.library.filter.1")
        let video = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "编辑视频")).firstMatch
        XCTAssertTrue(video.waitForExistence(timeout: 20)); waitUntilHittable(video); video.tap()
        XCTAssertTrue(app.buttons["pearl.videoEditor.play"].waitForExistence(timeout: 30), app.debugDescription)
        tap("pearl.videoEditor.tool.遮挡")
        tap("pearl.videoEditor.addMask")
        let remove = app.buttons["删除遮挡"].firstMatch
        XCTAssertTrue(remove.waitForExistence(timeout: 10))
        for _ in 0..<6 {
            if remove.isHittable { break }
            app.scrollViews.containing(.button, identifier: "删除遮挡").firstMatch.swipeUp()
        }
        remove.tap()
        capture("editing-desk-mask-delete")
        tap("完成工具编辑")
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        tap("pearl.videoEditor.tool.音轨")
        XCTAssertTrue(app.switches["静音当前片段"].waitForExistence(timeout: 15))
        capture("editing-desk-landscape")
        XCUIDevice.shared.orientation = .portrait
        tap("完成工具编辑")
        let previewReady = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"),
                                                    object: app.staticTexts["正在更新预览"])
        XCTAssertEqual(XCTWaiter.wait(for: [previewReady], timeout: 60), .completed)
        capture("editing-desk-main")
        tap("pearl.videoEditor.tool.字幕")
        let caption = app.textFields["输入字幕"]
        XCTAssertTrue(caption.waitForExistence(timeout: 10))
        caption.tap(); caption.typeText("SRT EXPORT CHECK\n")
        tap("添加")
        let exporter = app.buttons["导出 SRT 字幕"]
        XCTAssertTrue(exporter.waitForExistence(timeout: 10))
        for _ in 0..<8 {
            if exporter.isHittable { break }
            app.scrollViews.containing(.button, identifier: "导出 SRT 字幕").firstMatch.swipeUp()
        }
        exporter.tap()
        let save = app.navigationBars.buttons.matching(NSPredicate(format: "label IN %@", ["保存", "Save"])).firstMatch
        XCTAssertTrue(save.waitForExistence(timeout: 120), app.debugDescription)
        capture("editing-desk-srt-file-export")
        save.tap()
        tap("完成工具编辑")

    }


    func testProStudioTransitionsMotionPrecisionAndExport() {
        app.launchEnvironment["MONO_SCREENSHOT_SECTION"] = "library"
        app.launch()
        tap("pearl.library.filter.1")
        let video = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "编辑视频")).firstMatch
        XCTAssertTrue(video.waitForExistence(timeout: 20)); waitUntilHittable(video); video.tap()
        let play = app.buttons["pearl.videoEditor.play"]
        XCTAssertTrue(play.waitForExistence(timeout: 30))
        func ready() {
            XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: play)], timeout: 120), .completed, app.debugDescription)
        }
        ready(); capture("pro-studio-portrait")
        tap("全屏预览")
        tap("退出全屏预览")
        ready()
        tap("下一帧"); tap("上一帧")
        tap("pearl.videoEditor.tool.转场")
        XCTAssertTrue(app.staticTexts["50 款新增 · 51 款效果"].waitForExistence(timeout: 10))
        let firstThumbnail = app.buttons["pearl.transition.FadeFragment"]
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "画面缩略图已加载"), object: firstThumbnail)], timeout: 30), .completed)
        capture("pro-transitions-portrait")
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        let search = app.textFields["pearl.transition.search"]
        XCTAssertTrue(search.waitForExistence(timeout: 15)); waitUntilHittable(search)
        search.tap(); search.typeText("Cube\n")
        let cube = app.buttons["pearl.transition.CubeFragment"]
        XCTAssertTrue(cube.waitForExistence(timeout: 15))
        for _ in 0..<5 { if cube.isHittable { break }; app.scrollViews.containing(.textField, identifier: "pearl.transition.search").firstMatch.swipeUp() }
        cube.tap(); ready()
        capture("pro-transitions-search-cube")
        let preview = app.buttons["pearl.transition.preview"]
        if preview.isHittable { preview.tap(); Thread.sleep(forTimeInterval: 1) }
        tap("pearl.videoEditor.tool.运动")
        tap("推进"); ready()
        XCTAssertTrue(app.staticTexts["关键帧已应用到当前片段"].exists)
        capture("pro-keyframe-landscape")
        tap("撤销"); ready(); tap("重做"); ready()
        tap("pearl.videoEditor.openExport")
        tap("pearl.videoEditor.export")
        XCTAssertTrue(app.buttons["pearl.videoEditor.share"].waitForExistence(timeout: 180), app.debugDescription)
        capture("pro-studio-export-complete")
    }


    func testProStudioActualLandscapeGeometry() {
        app.launchEnvironment["MONO_SCREENSHOT_SECTION"] = "library"
        XCUIDevice.shared.orientation = .landscapeLeft
        app.launch()
        defer { XCUIDevice.shared.orientation = .portrait }
        let wide = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            self.app.windows.firstMatch.frame.width > self.app.windows.firstMatch.frame.height
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [wide], timeout: 20), .completed, "Root window did not rotate: \(app.windows.firstMatch.frame)")
        tap("pearl.library.filter.1")
        let video = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "编辑视频")).firstMatch
        XCTAssertTrue(video.waitForExistence(timeout: 20))
        for _ in 0..<6 { if video.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(video.isHittable, app.debugDescription); video.tap()
        let play = app.buttons["pearl.videoEditor.play"]
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: play)], timeout: 120), .completed)
        XCTAssertGreaterThan(app.windows.firstMatch.frame.width, app.windows.firstMatch.frame.height)
        capture("pro-studio-verified-landscape")
        tap("pearl.videoEditor.tool.转场")
        capture("pro-transitions-verified-landscape")
        print("VERIFIED_LANDSCAPE_WINDOW=\(app.windows.firstMatch.frame)")
    }

    private func confirmFileExport() {
        let navigation = app.navigationBars
        let save = navigation.buttons["保存"].exists ? navigation.buttons["保存"] : navigation.buttons["Save"]
        XCTAssertTrue(save.waitForExistence(timeout: 20))
        save.tap()
    }

    func testWideEditorBackgroundAudioImport() {
        app.launchEnvironment["MONO_SCREENSHOT_SECTION"] = "library"
        app.launch()
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        let video = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "编辑视频")).firstMatch
        XCTAssertTrue(video.waitForExistence(timeout: 25))
        video.tap()
        tap("pearl.videoEditor.tool.音轨")
        capture("wide-video-inspector")
        tap("导入背景音轨")
        XCTAssertTrue(app.navigationBars.firstMatch.waitForExistence(timeout: 60))
        capture("background-audio-import")
        let cancel = app.buttons["取消"].exists ? app.buttons["取消"] : app.buttons["Cancel"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 15))
        cancel.tap()
        XCTAssertTrue(app.buttons["导入背景音轨"].waitForExistence(timeout: 15))
    }

    func testWideEditorAndFullLyrics() {
        app.launchEnvironment["MONO_SCREENSHOT_SECTION"] = "library"
        app.launch()
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        let video = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "编辑视频")).firstMatch
        XCTAssertTrue(video.waitForExistence(timeout: 25))
        video.tap()
        tap("pearl.videoEditor.tool.音轨")
        capture("wide-video-inspector")
        if app.buttons["完成工具编辑"].exists { app.buttons["完成工具编辑"].tap() }
        app.buttons["返回"].firstMatch.tap()
        tap("pearl.library.filter.2")
        let audio = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "编辑音频")).firstMatch
        XCTAssertTrue(audio.waitForExistence(timeout: 20))
        audio.tap()
        tap("歌词")
        capture("lyrics-editing")
        tap("全屏预览")
        let line = app.staticTexts["pearl.lyrics.line.0"]
        XCTAssertTrue(line.waitForExistence(timeout: 10))
        XCTAssertTrue(line.label.contains("完整显示"))
        XCTAssertGreaterThan(line.frame.height, 40)
        capture("lyrics-full-text")
    }

    func testResponsivePagesAndSearch() {
        app.launch()
        XCTAssertTrue(app.buttons["pearl.capture.openAudio"].waitForExistence(timeout: 20))
        capture("responsive-capture")
        tap("pearl.openSettings")
        capture("responsive-settings")
        app.buttons["返回"].firstMatch.tap()
        tap("pearl.capture.openAudio")
        capture("responsive-audio")
        let record = app.buttons["pearl.audio.record"]
        if !record.isHittable { app.swipeUp() }
        XCTAssertTrue(record.isHittable)
        capture("responsive-audio-controls")
        app.buttons["返回"].firstMatch.tap()
        tap("pearl.tab.library")
        tap("搜索素材")
        let search = app.textFields["pearl.library.search"]
        XCTAssertTrue(search.waitForExistence(timeout: 10))
        search.tap()
        search.typeText("NoMatchingMedia123456789")
        XCTAssertTrue(app.staticTexts["没有找到素材"].waitForExistence(timeout: 10))
        capture("search-empty-keyboard")
        app.terminate()
        app.launchEnvironment["MONO_SCREENSHOT_SECTION"] = "onboarding"
        app.launch()
        XCTAssertTrue(app.buttons["pearl.onboarding.start"].waitForExistence(timeout: 20))
        capture("responsive-onboarding")
    }

    func testEditorLayoutAtLargeText() {
        app.launchEnvironment["MONO_SCREENSHOT_SECTION"] = "library"
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        tap("pearl.library.filter.2")
        let audio = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "编辑音频")).firstMatch
        XCTAssertTrue(audio.waitForExistence(timeout: 20))
        audio.tap()
        XCTAssertTrue(app.buttons["pearl.audioEditor.play"].waitForExistence(timeout: 20))
        capture("large-text-audio-editor")
        for _ in 0..<4 {
            if app.sliders["低频"].isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(app.sliders["低频"].isHittable)
        capture("large-text-equalizer")
    }

    func testWideNavigationAndLargeText() {
        app.launch()
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        capture("wide-capture")
        tap("pearl.tab.library")
        capture("wide-library")
        tap("pearl.tab.studio")
        capture("wide-studio")
        tap("pearl.tab.transcode")
        capture("wide-transcode")
        app.terminate()
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        capture("large-text-capture")
        tap("pearl.capture.openAudio")
        capture("large-text-audio")
        let record = app.buttons["pearl.audio.record"]
        for _ in 0..<4 {
            if record.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(record.isHittable)
        app.swipeUp()
        capture("large-text-audio-controls")
        app.buttons["返回"].firstMatch.tap()
        tap("pearl.openSettings")
        capture("large-text-settings")
        tap("pearl.settings.录制参数")
        capture("large-text-parameters")
    }

    func testRecordingParametersAndTimelineInteraction() {
        app.launch()
        tap("pearl.capture.frameRate")
        app.buttons["30 fps"].firstMatch.tap()
        tap("pearl.capture.frameRate")
        XCTAssertTrue(app.buttons["60 fps"].waitForExistence(timeout: 5))
        app.buttons["60 fps"].firstMatch.tap()
        tap("pearl.tab.library")
        let video = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "编辑视频")).firstMatch
        XCTAssertTrue(video.waitForExistence(timeout: 20))
        video.tap()
        XCTAssertTrue(app.buttons["pearl.videoEditor.play"].waitForExistence(timeout: 20))
        let playhead = app.otherElements["播放位置"].firstMatch
        XCTAssertTrue(playhead.waitForExistence(timeout: 15))
        let before = playhead.value as? String
        let start = playhead.coordinate(withNormalizedOffset: CGVector(dx: 0.4, dy: 0.5))
        let end = playhead.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.5))
        start.press(forDuration: 0.1, thenDragTo: end)
        XCTAssertNotEqual(playhead.value as? String, before)
        capture("timeline-seek")
        tap("pearl.videoEditor.play")
        XCTAssertEqual(app.buttons["pearl.videoEditor.play"].label, "暂停")
        tap("pearl.videoEditor.play")
    }

    func testTranscodeToRealFileAndOpenExporter() {
        app.launchEnvironment["MONO_SCREENSHOT_SECTION"] = "transcode"
        app.launchEnvironment["MONO_UI_TEST"] = "1"
        app.launchEnvironment["MONO_TEST_TRANSCODE_FILE"] = "Pearl-Voice.m4a"
        app.launch()
        tap("pearl.transcode.format", timeout: 25)
        capture("transcode-formats")
        app.buttons["返回"].firstMatch.tap()
        tap("pearl.transcode.start")
        let export = app.buttons["pearl.transcode.export"].firstMatch
        XCTAssertTrue(export.waitForExistence(timeout: 90))
        capture("transcode-completed")
        export.tap()
        XCTAssertTrue(app.navigationBars.firstMatch.waitForExistence(timeout: 60))
        capture("transcode-file-export")
        confirmFileExport()
        XCTAssertTrue(export.waitForExistence(timeout: 20))
        waitUntilHittable(export)
        capture("transcode-after-save")
    }
}
