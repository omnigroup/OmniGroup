// Copyright 2012-2016 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniAppKit/OAAnimation.h>

RCS_ID("$Id$")

@implementation OAAnimation

@synthesize currentCGFloatValue=_CGFloatValue, CGFloatValueTransformer=_CGFloatValueTransformer, progressHandler=_progressHandler;

- (void)dealloc;
{
    // TODO: This might not be threadsafe! Rather than stop the animation and synchronize with -setCurrentProgress:, just assert we aren't threaded.
    OBASSERT(self.animationBlockingMode != NSAnimationNonblockingThreaded);
    
    _CGFloatValueTransformer = nil;
    
    _progressHandler = nil;
}

- (float)currentValue;
{
    // Avoid round-tripping to lower-resolution type if we don't have a CGFloat value transformer.
    
    if (_CGFloatValueTransformer)
        return (float)_CGFloatValue;
    else
        return [super currentValue];
}

- (void)setCurrentProgress:(NSAnimationProgress)progress;
{
    [super setCurrentProgress:progress];
    
    if (_CGFloatValueTransformer) {
        _CGFloatValue = _CGFloatValueTransformer(progress);
        
        if (_progressHandler)
            _progressHandler(progress, _CGFloatValue);
    } else {
        _CGFloatValue = (CGFloat)[super currentValue];
        
        if (_progressHandler)
            _progressHandler(progress, (CGFloat)[super currentValue]);
    }
}

@end
