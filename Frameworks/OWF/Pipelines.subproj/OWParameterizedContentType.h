// Copyright 2000-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFObject.h>

@class NSLock;
@class OWContentType, OFMultiValueDictionary;

@interface OWParameterizedContentType : OFObject <NSMutableCopying>
{
    OWContentType *contentType;
    OFMultiValueDictionary *_parameters;
    NSLock *_parameterLock;
}

+ (OWParameterizedContentType *)contentTypeForString:(NSString *)aString;

- initWithContentType:(OWContentType *)aType;
- initWithContentType:(OWContentType *)aType parameters:(OFMultiValueDictionary *)parameters;

- (OWContentType *)contentType;
- (OFMultiValueDictionary *)parameters;

- (NSString *)objectForKey:(NSString *)aName;
- (void)setObject:(NSString *)newValue forKey:(NSString *)aName;

- (NSString *)contentTypeString;

@end
