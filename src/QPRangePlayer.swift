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

import AVKit

/// An entity for managing the playing of a single time range of an
/// AVAsset.
///
/// - Note: Each instance of this class keeps an AVQueuePlayer, which is
///         swapped into the AVPlayerView when this range begins to play.
///         This causes a noticeable gap in the playback when transitioning
///         from one range to the next.  This gap can probably be avoided
///         by using a single AVQueuePlayer and swaping the looper for each
///         range, instead of the entire player.  The author tried that
///         approach, but failed to make it work.
class QPRangePlayer : NSObject {

  // ---------- PROPERTIES GIVEN TO THE INITIALIZER ----------

  /// The asset to be played (initializer argument)
  let asset: AVAsset

  /// The start time within `asset` of this range (initializer argument)
  let startTime : CMTime

  /// The end time within `asset` of this range (initializer argument)
  let endTime: CMTime

  /// The per-play loop count (initializer argument).  This is the number
  /// of loops this range should play each time it is started, after which
  /// it should stop playing.  This stoppage will not be initiated by this
  /// class, which will happily continue playing unless made to stop
  /// externally.
  ///
  /// Note that:
  ///
  /// + In interactive mode, this number does not apply and is ignored.
  ///
  /// + In non-interactive mode, a value of 0 (zero) for this property has
  ///   the special meaning of "loop indefinitely" (until the user manually
  ///   stops the looping).
  let perPlayLoopCount: Int

  /// A function to be called when `readyToPlay` becomes true (initializer
  /// argument)
  var readyToPlayFunction: (QPRangePlayer) -> Void

  /// A function to be called when the looper's `loopCount` changes
  /// (initializer argument)
  var loopCountChangeFunction: (QPRangePlayer, Int) -> Void

  // ---------- INTERNAL PROPERTIES ----------

  /// The queue player
  var player = AVQueuePlayer()

  /// The looper
  var looper: AVPlayerLooper

  /// Whether this player is ready to play
  var readyToPlay = false

  /// The cumulative loop count the last time this player was told to stop
  /// playing (with a call to `stop()`)
  var lastStoppedLoopCount = 0

  /// The loop count for the current playing session (started with the last
  /// call to `start()`)
  var currentStartedLoopCount: Int {
    return looper.loopCount - lastStoppedLoopCount
  }

  // ---------- INIT ----------

  /// Initializer
  ///
  /// - Parameters:
  ///   - asset: The asset to be played
  ///   - startTime: The start time within `asset` of this range
  ///   - endTime: The end time within `asset` of this range
  ///   - perPlayLoopCount: Number of loops of this range to play
  ///   - readyToPlayFunction: Code to call when `readyToPlay` becomes true
  ///   - loopCountChangeFunction: Code to call when the loop count changes
  ///   - rp: This `QPRangePlayer` instance (i.e. `self`)
  ///   - count: The new loop count
  init(asset: AVAsset,
       startTime: CMTime,
       endTime: CMTime,
       perPlayLoopCount: Int,
       readyToPlayFunction:
         @escaping (_ rp: QPRangePlayer) -> Void,
       loopCountChangeFunction:
         @escaping (_ rp: QPRangePlayer, _ count: Int) -> Void)
  {
    self.asset = asset
    self.startTime = startTime
    self.endTime = endTime
    self.perPlayLoopCount = perPlayLoopCount
    self.readyToPlayFunction = readyToPlayFunction
    self.loopCountChangeFunction = loopCountChangeFunction
    looper = AVPlayerLooper(
      player: player,
      templateItem: AVPlayerItem(asset: self.asset),
      timeRange: CMTimeRange(start: self.startTime, end: self.endTime))
    super.init()
    // Observe the looper for its eventual ready-to-play status
    looper.addObserver(
      self,
      forKeyPath: "loopingPlayerItems",
      options: [.initial, .new],
      context: nil)
    // Observe the looper's loopCount
    looper.addObserver(
      self,
      forKeyPath: "loopCount",
      options: .new,
      context: nil)
  }

  // ---------- STARTING AND STOPPING ----------

  /// Start playing this range.
  ///
  /// - Parameter playerView:
  ///     If not nil, this range's `player` is first assigned as the
  ///     `player` property of this AVPlayerView before playing begins.
  func start(_ playerView: AVPlayerView? = nil) {
    if let pv = playerView {
      if pv.player != self.player {
        pv.player = self.player
      }
    }
    self.player.play()
  }

  /// Stop playing this range.
  ///
  /// This records the current cumulative loop count as the
  /// `lastStoppedLoopCount`.
  func stop() {
    player.pause()
    lastStoppedLoopCount = looper.loopCount
  }

  // ---------- KVO OBSERVER ----------

  override func observeValue(
    forKeyPath keyPath: String?,
    of object: Any?,
    change: [NSKeyValueChangeKey : Any]?,
    context: UnsafeMutableRawPointer?)
  {
    if let aLooper = object as? AVPlayerLooper {
      if aLooper === self.looper {
        if "loopingPlayerItems" == keyPath {
          // If this array is not empty, observe the `.status` property of
          // element 0, to be notified when it becomes `.readyToPlay`
          if self.looper.loopingPlayerItems.count > 0 {
            self.looper.loopingPlayerItems[0].addObserver(
              self,
              forKeyPath: "status",
              options: [.initial, .new],
              context: nil)
          }
        }
        if "loopCount" == keyPath {
          if let count = change?[.newKey] as? Int {
            loopCountChangeFunction(self, count)
          }
        }
      }
    }
    if let anItem = object as? AVPlayerItem {
      if anItem === self.looper.loopingPlayerItems[0] {
        // Check the item's `status` for `.readyToPlay`
        if "status" == keyPath {
          if anItem.status == .readyToPlay {
            anItem.removeObserver(self, forKeyPath: "status")
            // Do not put the next line where it logically should go (instead
            // of here), because that will cause a crash
            self.looper.removeObserver(self, forKeyPath: "loopingPlayerItems")
            self.readyToPlay = true
            readyToPlayFunction(self)
          }
        }
      }
    }
  }

}
