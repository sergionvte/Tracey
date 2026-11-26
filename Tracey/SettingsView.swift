//
//  SettingsView.swift
//  Tracey
//
//  Time-lapse speed, app icon picker (colors and the Notebook special edition), help, support,
//  privacy and the app version. Icons are drawn by Tools/make-icons.swift.
//

import SwiftUI
import UIKit

/// What happens by itself when a new image is picked from Photos (both off by default)
enum OpenImageOptions {
    static let autoCropKey = "autoCropOnOpen"
    static let autoFitKey = "autoFitSheetOnOpen"

    static var autoCrop: Bool { UserDefaults.standard.bool(forKey: autoCropKey) }
    static var autoFit: Bool { UserDefaults.standard.bool(forKey: autoFitKey) }
}

enum AppIconChoice: String, CaseIterable, Identifiable {
    case amber, indigo, mint, rose, graphite, notebook

    var id: String { rawValue }

    /// Name of the alternate icon set, or nil for the primary icon
    var alternateName: String? {
        self == .amber ? nil : "AppIcon-" + rawValue.capitalized
    }

    /// App icon sets can't be loaded as images, so each has a small copy for this screen
    var previewImageName: String { "IconPreview-" + rawValue.capitalized }

    var isSpecialEdition: Bool { self == .notebook }

    var title: String {
        switch self {
        case .amber: String(localized: "Amber")
        case .indigo: String(localized: "Indigo")
        case .mint: String(localized: "Mint")
        case .rose: String(localized: "Rose")
        case .graphite: String(localized: "Graphite")
        case .notebook: String(localized: "Notebook")
        }
    }

    /// The choice for an icon name iOS reports; unknown names count as the primary icon
    init(alternateName: String?) {
        self = Self.allCases.first { $0.alternateName == alternateName } ?? .amber
    }

    static var colors: [AppIconChoice] { allCases.filter { !$0.isSpecialEdition } }
}

struct SettingsView: View {
    let onShowTour: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selected = AppIconChoice(alternateName: UIApplication.shared.alternateIconName)
    @State private var iconError = false
    @AppStorage(TimelapseSpeed.storageKey) private var timelapseSpeed = TimelapseSpeed.default
    @AppStorage(OpenImageOptions.autoCropKey) private var autoCrop = false
    @AppStorage(OpenImageOptions.autoFitKey) private var autoFit = false

    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "–"
        let build = info?["CFBundleVersion"] as? String ?? "–"
        return "\(short) (\(build))"
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Speed", selection: $timelapseSpeed) {
                        ForEach(TimelapseSpeed.allCases) { speed in
                            Text(speed.label).tag(speed)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.vertical, 4)
                    .onChange(of: timelapseSpeed) { _, _ in Haptics.light() }
                } header: {
                    Text("Time-Lapse Speed")
                } footer: {
                    Text("An hour of drawing becomes a \(timelapseSpeed.clipLengthPerHour) clip. Applies to your next recording.")
                }

                Section {
                    Toggle(isOn: $autoCrop) {
                        Label("Crop on Open", systemImage: "crop")
                    }
                    Toggle(isOn: $autoFit) {
                        Label("Fit to Sheet on Open", systemImage: "doc.viewfinder")
                    }
                } header: {
                    Text("When Opening an Image")
                } footer: {
                    Text("Only for new images from Photos. You can always use the buttons.")
                }

                Section {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 84), spacing: 12)], spacing: 16) {
                        ForEach(AppIconChoice.colors) { choice in
                            IconTile(choice: choice, isSelected: selected == choice) { apply(choice) }
                        }
                    }
                    .padding(.vertical, 8)
                } header: {
                    Text("App Icon")
                }

                Section {
                    SpecialEditionRow(choice: .notebook, isSelected: selected == .notebook) { apply(.notebook) }
                } header: {
                    Text("Special Edition")
                } footer: {
                    Text("Included with your purchase, like everything in Tracey.")
                }

                Section {
                    Button {
                        dismiss()
                        onShowTour()
                    } label: {
                        Label("How to Use Tracey", systemImage: "questionmark.circle")
                    }
                    Link(destination: AppLinks.support) {
                        Label("Support", systemImage: "envelope")
                    }
                    Link(destination: AppLinks.privacy) {
                        Label("Privacy Policy", systemImage: "hand.raised")
                    }
                }

                Section {
                    LabeledContent("Version", value: version)
                } footer: {
                    Text("No ads, no account, no tracking. Your images stay on your device.")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .alert("Couldn't change the icon", isPresented: $iconError) {
                Button("OK", role: .cancel) {}
            }
        }
        .tint(Theme.accent)
    }

    private func apply(_ choice: AppIconChoice) {
        guard choice != selected, UIApplication.shared.supportsAlternateIcons else { return }
        let previous = selected
        selected = choice
        Haptics.light()
        Task { @MainActor in
            do {
                try await UIApplication.shared.setAlternateIconName(choice.alternateName)
            } catch {
                selected = previous
                iconError = true
            }
        }
    }
}

private struct IconPreview: View {
    let choice: AppIconChoice
    let side: CGFloat

    var body: some View {
        Image(choice.previewImageName)
            .resizable()
            .frame(width: side, height: side)
            .clipShape(RoundedRectangle(cornerRadius: side * 0.225, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: side * 0.225, style: .continuous)
                    .strokeBorder(.primary.opacity(0.12), lineWidth: 0.5)
            }
            .accessibilityHidden(true)
    }
}

private struct IconTile: View {
    let choice: AppIconChoice
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                IconPreview(choice: choice, side: 64)
                    .padding(4)
                    .overlay {
                        RoundedRectangle(cornerRadius: 72 * 0.225 + 2, style: .continuous)
                            .strokeBorder(Theme.accent, lineWidth: 3)
                            .opacity(isSelected ? 1 : 0)
                    }
                Text(choice.title)
                    .font(.caption)
                    .foregroundStyle(isSelected ? .primary : .secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(choice.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct SpecialEditionRow: View {
    let choice: AppIconChoice
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                IconPreview(choice: choice, side: 60)
                VStack(alignment: .leading, spacing: 2) {
                    Text(choice.title)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text("Graph paper and a classic pencil")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? Theme.accent : Color.secondary)
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
