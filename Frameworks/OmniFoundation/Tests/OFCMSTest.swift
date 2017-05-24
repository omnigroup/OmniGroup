// Copyright 2016-2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// RCS_ID("$Id$")

import Foundation
import XCTest
@testable import OmniFoundation
@testable import OmniFoundation.Private

class keysource : OFCMSKeySource {
    
    var password: String? = nil;
    var keypairs: [ (SecCertificate, SecKey) ] = [];
    
    @objc(promptForPasswordWithCount:hint:error:) func promptForPassword(withCount _: Int, hint: String?) throws -> String {
        
        if let result = self.password {
            return result;
        }
        
        var buf = Array(repeating: Int8(0), count: 128);
        let rv = readpassphrase("foo", &buf, buf.count, 0);
        if rv == nil {
            throw NSError(domain: OFErrorDomain, code: OFKeyNotAvailable, userInfo: nil);
        } else {
            guard let str = NSString(bytes: buf, length: Int(strlen(buf)), encoding: String.Encoding.utf8.rawValue) else {
                throw NSError(domain: NSCocoaErrorDomain, code: NSFileReadUnknownStringEncodingError, userInfo: nil);
            }
            guard str.length > 0 else {
                throw NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError, userInfo: nil);
            }
            return str as String;
        }
    }
    
    @objc
    func isUserInteractionAllowed() -> Bool {
        return true;
    }
    
    #if false  // This part of the protocol has never actually been needed
    @objc(asymmetricKeysForQuery:error:) func asymmetricKeys(forQuery searchPattern: CFDictionary) throws -> [Any] {
        
        if !keypairs.isEmpty {
            guard let cls = (searchPattern as NSDictionary)[kSecClass] as? NSObject? else {
                throw NSError(domain:NSOSStatusErrorDomain, code:-50, userInfo:nil);
            }
            if cls == kSecClassCertificate {
                return keypairs.map({ (cert, _) -> SecCertificate in cert });
            } else if cls == kSecClassKey {
                return keypairs.map({ (_, key) -> SecKey in key });
            }
        }
        
        throw NSError(domain: OFErrorDomain, code: OFKeyNotAvailable, userInfo: nil);
    }
    #endif
}

class OFCMSTest : XCTestCase {
    
    // This is the encoded message from RFC 4134 [5.1]/[5.3].
    let rfc4134_5_3 = "MIIBHgYJKoZIhvcNAQcDoIIBDzCCAQsCAQAxgcAwgb0CAQAwJjASMRAwDgYDVQQDEwdDYXJsUlNBAhBGNGvHgABWvBHTbi7NXXHQMA0GCSqGSIb3DQEBAQUABIGAC3EN5nGIiJi2lsGPcP2iJ97a4e8kbKQz36zg6Z2i0yx6zYC4mZ7mX7FBs3IWg+f6KgCLx3M1eCbWx8+MDFbbpXadCDgO8/nUkUNYeNxJtuzubGgzoyEd8Ch4H/dd9gdzTd+taTEgS0ipdSJuNnkVY4/M652jKKHRLFf02hosdR8wQwYJKoZIhvcNAQcBMBQGCCqGSIb3DQMHBAgtaMXpRwZRNYAgDsiSf8Z9P43LrY4OxUk660cu1lXeCSFOSOpOJ7FuVyU=";
    
    // This is the corresponding certificate for Bob (issuer=carl, sn=46:34:...) certificate from RFC 4134.
    let rfc4134_carl_issued_to_bob = "MIICJzCCAZCgAwIBAgIQRjRrx4AAVrwR024uzV1x0DANBgkqhkiG9w0BAQUFADASMRAwDgYDVQQDEwdDYXJsUlNBMB4XDTk5MDkxOTAxMDkwMloXDTM5MTIzMTIzNTk1OVowETEPMA0GA1UEAxMGQm9iUlNBMIGfMA0GCSqGSIb3DQEBAQUAA4GNADCBiQKBgQCp4WeYPznVX/Kgk0FepnmJhcg1XZqRW/sdAdoZcCYXD72lItA1hW16mGYUQVzPt7cIOwnJkbgZaTdt+WUee9mpMySjfzu7r0YBhjY0MssHA1lS/IWLMQS4zBgIFEjmTxz7XWDE4FwfU9N/U9hpAfEF+Hpw0b6Dxl84zxwsqmqn6wIDAQABo38wfTAMBgNVHRMBAf8EAjAAMA4GA1UdDwEB/wQEAwIFIDAfBgNVHSMEGDAWgBTp4JAnrHggeprTTPJCN04irp44uzAdBgNVHQ4EFgQU6PS4Z9izlqQq8xGqKdOVWoYWtCQwHQYDVR0RBBYwFIESQm9iUlNBQGV4YW1wbGUuY29tMA0GCSqGSIb3DQEBBQUAA4GBAHuOZsXxED8QIEyIcat7QGshM/pKld6dDltrlCEFwPLhfirNnJOIh/uLt359QWHh5NZt+eIEVWFFvGQnRMChvVl52R1kPCHWRbBdaDOS6qzxV+WBfZjmNZGjOd539OgcOyncf1EHl/M28FAK3Zvetl44ESv7V+qJba3JiNiPzyvT";
    // Values extracted using openssl
    let bobcert_ski = Data(bytes: [0xE8, 0xF4, 0xB8, 0x67, 0xD8, 0xB3, 0x96, 0xA4, 0x2A, 0xF3, 0x11, 0xAA, 0x29, 0xD3, 0x95, 0x5A, 0x86, 0x16, 0xB4, 0x24]);
    let bobcert_serial = Data(bytes: [0x46, 0x34, 0x6b, 0xc7, 0x80, 0x00, 0x56, 0xbc, 0x11, 0xd3, 0x6e, 0x2e, 0xcd, 0x5d, 0x71, 0xd0]);
    let bobcert_issuer = Data(bytes: [0x30, 0x12, 0x31, 0x10, 0x30, 0x0e, 0x06, 0x03, 0x55, 0x04, 0x03, 0x13, 0x07, 0x43, 0x61, 0x72, 0x6c, 0x52, 0x53, 0x41])

    // And Bob's private key
    let rfc4134_bob_private = "MIICXAIBAAKBgQCp4WeYPznVX/Kgk0FepnmJhcg1XZqRW/sdAdoZcCYXD72lItA1hW16mGYUQVzPt7cIOwnJkbgZaTdt+WUee9mpMySjfzu7r0YBhjY0MssHA1lS/IWLMQS4zBgIFEjmTxz7XWDE4FwfU9N/U9hpAfEF+Hpw0b6Dxl84zxwsqmqn6wIDAQABAoGAZ81ITJoNj5jCG2X/IoOcbfCmBh287acDiJTyHGsPizXeDoJ4MMvnumpWrXfG61F5cHkKoPT+ReCpsvQZ2oeY1jCEdOT8WWzBxnfcqZHQfDCgosUIXiFxQ/wNBz3w+m0Unk5j8BdYeRxLmBw9PbAb3/olO6PALJgF9hAJ2IfbAxkCQQDQwyLG3qKZGHaPjbymddZmP9SNRVKMdvVyxOvwRprxPlyqVQub2t1rbfj8OzwIQ5O1W/7O6v1ohCNir/MxwrnlAkEA0FH8HiK3W+21jgHI16vyWNT3gpTzU6gZRctmyigZX+IQK/OP7GowdPhNEfSnxCC1RyHcSQH5CiAp8CQIhGB9jwJANLpkyUgoV3TXVVDeakjvGypaHEh7HiFZw2A7m5epwO8YZqlOYlI4hM7lCYhIlGnFIBSZWlf+I2zkpyN70IC3hQJBAJ4vszea+wsGXVfhCQakXdmQlgYFXyQGQHKcOoiFnIcPnWISiBZoqDUaG0PoOMCYaa8DCkgyBE7pD493fTQwJQcCQFcYZ9YK0rWrwrp651TanAVPgdTvAYkeMj1pyzHEUshUVSUAOxwqfCZQ1emm13fLzxX17gvVje6zr0yhfGNGQfY=";
    
    let plaintext = "Greetings, Professor Falken. A strange game. The only winning move is not to play. How about a nice game of chess?";
    
    private var bobpair : Keypair {
        let bobcert = SecCertificateCreateWithData(kCFAllocatorDefault, NSData(base64Encoded: rfc4134_carl_issued_to_bob, options: [])!)!;

        let bobpriv = NSData(base64Encoded: rfc4134_bob_private, options: [])! as Data;
        let bobprivk = OFSecCopyPrivateKeyFromPKCS1Data(bobpriv)!;
        
        return Keypair.secCertificate(cert: bobcert, key: bobprivk);
    }
    
    func testPasswordRecipients() throws {
        
        let test_password = "hello";
        
        let cek = NSData.cryptographicRandomData(ofLength: 32);
        let ri = CMSPasswordRecipient(password: test_password);
        let rinfo = try ri.recipientInfo(wrapping: cek);
        
        var who : NSData? = nil;
        var what : NSData? = nil;
        var recipientType : OFCMSRecipientType = OFCMSRUnknown;
        let err = _OFASN1ParseCMSRecipient(rinfo, &recipientType, &who, &what);
        if let err = err {
            throw err;
        }
        XCTAssertEqual(recipientType, OFCMSRPassword);

        let ri_out = CMSPasswordRecipient(info: who! as Data);
        let cek_out = try ri_out.unwrap(password: test_password, data: what! as Data);
        
        XCTAssertEqual(cek, cek_out);
    }
    
    func testPKRecipient4134() throws {
        let message = NSData(base64Encoded: rfc4134_5_3, options: [])!;
        let ri = message.subdata(with: NSRange(location: 29, length: 192));
        
        var who : NSData? = nil;
        var what : NSData? = nil;
        var recipientType : OFCMSRecipientType = OFCMSRUnknown;
        let err = _OFASN1ParseCMSRecipient(ri, &recipientType, &who, &what);
        if let err = err {
            throw err;
        }
        XCTAssertEqual(recipientType, OFCMSRKeyTransport);
        
        let rid = try CMSRecipientIdentifier.fromDER(who! as Data);
        guard case CMSRecipientIdentifier.issuerSerial(let issu, let sn) = rid else {
            XCTAssert(false, "Parsed rid is not an issuerAndSerial");
            return;
        }
        
        XCTAssertEqual(issu, bobcert_issuer);
        XCTAssertEqual(sn, bobcert_serial);
        
        let parsable = OFASN1EnumerateAVAsInName(issu, { (attr, val, rdnseq, _) -> ()
            in
            XCTAssertEqual(attr, Data(bytes: [ 0x55, 0x04, 0x03 ]));
            XCTAssertEqual(OFASN1UnDERString(val), "CarlRSA");
            XCTAssertEqual(rdnseq, 0);
        });
        XCTAssertTrue(parsable, "OFASN1EnumerateAVAsInName");
        
        guard let cert = SecCertificateCreateWithData(kCFAllocatorDefault, NSData(base64Encoded: rfc4134_carl_issued_to_bob, options: [])!) else {
            XCTAssert(false, "SecCertificateCreateWithData");
            return;
        }
        XCTAssertTrue(rid.matches(certificate: cert));
        
        let cek = try CMSPKRecipient(rid: rid).unwrap(identity: bobpair, data: what! as Data);
        // This is the 3DES key we expect
        XCTAssertEqual(cek, Data(bytes: [ 0x08, 0x46, 0x76, 0x3b, 0x5d, 0xa1, 0x16, 0x6d, 0xef, 0x29, 0xfb, 0x1a, 0xd5, 0xd6, 0xfd, 0x85, 0x01, 0x07, 0x19, 0xe3, 0x04, 0x4c, 0xad, 0x19 ]));
    }
    
    func testPKRecipient_matching() throws {
        let bobcert = try bobpair.certificate()!;
        
        let pkrecip = try CMSPKRecipient(certificate: bobcert);
        
        guard case CMSRecipientIdentifier.keyIdentifier(ski: bobcert_ski) = pkrecip.rid else {
            XCTAssert(false, "Parsed rid \(pkrecip.rid) does not match expected value");
            return;
        }

        XCTAssertTrue(pkrecip.rid.matches(certificate: bobcert));
        
        XCTAssertFalse(CMSRecipientIdentifier.keyIdentifier(ski: Data(bytes: [0x01, 0x02, 0x03])).matches(certificate: bobcert));
        XCTAssertTrue(CMSRecipientIdentifier.issuerSerial(issuer: bobcert_issuer, serial: bobcert_serial).matches(certificate: bobcert));
        XCTAssertFalse(CMSRecipientIdentifier.issuerSerial(issuer: bobcert_issuer, serial: Data(bytes: [0x01, 0x02, 0x03])).matches(certificate: bobcert));
    }
    
    func testKeyTransportRSA() throws {
        let bobcert = try bobpair.certificate()!;
        
        let pkrecip = try CMSPKRecipient(certificate: bobcert);
        
        let sampleCEK = NSData.cryptographicRandomData(ofLength: 16);
        let rinfo = try pkrecip.recipientInfo(wrapping: sampleCEK);
        
        var who : NSData? = nil;
        var what : NSData? = nil;
        var recipientType : OFCMSRecipientType = OFCMSRUnknown;
        let err = _OFASN1ParseCMSRecipient(rinfo, &recipientType, &who, &what);
        if let err = err {
            throw err;
        }
        XCTAssertEqual(recipientType, OFCMSRKeyTransport);
        
        let recip = try CMSPKRecipient(rid: CMSRecipientIdentifier.fromDER(who! as Data));
        
        let transported = try recip.unwrap(identity: bobpair, data: what! as Data);
        
        XCTAssertEqual(sampleCEK, transported);
    }
    
    func testEnvelopedCompat() throws {
        // Tests compatibility with a message generated by OpenSSL (1.0.2)
        let message = NSData(base64Encoded:"MIIBiQYJKoZIhvcNAQcDoIIBejCCAXYCAQAxgcAwgb0CAQAwJjASMRAwDgYDVQQDEwdDYXJsUlNBAhBGNGvHgABWvBHTbi7NXXHQMA0GCSqGSIb3DQEBAQUABIGAAmpX4OoRWmcK2k/KLD21vluwOosT2Fc+Zfag9j2CAnWK7OJmI7/Kl/GjdGK87gqJez2qazKPT7aOoZb9XJ7Oldbxf4QODL6bGYk6eWsnMOadxpv8yoZtXbWzk2xv38y/JCMBhlBWrjwi6Ce+sQWNarbz5KZPI08+kwyHyOBYqBEwga0GCSqGSIb3DQEHATAdBglghkgBZQMEASoEECpUJ6p32YGXkcQ+tz/E9GeAgYDZ1emn7XlMqU2diY61oc3Rfr8nU19VaU/+jCOZFX5+HGqW32LSATawlnHvH7peACYcGmDKA1tnhTmy1fZ8PjWC4RNPjKGsfxYGtyPB30zZ8bkZwo+9+6Cp9Jj3ptYwJHKuJLc0XsH+Od0YsUK+TpDrpyNliBlnEXFJ9UfSha1Khg==", options: [])!;
        let content = plaintext.data(using: String.Encoding.ascii)!;
        
        let delegate = keysource();
        let bob = self.bobpair;
        
        let decr = try OFCMSUnwrapper(data: message as Data, keySource: delegate);
        XCTAssertEqual(decr.contentType, OFCMSContentType_envelopedData);
        
        decr.auxiliaryAsymmetricKeys.append(bob);
        
        try decr.peelMeLikeAnOnion();
        XCTAssertEqual(decr.contentType, OFCMSContentType_data);
        XCTAssertEqual(try decr.content(), content);
        
        #if false  // Currently disabled because "enable testability" doesn't seem to work with C symbols
        // Test round-tripping that message
        let cek192 = NSData.cryptographicRandomData(ofLength: 24);
        var error: NSError? = nil;
        guard let message2i = try OFCMSCreateEnvelopedData(cek192,
                                                           [ CMSPKRecipient(certificate: bob.certificate()!).recipientInfo(wrapping: cek192) ],
                                                           OFCMSContentType_XML.asDER(), content, &error) else {
            throw error!;
        }
        let message2 = OFCMSWrapContent(OFCMSContentType_envelopedData, message2i as AnyObject as! Data);
        
        let decr2 = try OFCMSUnwrapper(data: OFNSDataFromDispatchData(message2), keySource: delegate);
        XCTAssertEqual(decr2.contentType, OFCMSContentType_envelopedData);
        
        decr2.auxiliaryAsymmetricKeys.append(bob);
        
        try decr2.peelMeLikeAnOnion();
        XCTAssertEqual(decr2.contentType, OFCMSContentType_XML);
        XCTAssertEqual(try decr2.content(), content);
        #endif
    }

    #if WITH_RFC3211_KEY_WRAP
    func testRFC3211Recipients() throws {
        
        // Test data from RFC3211, with two changes:
        // - The outer tag's length has been corrected from 96 to 111 (and then to 114, because of the below)
        // - The implicit PBKDF2 output length has been replaced with an explicit one (we don't support the implicit length)
        let example_page11 : [UInt8] = [
            0xA3,  114,
            0x02,    1, 0x00,
            0xA0,   30,
            0x06,    9, 0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x05, 0x0C,
            0x30,   17,
            0x04,    8, 0x12, 0x34, 0x56, 0x78, 0x78, 0x56, 0x34, 0x12,
            0x02,    2, 0x01, 0xF4,
            0x02,    1, 0x18,
            0x30,   35,
            0x06,   11, 0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x09, 0x10, 0x03, 0x09,
            0x30,   20,
            0x06,    8, 0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x03, 0x07,
            0x04,    8, 0xBA, 0xF1, 0xCA, 0x79, 0x31, 0x21, 0x3C, 0x4E,
            0x04,   40,
                        0xC0, 0x3C, 0x51, 0x4A, 0xBD, 0xB9, 0xE2, 0xC5,
                        0xAA, 0xC0, 0x38, 0x57, 0x2B, 0x5E, 0x24, 0x55,
                        0x38, 0x76, 0xB3, 0x77, 0xAA, 0xFB, 0x82, 0xEC,
                        0xA5, 0xA9, 0xD7, 0x3F, 0x8A, 0xB1, 0x43, 0xD9,
                        0xEC, 0x74, 0xE6, 0xCA, 0xD7, 0xDB, 0x26, 0x0C
        ];
        let cek_page11 : [UInt8] = [
            0x8C, 0x63, 0x7D, 0x88, 0x72, 0x23, 0xA2, 0xF9,
            0x65, 0xB5, 0x66, 0xEB, 0x01, 0x4B, 0x0F, 0xA5,
            0xD5, 0x23, 0x00, 0xA3, 0xF7, 0xEA, 0x40, 0xFF,
            0xFC, 0x57, 0x72, 0x03, 0xC7, 0x1B, 0xAF, 0x3B
        ];
        
        var who : NSData? = nil;
        var what : NSData? = nil;
        var recipientType : OFCMSRecipientType = OFCMSRUnknown;
        let err = _OFASN1ParseCMSRecipient(Data(bytes: example_page11), &recipientType, &who, &what);
        if let err = err {
            throw err;
        }
        XCTAssertEqual(recipientType, OFCMSRPassword);
        
        let ri_out = CMSPasswordRecipient(info: who! as Data);
        let cek_out = try ri_out.unwrap(password: "All n-entities must communicate with other n-entities via n-1 entiteeheehees", data: what! as Data);
        
        XCTAssertEqual(Data(bytes: cek_page11), cek_out);
    }
    #endif
    
    func testRFC4134() throws {
        let message = NSData(base64Encoded: rfc4134_5_3, options: [])!;
        let delegate = keysource();
        
        let decr = try OFCMSUnwrapper(data: message as Data, keySource: delegate);
        XCTAssertEqual(decr.contentType, OFCMSContentType_envelopedData);
        
        decr.auxiliaryAsymmetricKeys.append(self.bobpair);
        
        try decr.decryptUED();
        XCTAssertEqual(decr.contentType, OFCMSContentType_data);
        XCTAssertEqual(try decr.content(), "This is some sample content.".data(using: String.Encoding.ascii));
    }
    
    func testFileWrapper() throws {
        let plaintext = "Bork bork bork?\n".data(using: String.Encoding.utf8)!;
        let password = "aplets & cotlets";
        let input = FileWrapper(regularFileWithContents: plaintext);
        let wr = OFCMSFileWrapper();
        let del = keysource();
        del.password = password;
        wr.delegate = del;
        let wrapped = try wr.wrap(input: input, previous: nil, schema: nil, recipients: [ CMSPasswordRecipient(password: password) ], options: []);
        
        XCTAssertTrue(wrapped.isRegularFile);
        XCTAssertGreaterThan(wrapped.regularFileContents!.count, plaintext.count, "Encryption has nonzero overhead");
        
        let unwrapped = try wr.unwrap(input: wrapped);
        
        XCTAssertEqual(plaintext, unwrapped.regularFileContents);
    }
    
    func testDirectoryWrapper() throws {
        
        let names = [ "SomeFile", "otherfile.png", "contents.xml", "doom" ];
        var initialData : [String:String] = [:];
        var members : [String:FileWrapper] = [:];
        for name in names {
            let content = "This is the content of the file wrapper named \"\(name)\".\n";
            initialData[name] = content;
            let member = FileWrapper(regularFileWithContents: content.data(using: String.Encoding.utf8)!);
            member.preferredFilename = name;
            members[name] = member;
        }
        let input = FileWrapper(directoryWithFileWrappers: members);

        let password = "kibbles & bits";
        let keypair = bobpair;
        
        let wr = OFCMSFileWrapper();
        let del = keysource();
        del.password = password;
        wr.delegate = del;
        let wrapped = try wr.wrap(input: input, previous: nil, schema: nil, recipients: [
            CMSPasswordRecipient(password: password),
            CMSPKRecipient(certificate: keypair.certificate()!)
            ], options: []);
        
        XCTAssertTrue(wrapped.isDirectory);
        
        // First, try unwrapping using the password we stuffed in the delegate
        
        let unwrapped = try wr.unwrap(input: wrapped);
        
        var unwrappedMembers : [String: String] = [:];
        for (k, v) in unwrapped.fileWrappers! {
            XCTAssertTrue(v.isRegularFile);
            unwrappedMembers[k] = String(data: v.regularFileContents!, encoding: String.Encoding.utf8)!;
        }
        
        XCTAssertEqual(wr.recipientsFoo.count, 2);
        XCTAssertTrue(wr.usedRecipient is CMSPasswordRecipient);
        
        XCTAssertEqual(initialData, unwrappedMembers)
        
        // Next, try unwrapping using the private key
        
        let wr2 = OFCMSFileWrapper();
        wr2.delegate = keysource();
        wr2.auxiliaryAsymmetricKeys.append(keypair);
        
        let unwrapped2 = try wr2.unwrap(input: wrapped);
        
        unwrappedMembers = [:];
        for (k, v) in unwrapped2.fileWrappers! {
            XCTAssertTrue(v.isRegularFile);
            unwrappedMembers[k] = String(data: v.regularFileContents!, encoding: String.Encoding.utf8)!;
        }
        
        XCTAssertEqual(wr2.recipientsFoo.count, 2);
        XCTAssertTrue(wr2.usedRecipient is CMSPKRecipient);
        let pkrecip = wr2.usedRecipient as! CMSPKRecipient;
        XCTAssertTrue(pkrecip.rid.matches(certificate: try keypair.certificate()!));
        // XCTAssertFalse(pkrecip.rid.matches(certificate: ...));
        
        XCTAssertEqual(initialData, unwrappedMembers)
    }

    fileprivate enum wrapperPrototype {
        case file(String);
        case dir([String : wrapperPrototype]);
        
        func toWrapper() -> FileWrapper {
            switch self {
            case .file(let txt):
                return FileWrapper(regularFileWithContents: txt.data(using: String.Encoding.utf8)!);
            case .dir(let kkvv):
                var entries : [String : FileWrapper] = [:];
                for (fn, fc) in kkvv {
                    entries[fn] = fc.toWrapper();
                }
                return FileWrapper(directoryWithFileWrappers: entries);
            }
        }
        
        func matchesWrapper(_ input: FileWrapper) -> Bool {
            switch self {
            case .file(let txt):
                XCTAssertTrue(input.isRegularFile);
                if !input.isRegularFile {
                    return false;
                }
                let expected = txt.data(using: String.Encoding.utf8);
                XCTAssertEqual(input.regularFileContents, expected);
                return (input.regularFileContents == expected);
            case .dir(let kkvv):
                XCTAssertTrue(input.isDirectory);
                if !input.isDirectory {
                    return false;
                }
                let entries = input.fileWrappers!;
                XCTAssertEqual(Set(kkvv.keys), Set(entries.keys));
                if !(Set(kkvv.keys) == Set(entries.keys)) {
                    return false;
                }
                return !kkvv.contains(where: { (akey, avalue) -> Bool in !avalue.matchesWrapper(entries[akey]!) });
            }
        }
    }
    
    func testDeeperDirectoryWrapper() throws {
        let input = wrapperPrototype.dir([
            "Hello": wrapperPrototype.file("Hello thing"),
            "EmptyDir": wrapperPrototype.dir([:]),
            "NonEmptyDir": wrapperPrototype.dir([
                "EmptyFile": wrapperPrototype.file(""),
                "bloop…": wrapperPrototype.file("bloop"),
                "Further...": wrapperPrototype.dir( [
                    "Further...": wrapperPrototype.dir([
                        "zo\"om>!": wrapperPrototype.file("Until the thrill of speed overcomes the fear of death"),
                        "Hello": wrapperPrototype.file("Different hello thing")
                        ])
                    ]),
                ]),
            ]);
        
        // Round-trip it through something
        
        let password = "kibbles & bits";
        let wr = OFCMSFileWrapper();
        let del = keysource();
        del.password = password;
        wr.delegate = del;
        let inputWrapper = input.toWrapper();
        debugPrintWrapper(inputWrapper);
        let wrapped = try wr.wrap(input: inputWrapper, previous: nil, schema: nil, recipients: [ CMSPasswordRecipient(password: password) ], options: []);
        debugPrintWrapper(wrapped);
        
        XCTAssertTrue(wrapped.isDirectory);
        for (_, contentFile) in wrapped.fileWrappers! {
            XCTAssertTrue(contentFile.isRegularFile);
        }
        
        let unwrapped = try wr.unwrap(input: wrapped);

        debugPrintWrapper(unwrapped);

        XCTAssert(input.matchesWrapper(unwrapped));
    }
    
    func testWrapperWithSchema() throws {
        let infiles = [
            "contents.txt": wrapperPrototype.file("I am some contents"),
            "thing": wrapperPrototype.file("I am some thing-contents"),
            "thang": wrapperPrototype.file("<stuff>I am some thang-contents</stuff>"),
            ];
        let input = wrapperPrototype.dir(infiles);
        
        let password = "many a forgotten volume";
        let recips = [ CMSPasswordRecipient(password: password) ];
        
        let wr = OFCMSFileWrapper();
        let del = keysource();
        del.password = password;
        wr.delegate = del;

        let exposed_thing : [String: AnyObject] = [OFDocEncryptionExposeName: "thing.cms" as AnyObject, OFDocEncryptionFileOptions: [OFCMSOptions.fileIsOptional] as OFCMSOptions as AnyObject];
        let bundled_ct    : [String: AnyObject] = [OFDocEncryptionFileOptions: [OFCMSOptions.storeInMain] as OFCMSOptions as AnyObject]
        
        let wrapped = try wr.wrap(input: input.toWrapper(), previous: nil,
                                  schema: [ "thing" : exposed_thing as AnyObject, "contents.txt" : bundled_ct as AnyObject ],
                                  recipients: recips, options: []);
        debugPrintWrapper(wrapped);

        // Verify that we have three files, one of which is "thing.cms"
        let wrappedFiles = wrapped.fileWrappers!;
        XCTAssertEqual(wrappedFiles.count, 3);
        XCTAssertNotNil(wrappedFiles["thing.cms"]);

        // Verify unwrappability
        let unwrapped = try wr.unwrap(input: wrapped);
        XCTAssert(input.matchesWrapper(unwrapped));
        
        // Verify optionality of the 'thing.cms' content
        wrapped.removeFileWrapper(wrappedFiles["thing.cms"]!);
        let unwrapped2 = try wr.unwrap(input: wrapped);
        var expected2 = infiles;
        expected2.removeValue(forKey: "thing");
        XCTAssert(wrapperPrototype.dir(expected2).matchesWrapper(unwrapped2));
        
    }
}

internal
func debugPrintWrapper(_ wrapper: FileWrapper, name: String? = nil, indent: UInt = 0) {
    let lhs = NSString.spaces(ofLength: indent) + ( name == nil ? "" : "\( name! ): " );
    if wrapper.isRegularFile {
        debugPrint("\(lhs)Regular file of length \( wrapper.regularFileContents!.count )");
    } else if wrapper.isDirectory {
        let items = wrapper.fileWrappers!;
        debugPrint("\(lhs)Directory containing \( items.count ) entries");
        for (k, v) in items {
            debugPrintWrapper(v, name: k, indent: indent + 4);
        }
    }
}

