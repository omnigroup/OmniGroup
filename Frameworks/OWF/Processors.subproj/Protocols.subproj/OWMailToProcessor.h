// Copyright 1997-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OWF/OWProcessor.h>

@class OWAddress;

// This is an abstract class which provides the fundamentals of parsing a mailto address, picking a good subject, etc.

// For this class to actually do anything, the -deliver method must be subclassed and the subclass must register itself as a process which converts url/mailto to Omni/Source.  (If multiple subclasses register themselves, the one with the lower cost wins.)

// The parameters dictionary will contain 

@interface OWMailToProcessor : OWProcessor
{
    OWAddress *mailToAddress;
    NSDictionary *parameterDictionary;
}

- (void)deliver;
    // This must be implemented by a subclass.  The mail parameters (to, subject, body) will have already been parsed into parameterDictionary.

@end

// Use these keys to retrieve values from the parameter dictionary.

extern NSString * const OWMailToProcessorToParameterKey;
    // The "to" address

extern NSString * const OWMailToProcessorSubjectParameterKey;
    // The subject line

extern NSString * const OWMailToProcessorBodyParameterKey;
    // The message body
