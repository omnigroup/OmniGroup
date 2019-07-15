// Copyright 2016-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// RCS_ID("$Id$")

import Foundation
import OmniFoundation.Private

/** A CMSRecipient instance corresponds to the [RecipientInfo](https://tools.ietf.org/html/rfc5652#section-6.2) datatype in CMS; it gives enough information to derive the CEK for one recipient. */
@objc(OFCMSRecipient) public
protocol CMSRecipient {
    
    /** Produce the CMS recipient information for this recipient, given the current file's content encryption key (CEK).
     Use `canWrap()` to discover whether the receiver actually has enough information to wrap a new CEK.
     
    - parameter cek: The Content-Encryption Key to be used by the receiver.
    - returns: The DER-encoded RecipientInformation structure.
     */
    func recipientInfo(wrapping cek: Data) throws -> Data;
    
    /** Tests whether the receiver has enough information to encrypt a new CEK. */
    func canWrap() -> Bool;
    
    @objc
    var type : OFCMSRecipientType { get };
    
    @objc optional
    var certificate : SecCertificate? { get };
    
    @objc
    func debugDictionary() -> NSMutableDictionary;
}

/** A CMSRecipientIdentifier corresponds to the [RecipientIdentifier](https://tools.ietf.org/html/rfc5652#section-6.2.1) datatype in CMS: it identifies a key. It can either be a key identifier (an opaque blob) or an issuer+serial pair. */
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
            throw OFError(.OFCMSFormatError)
        }
    }
    
    /** Find matching certificates in the keyring */
    func findCertificates() throws -> [SecCertificate] {
        
        let found = try self.keyringSearch(secClass: kSecClassCertificate, interactionAllowed: true);
        var results : [SecCertificate] = [];
        var ignored = 0;
        // Protecting against the utter bogosity of SecItemCopyMatching()
        for cert in found {
            if CFGetTypeID(cert) == SecCertificateGetTypeID() && self.matches(certificate: cert as! SecCertificate) {
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
    func findIdentities(allowInteraction: Bool = true) throws -> [Keypair] {
        let found = try self.keyringSearch(secClass: kSecClassIdentity, interactionAllowed: allowInteraction);
        var results : [Keypair] = [];
        var ignored = 0;
        // Protecting against the utter bogosity of SecItemCopyMatching()
        for ident in found {
            var matched = false;
            if CFGetTypeID(ident) == SecIdentityGetTypeID() {
                let ident = ident as! SecIdentity;
                var cert : SecCertificate? = nil;
                if SecIdentityCopyCertificate(ident, &cert) == noErr {
                    if self.matches(certificate: cert!) {
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
    func matches(certificate cert : SecCertificate) -> Bool {
        do {
            let certinfo = try CertificateIdentifiers(cert);
            return self.matches(identifiers: certinfo);
        } catch {
            return false;
        }
    }
    
    /** Checks whether the receiver is an identifier for a certificate with the given fields. */
    func matches(identifiers cert : CertificateIdentifiers) -> Bool {
        switch self {
        case .issuerSerial(cert.issuer, cert.serial):
            return true;
                
        case .keyIdentifier(let myski):
            if let certski = cert.ski {
                return myski == certski;
            } else {
                return false;
            }
            
        default:
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
    
    private func keyringSearch(secClass: CFString, interactionAllowed: Bool) throws -> [CFTypeRef] {
        let attrs = NSMutableDictionary();

        self.keyringSearchTerms(into: attrs);
        attrs[kSecClass as NSString] = secClass;
        attrs[kSecMatchLimit as NSString] = kSecMatchLimitAll;
        attrs[kSecReturnRef as NSString] = kCFBooleanTrue;
        
        if !interactionAllowed {
            attrs[kSecUseAuthenticationUI] = kSecUseAuthenticationUISkip;
        }
        
        var found : AnyObject? = nil;
        let oserr = SecItemCopyMatching(attrs, &found);
        if oserr == errSecItemNotFound {
            return [];
        } else if oserr != errSecSuccess {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(oserr), userInfo: [ "function": "SecItemCopyMatching" ] );
        } else if CFGetTypeID(found) != CFArrayGetTypeID() { // Protecting against the utter bogosity of SecItemCopyMatching()
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(errSecUnimplemented), userInfo: [ "rettype": CFCopyTypeIDDescription(CFGetTypeID(found))!,
                "function": "SecItemCopyMatching" ] );
        } else {
            return (found as! NSArray) as [CFTypeRef];
        }
    }
    
    static func bestCertificate(_ certs: [SecCertificate]) -> SecCertificate? {
        // TODO: Actually choose best. (Prefer valid, ... what else?)
        return certs.last;
    }
    
    func debugDictionary() -> NSMutableDictionary {
        let debugDictionary = NSMutableDictionary();
        
        switch self {
        case .issuerSerial(let issuer, let serial):
            debugDictionary["issuer"] = issuer as NSData;
            debugDictionary["serial"] = serial as NSData;
            
        case .keyIdentifier(let ski):
            debugDictionary["SKI"] = ski as NSData;
        }

        return debugDictionary;
    }
}

internal
struct CertificateIdentifiers {
    let issuer: Data;  // Issuer RDN
    let serial: Data;  // Issuer-assiged serial number
    let ski: Data?;    // Subject key identifier; optional (but very common)
    
    init(_ certificate: SecCertificate) throws {
        var cissuer, cserial, cski: NSData?;
        
        if OFSecCertificateGetIdentifiers(certificate, &cissuer, &cserial, &cski),
           let issuer = cissuer,
           let serial = cserial {
            
            self.issuer = issuer as Data
            self.serial = serial as Data
            if let ski = cski {
                self.ski = ski as Data
            } else {
                self.ski = nil
            }
        } else {
            throw OFError(.OFASN1Error, userInfo: ["function": "OFSecCertificateGetIdentifiers"])
        }
    }
    
    func recipientIdentifier()  -> CMSRecipientIdentifier {
        if let ski = self.ski {
            return CMSRecipientIdentifier.keyIdentifier(ski: ski);
        } else {
            return CMSRecipientIdentifier.issuerSerial(issuer: self.issuer, serial: self.serial);
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
            throw OFError(.OFKeyNotAvailable)
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
            throw OFError(.OFKeyNotAvailable)
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
    
    internal
    func didUnwrapWith(password: String) -> Bool? {
        guard let info = info else {
            // Shouldn't happen in normal operation
            return nil;
        }
        
        guard let kek = self.kek else {
            return nil;
        }
        
        var error : NSError?;
        guard let anotherKek = OFDeriveKEKForCMSPWRI(mapPassword(password), info, &error) else {
            return false;
        }
        
        return kek == anotherKek
    }
    
    internal
    func canTestPassword() -> Bool {
        return (info != nil && kek != nil);
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
    
    @objc public
    func debugDictionary() -> NSMutableDictionary {
        let debugDictionary = NSMutableDictionary();
        
        debugDictionary["type"] = "PWRI" as NSString;
        if let pw = self.password as NSString? {
            debugDictionary["password"] = pw;
        }
        if let kek_ = self.kek as NSData? {
            debugDictionary["kek"] = kek_;
        }
        
        return debugDictionary;
    }
}

/** A KEK recipient (which we also call a pre-shared-key recipient) just contains an identifier for a key which the receiver of the message already has. */
class CMSKEKRecipient : CMSRecipient {
    
    let type = OFCMSRPreSharedKey;
    
    var keyIdentifier: Data
    var kek: Data?
    
    func recipientInfo(wrapping cek: Data) throws -> Data {
        guard let key = kek else {
            throw OFError(.OFKeyNotAvailable)
        }
        
        if let rinfo = OFProduceRIForCMSKEK(key, cek, keyIdentifier, []) {
            return rinfo;
        } else {
            throw OFError(.OFKeyNotAvailable)
        }
    }
    
    init(keyIdentifier ki: Data, key: Data?) {
        keyIdentifier = ki
        kek = key
    }

    convenience init() {
        self.init(keyIdentifier: NSData.cryptographicRandomData(ofLength:12), key: NSData.cryptographicRandomData(ofLength:32));
    }
    
    func unwrap(kek: Data, data: Data) throws -> Data {
        var error : NSError?
        guard let unwrapped = OFUnwrapRIForCMSPWRI(data, kek, &error) else {
            throw error!
        }
        
        self.kek = kek
        return unwrapped
    }
    
    func canWrap() -> Bool {
        if kek == nil {
            return false
        }
        return true
    }
    
    @objc public
    func debugDictionary() -> NSMutableDictionary {
        let debugDictionary = NSMutableDictionary();
        
        debugDictionary["type"] = "KEKRI" as NSString;
        debugDictionary["keyIdentifier"] = self.keyIdentifier as NSData;
        if let kek_ = self.kek as NSData? {
            debugDictionary["kek"] = kek_;
        }
        
        return debugDictionary;
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
            throw OFError(.OFKeyNotAvailable)
        }
        
        var errbuf : NSError? = nil;
        if let rinfo = OFProduceRIForCMSRSAKeyTransport(encryptionKey, rid.asDER(), cek, &errbuf) {
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
            throw OFError(.OFASN1Error, userInfo: [ NSLocalizedDescriptionKey: "Could not parse X.509 certificate" ])
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
    
    func resolveWithKeychain() -> Bool {
        
        if cert == nil {
            // Exception here is equivalent to a lookup failure; just drop it on the floor.
            try? cert = CMSRecipientIdentifier.bestCertificate(rid.findCertificates());
        }

        return cert != nil;
    }
    
    func resolve(certificate: SecCertificate) -> Bool {
        if cert == nil && rid.matches(certificate: certificate) {
            cert = certificate;
        }
        return cert != nil;
    }
    
    func canWrap() -> Bool {
        if cert != nil {
            return true;
        }
        
        return false;
    }
    
    var certificate : SecCertificate? {
        get {
            return cert;
        }
    }
    
    @objc public
    func debugDictionary() -> NSMutableDictionary {
        let debugDictionary = self.rid.debugDictionary();
        
        debugDictionary["type"] = "KTRI" as NSString;
        debugDictionary["cert"] = ( self.cert == nil ? "NO" : "YES" );
        
        return debugDictionary;
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
    var cms: Data?;  // This is actually a DispatchData most of the time, but the DispatchData class isn't quite usable as of Xcode8
    var contentRange: NSRange;
    var contentType: OFCMSContentType;
    var fromContentInfo: Bool;  // Whether our content range came from a ContentInfo and therefore might be wrapped in an OCTET STRING
    
    // These contain information accumulated during unwrapping.
    var usedRecipient: CMSRecipient?     = nil;
    var allRecipients: [CMSRecipient]    = [];
    var discardedRecipientCount: UInt    = 0;
    var contentIdentifier: Data?         = nil;
    var authenticated: Bool              = false;
    var embeddedCertificates: [Data]     = [];

    // Sources of key material.
    internal var keySource : OFCMSKeySource?;
    internal var auxiliarySymmetricKeys : [Data : Data]  = [:];
    internal var auxiliaryAsymmetricKeys : [Keypair]     = [];
    internal var passwordHint : String? = nil;
    
    /// Create an unwrapper for a BER-encodeed CMS object.
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
        fromContentInfo = true;
        keySource = ks;
    }
    
    /** Internal initializer used for unwrapping multipart items. */
    private
    init(data: Data, location: NSRange, type: OFCMSContentType, keySource ks: OFCMSKeySource?) {
        cms = data;
        contentType = type;
        contentRange = location;
        fromContentInfo = true;
        keySource = ks;
    }
    
    /** Provide additional keys for use by KEK recipients. (Currently used for side files in file packages.) */
    public final func addSymmetricKeys(_ keys: [Data: Data]) {
        for kv in keys {
            auxiliarySymmetricKeys[kv.0] = kv.1;
        }
    }
    
    /** Provide additional asymmetric keys to supplement any found in the keychain. (Currently used by the unit tests.) */
    public final func addAsymmetricKeys(_ keys: [Keypair]) {
        auxiliaryAsymmetricKeys += keys;
    }
    
    /** Returns the current content of the unwrapper. This is generally only useful if the unwrapper has unwrapped everything down to a Data, XML, or other non-CMS-specific data type. */
    func content() throws -> Data {
        if let cms_ = cms {
            if fromContentInfo {
                switch contentType {
                case OFCMSContentType_XML, OFCMSContentType_data:
                    return OFASN1UnwrapOctetString(cms_, contentRange)!
                default:
                    // fallthrough
                    break
                }
            }
            return cms_.subdata(in: contentRange.location ..< NSMaxRange(contentRange));
        } else {
            throw unexpectedNullContent();
        }
    }
    
    /** Some content types contain optional content (for example, a detached signature does not contain its content). */
    var hasNullContent : Bool {
        get {
            if cms != nil {
                return contentRange.length == 0;
            } else {
                return true;
            }
        }
    }
    
    /** A helper structure for collections of recipients, parsed and sorted by recipient type. */
    private struct assortedRecipients {
        var passwordRecipients : [(CMSPasswordRecipient, Data)] = [];
        var pkRecipients : [(CMSPKRecipient, Data)] = [];
        var pskRecipients : [(CMSKEKRecipient, Data)] = [];
        var discardedRecipientCount : UInt = 0;
        var hint: String?
        
        mutating
        func parse(recipientBlob: Data) throws {
            var recipientType : OFCMSRecipientType = OFCMSRUnknown;
            var who, what : NSData?;
            
            let err = _OFASN1ParseCMSRecipient(recipientBlob, &recipientType, &who, &what);
            if err != nil {
                throw err!;
            }
            
            switch recipientType {
            case OFCMSRPassword:
                let recip = CMSPasswordRecipient(info: who! as Data);
                passwordRecipients.append( (recip, what! as Data) );
                
            case OFCMSRKeyTransport:
                let recip = CMSPKRecipient(rid: try CMSRecipientIdentifier.fromDER(who! as Data));
                pkRecipients.append( (recip, what! as Data) )
                
            case OFCMSRPreSharedKey:
                let recip = CMSKEKRecipient(keyIdentifier: who! as Data, key: nil);
                pskRecipients.append( (recip, what! as Data) )

            default:
                discardedRecipientCount += 1;
                break
                
            }
        }
        
        func allRecipients() -> [CMSRecipient] {
            return passwordRecipients.map { $0.0 as CMSRecipient } + pskRecipients.map { $0.0 as CMSRecipient } + pkRecipients.map { $0.0 as CMSRecipient };
        }
    };
    
    /** Parse the provided recipient infos and attempt to recover the message's key (CEK), potentially doing keychain searches or invoking the password prompt on the key source delegate in order to derive keys. */
    private func recoverContentKey(recipientBlobs: NSArray) throws -> (cek: Data, CMSRecipient, [CMSRecipient]) {
        var allRecipients = assortedRecipients();
        
        for (recipientBlob) in recipientBlobs {
            try allRecipients.parse(recipientBlob: recipientBlob as! Data);
        }
        
        if let recipientHint = allRecipients.hint {
            passwordHint = recipientHint
        }

        var cek : Data? = nil; // The content encryption key.
        var keyAccessError : NSError? = nil; // Stored error encountered while iterating over recipients.
        var usedRecipient : CMSRecipient? = nil; // The specific recipient we used.
        
        // Try boring pre-shared key recipients.
        for (recip, wrappedKey) in allRecipients.pskRecipients {
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
            let allowInteraction : Bool;
            if let ks = keySource {
                allowInteraction = ks.isUserInteractionAllowed();
            } else {
                allowInteraction = true;
            }
            for (recip, wrappedKey) in allRecipients.pkRecipients {
                var idents = try recip.rid.findIdentities(allowInteraction: allowInteraction);
                
                for kp in auxiliaryAsymmetricKeys {
                    if let cert = try? kp.certificate() {
                        if recip.rid.matches(certificate: cert) {
                            idents.insert(kp, at: 0);
                        }
                    }
                }
                
                for ident in idents {
                    do {
                        // TODO: We need to pass `allowInteraction` into the underlying crypto operation, but the post-10.7 APIs no longer allow us to do that. (RADAR 29629330, RADAR 29629171)
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
            if let (aCek, aRecip) = try passphrase(allRecipients.passwordRecipients) {
                cek = aCek;
                usedRecipient = aRecip;
            }
        }
        
        if let contentKey = cek {
            return (contentKey, usedRecipient!, allRecipients.allRecipients());
        } else {
            if let err = keyAccessError {
                throw err;
            }
            throw OFError(.OFKeyNotAvailable)
        }
    }
    
    /** Helper for recoverContentKey() for passphrase recipients. */
    private func passphrase(_ passwordRecipients: [(CMSPasswordRecipient, Data)]) throws -> (Data, CMSPasswordRecipient)? {
        
        if passwordRecipients.isEmpty {
            return nil;
        }
        
        guard let keySource = keySource else {
            return nil;
        }
        
        if !keySource.isUserInteractionAllowed() {
            return nil;
        }
        
        var failureCount : Int = 0;
        
        while true {
            let password = try keySource.promptForPassword(withCount: failureCount, hint: passwordHint)
            
            // Probably only one password recipient, but potentially several
            var passwordUseError: Error? = nil
            var anyNotApplicable: Bool = false
            for (passwordRecipient, wrappedKey) in passwordRecipients {
                do {
                    let aCek = try passwordRecipient.unwrap(password: password, data: wrappedKey)
                    return (aCek, passwordRecipient)
                } catch OFError.OFKeyNotApplicable {
                    // Incorrect password. Re-prompt unless another recipient matches.
                    anyNotApplicable = true
                } catch let err {
                    passwordUseError = err
                }
            }
            
            if anyNotApplicable {
                // Incorrect password. Re-prompt.
                failureCount += 1
            } else {
                // We failed for a reason other than an incorrect password.
                throw passwordUseError! // (This could only be nil if we have no passwordRecipients, but we check for that.)
            }
        }
    }
    
    /** The workhorse function: repeatedly unwraps the content contained in the receiver, stopping when we reach a content-type that we can't unwrap. */
    func peelMeLikeAnOnion() throws {
        while true {
            switch contentType {
            case OFCMSContentType_envelopedData:
                try decryptUED();
            case OFCMSContentType_authenticatedEnvelopedData:
                try decryptAEAD();
            case OFCMSContentType_signedData:
                try discardSignature();
            case OFCMSContentType_contentWithAttributes:
                try readAttributes();
            case OFCMSContentType_compressedData:
                try decompress();
            case OFCMSContentType_Unknown:
                throw OFError(.OFUnsupportedCMSFeature, userInfo: [NSLocalizedFailureReasonErrorKey: NSLocalizedString("Unexpected CMS content-type", tableName: "OmniFoundation", bundle: OFBundle, comment: "Document decryption error - unknown content-type found while unwrapping a Cryptographic Message Syntax object")])
            default:
                return;
            }
        }
    }
    
    /** Unwraps an unauthenticated encryption mode (e.g. CBC). See [RFC5652](https://tools.ietf.org/html/rfc5652#section-6) [6]. */
    func decryptUED() throws {
        
        assert(contentType == OFCMSContentType_envelopedData);
        
        var cmsVersion : Int32 = -1;
        let recipientBlobs = NSMutableArray();
        var innerType : OFCMSContentType = OFCMSContentType_Unknown;
        var algorithm : NSData? = nil;
        var innerContent : NSData? = nil;
        var unprotectedAttributes : NSArray? = nil

        let rc = OFASN1ParseCMSEnvelopedData(cms!, contentRange, &cmsVersion, recipientBlobs, &innerType, &algorithm, &innerContent, &unprotectedAttributes)
        if (rc != 0) {
            throw OFNSErrorFromASN1Error(rc, "EnvelopedData");
        }

        // Check version number. Version 4 indicates some features we don't support, but we should fail reasonably on them, so accept it anyway. See RFC5652 [6.1].
        try checkVersion(cmsVersion, "EnvelopedData", min: 0, max: 4);

        // Look for a password hint
        let unprotectedAttrs = try OFCMSUnwrapper.parseAttributes(unprotectedAttributes, innerType: innerType);
        if let hintData = unprotectedAttrs.passwordHintData {
            passwordHint = String(data: hintData, encoding: String.Encoding.utf8)
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
        self.fromContentInfo = false;
        self.usedRecipient = usedRecipient;
        self.allRecipients += allRecipients;
    }

    /** Unwraps an authenticated encryption mode (e.g. CCM or GCM). See [RFC5083](https://tools.ietf.org/html/rfc5083). */
    func decryptAEAD() throws {
        
        assert(contentType == OFCMSContentType_authenticatedEnvelopedData);

        var cmsVersion : Int32 = -1;
        let recipientBlobs = NSMutableArray();
        var innerType : OFCMSContentType = OFCMSContentType_Unknown;
        var algorithm : NSData? = nil;
        var innerContent : NSData? = nil;
        var authenticatedAttributes : NSArray? = nil;
        var unauthenticatedAttributes : NSArray? = nil
        var mac : NSData?;
        
        let rc = OFASN1ParseCMSAuthEnvelopedData(cms!, contentRange, &cmsVersion, recipientBlobs, &innerType, &algorithm, &innerContent, &authenticatedAttributes, &mac, &unauthenticatedAttributes)
        if (rc != 0) {
            throw OFNSErrorFromASN1Error(rc, "AuthEnvelopedData");
        }
        
        // Check version number. See RFC5083 [2.1].
        try checkVersion(cmsVersion, "AuthEnvelopedData", min: 0, max: 0);

        // Look for a password hint
        let unauthenticatedAttrs = try OFCMSUnwrapper.parseAttributes(unauthenticatedAttributes, innerType: innerType);
        if let hintData = unauthenticatedAttrs.passwordHintData {
            passwordHint = String(data: hintData, encoding: String.Encoding.utf8)
        }

        // Parse the attributes.
        let attrs = try OFCMSUnwrapper.parseAttributes(authenticatedAttributes, innerType: innerType);

        // Check that authenticated attributes includes the inner content type (see RFC 5083). For security reasons the content type attribute is only allowed to be missing if the content type is 'data'.
        if !attrs.sawMatchingContentType && innerType != OFCMSContentType_data {
            throw OFError(.OFCMSFormatError, userInfo: [ NSLocalizedFailureReasonErrorKey: "Content-Type missing" ])
        }
        
        let (contentKey, usedRecipient, allRecipients) = try self.recoverContentKey(recipientBlobs: recipientBlobs);
        
        var error : NSError? = nil;
        guard let plaintext = OFCMSDecryptContent(algorithm! as Data, contentKey, innerContent! as Data, authenticatedAttributes as [AnyObject]?, mac as Data?, &error) else {
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
        self.fromContentInfo = false;
        self.authenticated = true;
        self.usedRecipient = usedRecipient;
        self.allRecipients += allRecipients;
    }
    
    /** Unwraps a [SignedData](https://tools.ietf.org/html/rfc5652#section-5) content type. The signature itself is ignored, but any associated keys are retained in embeddedCertificates. */
    func discardSignature() throws {

        assert(contentType == OFCMSContentType_signedData);

        var cmsVersion : Int32 = -1;
        let certificateAccumulator = NSMutableArray();
        let signatureAccumulator = NSMutableArray();
        var innerType : OFCMSContentType = OFCMSContentType_Unknown;
        var innerContentLocation = NSRange();

        let rc = OFASN1ParseCMSSignedData(cms!, contentRange, &cmsVersion, certificateAccumulator, signatureAccumulator, &innerType, &innerContentLocation);
        if (rc != 0) {
            throw OFNSErrorFromASN1Error(rc, "SignedData");
        }
        
        for certificate in certificateAccumulator {
            let certificate = certificate as! NSData;
            embeddedCertificates.append(certificate as Data);
        }
        
        if innerContentLocation.length != 0 {
            cms = OFASN1UnwrapOctetString(cms!, innerContentLocation);
            if cms == nil {
                throw OFError(.OFCMSFormatError, userInfo: [ NSLocalizedFailureReasonErrorKey: "Problem with SignedData.encapsulatedContent" ])
            }
            contentRange = NSRange(location: 0, length: cms!.count);
        } else {
            cms = nil;
        }
        contentType = innerType;
        fromContentInfo = false;
        
    }
    
    /** Unwraps a [ContentCollection](https://tools.ietf.org/html/rfc4073#section-2) type (RFC 4073). Unlike the other unwrap methods, this returns a sequence of new CMSUnwrapper objects (referencing slices of the receiver's data) rather than modifying the receiver. */
    func splitParts() throws -> [OFCMSUnwrapper] {
        
        assert(contentType == OFCMSContentType_contentCollection);
        
        let cms_ = cms!;
        
        var results : [OFCMSUnwrapper] = [];
        let rc = OFASN1ParseCMSMultipartData(cms_, contentRange) { (ct: OFCMSContentType, r: NSRange) -> Int32 in
            let part = OFCMSUnwrapper(data: cms_, location: r, type: ct, keySource: keySource);
            part.fromContentInfo = true;
            part.authenticated = authenticated;
            results.append(part);
            return 0;
        };
        if (rc != 0) {
            throw OFNSErrorFromASN1Error(rc, "ContentCollection");
        }
        
        return results;
    }
    
    /** Unwraps a compressed part ([RFC 3274](https://tools.ietf.org/html/rfc3274)) */
    func decompress() throws {
        
        assert(contentType == OFCMSContentType_compressedData);
        
        var cmsVersion : Int32 = -1;
        var innerType : OFCMSContentType = OFCMSContentType_Unknown;
        var algorithm : OFASN1Algorithm = OFASN1Algorithm_Unknown;
        var innerContentLocation = NSRange();

        let rc = OFASN1ParseCMSCompressedData(cms!, contentRange, &cmsVersion, &algorithm, &innerType, &innerContentLocation);
        if (rc != 0) {
            throw OFNSErrorFromASN1Error(rc, "CompressedData");
        }

        // Check version number. See RFC3274 [1.1].
        try checkVersion(cmsVersion, "CompressedData", min: 0, max: 0);

        var error : NSError? = nil;
        guard let expanded = OFCMSDecompressContent(cms!, innerContentLocation, algorithm, &error) else {
            throw error!;
        }
        
        let cms_ = OFNSDataFromDispatchData(expanded);
        cms = cms_;
        contentRange = NSRange(location: 0, length: cms_.count);
        contentType = innerType;
        fromContentInfo = false;
    }
    
    /** Unwraps an attributed-data item, for cases where we don't have an enclosing part that holds attributes. ([RFC 4073](https://tools.ietf.org/html/rfc4073#section-3)) */
    func readAttributes() throws {

        assert(contentType == OFCMSContentType_contentWithAttributes);

        var innerType : OFCMSContentType = OFCMSContentType_Unknown;
        var innerContentLocation = NSRange();
        var attributes : NSArray? = nil;

        let rc = OFASN1ParseCMSAttributedContent(cms!, contentRange, &innerType, &innerContentLocation, &attributes);
        if (rc != 0) {
            throw OFNSErrorFromASN1Error(rc, "ContentWithAttributes");
        }

        // Parse the attributes.
        let attrs = try OFCMSUnwrapper.parseAttributes(attributes, innerType: innerType);
        
        contentRange = innerContentLocation;
        contentType = innerType;
        fromContentInfo = true;
        
        // The only atribute we process in this case is the content identifier
        if attrs.contentIdentifier != nil {
            self.contentIdentifier = attrs.contentIdentifier;
        }
    }
    
    private struct parsedAttributes {
        let sawMatchingContentType : Bool;
        let contentIdentifier : Data?;
        let messageDigest : Data?;
        var passwordHintData: Data?
    };
    private static func parseAttributes(_ attributes_: NSArray?, innerType: OFCMSContentType) throws -> parsedAttributes {
        var sawMatchingContentType = false
        var contentIdentifier: Data? = nil
        var messageDigest: Data? = nil
        var passwordHintData: Data? = nil

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
                    
                case OFCMSAttribute_omniHint:
                    passwordHintData = attrData as Data?

                //case OFCMSAttribute_signingTime:
                default:
                    break;
                }
            }
        }
        
        return parsedAttributes(sawMatchingContentType: sawMatchingContentType, contentIdentifier: contentIdentifier, messageDigest: messageDigest, passwordHintData: passwordHintData)
    }
}

private func unexpectedNullContent() -> Error {
    return OFError(.OFEncryptedDocumentFormatError, userInfo: [ NSLocalizedFailureReasonErrorKey: "Unexpected null content" ])
}

private
func checkVersion(_ version: Int32, _ location: String, min: Int32, max: Int32) throws {
    if (version < min || version > max) {
        throw OFError(.OFUnsupportedCMSFeature, userInfo: [ NSLocalizedFailureReasonErrorKey: "Unsupported \(location) version (expected \(min)-\(max), found \(version))" ])
    }
}
