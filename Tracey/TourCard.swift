//
//  TourCard.swift
//  Tracey
//
//  First-launch tour: four short pages in a card styled like the welcome card. Shown instead of
//  the welcome card on first launch, and again from "How Tracey works" / "How to Use Tracey".
//

import SwiftUI

struct TourCard: View {
    @Binding var page: Int
    /// Skip or Get Started
    let onFinish: () -> Void

    struct Page {
        let symbol: String
        let title: String
        let body: String
    }

    static let pages: [Page] = [
        Page(symbol: "photo.on.rectangle.angled",
             title: "Trace anything",
             body: "Pick an image. It floats over your camera view so you can follow its lines on paper."),
        Page(symbol: "iphone.gen3",
             title: "Set up your phone",
             body: "Hold it steady 20–40 cm above the paper. A stand, a glass or a stack of books works well."),
        Page(symbol: "lock.fill",
             title: "Place it, then lock",
             body: "Drag, pinch and rotate the image to fit your paper, then tap Lock. Tap the screen to hide the controls."),
        Page(symbol: "timelapse",
             title: "Record & refine",
             body: "Record a time-lapse of your drawing, and try the Outline filter to see the lines more clearly.")
    ]

    private var isLastPage: Bool { page >= Self.pages.count - 1 }

    var body: some View {
        VStack(spacing: 18) {
            TabView(selection: $page) {
                ForEach(Self.pages.indices, id: \.self) { index in
                    pageView(index)
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: 212)

            // Page dots
            HStack(spacing: 8) {
                ForEach(Self.pages.indices, id: \.self) { index in
                    Circle()
                        .fill(index == page ? Theme.accent : Color.white.opacity(0.3))
                        .frame(width: 6, height: 6)
                }
            }
            .accessibilityHidden(true)

            Button {
                if isLastPage {
                    onFinish()
                } else {
                    withAnimation(Theme.spring) { page += 1 }
                }
            } label: {
                Text(isLastPage ? "Get Started" : "Next")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(Theme.accent, in: Capsule())
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 24)
        .padding(.top, 34)
        .padding(.bottom, 24)
        .frame(maxWidth: 360)
        .overlay(alignment: .topTrailing) {
            Button(action: onFinish) {
                Text("Skip")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.8))
                    .padding(.horizontal, 12)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(8)
            .accessibilityLabel("Skip tour")
        }
        .glassSurface(RoundedRectangle(cornerRadius: 34, style: .continuous))
        // Taps on the card must not reach anything underneath
        .contentShape(RoundedRectangle(cornerRadius: 34, style: .continuous))
        .onTapGesture {}
        .animation(Theme.spring, value: page)
    }

    private func pageView(_ index: Int) -> some View {
        let item = Self.pages[index]
        return VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(Theme.accent.opacity(0.18))
                    .frame(width: 76, height: 76)
                Image(systemName: item.symbol)
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundStyle(Theme.accent)
            }

            VStack(spacing: 8) {
                Text(item.title)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                Text(item.body)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Page \(index + 1) of \(Self.pages.count). \(item.title). \(item.body)")
    }
}
