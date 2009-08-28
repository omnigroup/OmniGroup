// Copyright 2007-2009 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OmniFoundation/OFObject.h>
#import <Foundation/NSError.h>

// A way to simplify error recovery.  Each instance of subclasses handles a single error recovery.

@interface OFErrorRecovery : OFObject
{
@private
    NSString *_localizedRecoveryOption;
    id _object;
}

+ (NSError *)errorRecoveryErrorWithError:(NSError *)error;
+ (NSError *)errorRecoveryErrorWithError:(NSError *)error object:(id)object;
+ (NSError *)errorRecoveryErrorWithError:(NSError *)error localizedRecoveryOption:(NSString *)localizedRecoveryOption object:(id)object;
    
- initWithLocalizedRecoveryOption:(NSString *)localizedRecoveryOption object:(id)object;

- (NSString *)localizedRecoveryOption;
- (id)object;

// Informal protocol shared beteween OFErrorRecovery and OFMultipleOptionErrorRecovery
- (id)firstRecoveryOfClass:(Class)cls;

// Subclass responsibility
+ (NSString *)defaultLocalizedRecoveryOption;
- (BOOL)isApplicableToError:(NSError *)error;  // Should this option even be displayed?
- (BOOL)attemptRecoveryFromError:(NSError *)error; // only one of these two need be overrridden
- (BOOL)attemptRecovery;

@end
