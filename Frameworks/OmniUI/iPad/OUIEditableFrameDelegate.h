// Copyright 2010-2011 The Omni Group.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

@class OUIEditableFrame;

@protocol OUIEditableFrameDelegate <NSObject>

@optional

- (BOOL)textView:(OUIEditableFrame *)textView shouldInsertText:(NSString *)text;
- (BOOL)textView:(OUIEditableFrame *)textView shouldDeleteBackwardsFromIndex:(NSUInteger)startIndex;

- (void)textViewContentsChanged:(OUIEditableFrame *)textView;
- (void)textViewLayoutChanged:(OUIEditableFrame *)textView;
- (void)textViewSelectionChanged:(OUIEditableFrame *)textView;

- (BOOL)textViewShouldEndEditing:(OUIEditableFrame *)textView;
- (void)textViewWillEndEditing:(OUIEditableFrame *)textView;
- (void)textViewDidEndEditing:(OUIEditableFrame *)textView;

- (BOOL)textViewCanShowContextMenu:(OUIEditableFrame *)textView;

- (BOOL)textView:(OUIEditableFrame *)textView canPasteFromPasteboard:(UIPasteboard *)pasteboard;
- (NSAttributedString *)readAttributedStringFromPasteboard:(UIPasteboard *)pasteboard forTextView:(OUIEditableFrame *)textView;
- (BOOL)writeAttributedStringFromTextRange:(UITextRange *)textRange toPasteboard:(UIPasteboard *)pasteboard forTextView:(OUIEditableFrame *)textView;

@end

