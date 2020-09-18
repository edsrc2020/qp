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
import AVFoundation

/// Application delegate for qp
class QPAppDelegate : NSObject, NSApplicationDelegate {

  // ---------- DELEGATE CALLBACKS ----------

  // App launched.  This is the logical entry point of this program.
  func applicationDidFinishLaunching(_ notification: Notification) {
    switch options.runMode {
    case .play:
      play()
    case .listTracks:
      listTracks()
    case .printVersion:
      printVersion()
    }
  }

  // This app has at most one window, used for playback.  When that window
  // is closed, the app exits immediately.
  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication)
    -> Bool
  {
    return true
  }

  // ---------- PLAY ----------

  /// The name of the file to be played.  This is given by the user on the
  /// command line.
  private var filename: String!

  /// The asset corresponding to `filename`
  private var originalAsset: AVAsset!

  /// The object to handle all playback
  var player: QPPlayer!

  /// Play the single file given on the command line
  func play() {
    getOriginalAsset()
    player = QPPlayer(asset: originalAsset, filename: filename!)
    player.play()
  }

  /// Parse the command line for the asset to be played, and assign the
  /// results to `filename` and `originalAsset`.
  private func getOriginalAsset() {
    if getopts.remainingArgumentCount != 1 {
      usage(1);
    }
    filename = getopts.remainingArguments![0]
    if (access(filename, F_OK) != 0) {
      fprintf(stderr, "No such file \"\(filename!)\"\n")
      exit(1)
    }
    originalAsset = AVURLAsset(url: URL(fileURLWithPath: filename))
    if !originalAsset.isPlayable {
      fprintf(stderr, "Cannot play \"\(filename!)\"\n")
      exit(1)
    }
  }

  // ---------- LIST TRACKS ----------

  /// List tracks for each file given on the command line
  func listTracks() {
    if getopts.remainingArgumentCount == 0 {
      usage(1);
    }
    let filenames = getopts.remainingArguments!
    for filename in filenames {
      if (access(filename, F_OK) != 0) {
        fprintf(stderr, "No such file \"\(filename)\"\n")
        continue
      }
      print("\(filename)")
      let asset = AVURLAsset(url: URL(fileURLWithPath: filename))
      let tracks = asset.tracks
      if (tracks.count > 0) {
        for track in asset.tracks {
          track.printSummary()
        }
      } else {
        print("  No tracks")
      }
    }
    exit(0)
  }

  // ---------- PRINT VERSION ----------

  /// Print the current version of this program, and then exit.
  private func printVersion() {
    fprintf(stdout, "qp version \(QP_VERSION)\n")  // defined in main.swift
    exit(0)
  }

  // ---------- USAGE ----------

  /// Print a usage summary and then exit with the given exit code.
  ///
  /// - Parameter exitCode: The process exit code.
  private func usage(_ exitCode: Int32) {
    let cmd = GetOpt.commandBaseName
    fprintf(stdout, "Usage:\n")
    fprintf(stdout, "  \(cmd) [-a] [-g range] [-i] [-l] [-p] [-t track] <file> (Play a file)\n")
    fprintf(stdout, "  \(cmd) -T <files...>                                    (List tracks)\n")
    fprintf(stdout, "  \(cmd) -v                                               (Print version)\n")
    exit(exitCode)
  }

}
