// Copyright 2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
#import <Foundation/NSNotification.h>

NS_ASSUME_NONNULL_BEGIN

/*!
 This platform-agnostic notification is posted whenever there is a "significant" time change in the system. This includes things like the system clock or time preferences changing. On iOS, it also includes all the cases covered by UIApplicationSignificantTimeChangeNotification; this class listens for that notification and forwards it as this OFM equivalent. Callers should listen for this notification instead of any system notification.
 */
extern NSNotificationName const OASignificantTimeChangeNotification;

NS_ASSUME_NONNULL_END
