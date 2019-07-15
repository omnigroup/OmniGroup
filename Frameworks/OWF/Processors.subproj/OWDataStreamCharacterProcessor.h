// Copyright 2000-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OWF/OWProcessor.h>
#import <CoreFoundation/CFString.h>

@class OWAddress, OWDataStreamCursor, OWDataStreamCharacterCursor, OWParameterizedContentType, OWPipeline;

// If these keys are set in the pipeline's context dictionary, they should have a value which is an NSNumber
extern NSString *OWEncodingDefaultContextKey;
    // This indicates the CFStringEncoding to use in the absense of charset headers

extern NSString *OWEncodingOverrideContextKey;
    // This indicates the CFStringEncoding to use regardless of charset headers

@interface OWDataStreamCharacterProcessor : OWProcessor
{
    OWDataStreamCharacterCursor *characterCursor;
}

// + (CFStringEncoding)stringEncodingForAddress:(OWAddress *)anAddress;
+ (CFStringEncoding)defaultStringEncoding;
+ (CFStringEncoding)stringEncodingForDefault:(NSString *)encodingName;
+ (NSString *)defaultForCFEncoding:(CFStringEncoding)anEncoding;
+ (CFStringEncoding)stringEncodingForIANACharSetName:(NSString *)charset;

+ (CFStringEncoding)stringEncodingForContentType:(OWParameterizedContentType *)aType; // returns InvalidId if unspecified; call -defaultStringEncoding

+ (NSString *)charsetForCFEncoding:(CFStringEncoding)anEncoding;

- (CFStringEncoding)chooseStringEncoding:(OWDataStreamCursor *)dataCursor content:(OWContent *)sourceContent;

@end
