// Copyright 2000-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <Foundation/NSString.h>
#import <CoreFoundation/CFString.h>

#import <OmniFoundation/OFUnicodeUtilities.h>
#import <OmniBase/objc.h>

struct OFStringDecoderState {
    CFStringEncoding encoding;
    
    union {
       struct {
          unsigned int partialCharacter;  /* must be at least 31 bits */
          unsigned short utf8octetsremaining;
       } utf8;
       /* TODO: more state vars for other encodings */
    } vars;
};

struct OFCharacterScanResult {
    struct OFStringDecoderState state;
        
    NSUInteger bytesConsumed;
    NSUInteger charactersProduced;
};

/* Information about encodings */
extern BOOL OFCanScanEncoding(CFStringEncoding anEncoding);
extern BOOL OFEncodingIsSimple(CFStringEncoding anEncoding);

/* Functions for decoding a string */
extern struct OFStringDecoderState OFInitialStateForEncoding(CFStringEncoding anEncoding);
extern struct OFCharacterScanResult OFScanCharactersIntoBuffer(struct OFStringDecoderState state,  const unsigned char *in_bytes, NSUInteger in_bytes_count, unichar *out_characters, NSUInteger out_characters_max);
extern BOOL OFDecoderContainsPartialCharacters(struct OFStringDecoderState state);

/* An exception which can be raised by the above functions */
extern NSString * const OFCharacterConversionExceptionName;

/* For applying an encoding to a string which was scanned using OFDeferredASCIISupersetStringEncoding. See also -[NSString stringByApplyingDeferredCFEncoding:]. */
extern NSString *OFApplyDeferredEncoding(NSString *str, CFStringEncoding newEncoding);
extern NSString *OFMostlyApplyDeferredEncoding(NSString *str, CFStringEncoding newEncoding);
extern BOOL OFStringContainsDeferredEncodingCharacters(NSString *str);
/* This is equivalent to CFStringCreateExternalRepresentation(), except that it maps characters in our private-use deferred encoding range back into the bytes from whence they came */
extern CFDataRef OFCreateDataFromStringWithDeferredEncoding(CFStringRef str, CFRange range, CFStringEncoding newEncoding, UInt8 lossByte) CF_RETURNS_RETAINED;

