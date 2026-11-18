//
//  Speaker.swift
//  Habito
//
//  Reads a task out loud with the system voice, in the language it is written in.
//

import AVFoundation
import NaturalLanguage

@MainActor
final class Speaker {
    static let shared = Speaker()
    private let synthesizer = AVSpeechSynthesizer()

    func say(_ text: String) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
        // Speak even when the phone's silent switch is on: the child asked for it.
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        let utterance = AVSpeechUtterance(string: text)
        if let language = NLLanguageRecognizer.dominantLanguage(for: text)?.rawValue,
           let voice = AVSpeechSynthesisVoice(language: language) {
            utterance.voice = voice
        }
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.9
        synthesizer.speak(utterance)
    }

    func stop() {
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
    }
}
