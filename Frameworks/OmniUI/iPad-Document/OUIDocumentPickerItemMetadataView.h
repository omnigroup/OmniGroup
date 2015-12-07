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
+ (UIColor *)defaultEditingBackgroundColor;

@property(nonatomic,copy) NSString *name;
@property(nonatomic,strong) UIImage *nameBadgeImage;
@property(nonatomic) BOOL showsImage;
@property(nonatomic,copy) NSString *dateString;
@property(nonatomic,assign) BOOL showsProgress;
@property(nonatomic,assign) double progress;
@property(nonatomic,assign) BOOL isSmallSize;

// OUIDocumentRenameSession becomes the delegate of this while renaming
@property(nonatomic,retain) IBOutlet UITextField *nameTextField;
@property(nonatomic,retain) IBOutlet UILabel *dateLabel;
@property(nonatomic,readonly) UIImageView *nameBadgeImageView;
@property(nonatomic, retain) IBOutlet UIProgressView *transferProgressView;
@property (nonatomic, retain) IBOutlet UIView *topHairlineView;
@property(nonatomic, retain) UIView *startSnap; // for animating to/from large size when renaming
@property(nonatomic, retain) UIView *endSnap; // for animating to/from large size when renaming

// constraints
@property (nonatomic,retain) IBOutlet NSLayoutConstraint *padding;
@property (nonatomic,retain) IBOutlet NSLayoutConstraint *nameToDatePadding;
@property (nonatomic,retain) IBOutlet NSLayoutConstraint *nameHeightConstraint;
@property (nonatomic,retain) IBOutlet NSLayoutConstraint *dateHeightConstraint;
@property (nonatomic,retain) IBOutletCollection(NSLayoutConstraint) NSArray<NSLayoutConstraint*>* topAndBottomPadding;

@property (nonatomic) BOOL doubleSizeFonts;

- (BOOL)isEditing;
- (UIView*)viewForScalingStartFrame:(CGRect)startFrame endFrame:(CGRect)endFrame;
- (void)animationsToPerformAlongsideScalingToHeight:(CGFloat)height;

@end

@interface NSObject (OUIDocumentPickerItemMetadataView)
- (void)documentPickerItemNameStartedEditing:(id)sender;
- (void)documentPickerItemNameEndedEditing:(id)sender withName:(NSString *)name;
@end
