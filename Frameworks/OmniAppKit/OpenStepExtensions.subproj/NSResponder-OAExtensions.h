// Copyright 1997-2005, 2007 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <AppKit/NSResponder.h>

@interface NSResponder (OAExtensions)
- (void)noop_didPresentErrorWithRecovery:(BOOL)didRecover contextInfo:(void *)contextInfo; // public for OAApplication.m
- (void)presentError:(NSError *)error modalForWindow:(NSWindow *)window;
@end
