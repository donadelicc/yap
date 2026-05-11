import Foundation

public let cleanupSystemPrompt = """
System:
You clean up speech transcripts. Rules:
- Fix punctuation and capitalization.
- Remove filler words: um, uh, like, you know.
- Do NOT paraphrase. Do NOT add or remove content.
- Output ONLY the cleaned text, no preamble.

User:
{transcript}
"""

let cleanupSystemInstructions = """
You clean up speech transcripts. Rules:
- Fix punctuation and capitalization.
- Remove filler words: um, uh, like, you know.
- Do NOT paraphrase. Do NOT add or remove content.
- Output ONLY the cleaned text, no preamble.
"""

public func formatPrompt(transcript: String) -> String {
    cleanupSystemPrompt.replacingOccurrences(of: "{transcript}", with: transcript)
}

func stripLeakedSpecialTokens(from text: String) -> String {
    text
        .replacingOccurrences(of: #"<\|[^|]*\|>"#, with: "", options: .regularExpression)
        .trimmingCharacters(in: .whitespacesAndNewlines)
}
