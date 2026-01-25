//
//  ContentView.swift
//  vision
//
//  Created by Sweety on 1/24/26.
//

import SwiftUI
import RealityKit
@preconcurrency import ARKit
import Combine

struct ContentView: View {
    @StateObject private var navManager = VisionNavManager()
    @StateObject private var speechManager = SpeechManager()
    @State private var pulse = false

    private var statusColor: Color {
        if navManager.isSearching { return .green }
        if speechManager.userIsSpeaking { return .orange }
        return .white.opacity(0.6)
    }

    private var statusText: String {
        if speechManager.userIsSpeaking { return "Listening..." }
        if navManager.isSearching { return "Scanning" }
        return "Ready"
    }

    var body: some View {
        ZStack {
            ARViewContainer(session: navManager.arSession).ignoresSafeArea()
            DetectionOverlayView(detections: navManager.lastDetections,
                               targetObject: navManager.targetObject)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                LinearGradient(colors: [.black.opacity(0.5), .clear],
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: 120)
                Spacer()
                LinearGradient(colors: [.clear, .black.opacity(0.7)],
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: 260)
            }
            .ignoresSafeArea()

            VStack(spacing: 0) {

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Findar")
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                        HStack(spacing: 6) {
                            Circle()
                                .fill(statusColor)
                                .frame(width: 7, height: 7)
                                .opacity(pulse ? 0.5 : 1.0)
                                .animation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true), value: pulse)
                            Text(statusText)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.white.opacity(0.7))
                        }
                    }
                    Spacer()
                    Image(systemName: speechManager.isListening ? "waveform" : "mic.slash")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(speechManager.isListening ? .green : .white.opacity(0.4))
                        .padding(10)
                        .background(Circle().fill(.white.opacity(0.1)))
                }
                .padding(.horizontal, 24)
                .padding(.top, 60)

                Spacer()

                VStack(spacing: 20) {

                    Text(navManager.currentInstruction)
                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                        .multilineTextAlignment(.center)
                        .foregroundColor(.white)
                        .lineLimit(2)
                        .minimumScaleFactor(0.75)
                        .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
                        .padding(.horizontal, 30)
                        .animation(.easeInOut(duration: 0.3), value: navManager.currentInstruction)

                    Button(action: {
                        speechManager.startListening()
                    }) {
                        ZStack {
                            Circle()
                                .stroke(speechManager.isListening ? statusColor.opacity(0.4) : .white.opacity(0.15), lineWidth: 2)
                                .frame(width: 72, height: 72)

                            if speechManager.isListening {
                                Circle()
                                    .stroke(statusColor.opacity(0.3), lineWidth: 1.5)
                                    .frame(width: 72, height: 72)
                                    .scaleEffect(pulse ? 1.4 : 1.0)
                                    .opacity(pulse ? 0.0 : 0.6)
                                    .animation(.easeOut(duration: 2.0).repeatForever(autoreverses: false), value: pulse)
                            }

                            Circle()
                                .fill(speechManager.isListening ?
                                      statusColor.opacity(0.15) : .white.opacity(0.06))
                                .frame(width: 64, height: 64)

                            Image(systemName: speechManager.isListening ? "mic.fill" : "mic")
                                .font(.system(size: 26, weight: .medium))
                                .foregroundColor(speechManager.isListening ? statusColor : .white.opacity(0.6))
                        }
                    }
                    .accessibilityLabel(speechManager.isListening ? "Microphone active, listening for commands" : "Tap to start listening")

                    Text(speechManager.isListening ? "Say \"find my phone\" or any object" : "Tap mic to begin")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(.white.opacity(0.4))
                }
                .padding(.bottom, 50)
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            pulse = true
            navManager.greetUser()
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                speechManager.startListening()
            }
        }
        .onChange(of: speechManager.targetObject) { newTarget in
            navManager.setTarget(newTarget)
        }
        .onChange(of: speechManager.userIsSpeaking) { speaking in
            navManager.setUserSpeaking(speaking)
        }
        .onChange(of: navManager.isSearching) { searching in
            if !searching {
                speechManager.targetObject = nil
            }
        }
    }
}

//detection view
struct DetectionOverlayView: View {
    let detections: [VNRecognizedObjectObservation]
    let targetObject: String?

    var body: some View {
        GeometryReader { geometry in
            ForEach(Array(detections.enumerated()), id: \.offset) { _, detection in
                let rect = convertVisionRect(detection.boundingBox, to: geometry.size)
                let isTarget = isTargetDetection(detection)

                ZStack {
                    RoundedRectangle(cornerRadius: max(rect.width, rect.height) / 2)
                        .stroke(isTarget ? Color.green : Color.blue.opacity(0.6),
                               lineWidth: isTarget ? 4 : 2)
                        .frame(width: rect.width, height: rect.height)
                        .position(x: rect.midX, y: rect.midY)

                    if let label = detection.labels.first?.identifier {
                        VStack(spacing: 2) {
                            Text(label)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.white)
                            Text(String(format: "%.0f%%", detection.confidence * 100))
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.white.opacity(0.8))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(isTarget ? Color.green.opacity(0.8) : Color.blue.opacity(0.7))
                        )
                        .position(x: rect.midX, y: rect.minY - 20)
                    }
                }
                .animation(.easeInOut(duration: 0.2), value: detections.count)
            }
        }
    }

    private func isTargetDetection(_ detection: VNRecognizedObjectObservation) -> Bool {
        guard let target = targetObject?.lowercased() else { return false }
        guard let label = detection.labels.first?.identifier.lowercased() else { return false }

        return label.contains(target) || target.contains(label)
    }

    private func convertVisionRect(_ visionRect: CGRect, to size: CGSize) -> CGRect {
        let x = visionRect.origin.x * size.width
        let y = (1 - visionRect.origin.y - visionRect.height) * size.height
        let width = visionRect.width * size.width
        let height = visionRect.height * size.height

        return CGRect(x: x, y: y, width: width, height: height)
    }
}

struct ARViewContainer: UIViewRepresentable {
    let session: ARSession

    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)
        arView.session = session
        return arView
    }

    func updateUIView(_ uiView: ARView, context: Context) {}
}
