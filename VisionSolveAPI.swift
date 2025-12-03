//
// VisionSolveAPI.swift
// GlassesTestAssistant
//
// OCR → text-only Responses API → structured JSON answers
//

import Foundation
import UIKit
import Vision

// MARK: - Public Response Models (used by the rest of the app)

struct VisionSolvedQuestion: Decodable {
let number: String
let part: String?
let question: String
let answer: String
let explanation: String?
let checkExpression: String?
}

struct VisionSolveResponse: Decodable {
let questions: [VisionSolvedQuestion]
}

// Simple error wrapper so we can create errors with just a string.
struct SimpleError: LocalizedError {
let message: String
init(_ message: String) { self.message = message }
var errorDescription: String? { message }
}

// MARK: - Internal Models for OpenAI Responses API

private struct OpenAIErrorPayload: Decodable {
let message: String?
let type: String?
let param: String?
let code: String?
}

private struct OpenAIContentItem: Decodable {
let type: String
let text: String?
}

private struct OpenAIMessageItem: Decodable {
let id: String?
let type: String
let status: String?
let content: [OpenAIContentItem]
let role: String?
}

private struct OpenAIResponsesEnvelope: Decodable {
let id: String?
let object: String?
let output: [OpenAIMessageItem]?
let error: OpenAIErrorPayload?
}

// MARK: - OCR Line Model

private struct RecognizedLine {
let text: String
let boundingBox: CGRect // Vision normalized rect
let confidence: Float
}

// MARK: - VisionSolveAPI

final class VisionSolveAPI {

static let shared = VisionSolveAPI()
private init() {}

private let endpoint = URL(string: "https://api.openai.com/v1/responses")!
/// Text model; you can swap this for another Responses-compatible text model if you’d like.
private let modelName = "gpt-5.1"

// MARK: - PUBLIC ENTRY

/// Master entry point used by the rest of the app.
/// 1. OCR via Apple Vision
/// 2. Select best math problem block
/// 3. Send cleaned text to OpenAI Responses API in JSON mode
/// 4. Decode into `VisionSolveResponse`
func solve(from image: UIImage,
           completion: @escaping (Result<VisionSolveResponse, Error>) -> Void)
{
    performOCR(on: image) { [weak self] ocrResult in
        guard let self = self else { return }

        switch ocrResult {
        case .failure(let err):
            DispatchQueue.main.async {
                completion(.failure(err))
            }

        case .success(let lines):
            let cleaned = self.extractProblemText(from: lines)

            guard !cleaned.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                DispatchQueue.main.async {
                    completion(.failure(SimpleError("No usable text found in image.")))
                }
                return
            }

            self.callOpenAI(with: cleaned) { result in
                DispatchQueue.main.async {
                    completion(result)
                }
            }
        }
    }
}

// MARK: - STEP 1: OCR with Apple Vision

private func performOCR(on image: UIImage,
                        completion: @escaping (Result<[RecognizedLine], Error>) -> Void)
{
    guard let cgImage = image.cgImage else {
        completion(.failure(SimpleError("Image did not contain a CGImage.")))
        return
    }

    let request = VNRecognizeTextRequest { request, error in
        if let error = error {
            completion(.failure(error))
            return
        }

        guard let observations = request.results as? [VNRecognizedTextObservation] else {
            completion(.success([]))
            return
        }

        var lines: [RecognizedLine] = []

        for obs in observations {
            guard let candidate = obs.topCandidates(1).first else { continue }
            let text = candidate.string.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }

            let line = RecognizedLine(
                text: text,
                boundingBox: obs.boundingBox,
                confidence: candidate.confidence
            )
            lines.append(line)
        }

        completion(.success(lines))
    }

    // Higher accuracy, we don't care about speed here.
    request.recognitionLevel = .accurate
    request.usesLanguageCorrection = true

    let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])

    DispatchQueue.global(qos: .userInitiated).async {
        do {
            try handler.perform([request])
        } catch {
            completion(.failure(error))
        }
    }
}

// MARK: - STEP 2: Extract the math problem block

private func extractProblemText(from lines: [RecognizedLine]) -> String {
    guard !lines.isEmpty else { return "" }

    // Filter out very low-confidence noise
    let filtered = lines.filter { $0.confidence >= 0.35 }

    guard !filtered.isEmpty else { return "" }

    // Sort roughly top-to-bottom. Vision’s boundingBox is normalized with origin at bottom-left,
    // so lines with higher minY are higher on the image.
    let sorted = filtered.sorted { $0.boundingBox.minY > $1.boundingBox.minY }

    struct ScoredLine {
        let line: RecognizedLine
        let score: Int
        let digitCount: Int
    }

    let mathKeywords = [
        "mean", "median", "mode",
        "range", "iqr", "interquartile",
        "probability", "percent", "percentage",
        "standard deviation", "variance",
        "minutes", "data", "time", "studying",
        "question", "statistical", "sample",
        "distribution"
    ]

    let trashSnippets = [
        "chatgpt can make mistakes",
        "want another one",
        "harder?",
        "multiple choice?",
        "with a graph",
        "just let me know",
        "send a message"
    ]

    func score(_ line: RecognizedLine) -> ScoredLine {
        let lower = line.text.lowercased()

        // Digit density
        let digits = lower.filter { $0.isNumber }.count
        let len = max(lower.count, 1)
        let density = Double(digits) / Double(len)

        var s = 0

        // Encourage lines with digits (data, question numbering, etc.)
        if density >= 0.5 {
            s += 3
        } else if density >= 0.2 {
            s += 2
        } else if digits > 0 {
            s += 1
        }

        // Encourage math/question words
        if mathKeywords.contains(where: { lower.contains($0) }) {
            s += 3
        }

        // Bullet/numbered list style (1., 2., 3.)
        if lower.range(of: #"^\d+\."#, options: .regularExpression) != nil {
            s += 2
        }

        // Question mark => usually a sub-question sentence
        if lower.contains("?") {
            s += 2
        }

        // Penalize obvious UI/boilerplate lines
        if trashSnippets.contains(where: { lower.contains($0) }) {
            s -= 4
        }

        // Very short junk (one or two characters) often noise
        if len <= 2 && digits == 0 {
            s -= 2
        }

        // Confidence as a small boost
        if line.confidence >= 0.85 { s += 1 }

        return ScoredLine(line: line, score: s, digitCount: digits)
    }

    let scoredLines = sorted.map(score)

    // Group into vertical blocks based on y-gap
    struct Block {
        var lines: [ScoredLine] = []
        var totalScore: Int = 0
        var totalDigits: Int = 0
    }

    var blocks: [Block] = []
    var current = Block()

    let gapThreshold: CGFloat = 0.06

    for (idx, item) in scoredLines.enumerated() {
        if idx == 0 {
            current.lines = [item]
            current.totalScore = item.score
            current.totalDigits = item.digitCount
            continue
        }

        let prev = scoredLines[idx - 1]
        let dy = abs(item.line.boundingBox.midY - prev.line.boundingBox.midY)

        if dy <= gapThreshold {
            current.lines.append(item)
            current.totalScore += item.score
            current.totalDigits += item.digitCount
        } else {
            blocks.append(current)
            current = Block(lines: [item],
                            totalScore: item.score,
                            totalDigits: item.digitCount)
        }
    }
    blocks.append(current)

    // Choose the block with highest score, breaking ties by digit count.
    let bestBlock = blocks
        .filter { $0.totalScore > 0 }
        .max {
            if $0.totalScore == $1.totalScore {
                return $0.totalDigits < $1.totalDigits
            }
            return $0.totalScore < $1.totalScore
        }

    // If everything scored <= 0 (very unlikely), just fall back to all text.
    let linesToUse: [RecognizedLine]
    if let block = bestBlock {
        linesToUse = block.lines.map { $0.line }
    } else {
        linesToUse = sorted.map { $0 }
    }

    // Join into a single text blob, preserving top-to-bottom order.
    let joined = linesToUse
        .map { $0.text }
        .joined(separator: "\n")

    return joined
}

// MARK: - STEP 3: Call OpenAI Responses API (text-only JSON mode)

private func callOpenAI(with problemText: String,
                        completion: @escaping (Result<VisionSolveResponse, Error>) -> Void)
{
    var request = URLRequest(url: endpoint)
    request.httpMethod = "POST"
    request.addValue("application/json", forHTTPHeaderField: "Content-Type")
    request.addValue("Bearer \(Secrets.openAIKey)", forHTTPHeaderField: "Authorization")

    let systemPrompt = """
    You are a math assistant that receives OCR text extracted from a photo of a worksheet, \
    web page, or laptop screen. The text may include UI elements like buttons, hints, or \
    unrelated messages.

    Your job:
    1. Identify the single main math problem and its sub-questions the student must answer.
    2. Ignore UI text such as "Want another one?", "With a graph?", "ChatGPT can make mistakes.", etc.
    3. Solve each sub-question correctly and concisely.
    4. Return ONLY a valid JSON object with this exact shape:

       {
         "questions": [
           {
             "number": "1",
             "part": "a",
             "question": "Full text of the sub-question",
             "answer": "Short final numeric or word answer",
             "explanation": "Short explanation (optional)",
             "checkExpression": "Simple expression to verify the answer (optional)"
           }
         ]
       }

    - "number": question number if present, otherwise "1".
    - "part": set to null if there is no part label.
    - "answer": just the final answer, not steps.
    - "explanation": 1–3 concise sentences, or null.
    - "checkExpression": a simple expression that evaluates to the correct value
      (e.g. "40/8", "7/(5+7+8)", or "abs(x-12.3) < 0.01"), or null.

    Do not include any additional keys or text outside this JSON object.
    """

    let inputMessages: [[String: Any]] = [
        [
            "role": "system",
            "content": [
                ["type": "input_text", "text": systemPrompt]
            ]
        ],
        [
            "role": "user",
            "content": [
                ["type": "input_text", "text": problemText]
            ]
        ]
    ]

    let payload: [String: Any] = [
        "model": modelName,
        "input": inputMessages,
        "temperature": 0.0,
        "max_output_tokens": 600,
        "text": [
            "format": [
                "type": "json_object"
            ]
        ]
    ]

    do {
        request.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])
    } catch {
        completion(.failure(error))
        return
    }

    let task = URLSession.shared.dataTask(with: request) { data, response, error in

        if let error = error {
            completion(.failure(error))
            return
        }

        guard let data = data, !data.isEmpty else {
            completion(.failure(SimpleError("Empty response from OpenAI.")))
            return
        }

        // For debugging in Xcode if needed:
        // let raw = String(data: data, encoding: .utf8) ?? ""
        // print("RAW SERVER RESPONSE STRING:\n\(raw)")

        do {
            let decoder = JSONDecoder()
            let envelope = try decoder.decode(OpenAIResponsesEnvelope.self, from: data)

            if let apiError = envelope.error {
                let msg = apiError.message ?? "Unknown OpenAI error."
                completion(.failure(SimpleError(msg)))
                return
            }

            guard
                let outputMsg = envelope.output?.first,
                let textItem = outputMsg.content.first(where: { $0.text != nil }),
                let jsonText = textItem.text
            else {
                completion(.failure(SimpleError("No output text found in OpenAI response.")))
                return
            }

            guard let jsonData = jsonText.data(using: .utf8) else {
                completion(.failure(SimpleError("Output text was not valid UTF-8 JSON.")))
                return
            }

            let parsed = try decoder.decode(VisionSolveResponse.self, from: jsonData)

            // Extra safety: ensure we have at least one question
            if parsed.questions.isEmpty {
                completion(.failure(SimpleError("Finished processing, but no readable questions were found.")))
            } else {
                completion(.success(parsed))
            }
        } catch {
                    // If JSON decode fails, surface a helpful error
                    let raw = String(data: data, encoding: .utf8) ?? ""
                    print("JSON decode error: \(error)")
                    print("Raw text:", raw)
                    completion(.failure(error))
                }
            }

            task.resume()
        }

        }
