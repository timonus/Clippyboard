//
//  CLIPPasteboardPoller.m
//  Clippy
//
//  Created by Tim Johnsen on 7/31/14.
//  Copyright (c) 2014 tijo. All rights reserved.
//

#import "CLIPPasteboardPoller.h"

@interface CLIPPasteboardPoller ()

@property (nonatomic, assign) NSInteger changeCount;

@end

@implementation CLIPPasteboardPoller

+ (Class)pasteboardClass
{
    return [NSPasteboard class];
}

- (id)init
{
    if (self = [super init]) {
        self.changeCount = [[[[self class] pasteboardClass] generalPasteboard] changeCount];
        [NSTimer scheduledTimerWithTimeInterval:0.5 target:self selector:@selector(pollPasteboard:) userInfo:nil repeats:YES];
    }
    return self;
}

- (void)pollPasteboard:(id)sender
{
    if (!self.suppressChangeEvents) {
        NSInteger changeCount = [[[[self class] pasteboardClass] generalPasteboard] changeCount];
        if (self.changeCount != changeCount) {
            self.changeCount = changeCount;
            
            [self.delegate pasteboardDidChange];
        }
    }
}

- (void)setSuppressChangeEvents:(BOOL)suppressChangeEvents
{
    if (suppressChangeEvents != _suppressChangeEvents) {
        _suppressChangeEvents = suppressChangeEvents;
        
        if (!suppressChangeEvents) {
            self.changeCount = [[[[self class] pasteboardClass] generalPasteboard] changeCount];
        }
    }
}

@end
