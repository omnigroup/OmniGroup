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

#if DEBUG
private var randomGenerator = SystemRandomNumberGenerator()
#endif

extension View {
    public func printValues(_ vars: Any...) -> some View {
        #if DEBUG
        for v in vars { Swift.print(v) }
        let strings = vars.map { String(describing: $0) }
        return self
            .background(
                Text(verbatim: strings.joined(separator: ","))
                    .foregroundColor(.clear)
        )
        #else
        self
        #endif
    }
    public func randomColorBorder() -> some View {
        #if DEBUG
        self
            .border(Color(hue: Double(randomGenerator.next() % 1000) / 1000, saturation: 0.5, brightness: 1.0))
        #else
        self
        #endif
    }
}
