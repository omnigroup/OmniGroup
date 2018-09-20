// Copyright 2018 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

public extension Data {
    
    /** RFC4648 Base64 URL variant encoding uses only url-safe characters (_ and - instead of / and +), and does not include the trailing padding. */
    func base64URLEncodedData() -> Data {
        var b64m = self.base64EncodedData()
        for i in b64m.startIndex ..< b64m.endIndex {
            let b = b64m[i]
            if b == 0x2B {
                b64m[i] = 0x2D
            } else if b == 0x2F {
                b64m[i] = 0x5F
            }
        }
        
        while !b64m.isEmpty && b64m.last == 0x3D {
            b64m.removeLast()
        }
        
        return b64m
    }
    
    /** RFC4648 Base64 URL variant encoding uses only url-safe characters (_ and - instead of / and +), and does not include the trailing padding. */
    func base64URLEncodedString() -> String {
        return String(data: self.base64URLEncodedData(), encoding: .ascii)!
    }
    
    /** RFC4648 Base64 URL variant encoding uses only url-safe characters (_ and - instead of / and +), and does not include the trailing padding. */
    init?(base64URLEncoded: Data) {
        var b64m = base64URLEncoded
        for i in b64m.startIndex ..< b64m.endIndex {
            let b = b64m[i]
            if b == 0x2D {
                b64m[i] = 0x2B
            } else if b == 0x5F {
                b64m[i] = 0x2F
            }
        }
        
        let units = b64m.count % 4
        if units != 0 {
            for _ in units ..< 4 {
                b64m.append(0x3D)
            }
        }
        
        self.init(base64Encoded: b64m)
    }
    
    /** RFC4648 Base64 URL variant encoding uses only url-safe characters (_ and - instead of / and +), and does not include the trailing padding. */
    init?(base64URLEncoded: String) {
        guard let asBytes = base64URLEncoded.data(using: .ascii) else {
            return nil
        }
        self.init(base64URLEncoded: asBytes)
    }
}

