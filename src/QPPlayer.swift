// Copyright (c) 2020 Express Design Inc.
//
// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions are
// met:
//
// 1. Redistributions of source code must retain the above copyright
//    notice, this list of conditions and the following disclaimer.
//
// 2. Redistributions in binary form must reproduce the above copyright
//    notice, this list of conditions and the following disclaimer in the
//    documentation and/or other materials provided with the distribution.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS
// IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED
// TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A
// PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
// HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
// SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED
// TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
// PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF
// LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING
// NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
// SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

import Cocoa
import AVKit

/// An entity for managing the playing of a single file.
class QPPlayer : NSObject {

  // ---------- PROPERTIES GIVEN TO THE INITIALIZER ----------

  /// The original asset (initializer argument)
  let originalAsset: AVAsset

  /// The filename of the original asset (initializer argument)
  let filename: String

  // ---------- GENERAL PROPERTIES ----------

  /// The actual asset to be played.  It may or may not be the same as the
  /// original asset.  Depending on playback options specified, it may be a
  /// new asset derived from `originalAsset`.
  var playedAsset: AVAsset!

  /// The window for playback.  This window will always be created, but it
  /// is not shown in all playback cases.
  var window: NSWindow!

  /// The "Loop" menu item on the app menu bar, if the app menu bar is
  /// shown.  It needs to be adjusted at run time.
  var loopMenuItem: NSMenuItem!

  /// Does the asset to be played have video?
  var hasVideo: Bool {
    return playedAsset.tracks(withMediaType: .video).count > 0
  }

  // ---------- INIT ----------

  /// Initializer
  ///
  /// - Parameters:
  ///   - asset: The original asset
  ///   - filename: The filename of the original asset
  init(asset: AVAsset, filename: String) {
    self.originalAsset = asset
    self.filename = filename
    super.init()
    computePlayedAsset()
  }

  /// Compute the actual asset to be played, from the asset given to the
  /// initializer, and the playback options given on the command line.
  /// When finished, the actual asset to be played will be stored in the
  /// `playedAsset` property.
  ///
  /// There are two cases where a new asset will be created from the
  /// original asset:
  ///
  /// 1. Track selection: if `-a` or `-t`, or both, are given on the
  ///    command line, and the resulting set of tracks differs from the
  ///    original asset, a new asset is created to contain only the
  ///    selected tracks.
  ///
  /// 2. Range selection: if `-g` is given on the command line, possibly
  ///    multiple times, and `-i` (interactive mode) is also given, a new
  ///    asset that is the concatenation of all specified ranges is
  ///    created.
  func computePlayedAsset() {
    computeTracks()
    computeRanges()
  }

  /// Account for `-a` and `-t` track selections, possibly composing a new
  /// asset.  Either way, the actual asset to be played will be stored in
  /// the `playedAsset` property after this function finishes.
  func computeTracks() {
    // First assume no composition is needed
    playedAsset = originalAsset
    // Translate the "-a" option into the corresponding track(s)
    if (options.audioOnly) {
      let audioTracks = originalAsset.tracks(withMediaType: .audio)
      if (audioTracks.count == 0) {
        fprintf(stderr, "No audio tracks in \"\(filename)\"\n")
        exit(1)
      }
      for audioTrack in audioTracks {
        options.selectedTracks.insert(audioTrack.trackID)
      }
      debugPrint("Selected tracks after adjusting for -a: " +
                   "\(options.selectedTracks)")
    }
    // Verify that each selected track actually exists.  (Tracks may be
    // selected by arbitrary ID using the -t option.)
    for selectedTrack in options.selectedTracks {
      if (originalAsset.track(withTrackID: selectedTrack) == nil) {
        fprintf(stderr, "No track \(selectedTrack) in \"\(filename)\"\n")
        exit(1)
      }
    }
    // We will compose a new asset for playback if:
    //
    // 1. Tracks were selected, with either -a or -t, AND
    //
    // 2. The resulting set of tracks is not logically identical to the
    //    original asset
    if (options.selectedTracks.count != 0) {
      debugPrint("Cumulative selected tracks: \(options.selectedTracks)")
      var originalTracks = Set<CMPersistentTrackID>()
      for track in originalAsset.tracks {
        originalTracks.insert(track.trackID)
      }
      if (options.selectedTracks == originalTracks) {
        debugPrint("Selected tracks identical to original," +
                     " no composition required")
      } else {
        debugPrint("Composition required for track selection")
        let composition = AVMutableComposition()
        for track in options.selectedTracks {
          // For each selected track, insert a corresponding mutable track
          let originalTrack = originalAsset.track(withTrackID: track)!
          let compositionTrack = composition.addMutableTrack(
            withMediaType: originalTrack.mediaType,
            preferredTrackID: kCMPersistentTrackID_Invalid)!
          do {
            try compositionTrack.insertTimeRange(
              originalTrack.timeRange,
              of: originalTrack,
              at: .zero)
          } catch {
            fprintf(stderr,
                    "Failed to include track \(track), error: \(error)\n")
            exit(1)
          }
        }
        playedAsset = composition
      }
    }
  }

  /// Process `-g` range selections.  If ranges were specified, and
  /// interactive mode (`-i`) is requested, a new asset will be composed,
  /// constructed from the specified ranges in the same order as given on
  /// the command line.
  ///
  /// Note that:
  ///
  /// 1. When `-g` is given but `-i` is not given, i.e. the playback is
  ///    non-interactive, no new asset is created.  Non-interactive
  ///    playback of ranges uses a completely different mechanism.
  ///
  /// 2. When both `-g` and `-i` are given, any repetition count specified
  ///    for time ranges are ignored.  Each range specified with `-g` is
  ///    included exactly once in the newly created asset.
  func computeRanges() {
    if (!options.playInteractive) || (options.ranges.count == 0) {
      return
    }
    let composition = AVMutableComposition()
    for range in options.ranges {
      let rangeStartTime = CMTime(
        seconds: range.start,
        preferredTimescale: playedAsset.duration.timescale)
      let rangeEndTime = CMTime(
        seconds: range.end,
        preferredTimescale: playedAsset.duration.timescale)
      let timeRange = CMTimeRange(start:rangeStartTime, end: rangeEndTime)
      let currentEndTime = composition.duration
      do {
        try composition.insertTimeRange(
          timeRange,
          of: playedAsset,
          at: currentEndTime)
      } catch {
        fprintf(stderr,
                "Failed to include range \(range.spec), error: \(error)\n")
        exit(1)
      }
    }
    playedAsset = composition
  }

  // ---------- PLAY ----------

  /// Play the asset indicated by `playedAsset`.  The exact way of playing
  /// depends on the nature of the media file and options specified on the
  /// command line.  Each way of playing is handled by a separate function.
  func play() {
    if !hasVideo {
      if !options.playInteractive {
        play_noninteractive_audio()
      } else {
        play_interactive_audio()
      }
    } else {
      if !options.playInteractive {
        play_noninteractive_video()
      } else {
        play_interactive_video()
      }
    }
  }

  // ---------- INTERACTIVE PLAYBACK ----------

  /// A QPRangePlayer for use with interactive audio and video playback
  lazy var interactiveRangePlayer = QPRangePlayer(
    asset: playedAsset,
    startTime: .zero,
    endTime: playedAsset.duration,
    perPlayLoopCount: 0,  // not used for interactive playback
    readyToPlayFunction: { (rp) in
      debugPrint("Interactive player ready")
      self.window.makeKeyAndOrderFront(nil)
      if options.playOnStart {
        debugPrint("Play on start")
        rp.player.play()
      }
    },
    loopCountChangeFunction: { (rp, count) in
      if (!options.loop) {
        rp.stop()
      }
    })

  /// Play an audio file interactively.
  private func play_interactive_audio() {
    debugPrint("Play interactive audio")
    // Create the player view
    let playerView = AVPlayerView(
      frame: CGRect(origin: CGPoint(x: 0, y: 0),
                    size: CGSize(width: 400, height: 0)))
    playerView.player = interactiveRangePlayer.player
    createWindow(for: playerView)
    window.minSize = CGSize(width: 400, height: 80)
  }

  /// Play a video file interactively.
  private func play_interactive_video() {
    debugPrint("Play interactive video")
    // Create the player view
    let videoTracks = playedAsset.tracks(withMediaType: .video)
    let playerView = AVPlayerView(
      frame: CGRect(origin: CGPoint(x: 0, y:0),
                    size: videoTracks[0].naturalSize))
    playerView.player = interactiveRangePlayer.player
    playerView.videoGravity = .resizeAspect
    // Create the window for the player view
    createWindow(for: playerView)
    window.contentAspectRatio = videoTracks[0].naturalSize
  }

  // ---------- NON-INTERACTIVE PLAYBACK ----------

  /// For non-interactive playback, an array of QPRangePlayers
  lazy var rangePlayers = [QPRangePlayer]()

  /// For non-interactive playback, the index of the current range player
  var currentRangePlayerIndex: Int? = nil

  /// Play an audio file non-interactively
  private func play_noninteractive_audio() {
    debugPrint("Play non-interactive audio")
    createRangePlayers()
    // Create a player view and put it inside a dummy window.  This window
    // will not be shown.  It is needed to properly handle the play/pause
    // media control key.
    let playerView = AVPlayerView(
      frame: CGRect(origin: CGPoint(x: 0, y: 0),
                    size: CGSize(width: 0, height: 0)))
    window = NSWindow(
      contentRect: .zero,
      styleMask: [.titled, .closable, .miniaturizable, .resizable ],
      backing: .buffered,
      defer: false)
    window.contentView = playerView
  }

  /// Play a video file non-interactively
  private func play_noninteractive_video() {
    debugPrint("Play non-interactive video")
    createRangePlayers()
    // Create the player view
    let videoTracks = playedAsset.tracks(withMediaType: .video)
    let playerView = AVPlayerView(
      frame: CGRect(origin: CGPoint(x: 0, y:0),
                    size: videoTracks[0].naturalSize))
    playerView.videoGravity = .resizeAspect
    // Create the window for the player view
    createWindow(for: playerView)
    playerView.controlsStyle = .none
    window.contentAspectRatio = videoTracks[0].naturalSize
  }

  /// Populate the `rangePlayers` array from `-g` specifications given on
  /// the command line.
  private func createRangePlayers() {
    if (options.ranges.count == 0) {
      // No ranges were specified: create a single range player for the
      // entire duration of the `playedAsset`.
      rangePlayers.append(
        QPRangePlayer(
          asset: playedAsset,
          startTime: .zero,
          endTime: playedAsset.duration,
          perPlayLoopCount: 1,
          readyToPlayFunction: nonInteractiveReadyToPlay,
          loopCountChangeFunction: nonInteractiveLoopCountChange))
    } else {
      // Ranges were specified
      for range in options.ranges {
        rangePlayers.append(
          QPRangePlayer(
            asset: playedAsset,
            startTime: CMTime(
              seconds: range.start,
              preferredTimescale: playedAsset.duration.timescale),
            endTime: CMTime(
              seconds: range.end,
              preferredTimescale: playedAsset.duration.timescale),
            perPlayLoopCount: range.repetitions ?? 1,
            readyToPlayFunction: nonInteractiveReadyToPlay,
            loopCountChangeFunction: nonInteractiveLoopCountChange))
      }
    }
  }

  /// Ready-to-play callback for non-interactive playback, called as each
  /// range player becomes ready to play.  We wait until all range players
  /// become ready to begin playing the first range.
  private func nonInteractiveReadyToPlay(rangePlayer: QPRangePlayer) {
    for range in rangePlayers {
      if !range.readyToPlay {
        return
      }
    }
    // All ranges ready
    debugPrint("All ranges ready to play")
    // Show the window, but only when playing video
    if hasVideo {
      window.makeKeyAndOrderFront(nil)
    }
    // Play the first range
    playRange(0)
  }

  /// Play the range at the given index
  private func playRange(_ i: Int) {
    // First stop the current range, if any
    if let currentIndex = currentRangePlayerIndex {
      debugPrint("Stopping range \(currentIndex)")
      rangePlayers[currentIndex].stop()
    }
    // Then play the new range
    debugPrint("Starting range \(i)")
    currentRangePlayerIndex = i
    rangePlayers[currentRangePlayerIndex!]
      .start(window.contentView as? AVPlayerView)
  }

  /// Loop-count-change callback for non-interactive playback
  private func nonInteractiveLoopCountChange(
    rangePlayer: QPRangePlayer,
    count: Int)
  {
    let i = currentRangePlayerIndex!
    let currentRange = rangePlayers[i]
    let startedLoopCount = currentRange.currentStartedLoopCount
    debugPrint("Range \(i)," +
                 " cumulative loop count = \(count)," +
                 " current loop count = \(startedLoopCount)")
    if (currentRange.perPlayLoopCount == 0) {
      debugPrint("Range \(i): endless looping in effect, replaying range")
      return
    }
    if startedLoopCount >= currentRange.perPlayLoopCount {
      debugPrint("Range \(i) loop count reached, advancing")
      let nextRangePlayerIndex = currentRangePlayerIndex! + 1
      if nextRangePlayerIndex > (rangePlayers.count - 1) {
        if (options.loop) {
          debugPrint("No more ranges, but global looping is in effect")
          playRange(0)
        } else {
          debugPrint("No more ranges, exiting")
          NSApp.terminate(nil)
        }
      } else {
        playRange(nextRangePlayerIndex)
      }
    }
  }

  // ---------- MEDIA CONTROL KEYS ----------

  /// Handle a media control key press.  Note that the Play/Pause key is
  /// not explicitly handled by this function, but still seems to work in
  /// most (but not all) situations.  One situation where it doesn't work
  /// is to start initial playing in interactive mode.  The `-p` option was
  /// added in part to address this issue.
  ///
  /// - Parameter keyCode: the key code of the key being pressed
  /// - Returns: `true` if handled, `false` if not
  func handleMediaKey(_ keyCode: Int32) -> Bool {
    switch keyCode {
    case NX_KEYTYPE_REWIND:
      if options.playInteractive {
        interactiveRewind()
      } else {
        nonInteractiveRewind()
      }
      return true
    case NX_KEYTYPE_FAST:
      if options.playInteractive {
        interactiveFastForward()
      } else {
        nonInteractiveFastForward()
      }
      return true
    default:
      return false
    }
  }

  func interactiveRewind() {
    if !interactiveRangePlayer.readyToPlay {
      return
    }
    debugPrint("Interactive rewind")
    interactiveRangePlayer.player.seek(
      to: .zero,
      toleranceBefore: .zero,
      toleranceAfter: .zero)
  }

  func interactiveFastForward() {
    if !interactiveRangePlayer.readyToPlay {
      return
    }
    debugPrint("Interactive fast forward")
    interactiveRangePlayer.player.seek(
      to: interactiveRangePlayer.player.currentItem!.duration,
      toleranceBefore: .zero,
      toleranceAfter: .zero)
  }

  func nonInteractiveRewind() {
    if currentRangePlayerIndex == nil {
      return
    }
    let currentRange = rangePlayers[currentRangePlayerIndex!]
    if !currentRange.readyToPlay {
      return
    }
    debugPrint("Non-interactive rewind")
    currentRange.player.seek(
      to: currentRange.startTime,
      toleranceBefore: .zero,
      toleranceAfter: .zero)
  }

  func nonInteractiveFastForward() {
    if currentRangePlayerIndex == nil {
      return
    }
    let currentRange = rangePlayers[currentRangePlayerIndex!]
    if !currentRange.readyToPlay {
      return
    }
    debugPrint("Non-interactive fast forward")
    currentRange.player.seek(
      to: currentRange.endTime,
      toleranceBefore: .zero,
      toleranceAfter: .zero)
  }

  // ---------- USER INTERFACE ----------

  /// Create the playback window.  Whenever a window is created through
  /// this function, the app's activation policy will be set to `.regular`,
  /// making it a normal GUI app.
  private func createWindow(for playerView: AVPlayerView) {
    window = NSWindow(
      contentRect: .zero,
      styleMask: [.titled, .closable, .miniaturizable, .resizable ],
      backing: .buffered,
      defer: false)
    let fr = window.frameRect(forContentRect: playerView.frame)
    window.setFrame(fr, display: true)
    window.contentView = playerView
    window.isMovableByWindowBackground = true
    window.setTitleWithRepresentedFilename(filename)
    window.center()

    activateAsGUIApp()

    playerView.actionPopUpButtonMenu = NSApp.mainMenu!.items[0].submenu
    playerView.controlsStyle = .floating

    NSApp.activate(ignoringOtherApps: true)
  }

  /// Set the activation policy to `.regular`, making this a normal GUI
  /// app, with a dock icon.  Also create and set a main menu.
  private func activateAsGUIApp() {
    // Set activation policy to `.regular`
    NSApp.setActivationPolicy(.regular)
    // Badge the dock tile with the filename being played
    if let basefn = basename(filename.utf8MutableString) {
      NSApp.dockTile.badgeLabel = String(cString: basefn)
    }
    // Create and set the app's menu bar
    createAppMenu()
  }

  /// Create and display the app's main menu
  private func createAppMenu() {
    let qpMenu = NSMenu()
    // item: Toggle Full Screen (CMD-F)
    qpMenu.addItem(
      withTitle: "Togle Full Screen",
      action: #selector(NSWindow.toggleFullScreen(_:)),
      keyEquivalent: "f")
    // item separator
    qpMenu.addItem(NSMenuItem.separator())
    // item: Close Window (CMD-W)
    qpMenu.addItem(
      withTitle: "Close Window",
      action: #selector(NSWindow.performClose(_:)),
      keyEquivalent: "w")
    // item: Minimize (CMD-M)
    qpMenu.addItem(
      withTitle: "Minimize",
      action: #selector(NSWindow.performMiniaturize(_:)),
      keyEquivalent: "m")
    // item: Zoom
    qpMenu.addItem(
      withTitle: "Zoom",
      action: #selector(NSWindow.performZoom(_:)),
      keyEquivalent: "")
    // item separator
    qpMenu.addItem(NSMenuItem.separator())
    // item: Loop
    loopMenuItem = qpMenu.addItem(
      withTitle: "Loop",
      action: #selector(toggleLoop),
      keyEquivalent: "l")
    loopMenuItem.target = self
    loopMenuItem.state = options.loop ? .on : .off
    // item separator
    qpMenu.addItem(NSMenuItem.separator())
    // item: Hide qp
    qpMenu.addItem(
      withTitle: "Hide qp",
      action: #selector(NSApplication.hide(_:)),
      keyEquivalent: "h")
    // item: Hide Others
    qpMenu.addItem(
      withTitle: "Hide Others",
      action: #selector(NSApplication.hideOtherApplications(_:)),
      keyEquivalent: "h").keyEquivalentModifierMask = [.option, .command]
    // item: Show All
    qpMenu.addItem(
      withTitle: "Show All",
      action: #selector(NSApplication.unhideAllApplications(_:)),
      keyEquivalent: "")
    // item separator
    qpMenu.addItem(NSMenuItem.separator())
    // item: Quit (CMD-Q)
    qpMenu.addItem(
      withTitle: "Quit",
      action: #selector(NSApplication.terminate(_:)),
      keyEquivalent: "q")

    NSApp.mainMenu = NSMenu()
    let qpSubmenuItem =
      NSApp.mainMenu!.addItem(withTitle: "", action: nil, keyEquivalent: "")
    NSApp.mainMenu!.setSubmenu(qpMenu, for: qpSubmenuItem)
  }

  /// Toggle looping on or off
  @objc func toggleLoop() {
    options.loop = !options.loop
    loopMenuItem.state = options.loop ? .on : .off
  }

}
