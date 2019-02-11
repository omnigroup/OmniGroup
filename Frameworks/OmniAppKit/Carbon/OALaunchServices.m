// Copyright 2018 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniAppKit/OALaunchServices.h>

NS_ASSUME_NONNULL_BEGIN

@implementation NSWorkspace (OAExtensions)

- (nullable NSArray<NSURL *> *)applicationURLsForURL:(NSURL *)fileURL editor:(BOOL)editor;
{
    return CFBridgingRelease(LSCopyApplicationURLsForURL((__bridge CFURLRef)fileURL, editor ? kLSRolesEditor : kLSRolesViewer));
}

- (nullable NSURL *)defaultApplicationURLForURL:(NSURL *)fileURL editor:(BOOL)editor error:(NSError **)outError;
{
    CFErrorRef cfError = NULL;
    NSURL *result = CFBridgingRelease(LSCopyDefaultApplicationURLForURL((__bridge CFURLRef)fileURL, editor ? kLSRolesEditor : kLSRolesViewer, &cfError));
    if (result != nil) {
        return result;
    }

    OB_CFERROR_TO_NS(outError, cfError);
    return nil;
}

@end

NS_ASSUME_NONNULL_END
