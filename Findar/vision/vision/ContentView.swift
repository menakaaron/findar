//
//  ContentView.swift
//  vision
//
//  Created by Sweety on 1/24/26.
//

import SwiftUI
import RealityKit
import ARKit
import UIKit

struct ARViewContainer: UIViewRepresentable {
    let session: ARSession
    let navManager: VisionNavManager

    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)
        arView.session = session
        navManager.arView = arView
        return arView
    }

    func updateUIView(_ uiView: ARView, context: Context) {}
}

struct ContentView: View {
    @StateObject private var navManager = VisionNavManager()
    @StateObject private var speechManager = SpeechManager()
    @State private var searchText: String = ""
    @State private var showSearchBar: Bool = false
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        ZStack {
            ARViewContainer(session: navManager.arSession, navManager: navManager)
                .ignoresSafeArea()
                .onTapGesture {
                    dismissKeyboard()
                }

            VStack(spacing: 0) {
                statusBar
                    .padding(.top, 60)

                Spacer()

                if navManager.searchTarget != nil {
                    searchResultCard
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                bottomControls
                    .padding(.bottom, 40)
            }
            if navManager.isOnTarget && navManager.searchTarget == nil {
                indexingReticle
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: navManager.searchTarget)
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: showSearchBar)
        .onChange(of: speechManager.targetRequest) {
            if let query = speechManager.targetRequest {
                searchText = query
                navManager.searchForObject(named: query)
                showSearchBar = false
                dismissKeyboard()
            }
        }
    }

    private var statusBar: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Circle()
                    .fill(Color.green)
                    .frame(width: 6, height: 6)
                    .shadow(color: .green.opacity(0.6), radius: 4)

                Text(navManager.currentStatus.uppercased())
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundColor(.green)

                Spacer()

                HStack(spacing: 4) {
                    Image(systemName: "cube.fill")
                        .font(.system(size: 10))
                    Text("\(navManager.spatialIndex.count)")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                }
                .foregroundColor(.white.opacity(0.6))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.black.opacity(0.4))
            .background(.ultraThinMaterial.opacity(0.5))
            .clipShape(Capsule())

            if !navManager.debugInfo.isEmpty {
                Text(navManager.debugInfo)
                    .font(.system(size: 10, weight: .regular, design: .monospaced))
                    .foregroundColor(.white.opacity(0.5))
                    .lineLimit(2)
                    .padding(.horizontal, 14)
            }

            if let lastObject = navManager.lastDetectedObject {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.green)
                    Text("Found: \(lastObject)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white.opacity(0.7))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.green.opacity(0.2))
                .clipShape(Capsule())
            }

            if !navManager.spatialIndex.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(Array(navManager.spatialIndex.keys.sorted()), id: \.self) { key in
                            Text(key)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.white.opacity(0.7))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(.white.opacity(0.1))
                                .clipShape(Capsule())
                        }
                    }
                    .padding(.horizontal, 14)
                }
            }
        }
        .padding(.horizontal, 20)
    }

    private var searchResultCard: some View {
        Group {
            if let target = navManager.searchTarget {
                if navManager.searchResult != nil {
                    foundResultCard(for: target)
                } else {
                    notFoundCard(for: target)
                }
            }
        }
    }

    private func foundResultCard(for target: String) -> some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(LinearGradient(colors: [.green, .green.opacity(0.6)], startPoint: .leading, endPoint: .trailing))
                .frame(height: 4)

            VStack(spacing: 24) {
                ZStack {
                    Circle()
                        .fill(Color.green.opacity(0.15))
                        .frame(width: 70, height: 70)

                    Circle()
                        .stroke(Color.green.opacity(0.3), lineWidth: 1)
                        .frame(width: 70, height: 70)

                    Image(systemName: "location.fill")
                        .font(.system(size: 28))
                        .foregroundColor(.green)
                }
                .padding(.top, 8)

                VStack(spacing: 6) {
                    Text("Found your")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white.opacity(0.5))

                    Text(target.capitalized)
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                }

                if let hint = navManager.directionHint {
                    let lines = hint.split(separator: "\n")

                    VStack(spacing: 16) {
                        if let relativePart = lines.first {
                            HStack(spacing: 0) {
                                Text("It ")
                                    .foregroundColor(.white.opacity(0.7))
                                + Text(String(relativePart))
                                    .foregroundColor(.green)
                            }
                            .font(.system(size: 20, weight: .semibold, design: .rounded))
                        }
                        if lines.count > 1 {
                            HStack(spacing: 8) {
                                Image(systemName: directionIcon(for: String(lines[1])))
                                    .font(.system(size: 14))
                                Text(String(lines[1]))
                                    .font(.system(size: 13, weight: .medium))
                            }
                            .foregroundColor(.white.opacity(0.7))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(.white.opacity(0.1))
                            .clipShape(Capsule())
                        }
                    }
                }

                if let time = navManager.searchResultTime {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 6, height: 6)
                        Text("Indexed at \(time, formatter: timeFormatter)")
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                    }
                    .foregroundColor(.white.opacity(0.4))
                }

                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        navManager.clearSearch()
                        searchText = ""
                    }
                } label: {
                    Text("Done")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.green)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .padding(.top, 8)
            }
            .padding(24)
        }
        .background(Color.black.opacity(0.85))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.green.opacity(0.2), lineWidth: 1)
        )
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
    }

    private func notFoundCard(for target: String) -> some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(Color.orange.opacity(0.15))
                    .frame(width: 60, height: 60)

                Image(systemName: "eye.slash")
                    .font(.system(size: 24))
                    .foregroundColor(.orange)
            }

            VStack(spacing: 8) {
                Text("Haven't seen")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white.opacity(0.5))

                Text(target.capitalized)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundColor(.white)

                Text("Point your camera at it to index")
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.4))
                    .padding(.top, 4)
            }

            Button {
                withAnimation {
                    navManager.clearSearch()
                    searchText = ""
                }
            } label: {
                Text("Dismiss")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white.opacity(0.8))
                    .padding(.horizontal, 24)
                    .padding(.vertical, 10)
                    .background(.white.opacity(0.15))
                    .clipShape(Capsule())
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .background(Color.black.opacity(0.8))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.orange.opacity(0.2), lineWidth: 1)
        )
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
    }

    private var timeFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter
    }

    private var bottomControls: some View {
        VStack(spacing: 12) {
            if showSearchBar {
                // Search input
                HStack(spacing: 12) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.white.opacity(0.4))

                    TextField("What did you lose?", text: $searchText)
                        .font(.system(size: 16, weight: .regular))
                        .foregroundColor(.white)
                        .tint(.green)
                        .focused($isSearchFocused)
                        .submitLabel(.search)
                        .onSubmit {
                            submitSearch()
                        }

                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 18))
                                .foregroundColor(.white.opacity(0.4))
                        }
                    }

                    Button {
                        submitSearch()
                    } label: {
                        Image(systemName: "arrow.right.circle.fill")
                            .font(.system(size: 28))
                            .foregroundColor(searchText.isEmpty ? .white.opacity(0.2) : .green)
                    }
                    .disabled(searchText.isEmpty)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(.black.opacity(0.5))
                .background(.ultraThinMaterial.opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .padding(.horizontal, 20)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            HStack(spacing: 16) {
                if showSearchBar {
                    // Cancel button
                    Button {
                        withAnimation {
                            showSearchBar = false
                            searchText = ""
                            dismissKeyboard()
                        }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(.white.opacity(0.8))
                            .frame(width: 52, height: 52)
                            .background(.black.opacity(0.4))
                            .background(.ultraThinMaterial.opacity(0.5))
                            .clipShape(Circle())
                    }
                }

                if !showSearchBar {
                    Button {
                        withAnimation {
                            showSearchBar = true
                            isSearchFocused = true
                        }
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 18, weight: .semibold))
                            Text("Find Something")
                                .font(.system(size: 16, weight: .semibold))
                        }
                        .foregroundColor(.black)
                        .padding(.horizontal, 28)
                        .padding(.vertical, 16)
                        .background(
                            LinearGradient(
                                colors: [Color.green, Color.green.opacity(0.85)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .clipShape(Capsule())
                        .shadow(color: .green.opacity(0.4), radius: 12, y: 4)
                    }
                }

                Button {
                    speechManager.toggleListening()
                } label: {
                    ZStack {
                        Circle()
                            .fill(speechManager.isListening ? Color.red : Color.black.opacity(0.4))
                            .frame(width: 52, height: 52)
                            .background(.ultraThinMaterial.opacity(0.5))
                            .clipShape(Circle())

                        if speechManager.isListening {
                            // Pulsing ring when listening
                            Circle()
                                .stroke(Color.red.opacity(0.5), lineWidth: 2)
                                .frame(width: 52, height: 52)
                                .scaleEffect(speechManager.isListening ? 1.3 : 1.0)
                                .opacity(speechManager.isListening ? 0 : 1)
                                .animation(.easeOut(duration: 1.0).repeatForever(autoreverses: false), value: speechManager.isListening)
                        }

                        Image(systemName: speechManager.isListening ? "waveform" : "mic.fill")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundColor(.white)
                            .symbolEffect(.variableColor, isActive: speechManager.isListening)
                    }
                }
            }
        }
    }

    private var indexingReticle: some View {
        ZStack {
            Circle()
                .stroke(Color.green.opacity(0.3), lineWidth: 1)
                .frame(width: 160, height: 160)

            Circle()
                .stroke(Color.green.opacity(0.5), lineWidth: 1.5)
                .frame(width: 120, height: 120)

            ForEach(0..<4) { i in
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.green)
                    .frame(width: 20, height: 3)
                    .offset(x: 40)
                    .rotationEffect(.degrees(Double(i) * 90))
            }

            Circle()
                .fill(Color.green)
                .frame(width: 8, height: 8)
                .shadow(color: .green, radius: 8)

            Text("INDEXED")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(.green)
                .tracking(3)
                .offset(y: 100)
        }
    }

    private func submitSearch() {
        guard !searchText.isEmpty else { return }
        navManager.searchForObject(named: searchText)
        dismissKeyboard()
        withAnimation {
            showSearchBar = false
        }
    }

    private func dismissKeyboard() {
        isSearchFocused = false
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    private func directionIcon(for hint: String) -> String {
        if hint.contains("Ahead") {
            return "arrow.up.circle.fill"
        } else if hint.contains("Behind") {
            return "arrow.down.circle.fill"
        } else if hint.contains("right") {
            return "arrow.right.circle.fill"
        } else if hint.contains("left") {
            return "arrow.left.circle.fill"
        }
        return "scope"
    }
}
