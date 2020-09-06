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

import Foundation

/// A Swift wrapper for getopt(3)
struct GetOpt {

  /// A tuple type that represents one option specification.  The first
  /// element is the option character (as a String), and the second element
  /// is the argument to that option, or nil if none.
  typealias OptionSpec = (option: String, argument: String?)

  /// An array of all options that were successfully parsed by getopt(), or
  /// nil if none.  Repeated use of the same option results in multiple
  /// entries of that option in this array.
  var validOptions: [OptionSpec]? {
    return _validOptions
  }

  /// An array of invalid options, or nil if none.  These are option
  /// characters for which getopt() returned '?'.  You can decide whether a
  /// non-nil value for this array is a fatal error.  The second element of
  /// each tuple in this array will always be nil.
  var invalidOptions: [OptionSpec]? {
    return _invalidOptions
  }

  /// The number of remaining arguments, after getopt() returned -1.
  var remainingArgumentCount: Int {
    return _remainingArgumentCount
  }

  /// The remaining arguments as a String array, after getopt() returned
  /// -1, or nil if no arguments remain.
  var remainingArguments: [String]? {
    if remainingArgumentCount > 0 {
      return [String](CommandLine.arguments.suffix(remainingArgumentCount))
    } else {
      return nil
    }
  }

  /// Return true if the given option was specified.
  ///
  /// - Parameter option: The option to look up
  func hasOption(_ option: String) -> Bool {
    if (_validOptions != nil) {
      return _validOptions!.contains { $0.option == option }
    }
    return false;
  }

  /// Return an array of OptionSpecs for the given option, or nil if none.
  ///
  /// If the option was specified more than once, the returned array will
  /// have more than one element.
  ///
  /// - Parameter option: The option to look up
  func getOptionSpecs(_ option: String) -> [OptionSpec]? {
    if (validOptions == nil) {
      return nil
    } else {
      var result = [OptionSpec]()
      for validOption in validOptions! {
        if (validOption.option == option) {
          result.append(validOption)
        }
      }
      if (result.isEmpty) {
        return nil
      } else {
        return result
      }
    }
  }

  /// The basename of argv[0], i.e., the name of the current command
  /// without leading directories.  If basename() fails for any reason, the
  /// original (unprocessed) argv[0] is returned.
  static var commandBaseName: String {
    // func basename(UnsafeMutablePointer<Int8>?) -> UnsafeMutablePointer<Int8>?
    if let result = basename(CommandLine.unsafeArgv[0]) {
      return String(cString: result)
    } else {
      return CommandLine.arguments[0]
    }
  }

  /// Initializer: parse the options described by the given `optstring` and
  /// report the results back in this instance.
  ///
  /// See getopt(3) for the format of `optstring`.  This initializer does
  /// not support an `optstring` that starts with a colon (':').
  ///
  /// Note that you do not pass `argc` and `argv`.  Those are obtained
  /// directly from the `CommandLine` singleton.
  ///
  /// The parsing always starts from the beginning of argv[] for each call
  /// to this initializer.  You can therefore create multiple instances of
  /// this type, each parsing a different `optstring`.
  ///
  /// - Parameter optstring: A string describing valid options
  init(_ optstring: String) {
    // Begin a new pass (in case this is not the first pass)
    optreset = 1
    optind   = 1
    // Loop until getopt() returns -1
    let questionMark: Unicode.Scalar = "?"
    var result: Int32 =
      getopt(CommandLine.argc, CommandLine.unsafeArgv, optstring);
    while (result != -1) {
      // debugResult(result)
      let resultCharacter = Unicode.Scalar(UInt8(result))
      if (resultCharacter != questionMark) {
        // A valid option was parsed
        if _validOptions == nil {
          _validOptions = []
        }
        if optarg == nil {
          _validOptions!.append((String(resultCharacter), nil))
        } else {
          let optargString = String(utf8String: optarg)
          _validOptions!.append((String(resultCharacter), optargString))
        }
      } else {
        // An invalid option was encountered
        if _invalidOptions == nil {
          _invalidOptions = []
        }
        let optoptCharacter = Unicode.Scalar(UInt8(optopt))
        _invalidOptions!.append((String(optoptCharacter), nil))
      }
      result = getopt(CommandLine.argc, CommandLine.unsafeArgv, optstring);
    }
    _remainingArgumentCount = Int(CommandLine.argc - optind)
    // debugSelf()
  }

  // ---------- PRIVATE ----------

  // Backing store for public properties.
  private var _validOptions: [OptionSpec]?
  private var _invalidOptions: [OptionSpec]?
  private var _remainingArgumentCount: Int = 0

  /// For debugging: print a readable description of the result of the last
  /// call to getopt() along with the current values of all the associated
  /// global variables.
  ///
  /// - Parameter result: The result of the last call to `getopt()`
  private func debugResult(_ result: Int32) {
    print("'\(Unicode.Scalar(UInt8(result)))'")
    if optarg == nil {
      print("  optarg:   nil")
    } else {
      let optargString = String(utf8String: optarg)
      print("  optarg:   \"\(optargString ?? "fail")\"")
    }
    print("  optind:   \(optind)")
    print("  optopt:   '\(Unicode.Scalar(UInt8(optopt)))'")
    print("  opterr:   \(opterr)")
    print("  optreset: \(optreset)")
  }

  /// For debugging: print a readable description of this instance
  private func debugSelf() {
    if (validOptions != nil) {
      print("validOptions=\(validOptions!)")
    }
    if (invalidOptions != nil) {
      print("invalidOptions=\(invalidOptions!)")
    }
    print("remainingArgumentCount = \(remainingArgumentCount)")
    if (remainingArguments != nil) {
      print("remainingArguments:")
      for argument in remainingArguments! {
        print("  \(argument)")
      }
    }
  }
}

/**********************************************************************
 * Swift interface to getopt(3)
 * ----------------------------
 *
 * C signature:
 * ------------
 *
 *   int getopt(int argc, char * const argv[], const char *optstring);
 *
 * Imported Swift signature:
 * -------------------------
 *
 *   func getopt(_ argc: Int32,
 *               _ argv: UnsafePointer<UnsafeMutablePointer<Int8>?>?,
 *               _ optstring: UnsafePointer<Int8>?) -> Int32
 *
 * C Global        Imported Swift type and initial value
 * ----------------------------------------------------------------
 * char *optarg;   UnsafeMutablePointer<Int8>? = nil  (Current argument, or nil)
 * int   optind;   Int32 = 1  (Index in argv[] for next call to getopt())
 * int   optopt;   Int32 = 0  (Last known option returned by getopt())
 * int   opterr;   Int32 = 1  (If 0, disable printing of error messages)
 * int   optreset; Int32 = 0  (Set this and optind both to 1 to begin new pass)
 **********************************************************************/
