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

import AVFoundation

/// The parser for command line options recognized by this program.
///
/// * `-a`: Play only audio tracks
/// * `-g` _range_: Play the given range
/// * `-i`: Interactive playback (always show a playback window)
/// * `-l`: Loop playback
/// * `-t` _trackID_: Include the given track (multiple `-t` allowed)
/// * `-v`: Print version and exit
/// * `-T`: List tracks and exit (allows multiple file arguments)
let getopts = GetOpt("ag:ilpt:vT")

/// A singleton instance of the QPOptions structure
var options = QPOptions()



/// A structure to keep options for the `qp` program
struct QPOptions {

  // ---------- RUN MODES ----------

  /// Possible run modes.  This program can only run in one mode per
  /// invocation.
  enum RunMode {
    case play
    case listTracks
    case printVersion
  }

  // ---------- INITIALIZER ----------

  /// Initializer
  init() {
    // Exit if any unrecognized command-line option was given
    if (getopts.invalidOptions != nil) {
      fprintf(stderr, "Invalid options\n")
      exit(1)
    }
    // Determine the run mode
    if (getopts.hasOption("v")) {
      runMode = .printVersion
    } else if (getopts.hasOption("T")) {
      runMode = .listTracks
    } else {
      runMode = .play
    }
    // Get individual options
    audioOnly = getopts.hasOption("a")
    parseRanges()
    playInteractive = getopts.hasOption("i")
    playOnStart = getopts.hasOption("p")
    loop = getopts.hasOption("l")
    parseTrackSelections()
    printOptions()
  }

  // ---------- OPTION PROPERTIES ----------

  /// The run mode
  let runMode: RunMode

  /// Whether to play interactively
  var playInteractive: Bool = false

  /// Whether to play on start in interactive mode
  var playOnStart: Bool = false

  /// Whether to use only audio tracks
  var audioOnly: Bool = false

  /// Whether to loop playback
  var loop: Bool = false

  // ---------- TRACK SELECTION ----------

  /// Tracks selected with the `-t` or `-a` options, or an empty set if
  /// none.
  var selectedTracks = Set<CMPersistentTrackID>()

  /// Parse track selections specified using `-t` on command-line options
  private mutating func parseTrackSelections() {
    if let trackSpecs = getopts.getOptionSpecs("t") {
      for trackSpec in trackSpecs {
        let trackArgument = trackSpec.argument!
        if let track = CMPersistentTrackID(trackArgument) {
          selectedTracks.insert(track)
        } else {
          fprintf(stderr, "Invalid track specification \"\(trackArgument)\"\n")
          exit(1)
        }
      }
    }
  }

  // ---------- RANGES ----------

  /// A type representing a single range specification
  typealias Range =
    (start: Double, end: Double, repetitions: Int?, spec: String)

  /// An array holding the ranges specified on the command line
  var ranges = [Range]()

  /// Parse range specifications from command-line options
  private mutating func parseRanges() {
    if let rangeSpecs = getopts.getOptionSpecs("g") {
      for rangeSpec in rangeSpecs {
        let rangeArgument = rangeSpec.argument!
        parseRange(rangeArgument)
      }
    }
  }

  /// The regular expression pattern for a range specification, of the
  /// form `hh:mm:ss[.fff]-hh:mm:ss[.fff][xn]`
  private static let range_pattern = "^([0-9][0-9]):([0-5][0-9]):([0-5][0-9])(\\.([0-9][0-9][0-9]))?\\-([0-9][0-9]):([0-5][0-9]):([0-5][0-9])(\\.([0-9][0-9][0-9]))?(x([0-9]+))?$"

  /// The compiled regex_t for the above
  private static var range_re: regex_t = {
    var result = regex_t()
    if (regcomp(&result, QPOptions.range_pattern, REG_EXTENDED) != 0) {
      exit(1)
    } else {
      return result
    }
  }()

  /// Parse a single range
  ///
  /// - Parameter range: The range specification, as written by the user on
  ///                    the command line
  private mutating func parseRange(_ range: String) {
    let sub = UnsafeMutablePointer<regmatch_t>.allocate(capacity: 13)
    let rc = regexec(&QPOptions.range_re, range, 13, sub, 0)
    if (rc != 0) {
      fprintf(stderr, "Malformed range specification: \(range)\n")
      exit(1);
    } else {
      var start, end: Double
      start  = Double(sub2int(sub[1], range) * 60 * 60)
      start += Double(sub2int(sub[2], range) * 60)
      start += Double(sub2int(sub[3], range))
      if (sub[5].rm_so != -1) {
        start += Double(sub2int(sub[5], range)) / 1000.0
      }
      end  = Double(sub2int(sub[6], range) * 60 * 60)
      end += Double(sub2int(sub[7], range) * 60)
      end += Double(sub2int(sub[8], range))
      if (sub[10].rm_so != -1) {
        end += Double(sub2int(sub[10], range)) / 1000.0
      }
      if ((end - start) <= 0.0) {
        fprintf(stderr, "Invalid range duration: \(range)\n")
        exit(1)
      }
      if (sub[12].rm_so != -1) {
        let repetitions = sub2int(sub[12], range)
        ranges.append((start, end, repetitions, range))
      } else {
        ranges.append((start, end, nil, range))
      }
    }
    sub.deallocate()
  }

  /// Return the numeric value of the given regex match in the given string
  private func sub2int(_ sub: regmatch_t, _ target: UnsafePointer<Int8>) -> Int
  {
    var result = 0;
    for i in sub.rm_so ..< sub.rm_eo {
      result = result * 10 + Int(target[Int(i)] - 48)  // 48 = ASCII '0'
    }
    return result
  }

  // ---------- DEBUG ----------

  /// Print all options
  private func printOptions() {
    debugPrint("----- OPTIONS -----")
    debugPrint("audioOnly:       \(audioOnly)")
    debugPrint("ranges:          \(ranges)")
    debugPrint("playInteractive: \(playInteractive)")
    debugPrint("playOnStart:     \(playOnStart)")
    debugPrint("loop:            \(loop)")
    debugPrint("selected tracks: \(selectedTracks)")
    debugPrint("runMode:         \(runMode)")
    debugPrint("-------------------")
  }
}

/**********************************************************************
 * Swift Interface to regex(3)
 * ---------------------------
 *
 * func regcomp(_ preg:    UnsafeMutablePointer<regex_t>?,
 *              _ pattern: UnsafePointer<Int8>?,
 *              _ cflags:  Int32) -> Int32
 *
 * func regexec(_ preg:   UnsafePointer<regex_t>?,
 *              _ string: UnsafePointer<Int8>?,
 *              _ nmatch: Int,
 *              _ pmatch: UnsafeMutablePointer<regmatch_t>?,
 *              _ eflags: Int32) -> Int32
 *
 * struct regex_t {
 *   re_magic: Int32
 *   re_nsub:  Int
 *   re_endp:  UnsafePointer<Int8>?
 *   re_g:     OpaquePointer?
 * }
 *
 * struct regmatch_t {
 *   rm_so: regoff_t
 *   rm_eo: regoff_t
 * }
 **********************************************************************/
