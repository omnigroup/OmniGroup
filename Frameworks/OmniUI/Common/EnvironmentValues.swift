// Copyright 2020-2021 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

import Foundation
import SwiftUI

// Helpers to ensure that we don't put things in the environment that are non-comparable and generate spurious body evaluations of Views

extension View {
    @inlinable
    public func equatableEnvironment<Value : Equatable>(_ keyPath: WritableKeyPath<EnvironmentValues, Value>, _ value: Value) -> some View {
        self.environment(keyPath, value)
    }
    @inlinable
    public func equatableEnvironment<Value : Equatable>(_ keyPath: WritableKeyPath<EnvironmentValues, Value?>, _ value: Value?) -> some View {
        self.environment(keyPath, value)
    }
    @inlinable
    public func objectEnvironment<Value : AnyObject>(_ keyPath: WritableKeyPath<EnvironmentValues, Value>, _ value: Value) -> some View {
        self.environment(keyPath, value)
    }
    @inlinable
    public func objectEnvironment<Value : AnyObject>(_ keyPath: WritableKeyPath<EnvironmentValues, Value?>, _ value: Value?) -> some View {
        self.environment(keyPath, value)
    }
}
