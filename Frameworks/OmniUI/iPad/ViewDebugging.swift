// Copyright 2021 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.


import Foundation
import SwiftUI

// Debugging helper that can be used in @ViewBuilders

extension View {
    public func Print(_ vars: Any...) -> some View {
        #if DEBUG
        for v in vars { print(v) }
        #endif
        return EmptyView()
    }
}

extension View {
    public func printValues(_ vars: Any...) -> some View {
        #if DEBUG
        for v in vars { Swift.print(v) }
        #endif
        return self
    }
}
