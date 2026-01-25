//
//  SplashView.swift
//  vision
//
//  Created by Sweety on 1/24/26.
//

import SwiftUI

struct SplashView: View {
    @State private var ring1 = false
    @State private var ring2 = false
    @State private var ring3 = false
    @State private var showTitle = false
    @State private var showSubtitle = false
    @State private var iconScale: CGFloat = 0.5
    @State private var iconOpacity: Double = 0

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            ZStack {
                Circle()
                    .stroke(Color.green.opacity(0.15), lineWidth: 1.5)
                    .frame(width: 280, height: 280)
                    .scaleEffect(ring3 ? 1.0 : 0.3)
                    .opacity(ring3 ? 0.0 : 0.8)
                Circle()
                    .stroke(Color.green.opacity(0.25), lineWidth: 1.5)
                    .frame(width: 200, height: 200)
                    .scaleEffect(ring2 ? 1.0 : 0.3)
                    .opacity(ring2 ? 0.0 : 0.8)
                Circle()
                    .stroke(Color.green.opacity(0.4), lineWidth: 2)
                    .frame(width: 120, height: 120)
                    .scaleEffect(ring1 ? 1.0 : 0.3)
                    .opacity(ring1 ? 0.0 : 0.8)

                ZStack {
                    Circle()
                        .fill(Color.green.opacity(0.1))
                        .frame(width: 80, height: 80)

                    Image(systemName: "eye.fill")
                        .font(.system(size: 32, weight: .medium))
                        .foregroundColor(.green)
                }
                .scaleEffect(iconScale)
                .opacity(iconOpacity)
            }
            .offset(y: -40)

            VStack(spacing: 8) {
                Spacer()

                Text("Findar")
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .opacity(showTitle ? 1 : 0)
                    .offset(y: showTitle ? 0 : 20)

                Text("Find anything, anywhere")
                    .font(.system(size: 15, weight: .regular, design: .rounded))
                    .foregroundColor(.white.opacity(0.5))
                    .opacity(showSubtitle ? 1 : 0)
                    .offset(y: showSubtitle ? 0 : 10)

                Spacer()
                    .frame(height: 160)
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
                iconScale = 1.0
                iconOpacity = 1.0
            }
            withAnimation(.easeOut(duration: 1.2).delay(0.3)) {
                ring1 = true
            }
            withAnimation(.easeOut(duration: 1.4).delay(0.5)) {
                ring2 = true
            }
            withAnimation(.easeOut(duration: 1.6).delay(0.7)) {
                ring3 = true
            }
            withAnimation(.easeOut(duration: 0.6).delay(0.6)) {
                showTitle = true
            }
            withAnimation(.easeOut(duration: 0.6).delay(0.9)) {
                showSubtitle = true
            }
        }
    }
}
