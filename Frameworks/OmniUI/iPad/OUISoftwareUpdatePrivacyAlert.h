// Copyright 2010 The Omni Group.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OmniFoundation/OFObject.h>
#import <OmniUI/OUIFeatures.h>

#if OUI_SOFTWARE_UPDATE_CHECK

@class OUISoftwareUpdatePrivacyAlert;

@protocol OUISoftwareUpdatePrivacyAlertDelegate
- (void)softwareUpdatePrivacyAlert:(OUISoftwareUpdatePrivacyAlert *)alert completedWithAllowingReports:(BOOL)allowReports;
@end

@interface OUISoftwareUpdatePrivacyAlert : OFObject <UIAlertViewDelegate>
{
@private
    id <OUISoftwareUpdatePrivacyAlertDelegate> _nonretained_delegate;
    UIAlertView *_alertView;
}
- initWithDelegate:(id <OUISoftwareUpdatePrivacyAlertDelegate>)delegate;
- (void)show;
@end

#endif
