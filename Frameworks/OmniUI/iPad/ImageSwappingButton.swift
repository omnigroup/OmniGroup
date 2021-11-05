// Copyright 2020-2021 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

import Foundation
import SwiftUI

// A simple button that shows one of two images, depending on whether or not the button is pressed.
public struct ImageSwappingButton: OUIView {
    
    public let normalImage: UIImage
    public let alternateImage: UIImage
    public let action: () -> Void
    
    public init(normalImage: UIImage, alternateImage: UIImage, action: @escaping ()-> Void) {
        self.normalImage = normalImage
        self.alternateImage = alternateImage
        self.action = action
    }
    
    public var oui_body: some View {
        Button(action: action) {
            EmptyView()
        }.buttonStyle(ImageSwappingButtonStyle(normalImage: normalImage, alternateImage: alternateImage))
    }
}

struct ImageSwappingButtonStyle: ButtonStyle {
    
    let normalImage: UIImage
    let alternateImage: UIImage
    
    func makeBody(configuration: Configuration) -> some View {
        if configuration.isPressed {
            return Image(uiImage: alternateImage)
        } else {
            return Image(uiImage: normalImage)
        }
    }
    
}
