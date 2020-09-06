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

// Disable debugPrint() for non-debug builds
#if !DEBUG
func debugPrint
  (_ items: Any..., separator: String = " ", terminator: String = "\n") {}
#endif

/// Wrapper for vfprintf(3)
///
/// This is used primarily to direct output to a specific stream.
///
/// Note that you cannot pass a Swift String as the corresponding argument
/// for a "%s" format specifier.  You must turn the Swift String into a C
/// string.
///
/// It is best to use the Swift String's initializers that take a `format`
/// argument to do the actual formatting, and only use this wrapper to
/// direct the resulting string to a specific stream.
///
/// - Parameters:
///   + stream: The FILE to print to
///   + formatString: The format string
///   + args: The arguments to be formatted with `formatString`
func fprintf(_ stream: UnsafeMutablePointer<FILE>?,
             _ formatString: String,
             _ args: CVarArg...)
{
  vfprintf(stream, formatString, getVaList(args))
}


/**********************************************************************
 * String extensions
 **********************************************************************/

extension String {

  /// Return this string converted to a C string in UTF8 encoding
  var utf8String: UnsafePointer<Int8>? {
    return (self as NSString).utf8String
  }

  /// Return this string converted to a C string in UTF8 encoding, as an
  /// UnsafeMutablePointer<Int8>?
  var utf8MutableString: UnsafeMutablePointer<Int8>? {
    return UnsafeMutablePointer(mutating: utf8String)
  }

  /// Initialize a String representing a given FourCharCode
  init(_ fourCharCode: FourCharCode) {
    self.init(UTCreateStringForOSType(fourCharCode).takeUnretainedValue()
                as NSString)
  }

  /// Expose the `pathExtension` method of NSString.  This is the trailing
  /// part of this string after the last period ('.'), or the empty string
  /// if none.
  var pathExtension: String {
    return (self as NSString).pathExtension
  }

}


/**********************************************************************
 * AVAssetTrack extensions
 **********************************************************************/

extension AVAssetTrack {

  /// Print a readable summary of this track
  func printSummary() {
    var basicDescription = "  track \(trackID)"
    basicDescription    += ", duration: \(durationString())"
    basicDescription    += ", type: \(mediaTypeName())"
    var details = ""
    if let afd = getAudioFormatDescription() {
      // This is an audio track
      if let asbdp = CMAudioFormatDescriptionGetStreamBasicDescription(afd) {
        let asbd = asbdp.pointee
        details += ", \(asbd.mSampleRate / 1000.0) kHz"
        let chans = asbd.mChannelsPerFrame
        details += ", \(chans) channel" + ((chans > 1) ? "s" : "")
      }
      let dr = Int((estimatedDataRate / 1000.0).rounded())
      if (dr != 0) {
        details += ", \(dr) kbps"
      }
    }
    if let vfd = getVideoFormatDescription() {
      // This is a video track
      let dimensions = CMVideoFormatDescriptionGetDimensions(vfd)
      details += ", \(Int(dimensions.width)) x \(Int(dimensions.height))"
      details += ", \(Int(nominalFrameRate.rounded())) fps"
      let dr = Int((estimatedDataRate / 1000.0).rounded())
      if (dr != 0) {
        details += ", \(dr) kbps"
      }
    }
    print(basicDescription + details)
  }

  /// Return the duration of this track, in the form of "hh:mm:ss.fff"
  ///
  /// - Returns: A string describing the duration of this track
  func durationString() -> String {
    let totalSeconds = timeRange.duration.seconds
    let milliseconds =
      Int(totalSeconds.truncatingRemainder(dividingBy: 1.0) * 1000.0)
    let seconds
      = Int(totalSeconds.truncatingRemainder(dividingBy: 60.0))
    let minutes =
      Int((totalSeconds / 60.0).truncatingRemainder(dividingBy: 60.0))
    let hours
      = Int(totalSeconds / (60.0 * 60.0))
    return String(format: "%.2d:%.2d:%.2d.%.3d",
                  hours,
                  minutes,
                  seconds,
                  milliseconds)
  }

  /// Return a readable media type for this track, of the form
  /// "type/subtype".
  ///
  /// - Returns: A String describing the media type of this track
  func mediaTypeName() -> String {
    if (formatDescriptions.count == 0) {
      return "unknown/unknown"
    }
    let fd = formatDescriptions[0] as! CMFormatDescription
    // print(fd)
    let typeName =
      AVAssetTrack.mediaTypeString(CMFormatDescriptionGetMediaType(fd))
    let subTypeName =
      String(CMFormatDescriptionGetMediaSubType(fd))
    return "\(typeName)/\(subTypeName)"
  }

  /// Get the string description of a CMMediaType
  ///
  /// - Parameter mediaType: The media type
  ///
  /// - Returns: A string describing the given media type
  static func mediaTypeString(_ mediaType: CMMediaType) -> String {
    switch (mediaType) {
      case kCMMediaType_Audio:
        return "audio"
      case kCMMediaType_ClosedCaption:
        return "closed_caption"
      case kCMMediaType_Metadata:
        return "metadata"
      case kCMMediaType_Muxed:
        return "muxed"
      case kCMMediaType_Subtitle:
        return "subtitle"
      case kCMMediaType_Text:
        return "text"
      case kCMMediaType_TimeCode:
        return "time_code"
      case kCMMediaType_Video:
        return "video"
      default:
        return "unknown"
    }
  }

  /// Return whether this is an audio track
  func isAudio() -> Bool {
    return mediaType == .audio
  }

  /// Return whether this is a video track
  func isVideo() -> Bool {
    return mediaType == .video
  }

  /// Return the audio format description for this track, if applicable
  func getAudioFormatDescription() -> CMAudioFormatDescription? {
    if isAudio() && (formatDescriptions.count > 0) {
      let result: CMAudioFormatDescription =
        formatDescriptions[0] as! CMAudioFormatDescription
      return result
    } else {
      return nil
    }
  }

  /// Return the video format description for this track, if applicable
  func getVideoFormatDescription() -> CMVideoFormatDescription? {
    if isVideo() && (formatDescriptions.count > 0) {
      let result: CMVideoFormatDescription =
        formatDescriptions[0] as! CMVideoFormatDescription
      return result
    } else {
      return nil
    }
  }

}
