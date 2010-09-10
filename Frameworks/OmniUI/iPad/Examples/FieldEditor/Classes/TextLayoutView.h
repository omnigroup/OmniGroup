//  Copyright 2010 The Omni Group. All rights reserved.
//
// $Id$

#import <OmniFoundation/OFObject.h>

@class OUITextLayout;

@interface TextLayoutView : UIView
{
@private
    NSAttributedString *_text;
    OUITextLayout *_textLayout;
}

@property(copy,nonatomic) NSAttributedString *text;

@end
