// Copyright 1997-2005 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Header: svn+ssh://source.omnigroup.com/Source/svn/Omni/tags/OmniSourceRelease/2008-09-09/OmniGroup/Frameworks/OmniFoundation/OpenStepExtensions.subproj/NSThread-OFExtensions.h 68913 2005-10-03 19:36:19Z kc $

#import <Foundation/NSThread.h>

@interface NSThread (OFExtensions)

+ (void)setMainThread;
+ (NSThread *)mainThread;
+ (BOOL)inMainThread;
+ (BOOL)mainThreadOpsOK;   // returns true if we are the main thread *or* if we have locked the main thread

// For putting appkit stuff into subthreads without shipping data back and forth.  If you don't need the return value, then queuing a selector is much more efficient than this.
+ (void)lockMainThread;
+ (void)unlockMainThread;

- (void)yield;
    // Causes the thread to possibly stop executing and cause another thread to start executing.  Has no effect if not multithreaded.
- (BOOL)yieldMainThreadLock;
    // If we're the main thread and another thread is waiting to lock the main thread, yield the lock to them and return YES

@end

#define ASSERT_IN_MAIN_THREAD(reason) NSAssert([NSThread inMainThread], reason)
#define ASSERT_MAIN_THREAD_OPS_OK(reason) NSAssert([NSThread mainThreadOpsOK], reason)
