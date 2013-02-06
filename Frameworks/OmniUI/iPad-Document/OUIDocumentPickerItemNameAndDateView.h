// Copyright 2010-2012 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <UIKit/UIView.h>

// Flatten the view hierarchy for the name/date and possible iCloud status icon for fewer composited layers while scrolling.
@interface OUIDocumentPickerItemNameAndDateView : UIView
@property(nonatomic,copy) NSString *name;
@property(nonatomic,strong) UIImage *nameBadgeImage;
@property(nonatomic,copy) NSString *dateString;
@end
