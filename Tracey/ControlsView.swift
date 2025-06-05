//
//  ControlsView.swift
//  DrawingReference
//
//  Created by Sergio Navarrete on 31/05/25.
//

// ControlsView.swift - With animated hamburger menu and minimalist design
import SwiftUI

struct ControlsView: View {
    @ObservedObject var viewModel: CameraViewModel
    @Binding var showingImagePicker: Bool
    @Binding var showingImageControls: Bool
    let isPropertiesLocked: Bool
    @State private var showingSaveAlert = false
    @State private var saveSuccess = false
    @State private var isMenuExpanded = false

    var body: some View {
        VStack(spacing: 20) {
            ZStack {
                // Menu buttons - appear in a perfect circle around the main button
                if isMenuExpanded {
                    //let radius: CGFloat = 85
                    let radius: CGFloat = 70
                    let angleStep: CGFloat = .pi / 3 // 60 degrees between each button

                    // Select image button (position 0° - top)
                    Button(action: {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                            isMenuExpanded = false
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                            showingImagePicker = true
                        }
                    }) {
                        Image(systemName: "photo")
                            .font(.title2)
                            .foregroundColor(.white)
                            .frame(width: 45, height: 45)
                            .background(Color.blue)
                            .clipShape(Circle())
                            .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
                            .accessibilityLabel("Select Image")
                    }
                    .offset(
                        x: radius * sin(0),
                        y: -radius * cos(0)
                    )
                    .scaleEffect(isMenuExpanded ? 1.0 : 0.1)
                    .opacity(isMenuExpanded ? 1.0 : 0.0)
                    .animation(.spring(response: 0.4, dampingFraction: 0.7).delay(0.1), value: isMenuExpanded)

                    // View saved images button (position 60° - top right)
                    Button(action: {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                            isMenuExpanded = false
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                            viewModel.showingSavedImages = true
                        }
                    }) {
                        Image(systemName: "folder")
                            .font(.title2)
                            .foregroundColor(.white)
                            .frame(width: 45, height: 45)
                            .background(Color.green)
                            .clipShape(Circle())
                            .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
                            .accessibilityLabel("View Saved Images")
                    }
                    .offset(
                        x: radius * sin(angleStep),
                        y: -radius * cos(angleStep)
                    )
                    .scaleEffect(isMenuExpanded ? 1.0 : 0.1)
                    .opacity(isMenuExpanded ? 1.0 : 0.0)
                    .animation(.spring(response: 0.4, dampingFraction: 0.7).delay(0.15), value: isMenuExpanded)

                    // Additional buttons when there is an image
                    if viewModel.overlayImage != nil {
                        // Image controls button (position 120° - bottom right)
                        Button(action: {
                            if isPropertiesLocked {
                                // Consume tap but do nothing and do not hide the interface
                                return
                            }
                            // Close main menu with smooth animation
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                isMenuExpanded = false
                            }
                            // Wait for the close animation to finish before opening properties
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                withAnimation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.1)) {
                                    showingImageControls = true
                                }
                            }
                        }) {
                            Image(systemName: showingImageControls ? "slider.horizontal.below.rectangle" : "slider.horizontal.3")
                                .font(.title2)
                                .foregroundColor(.white)
                                .frame(width: 45, height: 45)
                                .background(isPropertiesLocked ? Color.gray.opacity(0.5) : (showingImageControls ? Color.yellow : Color.gray))
                                .clipShape(Circle())
                                .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
                                .accessibilityLabel("Image Controls")
                        }
                        .offset(
                            x: radius * sin(angleStep * 2),
                            y: -radius * cos(angleStep * 2)
                        )
                        .scaleEffect(isMenuExpanded ? 1.0 : 0.1)
                        .opacity(isMenuExpanded ? (isPropertiesLocked ? 0.6 : 1.0) : 0.0)
                        .animation(.spring(response: 0.4, dampingFraction: 0.7).delay(0.2), value: isMenuExpanded)
                        .disabled(false)

                        // Center image button (position 180° - bottom)
                        Button(action: {
                            if isPropertiesLocked {
                                // Consume tap but do nothing and do not hide the interface
                                return
                            }
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                isMenuExpanded = false
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                                viewModel.centerImage()
                            }
                        }) {
                            Image(systemName: "scope")
                                .font(.title2)
                                .foregroundColor(.white)
                                .frame(width: 45, height: 45)
                                .background(isPropertiesLocked ? Color.gray.opacity(0.5) : Color.purple)
                                .clipShape(Circle())
                                .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
                                .accessibilityLabel("Center Image")
                        }
                        .offset(
                            x: radius * sin(angleStep * 3),
                            y: -radius * cos(angleStep * 3)
                        )
                        .scaleEffect(isMenuExpanded ? 1.0 : 0.1)
                        .opacity(isMenuExpanded ? (isPropertiesLocked ? 0.6 : 1.0) : 0.0)
                        .animation(.spring(response: 0.4, dampingFraction: 0.7).delay(0.25), value: isMenuExpanded)
                        .disabled(false)

                        // Save button (position 240° - bottom left)
                        Button(action: {
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                isMenuExpanded = false
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                                saveSuccess = viewModel.saveCurrentConfiguration()
                                showingSaveAlert = true
                            }
                        }) {
                            Image(systemName: "square.and.arrow.down")
                                .font(.title2)
                                .foregroundColor(.white)
                                .frame(width: 45, height: 45)
                                .background(Color.orange)
                                .clipShape(Circle())
                                .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
                                .accessibilityLabel("Save Image")
                        }
                        .offset(
                            x: radius * sin(angleStep * 4),
                            y: -radius * cos(angleStep * 4)
                        )
                        .scaleEffect(isMenuExpanded ? 1.0 : 0.1)
                        .opacity(isMenuExpanded ? 1.0 : 0.0)
                        .animation(.spring(response: 0.4, dampingFraction: 0.7).delay(0.3), value: isMenuExpanded)

                        // Clear image button (position 300° - top left)
                        Button(action: {
                            if isPropertiesLocked {
                                // Consume tap but do nothing and do not hide the interface
                                return
                            }
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                isMenuExpanded = false
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                                viewModel.removeOverlayImage()
                                // Close properties smoothly when the image is removed
                                withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                                    showingImageControls = false
                                }
                            }
                        }) {
                            Image(systemName: "trash")
                                .font(.title2)
                                .foregroundColor(.white)
                                .frame(width: 45, height: 45)
                                .background(isPropertiesLocked ? Color.gray.opacity(0.5) : Color.red)
                                .clipShape(Circle())
                                .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
                                .accessibilityLabel("Clear Image")
                        }
                        .offset(
                            x: radius * sin(angleStep * 5),
                            y: -radius * cos(angleStep * 5)
                        )
                        .scaleEffect(isMenuExpanded ? 1.0 : 0.1)
                        .opacity(isMenuExpanded ? (isPropertiesLocked ? 0.6 : 1.0) : 0.0)
                        .animation(.spring(response: 0.4, dampingFraction: 0.7).delay(0.35), value: isMenuExpanded)
                        .disabled(false)

                    }
                }

                // Main button (hamburger/close)
                Button(action: {
                    // If the image controls menu is open, close it and open the main menu
                    if showingImageControls {
                        // Close image controls menu with smooth transition
                        withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                            showingImageControls = false
                        }
                        // Open the main menu after closing image controls with perfect timing
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                            withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
                                isMenuExpanded = true
                            }
                        }
                    } else {
                        // Toggle main menu with improved animation
                        withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
                            isMenuExpanded.toggle()
                        }
                    }
                }) {
                    ZStack {
                        // Button background with dynamic gradient and smooth transitions
                        Circle()
                            .fill(
                                LinearGradient(
                                    gradient: Gradient(colors: [
                                        showingImageControls ? Color.pink : (isMenuExpanded ? Color.pink : Color.blue),
                                        showingImageControls ? Color.pink.opacity(0.8) : (isMenuExpanded ? Color.pink.opacity(0.8) : Color.blue.opacity(0.8))
                                    ]),
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 60, height: 60)
                            .shadow(color: .black.opacity(0.4), radius: 6, x: 0, y: 3)
                            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: showingImageControls)
                            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: isMenuExpanded)

                        // Icon that changes according to the context with improved transitions
                        Image(systemName: showingImageControls ? "xmark" : (isMenuExpanded ? "xmark" : "ellipsis"))
                            .font(.title)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                            .rotationEffect(.degrees(showingImageControls ? 0 : (isMenuExpanded ? 180 : 0)))
                            .scaleEffect(showingImageControls ? 1.2 : (isMenuExpanded ? 1.1 : 1.0))
                            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: showingImageControls)
                            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: isMenuExpanded)
                    }
                }
                .scaleEffect(showingImageControls ? 1.2 : (isMenuExpanded ? 1.1 : 1.0))
                .animation(.spring(response: 0.4, dampingFraction: 0.8), value: showingImageControls)
                .animation(.spring(response: 0.4, dampingFraction: 0.8), value: isMenuExpanded)

                // Blurred background when the menu is open - with improved transition
                if isMenuExpanded {
                    Circle()
                        .fill(Color.black.opacity(0.08))
                        //.fill(Color.black.opacity(0))
                        .frame(width: 220, height: 220)
                        .scaleEffect(isMenuExpanded ? 1.0 : 0.1)
                        .opacity(isMenuExpanded ? 1.0 : 0.0)
                        .animation(.spring(response: 0.5, dampingFraction: 0.8), value: isMenuExpanded)
                        .allowsHitTesting(false)
                        .zIndex(-1)
                }
            }
        }
        .padding(.bottom, 50)
        // Observe changes in showingImageControls to close the main menu with a smooth transition
        .onChange(of: showingImageControls) { oldValue, newValue in
            if newValue && isMenuExpanded {
                // If the image controls menu is opened and the main menu is open, close the main menu smoothly
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    isMenuExpanded = false
                }
            }
        }
        .alert("Save Image", isPresented: $showingSaveAlert) {
            Button("OK") {
                showingImageControls = false // Ensures the main menu can be opened after saving
            }
        } message: {
            Text(saveSuccess ? "Image saved successfully" : "Error saving image")
        }
    }
}
