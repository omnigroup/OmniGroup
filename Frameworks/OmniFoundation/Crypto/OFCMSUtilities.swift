// Copyright 2016 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// RCS_ID("$Id$")

import Foundation
import OmniFoundation.Private
import Darwin

/* A CMSRecipiet instance corresponds to a RecipientInfo datatype in CMS; it give enough information to derive the CEK for one recipient. */
protocol CMSRecipient {
    
    /* Produce the DER-encoded recipient information for this recipient, given the current file's content encryption key (CEK). */
    func recipientInfo(withCEK cek: Data) throws -> Data;
    
    /* Tests whether the receiver has enough information to encrypt a new CEK. */
    func reusable() -> Bool;
    
}


/* A CMSRecipientIdentifier corresponds to the RecipientIndentifier datatype in CMS: it identifies a key. It can either be a key identifier (an opaque blob) or a subject+issuer pair. */
enum CMSRecipientIdentifier {
    
    /* The two possibilities for a RecipientIdentifier */
    case issuerSerial(issuer: Data, serial: Data)      /* IssuerAndSerialNumber */
    case keyIdentifier(ski: Data)                      /* SubjectKeyIdentifier */
    
    /* Produce a DER encoding of ourselves */
    func asDER() -> Data {
        switch self {
        case .issuerSerial(let issuer, let serial):
            return _OFCMSRIDFromIssuerSerial(issuer, serial)
            
        case .keyIdentifier(let ski):
            return _OFCMSRIDFromSKI(ski)
        }
    }
    
    /* Produce an instance from a DER encoding */
    static func fromDER(_ der: Data) throws -> CMSRecipientIdentifier {
        var blob1, blob2 : NSData?;
        var error : NSError?;
        let identifierType = OFASN1ParseCMSRecipientIdentifier(der, &blob1, &blob2, &error);
        switch identifierType {
        case _OFASN1RIDIssuerSerial:
            return .issuerSerial(issuer: blob1! as Data, serial: blob2! as Data);
        case _OFASN1RIDSKI:
            return .keyIdentifier(ski: blob1! as Data);
        default:
            throw error!;
        }
    }
    
    /* Find matching certificates in the keyring */
    func findCertificates() throws -> [SecCertificate] {
        
        let found = try self.keyringSearch(secClass: kSecClassCertificate);
        var results : [SecCertificate] = [];
        var ignored = 0;
        // Protecting against the utter bogosity of SecItemCopyMatching()
        for cert in found {
            if CFGetTypeID(cert) == SecCertificateGetTypeID() && self.matchesCertificate(cert as! SecCertificate) {
                results.append(cert as! SecCertificate);
            } else {
                ignored += 1;
            }
        }
        
        if ignored > 0 {
            NSLog("Ignoring %d non-matching certificates from SecItemCopyMatching()", ignored);
        }
        
        return results;
    }
    
    /* Find matching identities in the keyring */
    func findIdentities() throws -> [SecIdentity] {
        let found = try self.keyringSearch(secClass: kSecClassIdentity);
        var results : [SecIdentity] = [];
        var ignored = 0;
        // Protecting against the utter bogosity of SecItemCopyMatching()
        for ident in found {
            var matched = false;
            if CFGetTypeID(ident) == SecIdentityGetTypeID() {
                let ident = ident as! SecIdentity;
                var cert : SecCertificate? = nil;
                if SecIdentityCopyCertificate(ident, &cert) == noErr {
                    if self.matchesCertificate(cert!) {
                        results.append(ident);
                        matched = true;
                    }
                }
            }
            if !matched {
                ignored += 1;
            }
        }
        
        if ignored > 0 {
            NSLog("Ignoring %d non-matching identities from SecItemCopyMatching()", ignored);
        }
        
        return results;
    }
    
    /* Checks whether the receiver is an identifier for a given certificate. */
    func matchesCertificate(_ cert : SecCertificate) -> Bool {
        var cissuer, cserial, cski: NSData?;
        
        if OFSecCertificateGetIdentifiers(cert, &cissuer, &cserial, &cski) {
            switch self {
            case .issuerSerial(cissuer!, cserial!):
                return true;
                
            case .keyIdentifier(cski!):
                return true;
                
            default:
                return false;
            }
        } else {
            return false;
        }
    }
    
    /* A Swifty wrapper around SecItemCopyMatching() */
    private func keyringSearch(secClass: CFString) throws -> NSArray {
        let attrs = NSMutableDictionary();
        
        switch self {
        case .issuerSerial(let issuer, let serial):
            attrs[kSecAttrIssuer as NSString] = issuer;
            attrs[kSecAttrSerialNumber as NSString] = serial;
            
        case .keyIdentifier(let ski):
            attrs[kSecAttrSubjectKeyID as NSString] = ski;
        }
        
        // attrs[kSecAttrCertificateType as NSString] = CSSM_CERT_X_509v3;
        
        attrs[kSecClass as NSString] = secClass;
        attrs[kSecMatchLimit as NSString] = kSecMatchLimitAll;
        attrs[kSecReturnRef as NSString] = kCFBooleanTrue;
        
        var found : AnyObject? = nil;
        let oserr = SecItemCopyMatching(attrs, &found);
        if oserr == errSecItemNotFound {
            return [];
        } else if oserr != errSecSuccess {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(oserr), userInfo: [ "function": "SecItemCopyMatching" ] );
        } else if CFGetTypeID(found) != CFArrayGetTypeID() { // Protecting against the utter bogosity of SecItemCopyMatching()
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(errSecUnimplemented), userInfo: [ "rettype": CFCopyTypeIDDescription(CFGetTypeID(found)),
                "function": "SecItemCopyMatching" ] );
        } else {
            return found as! NSArray;
        }
    }
}

class CMSPasswordRecipient : CMSRecipient {
    
    // A PasswordRecipient can have various subsets of information depending on its history:
    // When a new document is saved (or a password is changed), the user supplies a password; we generate the AlgorithmIdentifier (containing salt and iteration parameters) when needed; and derive the KEK when needed.
    // When reading an existing document, we start with just the AlgorithmIdentifier, and gain the password when the user supplies one. Similar to the other case, we derive the KEK from the password and parameters when we need it.
    
    var password: NSString?;   // The password.
    var kek: Data?;            // The key-encryption-key derived from the password.
    var info: Data?;           // The parameters (salt, iterations, etc) for the KEK derivation.
    
    func recipientInfo(withCEK cek: Data) throws -> Data {
        
        // If we don't have a KEK, we can safely generate a new algorithm identifier
        if info == nil && password != nil {
            info = OFGeneratePBKDF2AlgorithmInfo(UInt(cek.count), 0);
            kek = nil;  // KEK depends on the value of info.
        }
        
        // We can generate a KEK from a password and alg id
        if kek == nil {
            if let info = info, let password = password {
                var error : NSError?;
                kek = OFDeriveKEKForCMSPWRI(mapPassword(password), info, &error);
                if kek == nil {
                    throw error!;
                }
            }
        }
        
        if let kek = kek, let info = info, let recip = OFProduceRIForCMSPWRI(kek, cek, info, []) {
            return recip;
        } else {
            throw NSError(domain: OFErrorDomain, code: OFKeyNotAvailable, userInfo: nil);
        }
    }
    
    init(password: NSString) {
        self.password = password;
    }
    
    init(info: Data) {
        self.info = info;
    }
    
    func unwrap(password: NSString, data: Data) throws -> Data {
        guard let info = info else {
            // Shouldn't happen in normal operation
            throw NSError(domain: OFErrorDomain, code: OFKeyNotAvailable, userInfo: nil);
        }

        var error : NSError?;
        guard let anotherKek = OFDeriveKEKForCMSPWRI(mapPassword(password), info, &error) else {
            throw error!;
        }
        
        guard let unwrapped = OFUnwrapRIForCMSPWRI(data, anotherKek, &error) else {
            throw error!;
        }
        
        self.password = password;
        self.kek = anotherKek;
        return unwrapped;
    }
    
    private func mapPassword(_ password: NSString) -> Data {
        return password.precomposedStringWithCanonicalMapping.data(using: String.Encoding.utf8)!;
    }
    
    func reusable() -> Bool {
        if info != nil && kek != nil {
            return true;
        } else if password != nil {
            return true;
        } else {
            return false;
        }
    }
}

class CMSPKRecipient : CMSRecipient {
    
    var rid: CMSRecipientIdentifier;
    var cert: SecCertificate?;
    
    func recipientInfo(withCEK cek: Data) throws -> Data {
        
        if cert == nil {
            cert = try rid.findCertificates().last; // TODO: choose best
        }
        
        guard let cert = cert else {
            throw NSError(domain: OFErrorDomain, code: OFKeyNotAvailable, userInfo: nil);
        }
        
        var keyHandle: SecKey? = nil;
        let oserr = SecCertificateCopyPublicKey(cert, &keyHandle);
        
        if oserr != errSecSuccess {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(oserr), userInfo: [ "function": "SecCertificateCopyPublicKey" ] );
        }
        
        var errbuf : NSError? = nil;
        let rinfo = OFProduceRIForCMSRSAKeyTransport(keyHandle!, rid.asDER(), cek, &errbuf);
        if let rinfo = rinfo {
            return rinfo;
        } else {
            throw errbuf!;
        }
    }
    
    init(rid: CMSRecipientIdentifier) {
        self.rid = rid;
    }
    
    init(certificate: SecCertificate) throws {
        var issuer, serial, ski: NSData?;
        
        if !OFSecCertificateGetIdentifiers(certificate, &issuer, &serial, &ski) {
            throw NSError(domain: OFErrorDomain, code: OFASN1Error, userInfo: [ NSLocalizedDescriptionKey: "Could not parse X.509 certificate" ]);
        }
        
        if let ski : Data = ski as Data? {
            self.rid = CMSRecipientIdentifier.keyIdentifier(ski: ski);
        } else {
            self.rid = CMSRecipientIdentifier.issuerSerial(issuer: issuer! as Data, serial: serial! as Data);
        }
        self.cert = certificate;
    }
    
    func unwrap(identity: SecIdentity, data: Data) throws -> Data {
        var privateKey : SecKey? = nil;
        
        let oserr = SecIdentityCopyPrivateKey(identity, &privateKey);
        if oserr != noErr {
            throw NSError(domain: NSOSStatusErrorDomain, code:Int(oserr), userInfo: [ "function": "SecIdentityCopyPrivateKey" ]);
        }
        
        let cek = try unwrap(privateKey: privateKey!, data: data);
    
        var certificate : SecCertificate? = nil;
        let oserr2 = SecIdentityCopyCertificate(identity, &certificate);
        if oserr2 != noErr {
            cert = certificate;
        } else {
            cert = nil;
        }
        
        return cek;
    }
    
    func unwrap(privateKey: SecKey, data: Data) throws -> Data {
        var error : NSError? = nil;
        let cek = OFUnwrapRIForCMSKeyTransport(privateKey, data, &error);
        if cek == nil {
            throw error!;
        } else {
            return cek!;
        }
    }
    
    func reusable() -> Bool {
        if cert != nil {
            return true;
        }
        
        // Otherwise, see if we can find a cert.
        do {
            let certs = try rid.findCertificates();
            if certs.count > 0 {
                return true;
            }
        } catch _ {
            // Exception here is equivalent to a lookup failure; just drop it on the floor.
        }
        
        return false;
    }
}

internal final class OFCMSUnwrapper {
    var cms: Data;
    var contentRange: NSRange;
    var contentType: OFCMSContentType;
    var usedRecipient: CMSRecipient?;
    var allRecipients: [CMSRecipient];
    
    var delegate : OFCMSUnwrapDelegate;
    
    init(data: Data, delegate: OFCMSUnwrapDelegate) throws {
        var innerType = OFCMSContentType_Unknown;
        var innerLocation = NSRange();
        let outer = OFASN1ParseCMSContent(data, &innerType, &innerLocation);
        if (outer != 0) {
            throw OFNSErrorFromASN1Error(outer, "CMS ContentInfo");
        }
        
        self.cms = data;
        self.contentType = innerType;
        self.contentRange = innerLocation;
        self.delegate = delegate;
        usedRecipient = nil;
        allRecipients = [];
    }
    
    func content() -> Data {
        return cms.subdata(in: contentRange.location ..< NSMaxRange(contentRange));
    }
    
    private func recoverContentKey(recipientBlobs: NSArray) throws -> (Data, CMSRecipient, [CMSRecipient]) {
        // Parse the recipients, looking for something we can use.
        var passwordRecipients : [(CMSPasswordRecipient, Data)] = [];
        var pkRecipients : [(CMSPKRecipient, Data)] = [];
        
        for (recipientBlob) in recipientBlobs {
            
            var recipientType : OFASN1RecipientType = OFCMSRUnknown;
            var who, what : NSData?;
            
            let err = OFASN1ParseCMSRecipient(recipientBlob as! Data, &recipientType, &who, &what);
            if err != nil {
                throw err!;
            }
            
            switch recipientType {
            case OFCMSRPassword:
                passwordRecipients.append( (CMSPasswordRecipient(info: who! as Data), what! as Data) );
                
            case OFCMSRKeyTransport:
                let rid = try CMSRecipientIdentifier.fromDER(who! as Data);
                pkRecipients.append( (CMSPKRecipient(rid: rid), what! as Data) )
                
            default:
                break
                
            }
        }
        
        let allRecipients = pkRecipients.map({ (recip, _) -> CMSRecipient in recip }) + passwordRecipients.map({ (recip, _) -> CMSRecipient in recip });
        
        var cek : Data? = nil; // The content encryption key.
        var keyAccessError : NSError? = nil; // Stored error encountered while iterating over recipients.
        var usedRecipient : CMSRecipient? = nil; // The specific recipient we used.
        
        // Try public-key recipients
        for (recip, wrappedKey) in pkRecipients {
            let idents = try recip.rid.findIdentities();
            
            for ident in idents {
                do {
                    cek = try recip.unwrap(identity: ident, data: wrappedKey);
                    break; // Success: unwrapped a key.
                } catch let err as NSError {
                    if err.domain == NSCocoaErrorDomain && err.code == NSUserCancelledError {
                        // Usability question: When the user hits cancel on this dialog, how much do they want to cancel?
                        // We interpret that as canceling the use of this particular recipient (even though there may be multiple, separately-cancelable keys for a recipient, that situation should be very rare).
                        // If we fail to decrypt, but one of our attempts involved a user cancellation, we'll fail with a user-cancelled error instead of a no-keys-available error. So store the error temporarily.
                        keyAccessError = err;
                        break;
                    } else {
                        // Keep trying other recipients/keys if there are any, but store this error for eventual presentation to the user if we never succeed.
                        keyAccessError = err;
                    }
                }
            }
            
            if cek != nil {
                usedRecipient = recip;
                break;
            }
        }
        
        // Try passwords
        if cek == nil && !passwordRecipients.isEmpty {

            // We don't need to catch here, because this is the last thing we try. If this fails (either due to cancellation or some difficulty prompting for a password) the decryption can fail for the same reason.
            let password = try delegate.promptForPassword();
            
            for (passwordRecipient, wrappedKey) in passwordRecipients {
                // TODO: Recover if an unwrap fails. We should try all the password recipients; if any fail for a recoverable reason (e.g. OFKeyNotApplicable), re-prompt the user.
                cek = try passwordRecipient.unwrap(password: password, data:wrappedKey);
                usedRecipient = passwordRecipient;
                break;
            }
        }
        
        if let contentKey = cek {
            return (contentKey, usedRecipient!, allRecipients);
        } else {
            if let err = keyAccessError {
                throw err;
            }
            throw NSError(domain: OFErrorDomain, code: OFKeyNotAvailable, userInfo: nil);
        }
    }
    
    /* Unwraps an unauthenticated encryption mode (e.g. CBC). See RFC5652 [6]. */
    func decryptUED() throws {
        
        assert(contentType == OFCMSContentType_envelopedData);
        
        var cmsVersion : Int32 = -1;
        let recipientBlobs = NSMutableArray();
        var innerType : OFCMSContentType = OFCMSContentType_Unknown;
        var algorithm : NSData? = nil;
        var innerContent : NSData? = nil;
        
        let rc = OFASN1ParseCMSEnvelopedData(cms, contentRange, &cmsVersion, recipientBlobs, &innerType, &algorithm, &innerContent);
        if (rc != 0) {
            throw OFNSErrorFromASN1Error(rc, "EnvelopedData");
        }

        // Check version number. Version 4 indicates some features we don't support, but we should fail reasonably on them, so accept it anyway.
        guard cmsVersion >= 0 && cmsVersion <= 4 else {
            throw NSError(domain: OFErrorDomain, code: OFUnsupportedCMSFeature, userInfo: [ NSLocalizedFailureReasonErrorKey: "Unknown EnvelopedData version" ]);
        }

        let (contentKey, usedRecipient, allRecipients) = try self.recoverContentKey(recipientBlobs: recipientBlobs);
        
        var error : NSError? = nil;
        guard let plaintext = OFCMSDecryptContent(algorithm! as Data, contentKey, innerContent! as Data, nil, nil, &error) else {
            throw error!;
        }
        let plaintext_ = OFNSDataFromDispatchData(plaintext);  // This is a no-op, but Swift doesn't know that
        
        // Success. Store the results back into ourself.
        self.cms = plaintext_ as Data;
        self.contentRange = NSRange(location: 0, length: plaintext_.count);
        self.contentType = innerType;
        self.usedRecipient = usedRecipient;
        self.allRecipients += allRecipients;
    }

    /* Unwraps an authenticated encryption mode (e.g. GCM). See RFC5083. */
    func decryptAEAD() throws {
        
        assert(contentType == OFCMSContentType_authenticatedEnvelopedData);

        var cmsVersion : Int32 = -1;
        let recipientBlobs = NSMutableArray();
        var innerType : OFCMSContentType = OFCMSContentType_Unknown;
        var algorithm : NSData? = nil;
        var innerContent : NSData? = nil;
        var authenticatedAttributes : NSArray? = nil;
        var mac : NSData?;
        
        let rc = OFASN1ParseCMSAuthEnvelopedData(cms, contentRange, &cmsVersion, recipientBlobs, &innerType, &algorithm, &innerContent, &authenticatedAttributes, &mac);
        if (rc != 0) {
            throw OFNSErrorFromASN1Error(rc, "AuthEnvelopedData");
        }
        
        // Check version number
        guard cmsVersion >= 0 && cmsVersion <= 4 else {
            throw NSError(domain: OFErrorDomain, code: OFUnsupportedCMSFeature, userInfo: [ NSLocalizedFailureReasonErrorKey: "Unknown AuthEnvelopedData version" ]);
        }

        // TODO: Check that authenticated attributes includes the inner content type (perhaps should be done by OFASN1ParseCMSAuthEnvelopedData())
        
        let (contentKey, usedRecipient, allRecipients) = try self.recoverContentKey(recipientBlobs: recipientBlobs);
        
        var error : NSError? = nil;
        guard let plaintext = OFCMSDecryptContent(algorithm! as Data, contentKey, innerContent! as Data, authenticatedAttributes as? [AnyObject], mac as Data?, &error) else {
            throw error!;
        }
        let plaintext_ = OFNSDataFromDispatchData(plaintext);  // This is a no-op, but Swift doesn't know that
        
        // Success. Store the results back into ourself.
        self.cms = plaintext_ as Data;
        self.contentRange = NSRange(location: 0, length: plaintext_.count);
        self.contentType = innerType;
        self.usedRecipient = usedRecipient;
        self.allRecipients += allRecipients;
    }
    
}

/* RFC3274: Compressed content */
/* RFC4073: Multiple content */

