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

/** A CMSRecipient instance corresponds to the RecipientInfo datatype in CMS; it gives enough information to derive the CEK for one recipient. */
internal
protocol CMSRecipient {
    
    /** Produce the CMS recipient information for this recipient, given the current file's content encryption key (CEK).
     
     - parameter wrapping: The Content-Encryption Key to be used by the receiver.
     - returns: The DER-encoded RecipientInformation structure.
     */
    func recipientInfo(wrapping cek: Data) throws -> Data;
    
    /** Tests whether the receiver has enough information to encrypt a new CEK. */
    func canWrap() -> Bool;
    
}

/** A CMSRecipientIdentifier corresponds to the RecipientIndentifier datatype in CMS: it identifies a key. It can either be a key identifier (an opaque blob) or an issuer+serial pair. */
enum CMSRecipientIdentifier {
    
    /* The two possibilities for a RecipientIdentifier */
    case issuerSerial(issuer: Data, serial: Data)      /* IssuerAndSerialNumber */
    case keyIdentifier(ski: Data)                      /* SubjectKeyIdentifier */
    
    /** Produce a DER encoding of ourselves */
    func asDER() -> Data {
        switch self {
        case .issuerSerial(let issuer, let serial):
            return _OFCMSRIDFromIssuerSerial(issuer, serial)
            
        case .keyIdentifier(let ski):
            return _OFCMSRIDFromSKI(ski)
        }
    }
    
    /** Produce an instance from a DER encoding */
    static func fromDER(_ der: Data) throws -> CMSRecipientIdentifier {
        var blob1, blob2 : NSData?;
        var identifierType : OFCMSRecipientIdentifierType = OFCMSRecipientIdentifierType(99 /* invalid value */);
        if let error = _OFASN1ParseCMSRecipientIdentifier(der, &identifierType, &blob1, &blob2) {
            throw error;
        }
        
        switch identifierType {
        case OFCMSRIDIssuerSerial:
            return .issuerSerial(issuer: blob1! as Data, serial: blob2! as Data);
        case OFCMSRIDSubjectKeyIdentifier:
            return .keyIdentifier(ski: blob1! as Data);
        default:
            throw NSError(domain: OFErrorDomain, code: OFCMSFormatError, userInfo: nil);
        }
    }
    
    /** Find matching certificates in the keyring */
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
    
    /** Find matching identities in the keyring */
    func findIdentities() throws -> [Keypair] {
        let found = try self.keyringSearch(secClass: kSecClassIdentity);
        var results : [Keypair] = [];
        var ignored = 0;
        // Protecting against the utter bogosity of SecItemCopyMatching()
        for ident in found {
            var matched = false;
            if CFGetTypeID(ident) == SecIdentityGetTypeID() {
                let ident = ident as! SecIdentity;
                var cert : SecCertificate? = nil;
                if SecIdentityCopyCertificate(ident, &cert) == noErr {
                    if self.matchesCertificate(cert!) {
                        results.append(Keypair.secIdentity(ident: ident));
                        matched = true;
                    }
                }
            }
            if !matched {
                ignored += 1;
            }
        }
        
        if ignored > 0 {
            // We often get non-matching identities here because of RADAR 18142578 (in addition to all the other usual SecItemCopyMatching() brokenness).
            NSLog("Ignoring %d non-matching identities from SecItemCopyMatching()", ignored);
        }
        
        return results;
    }
    
    /** Checks whether the receiver is an identifier for a given certificate. */
    func matchesCertificate(_ cert : SecCertificate) -> Bool {
        var cissuer, cserial, cski: NSData?;
        
        if OFSecCertificateGetIdentifiers(cert, &cissuer, &cserial, &cski) {
            switch self {
            case .issuerSerial(cissuer! as Data as Data, cserial! as Data as Data):
                return true;
                
            case .keyIdentifier(let myski):
                if let certski = cski {
                    return myski == certski as Data;
                } else {
                    return false;
                }
                
            default:
                return false;
            }
        } else {
            return false;
        }
    }
    
    /* A Swifty wrapper around SecItemCopyMatching() */
    
    func keyringSearchTerms(into attrs: NSMutableDictionary) {
        
        switch self {
        case .issuerSerial(let issuer, let serial):
            attrs[kSecAttrIssuer as NSString] = issuer;
            attrs[kSecAttrSerialNumber as NSString] = serial;
            
        case .keyIdentifier(let ski):
            attrs[kSecAttrSubjectKeyID as NSString] = ski;
        }
        
        // attrs[kSecAttrCertificateType as NSString] = CSSM_CERT_X_509v3;
    }
    
    private func keyringSearch(secClass: CFString) throws -> [CFTypeRef] {
        let attrs = NSMutableDictionary();

        self.keyringSearchTerms(into: attrs);
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
            return (found as! NSArray) as [CFTypeRef];
        }
    }
}

class CMSPasswordRecipient : CMSRecipient {
    
    let type = OFCMSRPassword;

    // A PasswordRecipient can have various subsets of information depending on its history:
    // When a new document is saved (or a password is changed), the user supplies a password; we generate the AlgorithmIdentifier (containing salt and iteration parameters) when needed; and derive the KEK when needed.
    // When reading an existing document, we start with just the AlgorithmIdentifier, and gain the password when the user supplies one. Similar to the other case, we derive the KEK from the password and parameters when we need it.
    
    var password: String?;     // The password.
    var kek: Data?;            // The key-encryption-key derived from the password.
    var info: Data?;           // The parameters (salt, iterations, etc) for the KEK derivation.
    
    func recipientInfo(wrapping cek: Data) throws -> Data {
        
        // If we don't have a KEK, we can safely generate a new algorithm identifier
        if info == nil && password != nil {
            info = OFGeneratePBKDF2AlgorithmInfo(UInt(cek.count), 0);
            kek = nil;  // KEK depends on the value of info.
        }
        
        // We can generate a KEK from a password and alg id
        if kek == nil, let info = info, let password = password {
            var error : NSError?;
            kek = OFDeriveKEKForCMSPWRI(mapPassword(password), info, &error);
            if kek == nil {
                throw error!;
            }
        }
        
        // The KEK and alg id are what we actually need to compute our result
        if let kek = kek, let info = info, let recip = OFProduceRIForCMSPWRI(kek, cek, info, []) {
            return recip;
        } else {
            throw NSError(domain: OFErrorDomain, code: OFKeyNotAvailable, userInfo: nil);
        }
    }
    
    init(password: String) {
        self.password = password;
    }
    
    init(info: Data) {
        self.info = info;
    }
    
    func unwrap(password: String, data: Data) throws -> Data {
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
    
    private func mapPassword(_ password: String) -> Data {
        return password.precomposedStringWithCanonicalMapping.data(using: String.Encoding.utf8)!;
    }
    
    func canWrap() -> Bool {
        if info != nil && kek != nil {
            return true;
        } else if password != nil {
            return true;
        } else {
            return false;
        }
    }
}

class CMSKEKRecipient : CMSRecipient {
    
    let type = OFCMSRPreSharedKey;

    // A KEK recipient (which we also call a pre-shared-key recipient) just contains an identifier for a key which the receiver of the message already has.
    
    var keyIdentifier: Data;
    var kek: Data?;
    
    func recipientInfo(wrapping cek: Data) throws -> Data {
        
        guard let key = kek else {
            throw NSError(domain: OFErrorDomain, code: OFKeyNotAvailable, userInfo: nil);
        }
        
        if let rinfo = OFProduceRIForCMSKEK(key, cek, keyIdentifier, []) {
            return rinfo;
        } else {
            throw NSError(domain: OFErrorDomain, code: OFKeyNotAvailable, userInfo: nil);
        }
    }

    init(keyIdentifier ki: Data, key: Data?) {
        keyIdentifier = ki;
        kek = key;
    }
    
    convenience init() {
        self.init(keyIdentifier: NSData.cryptographicRandomData(ofLength:12), key: NSData.cryptographicRandomData(ofLength:32));
    }
    
    func unwrap(kek: Data, data: Data) throws -> Data {
        var error : NSError?;
        guard let unwrapped = OFUnwrapRIForCMSPWRI(data, kek, &error) else {
            throw error!;
        }
        
        self.kek = kek;
        return unwrapped;
    }
    
    func canWrap() -> Bool {
        if kek == nil {
            return false;
        }
        return true;
    }
}

/** A Public-Key recipient uses an asymmetric keypair to perform key transport or key agreement.
 
 We currently only support RSA keypairs and key transport.
 If/when Apple brings ECDH-based key agreement APIs to both platforms, we may want to split this class into two concrete subclasses (one for RSA key transport and one for ECDH key agreement). Or if we give up and just implement a Curve25519-based feature, we might want a third subclass.
 
 The keypair is identified by a `CMSRecipientIdentifier`, although we may also store a reference to the recipient's public key.
 */
class CMSPKRecipient : CMSRecipient {
    
    let type = OFCMSRKeyTransport;

    var rid: CMSRecipientIdentifier;
    var cert: SecCertificate?;
    
    func recipientInfo(wrapping cek: Data) throws -> Data {
        
        guard let encryptionKey = try cert?.publicKey() else {
            throw NSError(domain: OFErrorDomain, code: OFKeyNotAvailable, userInfo: nil);
        }
        
        var errbuf : NSError? = nil;
        let rinfo = OFProduceRIForCMSRSAKeyTransport(encryptionKey, rid.asDER(), cek, &errbuf);
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
    
    func unwrap(identity: Keypair, data: Data) throws -> Data {
        let cek = try unwrap(privateKey: identity.privateKey(), data: data);
    
        // If we succeeded, squirrel away the corresponding certificate.
        try? cert = identity.certificate();
        
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
    
    func resolve(delegate: OFCMSKeySource?) throws -> () {
        
        if cert == nil {
            cert = try rid.findCertificates().last; // TODO: choose best
        }

    }
    
    func canWrap() -> Bool {
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

internal extension OFCMSContentType {
    /** The DER representation of the receiver
     */
    func asDER() -> Data {
        return OFCMSOIDFromContentType(self)!;
    }
}

/** Holds state during the multi-stage unwrapping of a CMS message.
 */
internal final
class OFCMSUnwrapper {
    
    // These are modified as we unwrap each layer.
    var cms: Data;  // This is actually a DispatchData most of the time, but the DispatchData class isn't quite usable as of Xcode8b6
    var contentRange: NSRange;
    var contentType: OFCMSContentType;
    
    // These contain information accumulated during unwrapping.
    var usedRecipient: CMSRecipient?;
    var allRecipients: [CMSRecipient];
    var discardedRecipientCount: UInt;
    var contentIdentifier: Data?;
    var authenticated: Bool;
    
    internal var keySource : OFCMSKeySource?;
    internal var auxiliarySymmetricKeys : [Data : Data];
    internal var auxiliaryAsymmetricKeys : [Keypair];
    
    init(data: Data, keySource ks: OFCMSKeySource?) throws {
        var innerType = OFCMSContentType_Unknown;
        var innerLocation = NSRange();
        let outer = OFASN1ParseCMSContent(data, &innerType, &innerLocation);
        if (outer != 0) {
            throw OFNSErrorFromASN1Error(outer, "CMS ContentInfo");
        }
        
        cms = data;
        contentType = innerType;
        contentRange = innerLocation;
        usedRecipient = nil;
        allRecipients = [];
        discardedRecipientCount = 0;
        authenticated = false;
        keySource = ks;
        auxiliarySymmetricKeys = [:];
        auxiliaryAsymmetricKeys = [];
    }
    
    public final func addSymmetricKeys(_ keys: [Data: Data]) {
        for kv in keys {
            auxiliarySymmetricKeys[kv.0] = kv.1;
        }
    }
    
    public final func addAsymmetricKeys(_ keys: [Keypair]) {
        auxiliaryAsymmetricKeys += keys;
    }
    
    func content() -> Data {
        return cms.subdata(in: contentRange.location ..< NSMaxRange(contentRange));
    }
    
    private func recoverContentKey(recipientBlobs: NSArray) throws -> (cek: Data, CMSRecipient, [CMSRecipient]) {
        // Parse the recipients, looking for something we can use.
        var passwordRecipients : [(CMSPasswordRecipient, Data)] = [];
        var pkRecipients : [(CMSPKRecipient, Data)] = [];
        var pskRecipients : [(CMSKEKRecipient, Data)] = [];
        var allRecipients : [CMSRecipient] = [];
        
        for (recipientBlob) in recipientBlobs {
            
            var recipientType : OFCMSRecipientType = OFCMSRUnknown;
            var who, what : NSData?;
            
            let err = _OFASN1ParseCMSRecipient(recipientBlob as! Data, &recipientType, &who, &what);
            if err != nil {
                throw err!;
            }
            
            switch recipientType {
            case OFCMSRPassword:
                let recip = CMSPasswordRecipient(info: who! as Data);
                passwordRecipients.append( (recip, what! as Data) );
                allRecipients.append(recip);
                
            case OFCMSRKeyTransport:
                let recip = CMSPKRecipient(rid: try CMSRecipientIdentifier.fromDER(who! as Data));
                pkRecipients.append( (recip, what! as Data) )
                allRecipients.append(recip);
                
            case OFCMSRPreSharedKey:
                let recip = CMSKEKRecipient(keyIdentifier: who! as Data, key: nil);
                pskRecipients.append( (recip, what! as Data) )
                allRecipients.append(recip);
                
            default:
                discardedRecipientCount += 1;
                break
                
            }
        }
        
        var cek : Data? = nil; // The content encryption key.
        var keyAccessError : NSError? = nil; // Stored error encountered while iterating over recipients.
        var usedRecipient : CMSRecipient? = nil; // The specific recipient we used.
        
        // Try boring pre-shared key recipients.
        for (recip, wrappedKey) in pskRecipients {
            if let psk = auxiliarySymmetricKeys[recip.keyIdentifier] {
                do {
                    cek = try recip.unwrap(kek: psk, data: wrappedKey);
                    usedRecipient = recip;
                    break; // Success: unwrapped a key.
                } catch let err as NSError {
                    // Keep trying other recipients/keys if there are any, but store this error for eventual presentation to the user if we never succeed.
                    keyAccessError = err;
                }
            }
        }
        
        // Try public-key recipients
        if cek == nil {
            for (recip, wrappedKey) in pkRecipients {
                var idents = try recip.rid.findIdentities();
                
                for kp in auxiliaryAsymmetricKeys {
                    if let cert_ = try? kp.certificate(), let cert = cert_ {
                        if recip.rid.matchesCertificate(cert) {
                            idents.insert(kp, at: 0);
                        }
                    }
                }
                
                for ident in idents {
                    do {
                        cek = try recip.unwrap(identity: ident, data: wrappedKey);
                        usedRecipient = recip;
                        break; // Success: unwrapped a key.
                    } catch let err as NSError {
                        if err.domain == NSCocoaErrorDomain && err.code == NSUserCancelledError {
                            // Usability question: When the user hits cancel on this dialog, how much do they want to cancel?
                            // We interpret that as canceling the use of this particular recipient (even though there may be multiple, separately-cancelable keys for a recipient, that situation should be very rare).
                            // However, we will keep trying other recipients, if any are applicable.
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
                    break
                }
            }
        }
        
        // Try passwords
        if cek == nil {
            if let (aCek, aRecip) = try passphrase(passwordRecipients) {
                cek = aCek;
                usedRecipient = aRecip;
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
    
    private func passphrase(_ passwordRecipients: [(CMSPasswordRecipient, Data)]) throws -> (Data, CMSPasswordRecipient)? {
        
        if passwordRecipients.isEmpty {
            return nil;
        }
        
        guard let keySource = keySource else {
            return nil;
        }
        
        var failureCount : Int = 0;
        
        prompting: while true {
            let password = try keySource.promptForPassword(withCount: failureCount);
            
            // Probably only one password recipient, but potentially several
            var passwordUseError : NSError? = nil;
            var anyNotApplicable : Bool = false;
            for (passwordRecipient, wrappedKey) in passwordRecipients {
                do {
                    let aCek = try passwordRecipient.unwrap(password: password, data:wrappedKey);
                    return (aCek, passwordRecipient);
                } catch let err as NSError {
                    if err.domain == OFErrorDomain && err.code == OFKeyNotApplicable {
                        // Incorrect password. Re-prompt unless another recipient matches.
                        anyNotApplicable = true;
                    } else {
                        passwordUseError = err;
                    }
                }
            }
            
            if anyNotApplicable {
                // Incorrect password. Re-prompt.
                failureCount += 1;
            } else {
                // We failed for a reason other than an incorrect password.
                throw passwordUseError!; // (This could only be nil if we have no passwordRecipients, but we check for that.)
            }
        };
    }
    
    func peelMeLikeAnOnion() throws {
        while true {
            switch contentType {
            case OFCMSContentType_envelopedData:
                try decryptUED();
            case OFCMSContentType_authenticatedEnvelopedData:
                try decryptAEAD();
            case OFCMSContentType_Unknown:
                throw NSError(domain: OFErrorDomain, code: OFUnsupportedCMSFeature, userInfo: [NSLocalizedDescriptionKey: "Unimplemented content-type" /* TODO: Localize. */]);
            default:
                return;
            }
        }
    }
    
    /** Unwraps an unauthenticated encryption mode (e.g. CBC). See RFC5652 [6]. */
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

        // Check version number. Version 4 indicates some features we don't support, but we should fail reasonably on them, so accept it anyway. See RFC5652 [6.1].
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

    /** Unwraps an authenticated encryption mode (e.g. CCM or GCM). See RFC5083. */
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
        
        // Check version number. See RFC5083 [2.1].
        guard cmsVersion == 0 else {
            throw NSError(domain: OFErrorDomain, code: OFUnsupportedCMSFeature, userInfo: [ NSLocalizedFailureReasonErrorKey: "Unknown AuthEnvelopedData version" ]);
        }

        // Parse the attributes.
        let attrs = try OFCMSUnwrapper.parseAttributes(authenticatedAttributes, innerType: innerType);
        
        // Check that authenticated attributes includes the inner content type (see RFC 5083). For security reasons the content type attribute is only allowed to be missing if the content type is 'data'.
        if !attrs.sawMatchingContentType && innerType != OFCMSContentType_data {
            throw NSError(domain: OFErrorDomain, code: OFCMSFormatError, userInfo: [ NSLocalizedFailureReasonErrorKey: "Content-Type missing" ]);
        }
        
        let (contentKey, usedRecipient, allRecipients) = try self.recoverContentKey(recipientBlobs: recipientBlobs);
        
        var error : NSError? = nil;
        guard let plaintext = OFCMSDecryptContent(algorithm! as Data, contentKey, innerContent! as Data, authenticatedAttributes as? [AnyObject], mac as Data?, &error) else {
            throw error!;
        }
        let plaintext_ = OFNSDataFromDispatchData(plaintext);  // This is a no-op, but Swift doesn't know that
        
        // Success. Store the results back into ourself.
        if attrs.contentIdentifier != nil {
            self.contentIdentifier = attrs.contentIdentifier;
        }
        self.cms = plaintext_ as Data;
        self.contentRange = NSRange(location: 0, length: plaintext_.count);
        self.contentType = innerType;
        self.authenticated = true;
        self.usedRecipient = usedRecipient;
        self.allRecipients += allRecipients;
    }
    
    private struct parsedAttributes {
        let sawMatchingContentType : Bool;
        let contentIdentifier : Data?;
        let messageDigest : Data?;
    };
    private static func parseAttributes(_ attributes_: NSArray?, innerType: OFCMSContentType) throws -> parsedAttributes {
        var sawMatchingContentType = false;
        var contentIdentifier : Data? = nil;
        var messageDigest : Data? = nil;
        
        if let attributes = attributes_ {
            for attribute in attributes {
                var attrIdentifier : OFCMSAttribute = OFCMSAttribute_Unknown;
                var attrIndex : UInt32 = 0;
                var attrData : NSData? = nil;
                if let error = OFCMSParseAttribute(attribute as! Data, &attrIdentifier, &attrIndex, &attrData) {
                    throw error;
                }
                switch(attrIdentifier) {
                case OFCMSAttribute_contentType:
                    if innerType.rawValue == attrIndex {
                        sawMatchingContentType = true;
                    } else {
                        throw NSError(domain: NSOSStatusErrorDomain, code: -4304 /* kCCDecodeError */, userInfo: [ NSLocalizedFailureReasonErrorKey: "Content-Type mismatch" ]);
                    }
                    
                case OFCMSAttribute_contentIdentifier:
                    contentIdentifier = attrData as Data?;
                    
                case OFCMSAttribute_messageDigest:    // We'll need this if we support verifying of signed data or (non-AEAD) authenticated data.
                    messageDigest = attrData as Data?;
                    
                //case OFCMSAttribute_signingTime:
                default:
                    break;
                }
            }
        }
        
        return parsedAttributes(sawMatchingContentType: sawMatchingContentType, contentIdentifier: contentIdentifier, messageDigest: messageDigest);
    }
}

/* RFC3274: Compressed content */
/* RFC4073: Multiple content */

