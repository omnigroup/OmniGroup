// Copyright 2012-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <Foundation/NSArray.h>

/**
  This class is meant to provide an implementation of a mutable array that can
  be "shifted" by an arbitrary amount in some direction. A shift here means
  that the entire contents of the array appear at indexes offset by the
  specified shift; for example, a shift of 1 would move the object normally at
  index 1 to a new location at index 0. The count of the array and other
  summary methods are also updated to reflect any items that become "missing"
  as a result of this shift.

  This effect is achieved by using a plain NSMutableArray to back this one and
  overriding the core NSArray and NSMutableArray methods to account for the
  shift. Particularly interesting details on this class include:

  * `-unadjustedArray`, which returns the NSMutableArray instance with "raw" data not masked by the shift
  * `@property NSUInteger offset`, which is the amount by which this array is shifted
 
  It's important to note that the shifting behavior provided in this class
  applies only to operations which specifically reference an index. Standard
  array methods that specify relative positions, such as -addObject: (implying
  last position) and -removeLastObject (specifying last position) will always
  operate on the underlying unadjusted array, even if the visible (shifted)
  portion of that array is empty.
 
  Furthermore, methods that do specify an index are translated mechanically to
  the unadjusted array. This can have negative implications if the underlying
  array is not sufficiently filled to behave as expected with a given offset;
  for example, the following is an error:

      OFOffsetMutableArray *arr = [[[OFOffsetMutableArray alloc] init] autorelease];
      arr.offset = 1;
      [arr insertObject:@"foo" atIndex:0];

  Even though the array is "empty," an object cannot yet be inserted at index
  0, since that index corresponds to index 1 in the underlying unadjusted
  array, and no object exists at the unadjusted array's 0th position.
  OFOffsetMutableArray will allow the underlying array to throw an exception in
  this case. (This behavior is preferable to the alternative, where
  OFOffsetMutableArray would need to silently fill the shifted-out portions of
  the unadjusted array with arbitrary values in order to satisfy the insertion
  request.)
 */

@interface OFOffsetMutableArray : NSMutableArray {
    NSUInteger _offset;
    NSMutableArray *_backingArray;
}

@property (nonatomic, assign) NSUInteger offset;

- (NSMutableArray *)unadjustedArray;
    // NB: changes to unadjustedArray are reflected in this array as well

@end
