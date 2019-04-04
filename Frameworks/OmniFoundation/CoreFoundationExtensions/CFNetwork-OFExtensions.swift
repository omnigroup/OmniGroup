// Copyright 2018-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

import Foundation

public extension CFSocket {
    
    var socketFlags : CFOptionFlags {
        get {
            return CFSocketGetSocketFlags(self)
        }
        set {
            return CFSocketSetSocketFlags(self, newValue)
        }
    }
    
    func enableCallBacks(_ cb: CFSocketCallBackType) {
        CFSocketEnableCallBacks(self, cb.rawValue)
    }
    
    func disableCallBacks(_ cb: CFSocketCallBackType) {
        CFSocketDisableCallBacks(self, cb.rawValue)
    }
    
    func invalidate() {
        CFSocketInvalidate(self)
    }
    
    var fileDescriptor : CInt {
        get {
            return CFSocketGetNative(self)
        }
    }
}


fileprivate func fdCallbackToSwift(cfref: CFFileDescriptor?, events: CFOptionFlags, context: UnsafeMutableRawPointer?) -> Void {
    let callBack : CFFileDescriptor.CallBack = ( Unmanaged<AnyObject>.fromOpaque(context!) ).takeUnretainedValue() as! CFFileDescriptor.CallBack
    callBack(cfref!, CFFileDescriptor.CallBackReason(rawValue: events))
}

public extension CFFileDescriptor {
    
    struct CallBackReason: OptionSet {
        public typealias RawValue = CFOptionFlags
        public let rawValue: RawValue
        public init(rawValue: RawValue) {
            self.rawValue = rawValue
        }

        public static let read = CallBackReason(rawValue: kCFFileDescriptorReadCallBack)
        public static let write = CallBackReason(rawValue: kCFFileDescriptorWriteCallBack)
    }
    
    typealias CallBack = (CFFileDescriptor, CallBackReason) -> Void;
    
    class func withDescriptor(_ fd: CInt, callBacks: @escaping CFFileDescriptor.CallBack) -> CFFileDescriptor {
        
        let info = Unmanaged.passRetained(callBacks as AnyObject)
        defer {
            info.release();
        }
        
        var context = CFFileDescriptorContext(version: 0,
                                              info: info.toOpaque(),
                                              retain: { ifo in UnsafeMutableRawPointer(Unmanaged<AnyObject>.fromOpaque(ifo!).retain().toOpaque())},
                                              release: { ifo in Unmanaged<AnyObject>.fromOpaque(ifo!).release() },
                                              copyDescription: nil);
        
        return CFFileDescriptorCreate(kCFAllocatorDefault, fd, true, fdCallbackToSwift, &context);
    }
    
    func enableCallBacks(_ cb: CallBackReason) {
        CFFileDescriptorEnableCallBacks(self, cb.rawValue)
    }
    
    func disableCallBacks(_ cb: CallBackReason) {
        CFFileDescriptorDisableCallBacks(self, cb.rawValue)
    }
    
    func invalidate() {
        CFFileDescriptorInvalidate(self)
    }
    
    var fileDescriptor : CInt {
        get {
            return CFFileDescriptorGetNativeDescriptor(self)
        }
    }
}
