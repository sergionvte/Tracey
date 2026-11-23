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
    /// Tallest the card may be (the screen); pages scroll inside if they don't fit
    var maxHeight: CGFloat = .infinity
    /// Matches the welcome card's height so the crossfade doesn't jump
    var minHeight: CGFloat = 0
    /// Reports the card's own height (before `minHeight`)
    var onNaturalHeight: (CGFloat) -> Void = { _ in }

    struct Page {
        let symbol: String
        let title: String
        let body: String
    }

    static let pages: [Page] = [
        Page(symbol: "photo.on.rectangle.angled",
             title: String(localized: "Trace anything"),
             body: String(localized: "Pick an image. It floats over your camera view so you can follow its lines on paper.")),
        Page(symbol: "iphone.gen3",
             title: String(localized: "Set up your phone"),
             body: String(localized: "Hold it steady 20–40 cm above the paper. A stand, a glass or a stack of books works well.")),
        Page(symbol: "lock.fill",
             title: String(localized: "Place it, then lock"),
             body: String(localized: "Drag, pinch and rotate the image to fit your paper, then tap Lock. Tap the screen to hide the controls.")),
        Page(symbol: "timelapse",
             title: String(localized: "Record & refine"),
             body: String(localized: "Record a time-lapse of your drawing, and try the Outline filter to see the lines more clearly."))
    ]

    private var isLastPage: Bool { page >= Self.pages.count - 1 }

    /// Icon circle grows with the text, up to a point
    @ScaledMetric(relativeTo: .title2) private var scaledIcon: CGFloat = 76
    private var iconSize: CGFloat { min(scaledIcon, 108) }

    /// Height of the tallest page at the current text size
    @State private var tallestPage: CGFloat = 0
    /// Dots + main button
    @State private var footerHeight: CGFloat = 0

    /// Room for Skip above the pages (grows with the text size)
    @ScaledMetric(relativeTo: .subheadline) private var topPadding: CGFloat = 34
    private let bottomPadding: CGFloat = 24
    private let spacing: CGFloat = 18

    /// The paging area fits the tallest page, unless the card would outgrow the screen
    private var pageAreaHeight: CGFloat {
        let room = maxHeight - topPadding - bottomPadding - spacing - footerHeight
        return max(120, min(tallestPage, room))
    }

    var body: some View {
        VStack(spacing: spacing) {
            TabView(selection: $page) {
                ForEach(Self.pages.indices, id: \.self) { index in
                    // Scrolls only when the text is too large for the card
                    ScrollView {
                        pageView(index)
                    }
                    .scrollBounceBehavior(.basedOnSize)
                    .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: pageAreaHeight)
            // Measure every page at its natural height (hidden), so the area fits the tallest
            .background {
                ZStack {
                    ForEach(Self.pages.indices, id: \.self) { index in
                        pageView(index).fixedSize(horizontal: false, vertical: true)
                    }
                }
                .hidden()
                .accessibilityHidden(true)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { tallestPage = $0 }
            }

            VStack(spacing: spacing) {
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
                    Text(isLastPage ? String(localized: "Get Started") : String(localized: "Next"))
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.black)
                        .multilineTextAlignment(.center)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 52)
                        .background(Theme.accent, in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { footerHeight = $0 }
        }
        .padding(.horizontal, 24)
        .padding(.top, topPadding)
        .padding(.bottom, bottomPadding)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { onNaturalHeight($0) }
        .frame(maxWidth: 360, minHeight: minHeight)
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
                    .frame(width: iconSize, height: iconSize)
                Image(systemName: item.symbol)
                    .font(.system(size: iconSize * 32 / 76, weight: .semibold))
                    .foregroundStyle(Theme.accent)
            }

            VStack(spacing: 8) {
                Text(item.title)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Text(item.body)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Page \(index + 1) of \(Self.pages.count). \(item.title). \(item.body)")
    }
}
