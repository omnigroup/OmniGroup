// Copyright 2010 The Omni Group.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OmniUI/OUISingleViewInspectorPane.h>

@interface OUIFontInspectorPane : OUISingleViewInspectorPane <UITableViewDataSource, UITableViewDelegate>
{
@private
    UIFont *_showFacesOfFont;
    NSArray *_sections;
    
    NSArray *_fonts;
    NSArray *_fontNames;
    NSSet *_selectedFonts;
}

+ (NSSet *)recommendedFontFamilyNames;

@property(retain,nonatomic) UIFont *showFacesOfFont; // If nil, we show families

@end
