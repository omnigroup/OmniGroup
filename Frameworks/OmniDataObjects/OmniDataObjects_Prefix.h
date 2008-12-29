// Copyright 2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OmniBase/OmniBase.h>
#import <OmniBase/system.h>

#import <OmniFoundation/OFNull.h>
#import <OmniFoundation/CFArray-OFExtensions.h>
#import <OmniFoundation/OFCFCallbacks.h>

#import <OmniDataObjects/Errors.h>
#import <OmniDataObjects/ODOPredicate.h> // Make sure everyone gets the #defines in here

#import <Foundation/NSArray.h>
#import <Foundation/NSDictionary.h>
#import <Foundation/NSEnumerator.h>
#import <Foundation/NSCharacterSet.h>
#import <Foundation/NSURL.h>
#import <Foundation/NSNull.h>
#import <Foundation/NSData.h>
#import <Foundation/NSPropertyList.h>
#import <Foundation/NSNotification.h>
#import <Foundation/NSDate.h>
#import <Foundation/NSSet.h>
#import <Foundation/NSKeyValueCoding.h>
#import <Foundation/NSKeyValueObserving.h>
#import <Foundation/NSSortDescriptor.h>
#import <Foundation/NSUserDefaults.h>

#import <CoreFoundation/CFNumber.h>
#import <CoreFoundation/CFSet.h>

#if 0 && defined(DEBUG)
    #define DEBUG_UNDO(format, ...) NSLog((format), ## __VA_ARGS__)
#else
    #define DEBUG_UNDO(format, ...)
#endif
