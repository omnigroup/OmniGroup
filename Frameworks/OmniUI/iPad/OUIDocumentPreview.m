// Copyright 2010-2011 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUIDocumentPreview.h>

#import <OmniUI/OUIDrawing.h>
#import <OmniQuartz/OQDrawing.h>

RCS_ID("$Id$");

@implementation OUIDocumentPreview
{
    OUIDocumentStoreFileItem *_fileItem;
    NSDate *_date;
    UIImage *_originalImage;
    BOOL _landscape;
    OUIDocumentPreviewType _type;
    BOOL _superseded;
}

- initWithFileItem:(OUIDocumentStoreFileItem *)fileItem date:(NSDate *)date image:(UIImage *)image landscape:(BOOL)landscape type:(OUIDocumentPreviewType)type;
{
    OBPRECONDITION(fileItem);
    OBPRECONDITION(date);
    OBPRECONDITION(image);
    
    if (!(self = [super init]))
        return nil;

    _fileItem = [fileItem retain];
    _date = [date copy];
    _landscape = landscape;
    _type = type;
    _originalImage = [image retain];
    
    return self;
}

- (void)dealloc;
{
    [_fileItem release];
    [_date release];
    [_originalImage release];
    [super dealloc];
}

@synthesize fileItem = _fileItem;
@synthesize date = _date;
@synthesize landscape = _landscape;
@synthesize type = _type;
@synthesize superseded = _superseded;

@synthesize image = _originalImage;

- (CGSize)size;
{
    return _originalImage.size;
}

- (void)drawInRect:(CGRect)rect;
{
    OBPRECONDITION(rect.size.width >= 1);
    OBPRECONDITION(rect.size.height >= 1);
    
    CGImageRef image = [_originalImage CGImage];
    if (!image || rect.size.width < 1 || rect.size.height < 1)
        return;
    
    size_t width = CGImageGetWidth(image);
    size_t height = CGImageGetHeight(image);
    
    if (width == 0 || height == 0) {
        OBASSERT_NOT_REACHED("Degenerate image");
        return;
    }
    
    PREVIEW_DEBUG(@"Drawing scaled preview %@ -> %@", NSStringFromCGSize(CGSizeMake(width, height)), NSStringFromCGRect(rect));
    
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    CGContextSaveGState(ctx);
    {
        CGContextTranslateCTM(ctx, rect.origin.x, rect.origin.y);
        rect.origin = CGPointZero;
        
        OQFlipVerticallyInRect(ctx, rect);
        
        CGContextSetInterpolationQuality(ctx, kCGInterpolationHigh);
        CGContextDrawImage(ctx, rect, image);
    }
    CGContextRestoreGState(ctx);
}

#pragma mark -
#pragma mark Debugging

- (NSString *)shortDescription;
{
    NSString *typeString;
    switch (_type) {
        case OUIDocumentPreviewTypeRegular:
            typeString = @"regular";
            break;
        case OUIDocumentPreviewTypePlaceholder:
            typeString = @"placeholder";
            break;
        case OUIDocumentPreviewTypeEmpty:
            typeString = @"empty";
            break;
        default:
            typeString = @"UNKNOWN";
            break;
    }
    
    return [NSString stringWithFormat:@"<%@:%p item:%@ date:%f image:%p landscape:%d type:%@>", NSStringFromClass([self class]), self, [_fileItem shortDescription], [_date timeIntervalSinceReferenceDate], _originalImage, _landscape, typeString];
}

@end
