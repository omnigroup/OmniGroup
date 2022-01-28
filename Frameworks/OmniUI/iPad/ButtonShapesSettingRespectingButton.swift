// Copyright 2021 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

import SwiftUI

// FB9589088: Enabling the Accessibility "Button Shapes" setting causes buttons with custom labels to grow larger than their content
// Enabling this setting causes a button with a label specified by a closure to grow larger than the size of the content specified by the closure. This view mimics the behavior and visual style of a button both with and without that setting enabled, but prevents the button from growing larger when the accessibility setting becomes enabled.
// The drawback here is that the ButtonShapesSettingRespectingButton becomes entirely hidden from all other accessibility features. This is not a problem in OF, where these buttons are used in a hierarchy that requires custom labels and actions anyway, but should be noted in case this proves useful in another context.

public struct ButtonShapesSettingRespectingButton<Label: View>: OUIView {
    
    @State private var isPressed: Bool = false
    
    private let label: ()->Label
    private let action: ()->Void
    
    public init(action: @escaping ()->Void, @ViewBuilder label: @escaping ()->Label) {
        self.label = label
        self.action = action
    }
    
    @Environment(\.accessibilityShowButtonShapes) var showingButtonShapes
    
    public var oui_body: some View {
        label()
            .foregroundColor(Color.accentColor)
            .opacity(isPressed ? 0.5 : 1.0)
            .overlay(
                // This overlay button is the thing that actually intercepts the taps. Its custom button style prevents it from drawing a Button Shape.
                Button(action: action) {
                    Rectangle()
                        .foregroundColor(almostClearColor)
                }
                    .buttonStyle(IsPressedUpdatingButtonStyle(isPressed: $isPressed))
            )
            .background(
                // This background button is just here to draw the accessibility button shape, and will never be tapped as the overlay button will intercept taps first.
                Group {
                    if showingButtonShapes {
                        Button(action: {}, label: { Color.clear })
                    }
                }
            )
        // A system SwiftUI button with a custom view for its label does not interact well with accessibility already- it's up to callers to provide accessibility content for this element.
            .accessibilityHidden(true)
    }
}

private struct IsPressedUpdatingButtonStyle: ButtonStyle {
    @Binding var isPressed: Bool
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .onAppear(perform: { isPressed = configuration.isPressed })
            .loggingOnChange(of: configuration.isPressed, perform: { newValue in isPressed = newValue })
    }
}

fileprivate let almostClearColor = Color("OUIAlmostClearColor", bundle: OmniUIBundle)
