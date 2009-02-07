// Copyright 1997-2005, 2009 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OmniBase/OBObject.h>
#import <OmniBase/assertions.h>

@interface OBPostLoader : OBObject

+ (void)processClasses;

+ (void) processSelector: (SEL) selectorToCall
              initialize: (BOOL) shouldInitialize;

+ (BOOL) isMultiThreaded;

@end

@interface NSObject (OBPostLoader)

/*"
This method will be called on every class (or category) which implements it.
"*/
+ (void) performPosing;

/*"
This method will be called on every class (or category) which implements it.
"*/
+ (void) didLoad;

/*"
This is called on each class implementation with this selector name the first time the application is about to become multi-threaded.  Classes can implement this method to allocate locks that will be necessary to arbitrate access to shared data owned by the class.  This method is NOT automatically called on instances -- they will need to manually subscribe to NSWillBecomeMultiThreadedNotification.
"*/
+ (void) becomingMultiThreaded;

@end
