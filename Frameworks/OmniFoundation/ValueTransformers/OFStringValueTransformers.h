// Copyright 2013-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <Foundation/NSString.h>
#import <Foundation/NSValueTransformer.h>

@interface OFUppercaseStringTransformer : NSValueTransformer

@end

@interface OFLowercaseStringTransformer : NSValueTransformer

@end

extern NSString * const OFUppercaseStringTransformerName;
extern NSString * const OFLowercaseStringTransformerName;
