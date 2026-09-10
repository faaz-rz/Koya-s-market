import Foundation
import Vision
import ImageIO

// Read-only image analysis. The report is evidence for review, not approval.
let input = URL(fileURLWithPath: CommandLine.arguments[1])
let output = URL(fileURLWithPath: CommandLine.arguments[2])
let root = URL(fileURLWithPath: CommandLine.arguments[3], isDirectory: true)
let data = try Data(contentsOf: input)
let inventory = try JSONSerialization.jsonObject(with: data) as! [String: Any]
let assets = inventory["assets"] as! [[String: Any]]
FileManager.default.createFile(atPath: output.path, contents: nil)
let handle = try FileHandle(forWritingTo: output)
for (index, asset) in assets.enumerated() {
    autoreleasepool {
        let relativePath = asset["assetImagePath"] as! String
        var result: [String: Any] = ["assetImagePath": relativePath, "index": asset["index"]!]
        do {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["en-US"]
            request.usesLanguageCorrection = false
            let handler = VNImageRequestHandler(url: root.appendingPathComponent(relativePath))
            try handler.perform([request])
            result["text"] = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: " | ")
        } catch {
            result["error"] = error.localizedDescription
        }
        if let bytes = try? JSONSerialization.data(withJSONObject: result, options: [.sortedKeys]) {
            handle.write(bytes)
            handle.write(Data([10]))
        }
    }
    if (index + 1) % 100 == 0 { print("Read \(index + 1)/\(assets.count) product images") }
}
try handle.close()
print("Image text report: \(output.path)")
