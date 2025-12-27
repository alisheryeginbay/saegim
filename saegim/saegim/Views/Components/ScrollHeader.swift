//
//  ScrollHeader.swift
//  saegim
//
//  Blur header that appears when content scrolls
//

import SwiftUI

struct ScrollHeader<Content: View>: View {
    let title: String
    @ViewBuilder var content: () -> Content

    @State private var scrollOffset: CGFloat = 0

    private var showBlur: Bool {
        scrollOffset < -10
    }

    var body: some View {
        ZStack(alignment: .top) {
            // Scrollable content
            ScrollView {
                VStack(spacing: 0) {
                    // Invisible offset tracker
                    GeometryReader { geometry in
                        Color.clear
                            .preference(
                                key: ScrollOffsetPreferenceKey.self,
                                value: geometry.frame(in: .named("scroll")).minY
                            )
                    }
                    .frame(height: 0)

                    content()
                }
            }
            .coordinateSpace(name: "scroll")
            .onPreferenceChange(ScrollOffsetPreferenceKey.self) { value in
                scrollOffset = value
            }

            // Blur header overlay
            if showBlur {
                VStack(spacing: 0) {
                    Rectangle()
                        .fill(.ultraThinMaterial)
                        .frame(height: 52)
                        .overlay(alignment: .bottom) {
                            Divider()
                        }

                    Spacer()
                }
                .ignoresSafeArea()
                .allowsHitTesting(false)
                .transition(.opacity.animation(.easeInOut(duration: 0.15)))
            }
        }
        .navigationTitle(title)
        .animation(.easeInOut(duration: 0.15), value: showBlur)
    }
}

private struct ScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

#Preview {
    NavigationStack {
        ScrollHeader(title: "Test") {
            VStack(spacing: 16) {
                ForEach(0..<50) { i in
                    Text("Item \(i)")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(.quaternary)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
            .padding()
        }
    }
}
