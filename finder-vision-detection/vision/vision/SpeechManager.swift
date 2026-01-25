//
//  SpeechManager.swift
//  vision
//
//  Created by Sweety on 1/24/26.
//

import Foundation
import Combine
import Speech
import AVFoundation

class SpeechManager: ObservableObject {
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()

    @Published var isListening = false
    @Published var targetObject: String? = nil
    @Published var userIsSpeaking = false

    // Debounce: wait for user to finish speaking before acting
    private var debounceTimer: Timer?
    private var pendingTarget: String? = nil

    func startListening() {
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            DispatchQueue.main.async {
                if status == .authorized {
                    self?.beginSession()
                } else {
                    print("[Speech] Not authorized")
                }
            }
        }
    }

    private func beginSession() {
        guard !isListening else { return }

        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil

        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }

        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothHFP])
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            print("[Speech] Audio session error: \(error)")
            return
        }

        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let request = recognitionRequest else { return }
        request.shouldReportPartialResults = true

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        guard recordingFormat.sampleRate > 0 else { return }

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            request.append(buffer)
        }

        recognitionTask = speechRecognizer?.recognitionTask(with: request) { [weak self] result, error in
            guard let self = self else { return }

            if let result = result {
                let text = result.bestTranscription.formattedString.lowercased()

                DispatchQueue.main.async {
                    self.userIsSpeaking = true
                }

                self.handlePartialResult(text, isFinal: result.isFinal)

                if result.isFinal {
                    DispatchQueue.main.async {
                        self.userIsSpeaking = false
                    }
                }
            }

            if error != nil || (result?.isFinal == true) {
                DispatchQueue.main.async {
                    self.userIsSpeaking = false
                }
                self.stopSession()
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    self.beginSession()
                }
            }
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
            isListening = true
        } catch {
            print("[Speech] Engine error: \(error)")
            stopSession()
        }
    }

    private func stopSession() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask = nil
        isListening = false
    }

    private func handlePartialResult(_ text: String, isFinal: Bool) {
        if text.hasSuffix("stop") || text.hasSuffix("cancel") || text.hasSuffix("never mind") {
            DispatchQueue.main.async {
                self.debounceTimer?.invalidate()
                self.pendingTarget = nil
                self.targetObject = nil
            }
            return
        }

        let explicitPatterns = ["find my ", "find the ", "find a ", "find ", "look for ",
                                "where is my ", "where's my ", "where is the ", "where's the ",
                                "help me find ", "i need my ", "i need the "]

        let fallbackPatterns = ["my ", "the ", "a "]

        var foundTarget: String? = nil

        let noiseWords: Set<String> = ["and", "or", "the", "um", "uh", "like", "so",
                                         "well", "okay", "hey", "hi", "a", "an"]

        for pattern in explicitPatterns {
            if let range = text.range(of: pattern, options: .backwards) {
                let raw = String(text[range.upperBound...])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !raw.isEmpty {
                    let words = raw.components(separatedBy: " ")
                        .filter { !noiseWords.contains($0) }
                        .prefix(2)
                    if !words.isEmpty {
                        foundTarget = words.joined(separator: " ")
                        break
                    }
                }
            }
        }

        if foundTarget == nil {
            for pattern in fallbackPatterns {
                if let range = text.range(of: pattern, options: .backwards) {
                    let raw = String(text[range.upperBound...])
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    if !raw.isEmpty {
                        let words = raw.components(separatedBy: " ").prefix(2)
                        let candidate = words.joined(separator: " ")
                        // Only accept if it's a reasonable object name (not filler words)
                        let fillers = ["um", "uh", "like", "so", "well", "okay", "hey", "hi"]
                        if !fillers.contains(candidate) {
                            foundTarget = candidate
                            break
                        }
                    }
                }
            }
        }

        if foundTarget == nil, targetObject == nil {
            let words = text.components(separatedBy: " ")
            let meaningful = words.suffix(2).filter { word in
                let fillers = ["um", "uh", "like", "so", "well", "okay", "hey", "hi",
                               "can", "you", "help", "me", "i", "want", "need", "the",
                               "a", "an", "my", "please", "to", "it", "is"]
                return word.count >= 2 && !fillers.contains(word)
            }
            if !meaningful.isEmpty {
                foundTarget = meaningful.joined(separator: " ")
            }
        }

        guard let target = foundTarget else { return }

        DispatchQueue.main.async {
            self.pendingTarget = target
            self.debounceTimer?.invalidate()

            let delay: TimeInterval = isFinal ? 0.3 : 1.5
            self.debounceTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { _ in
                if let pending = self.pendingTarget {
                    self.targetObject = pending
                    self.pendingTarget = nil
                    self.userIsSpeaking = false
                }
            }
        }
    }
}
