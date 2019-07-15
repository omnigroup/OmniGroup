// Copyright 2016-2019 Omni Development, Inc. All rights reserved.
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
    
    @nonobjc final
    func publicKey() throws -> SecKey {
        guard let pubkey = SecCertificateCopyKey(self) else {
            // The new API no longer has any kind of error indication (I no longer bother to file RADARs against these APIs). The documentation says "The return reference is NULL if the public key has an encoding issue or uses an unsupported algorithm.", so we'll report this as an unsupported key format.
            throw makeError(errSecUnsupportedKeyFormat, inFunction: "SecCertificateCopyKey")
            }
        return pubkey
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
    
    @nonobjc final
    func publicKey() throws -> SecKey {
        return try self.certificate().publicKey();
    }
    
    @nonobjc final
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

 public struct OFKeyUsage: OptionSet {
    public let rawValue: Int32
    public init(rawValue: Int32) {
        self.rawValue = rawValue
    }
    
    static let sign      = OFKeyUsage(rawValue: kOFKeyUsageSign)     /// compute digital signature or MAC
    static let verify    = OFKeyUsage(rawValue: kOFKeyUsageVerify)   /// verify digital signature or MAC
    static let encrypt   = OFKeyUsage(rawValue: kOFKeyUsageEncrypt)  /// encrypt content
    static let decrypt   = OFKeyUsage(rawValue: kOFKeyUsageDecrypt)  /// decrypt content and validate decryption, if applicable
    static let wrapKey   = OFKeyUsage(rawValue: kOFKeyUsageWrap)     /// encrypt key
    static let unwrapKey = OFKeyUsage(rawValue: kOFKeyUsageUnwrap)   /// decrypt key and validate decryption, if applicable
    static let derive    = OFKeyUsage(rawValue: kOFKeyUsageDerive)   /// perform key agreement or shared-secret derivation
    
    static let integrity : OFKeyUsage = [ .sign, .verify ]
    static let confidentiality : OFKeyUsage = [ .encrypt, .decrypt, .wrapKey, .unwrapKey ]
    static let publicOperations : OFKeyUsage = [ .verify, .encrypt, .wrapKey ]
    
    public func asSecKeyUsage() -> NSMutableArray {
        let attrs = NSMutableArray()
        
        if self.contains(.sign)      { attrs.add(kSecAttrCanSign) }
        if self.contains(.verify)    { attrs.add(kSecAttrCanVerify) }
        if self.contains(.encrypt)   { attrs.add(kSecAttrCanEncrypt) }
        if self.contains(.decrypt)   { attrs.add(kSecAttrCanDecrypt) }
        if self.contains(.wrapKey)   { attrs.add(kSecAttrCanWrap) }
        if self.contains(.unwrapKey) { attrs.add(kSecAttrCanUnwrap) }
        if self.contains(.derive)    { attrs.add(kSecAttrCanDerive) }

        return attrs
    }
}

private func makeError(_ oserr: OSStatus, inFunction fnname: String) -> NSError {
    return NSError(domain: NSOSStatusErrorDomain, code:Int(oserr), userInfo: [ "function": fnname ]);
}
