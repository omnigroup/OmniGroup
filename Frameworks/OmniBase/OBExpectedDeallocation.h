// Copyright 2013 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <Foundation/NSObject.h>

/*
 The intended use of this is to detect retain cycles that tend to creep into an app and prevent "large" objects from being deallocated (taking tons of memory with them).
 
 To use this, simply invoke `OBExpectDeallocation(object);` for any objects that are known to be at their end of live. If they aren't deallocated within a few seconds, an assertion will be logged with the pointer, class, and a backtrace from the invocation of OBExpectDeallocation().
 
 For example, when your NSDocument or NSWindowController subclass closes, it might invoke this on itself and some key views, controllers, and model objects. The intention is not to invoke this on every single object that might be deallocated, but just the central hubs that tend to hold onto the majority of other things. This aids in quickly detecting a regression in memory management due to retain cycles (block capture, backpointers that should be __weak, explicit retain cycles that need to be manually broken, etc).
 */

#ifdef DEBUG
    extern void OBExpectDeallocation(id object);
#else
    #define OBExpectDeallocation(object)
#endif
