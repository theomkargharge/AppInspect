// Cuts a simulator recording to the middle 9:16 band and scales it to
// 1080x1920, the vertical format LinkedIn, Reels and Shorts expect.
//
//   swift tool/export_vertical.swift raw.mov out.mp4
import AVFoundation
import Foundation

let arguments = CommandLine.arguments
guard arguments.count == 3 else {
  print("Usage: swift export_vertical.swift <input.mov> <output.mp4>")
  exit(64)
}
let input = URL(fileURLWithPath: arguments[1])
let output = URL(fileURLWithPath: arguments[2])

let asset = AVURLAsset(url: input)
let semaphore = DispatchSemaphore(value: 0)
var failure: String?

Task {
  do {
    guard let track = try await asset.loadTracks(withMediaType: .video).first else {
      failure = "No video in \(input.path)"
      semaphore.signal()
      return
    }
    let (natural, transform) = try await track.load(.naturalSize, .preferredTransform)
    let duration = try await asset.load(.duration)
    let oriented = natural.applying(transform)
    let width = abs(oriented.width)
    let height = abs(oriented.height)

    // The middle 9:16 band, scaled to 1080 wide.
    let band = width * 16 / 9
    let top = max(0, (height - band) / 2)
    let target = CGSize(width: 1080, height: 1920)
    let scale = target.width / width

    let layer = AVMutableVideoCompositionLayerInstruction(assetTrack: track)
    layer.setTransform(
      transform
        .concatenating(CGAffineTransform(translationX: 0, y: -top))
        .concatenating(CGAffineTransform(scaleX: scale, y: scale)),
      at: .zero)
    let instruction = AVMutableVideoCompositionInstruction()
    instruction.timeRange = CMTimeRange(start: .zero, duration: duration)
    instruction.layerInstructions = [layer]
    let composition = AVMutableVideoComposition()
    composition.renderSize = target
    composition.frameDuration = CMTime(value: 1, timescale: 60)
    composition.instructions = [instruction]

    guard let export = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality) else {
      failure = "Can't export \(input.path)"
      semaphore.signal()
      return
    }
    try? FileManager.default.removeItem(at: output)
    export.videoComposition = composition
    export.shouldOptimizeForNetworkUse = true
    if #available(macOS 15, *) {
      try await export.export(to: output, as: .mp4)
    } else {
      export.outputURL = output
      export.outputFileType = .mp4
      await export.export()
      if export.status != .completed {
        failure = "Export failed: \(export.error?.localizedDescription ?? "unknown error")"
      }
    }
  } catch {
    failure = "\(error)"
  }
  semaphore.signal()
}
semaphore.wait()
if let failure {
  print(failure)
  exit(1)
}
print("Wrote \(output.path)")
