// Copyright 1997-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <AppKit/NSResponder.h>

NS_ASSUME_NONNULL_BEGIN

@interface NSResponder (OAExtensions)

- (void)noop_didPresentErrorWithRecovery:(BOOL)didRecover contextInfo:(void *)contextInfo; // public for OAApplication.m
- (void)presentError:(NSError *)error modalForWindow:(NSWindow *)window;

/// Returns an array of all the NSResponders between the receiver and the application, constructed by repeatedly calling -nextResponder. The returned array will include the receiver at index 0.
- (NSArray<NSResponder *> *)responderChain;

/// Returns a string containing the -shortDescription of all responders in the array returned by -responderChain.
- (NSString *)responderChainDescription;

/// Searches the responder chain for an NSResponder that is an instance of the specified class.
- (nullable NSResponder *)nextResponderOfClass:(Class)cls;

@end

NS_ASSUME_NONNULL_END
