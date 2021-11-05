// Copyright 2021 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

import Foundation
import Combine

public enum OFPublisherDebugging {
#if DEBUG
    public static var loggingEnabled: Bool {
        return false
    }
#else
    @inlinable
    public static var loggingEnabled: Bool {
        return false
    }
#endif
}

#if DEBUG
public func OFPublisherDebugLog(_ message: @autoclosure () -> String) {
    if OFPublisherDebugging.loggingEnabled {
        print("🟪⬜️ " + message())
    }
}
#else
@inlinable
public func OFPublisherDebugLog(_ message: @autoclosure () -> String) {
}
#endif


@available(macOSApplicationExtension 10.15, *)
extension ObservableObjectPublisher {
#if DEBUG
    public func loggingSend(function: String = #function, file: String = #file, line: Int = #line) {
        OFPublisherDebugLog("\(function) \((file as NSString).lastPathComponent):\(line)")
        send()
    }
#else
    @inlinable
    public func loggingSend() {
        send()
    }
#endif
}

@available(macOSApplicationExtension 10.15, *)
extension PassthroughSubject {
#if DEBUG
    public func loggingSend(_ input: Output, function: String = #function, file: String = #file, line: Int = #line) {
        OFPublisherDebugLog("\(function) \((file as NSString).lastPathComponent):\(line) -- \(input)")
        send(input)
    }

    public func loggingSend(function: String = #function, file: String = #file, line: Int = #line) where Output == Void {
        OFPublisherDebugLog("\(function) \((file as NSString).lastPathComponent):\(line)")
        send()
    }
#else
    @inlinable
    public func loggingSend(_ input: Output) {
        send(input)
    }

    @inlinable
    public func loggingSend() where Output == Void {
        send()
    }
#endif
}

@available(macOSApplicationExtension 10.15, *)
extension CurrentValueSubject {
#if DEBUG
    public func loggingSend(_ input: Output, function: String = #function, file: String = #file, line: Int = #line) {
        OFPublisherDebugLog("\(function) \((file as NSString).lastPathComponent):\(line) -- \(input)")
        send(input)
    }
#else
    @inlinable
    public func loggingSend(_ input: Output) {
        send(input)
    }
#endif
}
