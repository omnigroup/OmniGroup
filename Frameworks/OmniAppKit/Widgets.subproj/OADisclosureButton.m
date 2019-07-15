// Copyright 2014-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniAppKit/OADisclosureButton.h>
#import <OmniAppKit/OADisclosureButtonCell.h>

RCS_ID("$Id$");

@implementation OADisclosureButton

+ (Class)cellClass;
{
    return [OADisclosureButtonCell class];
}

- (id)initWithFrame:(NSRect)frame;
{
    self = [super initWithFrame:frame];
    if (self == nil) {
        return nil;
    }
    
    [self OADisclosureButton_commonInit];
    
    return self;
}

- (id)initWithCoder:(NSCoder *)coder;
{
    self = [super initWithCoder:coder];
    if (self == nil) {
        return nil;
    }
    
    [self OADisclosureButton_commonInit];
    
    return self;
}

- (void)OADisclosureButton_commonInit;
{
#ifdef OMNI_ASSERTIONS_ON
    Class cellClass = [[self class] cellClass];
    OBASSERT([[self cell] isKindOfClass:cellClass]);
#endif

    [self setImagePosition:NSImageOnly];
    [self setBezelStyle:NSBezelStyleShadowlessSquare];
    [self setButtonType:NSButtonTypeMomentaryPushIn];
    [self setBordered:NO];

    [[self cell] setImageDimsWhenDisabled:NO];
}

- (NSImage *)collapsedImage;
{
    OADisclosureButtonCell *cell = OB_CHECKED_CAST(OADisclosureButtonCell, self.cell);
    return cell.collapsedImage;
}

- (void)setCollapsedImage:(NSImage *)collapsedImage;
{
    OADisclosureButtonCell *cell = OB_CHECKED_CAST(OADisclosureButtonCell, self.cell);
    cell.collapsedImage = collapsedImage;
}

- (NSImage *)expandedImage;
{
    OADisclosureButtonCell *cell = OB_CHECKED_CAST(OADisclosureButtonCell, self.cell);
    return cell.collapsedImage;
}

- (void)setExpandedImage:(NSImage *)expandedImage;
{
    OADisclosureButtonCell *cell = OB_CHECKED_CAST(OADisclosureButtonCell, self.cell);
    cell.expandedImage = expandedImage;
}

- (BOOL)showsStateByAlpha;
{
    OADisclosureButtonCell *cell = OB_CHECKED_CAST(OADisclosureButtonCell, self.cell);
    return cell.showsStateByAlpha;
}

- (void)setShowsStateByAlpha:(BOOL)showsStateByAlpha;
{
    OADisclosureButtonCell *cell = OB_CHECKED_CAST(OADisclosureButtonCell, self.cell);
    cell.showsStateByAlpha = showsStateByAlpha;
}

@end
