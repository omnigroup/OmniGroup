// Copyright 2010-2015 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <UIKit/UIView.h>

// Flatten the view hierarchy for the name/date and possible iCloud status icon for fewer composited layers while scrolling.
@interface OUIDocumentPickerItemMetadataView : UIView
+ (UIColor *)defaultBackgroundColor;

@property(nonatomic,copy) NSString *name;
@property(nonatomic,strong) UIImage *nameBadgeImage;
@property(nonatomic) BOOL showsImage;
@property(nonatomic,copy) NSString *dateString;
@property(nonatomic,assign) BOOL showsProgress;
@property(nonatomic,assign) double progress;
@property(nonatomic,assign) BOOL isSmallSize;

// OUIDocumentRenameSession becomes the delegate of this while renaming
@property(nonatomic,readonly) UITextField *nameTextField;
@property(nonatomic,readonly) UILabel *dateLabel;
@property(nonatomic,readonly) UIImageView *nameBadgeImageView;

@end

@interface NSObject (OUIDocumentPickerItemMetadataView)
- (void)documentPickerItemNameStartedEditing:(id)sender;
- (void)documentPickerItemNameEndedEditing:(id)sender withName:(NSString *)name;
@end
