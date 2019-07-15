// Copyright 2010-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <UIKit/UIView.h>

NS_ASSUME_NONNULL_BEGIN

// Flatten the view hierarchy for the name/date and possible iCloud status icon for fewer composited layers while scrolling.
// This is a subclass of UIControl so it can 
@interface OUIDocumentPickerItemMetadataView : UIView

@property (class, nonatomic, readonly) UIColor *defaultBackgroundColor;

@property (nullable, nonatomic, copy) NSString *name;
@property (nullable, nonatomic, copy) NSString *dateString;
@property (nullable, nonatomic, strong) UIImage *nameBadgeImage;
@property (nonatomic) BOOL showsImage;
@property (nonatomic) BOOL showsProgress;
@property (nonatomic) float progress;
@property (nonatomic) BOOL isSmallSize;
@property (nonatomic) BOOL doubleSizeFonts;
@property (nonatomic, readonly) BOOL isEditing;

// OUIDocumentRenameSession becomes the delegate of this while renaming
- (UITextField *)startEditingName;
- (void)didEndEditing;

@property (nullable, nonatomic, readonly) UIProgressView *transferProgressView;

- (UIView *)viewForScalingStartFrame:(CGRect)startFrame endFrame:(CGRect)endFrame;
- (void)animationsToPerformAlongsideScalingToHeight:(CGFloat)height;

@end

@interface NSObject (OUIDocumentPickerItemMetadataView)
- (void)documentPickerItemNameStartedEditing:(id)sender;
- (void)documentPickerItemNameEndedEditing:(id)sender withName:(NSString *)name;
@end

NS_ASSUME_NONNULL_END

