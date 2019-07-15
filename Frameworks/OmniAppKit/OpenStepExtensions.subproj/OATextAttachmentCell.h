// Copyright 2011-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <Availability.h>

@class OFXMLDocument;

#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
// NSTextAttachment conforms to NSTextAttachmentContainer and there doesn't seem to be any separate NSTextAttachmentCell
@class NSData;
@class NSLayoutManager;
#import <UIKit/NSAttributedString.h>
#import <UIKit/NSTextAttachment.h>
#else
#import <AppKit/NSTextAttachment.h>
#endif

#import <Foundation/NSObject.h>
#import <OmniAppKit/OATextAttachment.h>

#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE

#import <CoreGraphics/CGGeometry.h>

@class UIView;

@protocol OATextAttachmentCell <NSObject>
- (void)drawWithFrame:(CGRect)cellFrame inView:(UIView *)controlView characterIndex:(NSUInteger)charIndex layoutManager:(NSLayoutManager *)layoutManager;
#if 0
- (BOOL)wantsToTrackMouse;
- (void)highlight:(BOOL)flag withFrame:(NSRect)cellFrame inView:(NSView *)controlView;
- (BOOL)trackMouse:(NSEvent *)theEvent inRect:(NSRect)cellFrame ofView:(NSView *)controlView untilMouseUp:(BOOL)flag;
#endif
@property(nonatomic,readonly) CGSize cellSize;
- (CGPoint)cellBaselineOffset;

@property(nonatomic,weak) OATextAttachment *attachment;

#if 0
// Sophisticated cells should implement these in addition to the simpler methods, above.  The class NSTextAttachmentCell implements them to simply call the simpler methods; more complex conformers should implement the simpler methods to call these.
- (void)drawWithFrame:(NSRect)cellFrame inView:(NSView *)controlView characterIndex:(NSUInteger)charIndex;
- (void)drawWithFrame:(NSRect)cellFrame inView:(NSView *)controlView characterIndex:(NSUInteger)charIndex layoutManager:(NSLayoutManager *)layoutManager;
- (BOOL)wantsToTrackMouseForEvent:(NSEvent *)theEvent inRect:(NSRect)cellFrame ofView:(NSView *)controlView atCharacterIndex:(NSUInteger)charIndex;
- (BOOL)trackMouse:(NSEvent *)theEvent inRect:(NSRect)cellFrame ofView:(NSView *)controlView atCharacterIndex:(NSUInteger)charIndex untilMouseUp:(BOOL)flag;
- (NSRect)cellFrameForTextContainer:(NSTextContainer *)textContainer proposedLineFragment:(NSRect)lineFrag glyphPosition:(NSPoint)position characterIndex:(NSUInteger)charIndex;
#endif

@optional
- (void)appendXMLForNonDefaultCellInformation:(OFXMLDocument *)doc;

@end

// Subclasses NSCell on the Mac, but no such thing here.
@interface OATextAttachmentCell : NSObject <OATextAttachmentCell>

@property(nonatomic,weak) OATextAttachment *attachment;

@end


#else

#define OATextAttachmentCell NSTextAttachmentCell

#endif

@interface OATextAttachmentCell (OATextAttachmentCellXML)

+ (void)appendXMLForNonDefaultCellInformation:(OFXMLDocument *)doc imageSize:(CGSize)imageSize;

@end
