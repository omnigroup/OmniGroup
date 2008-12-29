// Copyright 2000-2005, 2007 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Header: svn+ssh://source.omnigroup.com/Source/svn/Omni/tags/OmniSourceRelease/2008-09-09/OmniGroup/Frameworks/OmniAppKit/Widgets.subproj/OAAquaButton.h 92244 2007-10-03 20:26:28Z wiml $

#import <AppKit/NSButton.h>
#import <OmniAppKit/FrameworkDefines.h>

@class NSBundle; // Foundation

@interface OAAquaButton : NSButton
{
    NSImage *clearImage;
    NSImage *aquaImage;
    NSImage *graphiteImage;
}

- (void)setImageName:(NSString *)anImageName inBundle:(NSBundle *)aBundle;
    // The image named anImageName will be used for the normal state of the button.  The alternate image of the button will be the image named anImageName with either "Aqua" or "Graphite" appended to it.
    
@end

// Legacy symbols. New code should use OAGraphiteImageTintSuffix, etc., defined in NSImage-OAExtensions.h.
OmniAppKit_EXTERN NSString *OAAquaButtonAquaImageSuffix;	// "Aqua"
OmniAppKit_EXTERN NSString *OAAquaButtonGraphiteImageSuffix;	// "Graphite"
OmniAppKit_EXTERN NSString *OAAquaButtonClearImageSuffix;	// "Clear"
