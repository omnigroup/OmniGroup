// Copyright 2020-2022 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

import Foundation
import SwiftUI

/*
 Use these modifiers with caution! Wherever they are used, they are equivalent to an inline if-else. This means in a situation like this:
 
 var body: some View {
    MyView()
        .if(condition) { view in
            view.background(Color.blue)
        }
 }
 
 You are really writing this:
 
 
 var body: some View {
    if condition {
        MyView().background(Color.blue)
    } else {
        MyView()
    }
 }
 
 You are potentially returning two *different* views using that modifier, even though it only looks like one view is initialized in the original code. If you modify an @State variable in one and then `condition` changes, that @State change will *not* be carried over to the view in the other branch of the conditional.
 
 */
extension View {
    @ViewBuilder
    public func `if`<Transform: View>( _ condition: Bool, @ViewBuilder transform: (Self) -> Transform ) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
    
    @ViewBuilder
    public func `ifLet`<Transform: View, T: Any>( _ optional: T?, @ViewBuilder transform: (T, Self) -> Transform ) -> some View {
        if let instance = optional {
            transform(instance, self)
        } else {
            self
        }
    }
    
    @ViewBuilder
    public func `ifElse`<IfTransform: View, ElseTransform: View>( _ condition: Bool, @ViewBuilder ifTransform: (Self) -> IfTransform, @ViewBuilder elseTransform: (Self) -> ElseTransform ) -> some View {
        if condition {
            ifTransform(self)
        } else {
            elseTransform(self)
        }
    }
    
    @ViewBuilder
    public func `ifLetElse`<IfTransform: View, ElseTransform: View, T: Any>( _ optional: T?, @ViewBuilder ifTransform: (T, Self) -> IfTransform, @ViewBuilder elseTransform: (Self) -> ElseTransform ) -> some View {
        if let instance = optional {
            ifTransform(instance, self)
        } else {
            elseTransform(self)
        }
    }

    public func assertNotReached(_ message: String) -> Self {
        Swift.assertionFailure(message)
        return self
    }
}

/*

 UIViewRepresentable views do not receive taps via .onTapGesture (presumably since the UIView can just add its own gestures.

 BUT! if the containing View has an .onTapGesture, it will be invoked on the container view. This seems like a bug, but we can work around this here.

 */

#if os(iOS)
extension UIViewRepresentable {

    @ViewBuilder
    public var captureTapGesture: some View {
        Group {
            self
        }.onTapGesture {
            // Tap captured by the Group, being the closest container
        }
    }
}
#endif
