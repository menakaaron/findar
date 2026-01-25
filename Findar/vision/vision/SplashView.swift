//
//  SplashView.swift
//  vision
//
//  Created by Sweety on 1/24/26.
//

import SwiftUI

struct SplashView: View {
    @State private var ringScale: CGFloat = 0.5
    @State private var ringOpacity: Double = 0.8
    @State private var iconScale: CGFloat = 0.5
    @State private var iconOpacity: Double = 0
    @State private var textOpacity: Double = 0
    @State private var textOffset: CGFloat = 20

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 0) {
                Spacer()
                ZStack {
                    ForEach(0..<3) { i in
                        Circle()
                            .stroke(
                                Color.green.opacity(0.15 + Double(i) * 0.1),
                                lineWidth: 1.5
                            )
                            .frame(width: CGFloat(200 - i * 50), height: CGFloat(200 - i * 50))
                            .scaleEffect(ringScale)
                            .opacity(ringOpacity)
                    }

                    ZStack {
                        Circle()
                            .fill(Color.green.opacity(0.15))
                            .frame(width: 80, height: 80)

                        Image(systemName: "scope")
                            .font(.system(size: 36, weight: .light))
                            .foregroundColor(.green)
                    }
                    .scaleEffect(iconScale)
                    .opacity(iconOpacity)
                }

                Spacer()
                    .frame(height: 60)

                VStack(spacing: 8) {
                    Text("Findar")
                        .font(.system(size: 42, weight: .bold, design: .rounded))
                        .foregroundColor(.white)

                    Text("Remember where everything is")
                        .font(.system(size: 15, weight: .regular, design: .rounded))
                        .foregroundColor(.white.opacity(0.4))
                }
                .opacity(textOpacity)
                .offset(y: textOffset)

                Spacer()
                Spacer()
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.8, dampingFraction: 0.6)) {
                iconScale = 1.0
                iconOpacity = 1.0
            }

            withAnimation(.easeOut(duration: 1.5).delay(0.2)) {
                ringScale = 1.3
                ringOpacity = 0
            }

            withAnimation(.easeOut(duration: 0.6).delay(0.4)) {
                textOpacity = 1
                textOffset = 0
            }
        }
    }
}
