//
//  SolveAPI.swift
//  GlassesTestAssistant
//
//  Created by Connor Pauley on 12/1/25.
//

import Foundation

// One question extracted from the OCR text
struct SolvedQuestion: Decodable {
    let number: String          // e.g. "1", "2", "3", "10"
    let part: String?           // e.g. "a", "b", "c" or null if no part
    let question: String        // full readable question text (as much as OCR gave)
    let answer: String?         // the answer text if readable
    let status: String          // "answered" or "needs_retake"
    let reason: String?         // short reason if needs_retake
}

// Top-level response we expect GPT to return as JSON text
struct SolveResponse: Decodable {
    let questions: [SolvedQuestion]
}

/// Calls OpenAI with recognized text (no images), asking for a structured list of questions.
final class SolveAPI {

    static let shared = SolveAPI()

    private init() {}

    private let endpoint = URL(string: "https://api.openai.com/v1/chat/completions")!

    // Public entry: always starts at attempt 0
    func solve(questionText: String,
               completion: @escaping (Result<SolveResponse, Error>) -> Void) {
        solveInternal(questionText: questionText, attempt: 0, completion: completion)
    }

    // MARK: - Core solver with retry

    /// attempt = 0 → normal prompt
    /// attempt = 1 → stricter "JSON-only" prompt
    private func solveInternal(questionText: String,
                               attempt: Int,
                               completion: @escaping (Result<SolveResponse, Error>) -> Void) {

        let baseSystemPrompt = """
        You are an educational assistant.

        You will receive OCR'd text from one or more test or worksheet questions.
        The text may include:
        - A shared stem or header describing a scenario (for example, a description of SAT scores, a data table, or a graph),
        - Followed by multiple subparts like (a), (b), (c) that ALL refer back to the same stem.

        Your job is to:
        - Consider the ENTIRE OCR block together (stem + all parts).
        - Identify each distinct question number (1, 2, 3, etc.).
        - For each question number, identify any subparts (a, b, c, etc.) that share the same stem.
        - For every subpart, reuse ANY information given in the shared stem and earlier parts for that same question.
        - Compute and provide a clear, direct answer for every question and subpart.

        VERY IMPORTANT:
        - You must ALWAYS provide an answer string for every question in the "answer" field.
          Do NOT tell the user to retake a photo, and do NOT skip answering.
        - If the text is slightly messy (for example, minor OCR glitches around punctuation like "d15%" or missing a % symbol),
          infer the intended values and answer anyway as long as you can reasonably interpret the question.
        - For normal-distribution/statistics questions, if you have a mean and standard deviation and a threshold value,
          you should compute the probability or percentage as best you can. Return the percentage as a numeric value (for example "2.3%").
        - You MAY use the "reason" field to briefly note if the OCR was messy or if your answer is low confidence,
          but you MUST still fill in the "answer" field.

        Return your result as pure JSON with this exact structure:

        {
          "questions": [
            {
              "number": "1",
              "part": "a",                // or null / "" if no part
              "question": "full question text here (include the relevant stem + this part)",
              "answer": "short direct answer here (always filled with your best answer)",
              "status": "answered",       // always use "answered"
              "reason": "optional note about OCR quality or null"
            }
          ]
        }

        Rules:
        - "status" should simply be "answered" for all questions.
        - "answer" must ALWAYS be a non-empty string containing your best attempt at the answer.
        - "reason" is optional and only used to explain low confidence or messy OCR, NOT to avoid answering.
        - If you can't find a clear number label in the text, you may assign a reasonable "number" like "?".
        """



        // On second attempt, be extra strict about JSON-only output.
        let jsonOnlySuffix = """
        Output ONLY raw JSON. No markdown, no backticks, no explanation text, no comments.
        The first character MUST be '{' and the last character MUST be '}'.
        """

        let systemPrompt: String
        if attempt == 0 {
            systemPrompt = baseSystemPrompt + "\n\n" + jsonOnlySuffix
        } else {
            // Second attempt: explicitly state this is a retry due to invalid JSON last time.
            systemPrompt = """
            \(baseSystemPrompt)

            The previous attempt returned invalid JSON. This time you MUST follow these rules:

            - Output ONLY raw JSON. No markdown, no backticks, no explanation text, no comments.
            - The first character MUST be '{' and the last character MUST be '}'.
            - Do not wrap the JSON in ```json or ``` blocks.
            - Do not add any extra text before or after the JSON.

            """ + jsonOnlySuffix
        }

        let payload: [String: Any] = [
            "model": "gpt-4o-mini",
            "messages": [
                [
                    "role": "system",
                    "content": systemPrompt
                ],
                [
                    "role": "user",
                    "content": questionText
                ]
            ],
            "temperature": 0
        ]

        guard let bodyData = try? JSONSerialization.data(withJSONObject: payload) else {
            completion(.failure(NSError(domain: "SolveAPI",
                                        code: 0,
                                        userInfo: [NSLocalizedDescriptionKey: "Failed to encode JSON payload."])))
            return
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(Secrets.openAIKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = bodyData

        URLSession.shared.dataTask(with: request) { data, response, error in
            // Network / transport error → real error
            if let error = error {
                completion(.failure(error))
                return
            }

            guard let data = data else {
                completion(.failure(NSError(domain: "SolveAPI",
                                            code: 0,
                                            userInfo: [NSLocalizedDescriptionKey: "No data from server."])))
                return
            }

            // 1) Extract the assistant text out of the OpenAI envelope
            guard let rawText = self.extractAssistantText(from: data) else {
                // If we can't even find choices/message/content, treat it as a needs_retake
                let fallback = self.makeNeedsRetakeFallback(questionText: questionText,
                                                            reason: "Received an unexpected server format. Please retake a clear photo.")
                completion(.success(fallback))
                return
            }

            // 2) Try to clean and decode as SolveResponse
            if let solved = self.decodeSolveResponse(from: rawText) {
                completion(.success(solved))
                return
            }

            // 3) If JSON parsing failed, maybe retry once with stricter system prompt
            if attempt == 0 {
                self.solveInternal(questionText: questionText, attempt: 1, completion: completion)
                return
            }

            // 4) Second attempt also failed → final fallback:
            // Treat the entire model reply as a single ANSWERED item (no error thrown).
            let fallback = self.makeAnsweredFallback(questionText: questionText,
                                                     modelReply: rawText)
            completion(.success(fallback))

        }.resume()
    }

    // MARK: - Extract assistant text from OpenAI envelope

    /// Handles both:
    /// - choices[0].message.content as String
    /// - choices[0].message.content as [ { "type": "...", "text": "..." }, ... ]
    private func extractAssistantText(from data: Data) -> String? {
        do {
            let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any]
            guard
                let root = json,
                let choices = root["choices"] as? [[String: Any]],
                let firstChoice = choices.first,
                let message = firstChoice["message"] as? [String: Any]
            else {
                return nil
            }

            // Case 1: content is a plain string
            if let contentString = message["content"] as? String {
                return contentString
            }

            // Case 2: content is an array of content parts
            if let contentArray = message["content"] as? [[String: Any]] {
                // join all "text" fields
                let texts = contentArray.compactMap { part -> String? in
                    if let text = part["text"] as? String {
                        return text
                    }
                    // some APIs use { "type": "output_text", "text": { "value": "..." } }
                    if let textObj = part["text"] as? [String: Any],
                       let value = textObj["value"] as? String {
                        return value
                    }
                    return nil
                }
                if !texts.isEmpty {
                    return texts.joined(separator: "\n")
                }
            }

            return nil
        } catch {
            print("SolveAPI: JSON envelope parse error:", error)
            return nil
        }
    }

    // MARK: - Decode inner JSON or fall back

    /// Try to clean the model's text and decode it as SolveResponse JSON.
    private func decodeSolveResponse(from rawText: String) -> SolveResponse? {
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)

        // Extract substring from first '{' to last '}', in case there's extra noise.
        let jsonString: String
        if let start = trimmed.firstIndex(of: "{"),
           let end = trimmed.lastIndex(of: "}") {
            jsonString = String(trimmed[start...end])
        } else {
            jsonString = trimmed
        }

        guard let jsonData = jsonString.data(using: .utf8) else {
            return nil
        }

        do {
            let solved = try JSONDecoder().decode(SolveResponse.self, from: jsonData)
            return solved
        } catch {
            print("SolveAPI: Failed to decode SolveResponse JSON:", error)
            print("SolveAPI: raw model text:\n\(rawText)")
            return nil
        }
    }

    // MARK: - Fallback builders

    private func makeNeedsRetakeFallback(questionText: String, reason: String) -> SolveResponse {
        let q = SolvedQuestion(
            number: "?",
            part: nil,
            question: questionText,
            answer: nil,
            status: "needs_retake",
            reason: reason
        )
        return SolveResponse(questions: [q])
    }

    /// Final safety net: treat the entire model reply as a single answered question.
    private func makeAnsweredFallback(questionText: String, modelReply: String) -> SolveResponse {
        let q = SolvedQuestion(
            number: "?",
            part: nil,
            question: questionText,
            answer: modelReply,
            status: "answered",
            reason: "Parsed answer directly from the assistant reply."
        )
        return SolveResponse(questions: [q])
    }
}
