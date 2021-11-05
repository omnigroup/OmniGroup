// Copyright 2020 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

import Foundation
import SwiftUI

extension View {
    @ViewBuilder
    public func `if`<Transform: View>( _ condition: Bool, transform: (Self) -> Transform ) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
    
    @ViewBuilder
    public func `ifLet`<Transform: View, T: Any>( _ optional: T?, transform: (T, Self) -> Transform ) -> some View {
        if let instance = optional {
            transform(instance, self)
        } else {
            self
        }
    }
    
    @ViewBuilder
    public func `ifElse`<IfTransform: View, ElseTransform: View>( _ condition: Bool, ifTransform: (Self) -> IfTransform, elseTransform: (Self) -> ElseTransform ) -> some View {
        if condition {
            ifTransform(self)
        } else {
            elseTransform(self)
        }
    }
    
    @ViewBuilder
    public func `ifLetElse`<IfTransform: View, ElseTransform: View, T: Any>( _ optional: T?, ifTransform: (T, Self) -> IfTransform, elseTransform: (Self) -> ElseTransform ) -> some View {
        if let instance = optional {
            ifTransform(instance, self)
        } else {
            elseTransform(self)
        }
    }
}
