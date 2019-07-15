// Copyright 2008-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

typedef NS_ENUM(NSUInteger, ODOEditingContextFaultErrorRecovery) {
    ODOEditingContextFaultErrorUnhandled = 0,
    ODOEditingContextFaultErrorIgnored,
    ODOEditingContextFaultErrorRepaired,
};

NS_ASSUME_NONNULL_BEGIN

@interface ODOEditingContext (/*Subclass*/)

/*!
 This method is called when the editing context failed to fulfill a fault for any reason. Subclasses may override this method to attempt to recover from the given error, and should return one of the following:
 
     * ODOEditingContextFaultErrorUnhandled if the error was left unhandled, and needs to be reported further. This is the default.
     * ODOEditingContextFaultErrorIgnored if the error was not handled, but can be ignored by callers.
     * ODOEditingContextFaultErrorRepaired if the error was handled, and a subsequent attempt of the same operation is expected to succeed.
 */
- (ODOEditingContextFaultErrorRecovery)handleFaultFulfillmentError:(NSError *)error;

@end

NS_ASSUME_NONNULL_END
