//
//  SpeechManager.swift
//  vision
//
//  Created by Sweety on 1/24/26.
//

import Foundation
import Speech
import AVFoundation
import Combine

@MainActor
class SpeechManager: ObservableObject {
    @Published var targetRequest: String? = nil
    @Published var isListening: Bool = false

    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()

    func toggleListening() {
        if isListening {
            stopListening()
        } else {
            requestPermissionsAndStart()
        }
    }

    private func requestPermissionsAndStart() {
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            DispatchQueue.main.async {
                guard status == .authorized else { return }
                AVAudioApplication.requestRecordPermission { granted in
                    DispatchQueue.main.async {
                        if granted {
                            self?.startListening()
                        }
                    }
                }
            }
        }
    }

    private func startListening() {
        recognitionTask?.cancel()
        recognitionTask = nil

        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            return
        }

        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else { return }
        recognitionRequest.shouldReportPartialResults = true

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            recognitionRequest.append(buffer)
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
            isListening = true
        } catch {
            return
        }

        recognitionTask = speechRecognizer?.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            DispatchQueue.main.async {
                guard let self = self else { return }

                if let result = result {
                    let text = result.bestTranscription.formattedString.lowercased()
                    self.parseCommand(from: text)
                }

                if error != nil || (result?.isFinal ?? false) {
                    self.stopListening()
                }
            }
        }
    }

    private func stopListening() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        isListening = false
    }

    private func parseCommand(from text: String) {
        let patterns = ["where is my ", "where is the ", "where are my ", "where are the ",
                        "find my ", "find the ", "where's my ", "where's the "]

        for pattern in patterns {
            if let range = text.range(of: pattern) {
                let objectName = String(text[range.upperBound...])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .components(separatedBy: CharacterSet.alphanumerics.inverted)
                    .filter { !$0.isEmpty }
                    .joined(separator: " ")

                if !objectName.isEmpty {
                    targetRequest = objectName
                }
                return
            }
        }
    }
}
