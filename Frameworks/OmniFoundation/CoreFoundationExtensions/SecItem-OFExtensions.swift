// Copyright 2016 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

import Foundation
import Security

public extension SecCertificate {
    
    @nonobjc
    func publicKey() throws -> SecKey {
        #if os(OSX)
            var publicKey : SecKey? = nil;
            let oserr = SecCertificateCopyPublicKey(self, &publicKey);
            if let result = publicKey {
                return result;
            } else {
                throw makeError(oserr, inFunction: "SecCertificateCopyPublicKey");
            }
        #else
            var errbuf : NSError? = nil;
            let publicKey = OFSecCertificateCopyPublicKey(self, &errbuf);
            if let pkey = publicKey {
                return pkey;
            } else {
                throw errbuf!;
            }
        #endif
    }
    
}

public extension SecIdentity {
    
    @nonobjc
    final func certificate() throws -> SecCertificate {
        var certificate : SecCertificate? = nil;
        let oserr = SecIdentityCopyCertificate(self, &certificate);
        if let result = certificate {
            return result;
        } else {
            throw makeError(oserr, inFunction: "SecIdentityCopyCertificate");
        }
    }
    
    @nonobjc
    func publicKey() throws -> SecKey {
        return try self.certificate().publicKey();
    }
    
    @nonobjc
    func privateKey() throws -> SecKey {
        var privateKey : SecKey? = nil;
        let oserr = SecIdentityCopyPrivateKey(self, &privateKey);
        if let result = privateKey {
            return result;
        } else {
            throw makeError(oserr, inFunction: "SecIdentityCopyPrivateKey");
        }
    }
    
}

/* This is functionally equivalent to a SecIdentityRef.  The reason we have this wrapper is that for reasons known only to Apple, there's no way to create a SecIdentity without putting its private key in a keychain. */
public enum Keypair {
    case secIdentity(ident: SecIdentity)
    case secCertificate(cert: SecCertificate, key: SecKey)
    case anonymous(pubkey: SecKey, key: SecKey)
    
    public func privateKey() throws -> SecKey {
        switch self {
        case .secIdentity(let identity):
            return try identity.privateKey();
            
        case .secCertificate(_, let key):
            return key
            
        case .anonymous(_, let key):
            return key
        }
    }
    
    public func publicKey() throws -> SecKey {
        switch self {
        case .secIdentity(let identity):
            return try identity.publicKey();
            
        case .secCertificate(let cert, _):
            return try cert.publicKey();
            
        case .anonymous(let pubkey, _):
            return pubkey;
        }
    }
    
    public func certificate() throws -> SecCertificate? {
        switch self {
        case .secIdentity(let identity):
            return try identity.certificate();
            
        case .secCertificate(let cert, _):
            return cert
            
        case .anonymous(_, _):
            return nil;
        }
    }
}

private func makeError(_ oserr: OSStatus, inFunction fnname: String) -> NSError {
    return NSError(domain: NSOSStatusErrorDomain, code:Int(oserr), userInfo: [ "function": fnname ]);
}
