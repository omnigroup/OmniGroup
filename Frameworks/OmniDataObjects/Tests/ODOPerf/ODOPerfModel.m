// Copyright 2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "ODOPerfModel.h"

RCS_ID("$Header: svn+ssh://source.omnigroup.com/Source/svn/Omni/tags/OmniSourceRelease/2008-09-09/OmniGroup/Frameworks/OmniDataObjects/Tests/ODOPerf/ODOPerfModel.m 104583 2008-09-06 21:23:18Z kc $")

NSString * const Bug_EntityName = @"Bug";
NSString * const Bug_DateAdded = @"dateAdded";
NSString * const Bug_Title = @"title";
NSString * const Bug_BugTags = @"bugTags";
NSString * const Bug_Notes = @"notes";
NSString * const Bug_State = @"state";

NSString * const BugTag_EntityName = @"BugTag";
NSString * const BugTag_Bug = @"bug";
NSString * const BugTag_Tag = @"tag";

NSString * const Note_EntityName = @"Note";
NSString * const Note_Author = @"author";
NSString * const Note_DateAdded = @"dateAdded";
NSString * const Note_Text = @"text";
NSString * const Note_Bug = @"bug";

NSString * const State_EntityName = @"State";
NSString * const State_Name = @"name";
NSString * const State_Bugs = @"bugs";

NSString * const Tag_EntityName = @"Tag";
NSString * const Tag_Name = @"name";
NSString * const Tag_Bugs = @"bugs";
