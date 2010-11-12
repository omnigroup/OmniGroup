// Copyright 2010 The Omni Group.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import "OUIEditableLabeledValueCell.h"
#import "OUISetUpSyncBaseController.h"

@class OFPreference;

@interface OUISetUpWebDAVSyncController : OUISetUpSyncBaseController <OUIEditableLabeledValueCellDelegate>
{
@private
    OFPreference *_webDAVSyncURLPreference;
    UIView *_syncSectionHeaderView;
    UIView *_syncSectionFooterView;
}

@end
